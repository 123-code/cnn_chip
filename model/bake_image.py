"""Bake an MNIST test image into mem_image_ram.v (Gowin SP IP).

Usage: python bake_image.py <digit>
       e.g. python bake_image.py 7

Picks the first test-set sample with that label, finds one the trained
model classifies correctly (so the demo never silently misclassifies),
and patches the INIT_RAM_xx defparams in mem_image_ram.v.
"""
import os
import re
import sys
import numpy as np
from torchvision import datasets, transforms

GOWIN_SRC = "/Applications/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/bin/cnn_chip/src"
SRAM_V = f"{GOWIN_SRC}/gowin_sp/mem_image_ram.v"

if len(sys.argv) != 2:
    sys.exit("usage: bake_image.py <digit 0-9>")
target_digit = int(sys.argv[1])

ds = datasets.MNIST(root="/Users/joseignacio/cnn_chip/model/data",
                    train=False, download=False, transform=transforms.ToTensor())

# Load the same quantized weights/biases the FPGA uses, so we can
# pre-check that the model classifies a candidate correctly before baking.
def load_mi(path, w):
    out = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            v = int(s, 16)
            if v & (1 << (w - 1)):
                v -= 1 << w
            out.append(v)
    return out

weights = load_mi("/Users/joseignacio/cnn_chip/weights.mi", 8)
biases  = load_mi("/Users/joseignacio/cnn_chip/model/bias.mi", 32)
conv_w  = np.array(weights[:9], dtype=np.int32).reshape(3, 3)
fc_w    = np.array(weights[9:9 + 169 * 10], dtype=np.int32).reshape(10, 169)
fc_b    = np.array(biases[1:11], dtype=np.int32)

def predict_chip(px28):
    img = px28.astype(np.int32)
    conv_out = np.zeros((26, 26), dtype=np.int32)
    for oy in range(26):
        for ox in range(26):
            acc = int((img[oy:oy + 3, ox:ox + 3] * conv_w).sum())
            conv_out[oy, ox] = 0 if acc < 0 else min(acc >> 8, 255)
    pool = conv_out.reshape(13, 2, 13, 2).max(axis=(1, 3)).flatten().astype(np.int32)
    scores = (fc_w * pool[None, :]).sum(axis=1) + fc_b
    return int(np.argmax(scores))

# Find the FIRST sample with the requested label that the chip predicts correctly.
picked_idx = None
for idx in range(len(ds)):
    img, lbl = ds[idx]
    if lbl != target_digit:
        continue
    px = (img.squeeze().numpy() * 255).round().astype(int).clip(0, 255)
    if predict_chip(np.array(px, dtype=np.int32)) == target_digit:
        pixels = px
        picked_idx = idx
        print(f"Picked MNIST test image #{idx} "
              f"(label {target_digit}, chip predicts {target_digit} ✓)")
        break
if picked_idx is None:
    sys.exit(f"No digit-{target_digit} sample in the test set classifies correctly. "
             f"Retrain the model.")

# Show the image as ASCII so the demo viewer sees what we're sending in
print(f"\nSent:")
print("┌" + "──" * 28 + "┐")
for row in pixels:
    line = "│"
    for v in row:
        if   v > 192: line += "██"
        elif v > 128: line += "▓▓"
        elif v >  64: line += "▒▒"
        elif v >  16: line += "░░"
        else:         line += "  "
    line += "│"
    print(line)
print("└" + "──" * 28 + "┘")

# Pad to 25 INIT_RAM_xx words of 32 bytes each (800 bytes total, 784 used)
flat = pixels.flatten().tolist() + [0] * (25 * 32 - 784)

with open(SRAM_V) as f:
    content = f.read()
for w in range(25):
    chunk = flat[w * 32 : (w + 1) * 32]
    hex_str = "".join(f"{b:02X}" for b in reversed(chunk))
    pat = re.compile(
        r"defparam sp_inst_0\.INIT_RAM_" + f"{w:02X}" +
        r"\s*=\s*256'h[0-9A-Fa-f]+;"
    )
    new = f"defparam sp_inst_0.INIT_RAM_{w:02X} = 256'h{hex_str};"
    content = pat.sub(new, content)
with open(SRAM_V, "w") as f:
    f.write(content)
print(f"Patched {SRAM_V}")
print(f"\nFPGA should light up (active-low: bit=1 → LED ON):")
b = target_digit
print(f"  ● led[5]  blinking heartbeat")
print(f"  {'●' if (b >> 3) & 1 else '○'} led[4]  bit 3 of prediction")
print(f"  ● led[3]  math_done")
for i in [2, 1, 0]:
    mark = '●' if (b >> i) & 1 else '○'
    print(f"  {mark} led[{i}]  bit {i} of prediction")
print(f"\n→ predicted_digit = {b:04b} = {b}")
