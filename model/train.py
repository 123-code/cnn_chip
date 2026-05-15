import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader
import numpy as np
import os

# ==========================================
# 1. Define the Hardware-Accurate Model
# ==========================================
class HardwareCNN(nn.Module):
    def __init__(self):
        super(HardwareCNN, self).__init__()
        # 1 input channel, 1 output channel, 3x3 kernel
        self.conv1 = nn.Conv2d(1, 1, kernel_size=3, stride=1, padding=0)
        self.relu = nn.ReLU()
        # 2x2 max pool, stride 2
        self.pool = nn.MaxPool2d(kernel_size=2, stride=2)
        # 169 inputs (13x13x1), 10 outputs (digits 0-9)
        self.fc = nn.Linear(169, 10)

    def forward(self, x):
        x = self.conv1(x)
        x = self.relu(x)
        x = self.pool(x)
        x = torch.flatten(x, 1) 
        x = self.fc(x)
        return x

# ==========================================
# 2. Get the Data! (The Missing Piece)
# ==========================================
print("Downloading and formatting MNIST dataset...")

# Neural networks like data scaled between 0 and 1, not 0 and 255.
transform = transforms.Compose([transforms.ToTensor()])

# Download the training data
train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
train_loader = DataLoader(train_dataset, batch_size=64, shuffle=True)

# Instantiate the model, loss function, and optimizer
model = HardwareCNN()
criterion = nn.CrossEntropyLoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)

# ==========================================
# 3. Train the Model
# ==========================================
print("Starting Training (1 Epoch for proof-of-concept)...")
model.train()

# We only run 1 epoch just to get some trained weights quickly. 
# You can increase this later to get better accuracy!
for batch_idx, (data, target) in enumerate(train_loader):
    optimizer.zero_grad()
    output = model(data)
    loss = criterion(output, target)
    loss.backward()
    optimizer.step()
    
    if batch_idx % 100 == 0:
        print(f"Batch {batch_idx}/{len(train_loader)} | Loss: {loss.item():.4f}")

print("Training Complete!")

# ==========================================
# 4. Hardware Co-Design: Quantize and Export
# ==========================================
print("Crushing Float32 down to INT8 for the Tang Nano FPGA...")

def export_to_hex(model, filename="weights.hex"):
    with open(filename, "w") as f:
        # --- 1. Export Convolution Weights (9 values) ---
        # Get the weights and convert them to a numpy array
        conv_weights = model.conv1.weight.detach().numpy().flatten()
        
        # Find the absolute maximum value to scale everything to INT8 (-128 to 127)
        conv_max = np.max(np.abs(conv_weights))
        conv_scale = 127.0 / conv_max if conv_max > 0 else 1.0
        
        f.write("// --- CONV LAYER WEIGHTS (3x3) ---\n")
        for w in conv_weights:
            # Quantize: multiply by scale, round to nearest integer
            q_w = int(np.round(w * conv_scale))
            # Convert to 8-bit Two's Complement Hexadecimal
            hex_w = format(q_w & 0xFF, '02X') 
            f.write(f"{hex_w}\n")
            
        # --- 2. Export Fully Connected Weights (1690 values) ---
        fc_weights = model.fc.weight.detach().numpy().flatten()
        fc_max = np.max(np.abs(fc_weights))
        fc_scale = 127.0 / fc_max if fc_max > 0 else 1.0
        
        f.write("// --- FC LAYER WEIGHTS (169 inputs * 10 outputs) ---\n")
        for w in fc_weights:
            q_w = int(np.round(w * fc_scale))
            hex_w = format(q_w & 0xFF, '02X')
            f.write(f"{hex_w}\n")

    print(f"Success! Saved {filename}. You can now load this into the Gowin IP Core Generator.")

# Run the exporter
export_to_hex(model)