"""Pick N MNIST test images, bake them into images_batch.hex (for $readmemh in
mem_image_batch.v), and record their ground-truth labels so the host can
compute accuracy. Also computes:
  - CPU accuracy: PyTorch float32 model on the full test set
  - Chip-expected accuracy: hw_sim on the N picked images (bit-accurate to FPGA)
"""
import os
import sys
import numpy as np
import torch
from torchvision import datasets, transforms

N = 50

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')

print(f"Loading MNIST test set...")
test_ds = datasets.MNIST(root=DATA, train=False, download=False,
                         transform=transforms.ToTensor())

# Pick first N images
selected = list(range(N))

# Hex file for $readmemh
batch_hex = os.path.join(os.path.dirname(HERE), 'images_batch.hex')
labels = []
with open(batch_hex, 'w') as f:
    for i in selected:
        img, lbl = test_ds[i]
        pixels = (img.squeeze().numpy() * 255).round().astype(int).clip(0, 255)
        f.write(f"// image {i} label {lbl}\n")
        for v in pixels.flatten():
            f.write(f"{int(v):02X}\n")
        labels.append(int(lbl))

with open(os.path.join(HERE, 'batch_labels.txt'), 'w') as f:
    for lbl in labels:
        f.write(f"{lbl}\n")

print(f"Wrote {batch_hex} with {N} images")
print(f"Labels: {labels}")

# === CPU accuracy (PyTorch float32 model) on the same N images
# Recreate the model exactly as train.py
import torch.nn as nn
class HardwareCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 1, kernel_size=3, stride=1, padding=0, bias=False)
        self.relu  = nn.ReLU()
        self.pool  = nn.MaxPool2d(kernel_size=2, stride=2)
        self.fc    = nn.Linear(169, 10)
    def forward(self, x):
        x = self.conv1(x); x = self.relu(x); x = self.pool(x)
        x = torch.flatten(x, 1); x = self.fc(x); return x

# Re-train quickly OR load weights from .mi files. Simpler: just retrain in
# memory using the same train.py logic.
from torch.utils.data import DataLoader
import torch.optim as optim

print("\nRetraining quickly (3 epochs) for the CPU baseline...")
model = HardwareCNN()
opt = optim.Adam(model.parameters(), lr=0.001)
crit = nn.CrossEntropyLoss()
train_ds = datasets.MNIST(root=DATA, train=True, download=False,
                          transform=transforms.ToTensor())
train_dl = DataLoader(train_ds, batch_size=64, shuffle=True)
model.train()
for ep in range(3):
    for data, target in train_dl:
        opt.zero_grad()
        out = model(data); loss = crit(out, target)
        loss.backward(); opt.step()
    print(f"  epoch {ep+1} done")

# CPU accuracy on FULL test set
model.eval()
test_dl = DataLoader(test_ds, batch_size=1000)
correct_full = 0
with torch.no_grad():
    for data, target in test_dl:
        pred = model(data).argmax(dim=1)
        correct_full += (pred == target).sum().item()
acc_cpu_full = 100.0 * correct_full / len(test_ds)
print(f"\nCPU (float32 PyTorch) accuracy on full 10000-image test set: {acc_cpu_full:.2f}%")

# CPU accuracy on the N picked
correct_n = 0
preds_cpu = []
for i in selected:
    img, lbl = test_ds[i]
    p = model(img.unsqueeze(0)).argmax(dim=1).item()
    preds_cpu.append(p)
    if p == lbl: correct_n += 1
acc_cpu_n = 100.0 * correct_n / N
print(f"CPU (float32 PyTorch) accuracy on the {N} picked images: {acc_cpu_n:.1f}%")

