"""Send a 28x28 MNIST image to the Tang Nano 20K CNN accelerator and
read back the predicted digit.

Wire protocol (matches top_mnist_accel.v):
  PC -> chip : 784 raw bytes (one per pixel, row-major, 0..255)
  chip -> PC : 1 raw byte. Lower 4 bits = predicted digit (0..9).
               Upper 4 bits are always 0 (NOT ASCII).
"""

import os
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial not installed. Run: pip install pyserial")

# === EDIT ME =================================================================
USB_PORT  = "/dev/cu.usbserial-20250303171"   # find with: ls /dev/cu.usbserial*
IMAGE_HEX = os.path.join(os.path.dirname(__file__), "..", "test_image.hex")
# =============================================================================

BAUD = 115200


def load_image(path):
    """Read test_image.hex (one hex byte per line) into a list of 784 ints."""
    pixels = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            pixels.append(int(line, 16))
    if len(pixels) != 784:
        sys.exit(f"Expected 784 pixels, got {len(pixels)} in {path}")
    return pixels


def main():
    pixels = load_image(IMAGE_HEX)
    print(f"Loaded {len(pixels)} pixels from {IMAGE_HEX}")

    try:
        port = serial.Serial(USB_PORT, BAUD, timeout=5)
    except serial.SerialException as e:
        sys.exit(f"Could not open {USB_PORT}: {e}\n"
                 f"Tip: run `ls /dev/cu.usbserial*` and edit USB_PORT.")

    # Drop any stale bytes the FPGA / USB bridge might have buffered
    # from a previous run.
    time.sleep(0.1)
    port.reset_input_buffer()
    port.reset_output_buffer()
    stale = port.read(port.in_waiting or 0)
    if stale:
        print(f"Drained {len(stale)} stale byte(s): {stale.hex()}")

    # 2. Send the pixels to the hardware!
    print("Streaming 784 pixels to the FPGA (Throttled for safety)...")
    start_time = time.time()

    # Feed the bytes one by one with a tiny 1-millisecond delay
    for b in pixels:
        port.write(bytes([b]))
        port.flush() # Force it out of the OS buffer
        time.sleep(0.001)

    t_write = time.time() - start_time
    print(f"  write returned in {t_write * 1000:.1f} ms")

    # 3. Wait for the hardware to reply
    print("Waiting for the chip to compute and reply...")
    t1 = time.time()
    reply = port.read(1)
    t_read = time.time() - t1
    print(f"  reply received after {t_read * 1000:.1f} ms")
    if not reply:
        sys.exit("Timed out waiting for the chip. Is the FPGA powered + flashed "
                 "with the latest bitstream?")

    digit = reply[0] & 0x0F
    print(f"\nRaw byte from chip: 0x{reply[0]:02X}")
    print(f"PREDICTED DIGIT  : {digit}")
    port.close()


if __name__ == "__main__":
    main()
