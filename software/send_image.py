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
USB_PORT  = "/dev/cu.usbserial-20250303170"   # find with: ls /dev/cu.usbserial*
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

    # Drop any stale bytes. The FPGA's UART_TX line can spit out a junk
    # framing byte right after configuration / power-up.
    drained = bytearray()
    drain_deadline = time.time() + 1.0
    while time.time() < drain_deadline:
        port.reset_input_buffer()
        time.sleep(0.1)
        n = port.in_waiting
        if n:
            chunk = port.read(n)
            drained.extend(chunk)
            drain_deadline = time.time() + 0.5  # extend if activity
    if drained:
        print(f"Drained {len(drained)} stale byte(s): {drained.hex()}")

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

    # 3. Wait for the hardware to reply — collect for up to 3s so we don't
    #    confuse a config-transition glitch byte with the real answer.
    print("Waiting for the chip to compute and reply...")
    t1 = time.time()
    received = bytearray()
    deadline = t1 + 3.0
    while time.time() < deadline:
        chunk = port.read(port.in_waiting or 1)
        if chunk:
            received.extend(chunk)
            deadline = time.time() + 0.5  # extend if activity
    t_read = time.time() - t1
    print(f"  collected {len(received)} byte(s) in {t_read*1000:.0f} ms: {received.hex()}")
    if not received:
        sys.exit("No reply.")

    # Heuristic: the real answer is the LAST byte (any earlier ones are
    # boot/config glitches).
    last = received[-1]
    digit = last & 0x0F
    print(f"\nLast byte from chip: 0x{last:02X}")
    print(f"PREDICTED DIGIT   : {digit}")
    port.close()


if __name__ == "__main__":
    main()