# Now export quantized weights/biases that match this trained model
import json
def export():
    conv_w = model.conv1.weight.detach().numpy().flatten()
    fc_w   = model.fc.weight.detach().numpy().flatten()
    fc_b   = model.fc.bias.detach().numpy()
    conv_scale = 127.0 / max(np.max(np.abs(conv_w)), 1e-9)
    fc_scale   = 127.0 / max(np.max(np.abs(fc_w)),   1e-9)
    bias_scale = (255.0/256.0) * conv_scale * fc_scale

    # weights.hex
    with open(os.path.join(os.path.dirname(HERE), 'weights.hex'), 'w') as f:
        for w in conv_w: f.write(f"{int(round(w*conv_scale)) & 0xFF:02X}\n")
        for w in fc_w:   f.write(f"{int(round(w*fc_scale))   & 0xFF:02X}\n")
    # bias.hex
    with open(os.path.join(os.path.dirname(HERE), 'bias.hex'), 'w') as f:
        f.write("00000000\n")
        for b in fc_b:
            f.write(f"{int(round(b*bias_scale)) & 0xFFFFFFFF:08X}\n")
    # also .mi for Gowin
    with open(os.path.join(os.path.dirname(HERE), 'weights.mi'), 'w') as f:
        f.write(f"#File_format=Hex\n#Address_depth={len(conv_w)+len(fc_w)}\n#Data_width=8\n")
        for w in conv_w: f.write(f"{int(round(w*conv_scale)) & 0xFF:02X}\n")
        for w in fc_w:   f.write(f"{int(round(w*fc_scale))   & 0xFF:02X}\n")
    with open(os.path.join(HERE, 'bias.mi'), 'w') as f:
        f.write(f"#File_format=Hex\n#Address_depth={len(fc_b)+1}\n#Data_width=32\n")
        f.write("00000000\n")
        for b in fc_b: f.write(f"{int(round(b*bias_scale)) & 0xFFFFFFFF:08X}\n")
    return conv_scale, fc_scale

conv_scale, fc_scale = export()
print(f"\nExported weights/bias .hex and .mi  (conv_scale={conv_scale:.2f}, fc_scale={fc_scale:.2f})")

# Chip-expected accuracy via hw_sim math on the N picked images
def predict_chip(pixels28):
    img = pixels28.astype(np.int32)
    # Conv
    conv_w_q = np.array(
        [int(round(w*conv_scale)) for w in model.conv1.weight.detach().numpy().flatten()],
        dtype=np.int32
    ).reshape(3,3)
    conv_out = np.zeros((26,26), dtype=np.int32)
    for oy in range(26):
        for ox in range(26):
            acc = int((img[oy:oy+3, ox:ox+3] * conv_w_q).sum())
            conv_out[oy, ox] = 0 if acc < 0 else min(acc >> 8, 255)
    pool = conv_out.reshape(13,2,13,2).max(axis=(1,3)).flatten().astype(np.int32)
    fc_w_q = np.array(
        [int(round(w*fc_scale)) for w in model.fc.weight.detach().numpy().flatten()],
        dtype=np.int32
    ).reshape(10, 169)
    bs = (255.0/256.0) * conv_scale * fc_scale
    fc_b_q = np.array([int(round(b*bs)) for b in model.fc.bias.detach().numpy()], dtype=np.int32)
    scores = (fc_w_q * pool[None,:]).sum(axis=1) + fc_b_q
    return int(np.argmax(scores))

print("\nChip-expected predictions (bit-accurate sim of the FPGA):")
correct_chip = 0
preds_chip = []
for idx, i in enumerate(selected):
    img, lbl = test_ds[i]
    px = (img.squeeze().numpy() * 255).round().astype(np.int32).clip(0, 255)
    p = predict_chip(px)
    preds_chip.append(p)
    if p == lbl: correct_chip += 1
acc_chip_n = 100.0 * correct_chip / N
print(f"  Chip (bit-accurate sim) accuracy on {N} images: {acc_chip_n:.1f}%")

# Save predictions and labels for comparison after the FPGA runs
import json
with open(os.path.join(HERE, 'batch_meta.json'), 'w') as f:
    json.dump({
        'N': N,
        'selected_indices': selected,
        'labels': labels,
        'preds_cpu': preds_cpu,
        'preds_chip_sim': preds_chip,
        'acc_cpu_full': acc_cpu_full,
        'acc_cpu_picked': acc_cpu_n,
        'acc_chip_sim_picked': acc_chip_n,
    }, f, indent=2)

print(f"\nSummary:")
print(f"  CPU (float32, full 10k):   {acc_cpu_full:.2f}%")
print(f"  CPU (float32, picked {N}): {acc_cpu_n:.1f}%")
print(f"  Chip sim (picked {N}):     {acc_chip_n:.1f}%   ← the FPGA should match this")
