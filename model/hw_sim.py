"""
Cycle-accurate-ish hardware simulator.
Reads weights.mi / bias.mi (the exact bytes loaded into the FPGA ROMs)
and the image bytes from mem_image_ram.v, then runs the same fixed-point
pipeline the FPGA does: 3x3 conv (no bias, >>8 quantize, clamp 0..255),
2x2 max pool, FC (with scaled bias), argmax.
"""
import re
import numpy as np

WEIGHTS_MI = "/Users/joseignacio/cnn_chip/weights.mi"
BIAS_MI    = "/Users/joseignacio/cnn_chip/model/bias.mi"
IMAGE_V    = "/Applications/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/bin/cnn_chip/src/gowin_sp/mem_image_ram.v"


def load_mi(path, width_bits):
    bytes_per_entry = width_bits // 4  # hex chars
    vals = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            v = int(s, 16)
            # convert to signed if MSB is set
            if v & (1 << (width_bits - 1)):
                v -= 1 << width_bits
            vals.append(v)
    return vals


def load_image(path):
    """Extract the 784-byte image from INIT_RAM_xx defparams (32 bytes per word, LSB-first)."""
    image = [0] * 784
    pat = re.compile(r"INIT_RAM_([0-9A-F]+)\s*=\s*256'h([0-9A-Fa-f]+)")
    with open(path) as f:
        for line in f:
            m = pat.search(line)
            if not m:
                continue
            idx = int(m.group(1), 16)
            data = m.group(2).rjust(64, "0")
            base = idx * 32
            # rightmost hex pair = lowest address byte
            for byte_i in range(32):
                hex_pair = data[64 - 2 * (byte_i + 1): 64 - 2 * byte_i]
                addr = base + byte_i
                if addr < 784:
                    image[addr] = int(hex_pair, 16)
    return np.array(image, dtype=np.int32).reshape(28, 28)


def main():
    weights = load_mi(WEIGHTS_MI, 8)
    biases  = load_mi(BIAS_MI, 32)
    assert len(weights) == 1699, f"expected 1699 weights, got {len(weights)}"
    assert len(biases)  == 11,   f"expected 11 biases,   got {len(biases)}"

    img = load_image(IMAGE_V)
    print("Image (28x28), nonzero count:", int(np.sum(img > 0)))
    print("Image preview (thresholded at 64):")
    for row in img:
        print("".join("#" if v > 64 else "." for v in row))

    conv_w = np.array(weights[0:9], dtype=np.int32).reshape(3, 3)
    print("\nConv kernel:\n", conv_w)

    # --- Conv: 26x26 output, no bias, ReLU, >>8, clamp 0..255 ---
    conv_out = np.zeros((26, 26), dtype=np.int32)
    for oy in range(26):
        for ox in range(26):
            acc = 0
            for ky in range(3):
                for kx in range(3):
                    acc += int(img[oy + ky, ox + kx]) * int(conv_w[ky, kx])
            if acc < 0:
                v = 0
            else:
                v = acc >> 8
                if v > 255:
                    v = 255
            conv_out[oy, ox] = v
    print("\nConv output range:", conv_out.min(), "..", conv_out.max(),
          " saturated@255:", int(np.sum(conv_out == 255)),
          " zeros:", int(np.sum(conv_out == 0)))

    # --- 2x2 max pool, stride 2 → 13x13 ---
    pool_out = conv_out[:26, :26].reshape(13, 2, 13, 2).max(axis=(1, 3))

    # --- FC: 10 digits, weights at addr 9..1698 (169 per digit) ---
    flat = pool_out.flatten().astype(np.int32)  # 169
    fc_weights = np.array(weights[9:], dtype=np.int32).reshape(10, 169)
    # bias addressing in hardware: digit_counter + 1 → biases[1..10]
    fc_bias = np.array(biases[1:11], dtype=np.int32)

    scores = (fc_weights * flat[np.newaxis, :]).sum(axis=1) + fc_bias
    print("\nFC scores per digit:")
    for d, s in enumerate(scores):
        marker = " <-- argmax" if d == int(np.argmax(scores)) else ""
        print(f"  digit {d}: {s:>14d}{marker}")

    print("\nPredicted digit:", int(np.argmax(scores)))


if __name__ == "__main__":
    main()
