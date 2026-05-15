import torch
import torch.nn as nn
from torchvision import datasets, transforms
from torch.utils.data import DataLoader
import numpy as np

from train import HardwareCNN

transform = transforms.Compose([transforms.ToTensor()])
test_dataset = datasets.MNIST(root='./data', train=False, download=True, transform=transform)
test_loader = DataLoader(test_dataset, batch_size=1000, shuffle=False)

train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
train_loader = DataLoader(train_dataset, batch_size=64, shuffle=True)

model = HardwareCNN()
criterion = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

print("Training for 1 epoch...")
model.train()
for batch_idx, (data, target) in enumerate(train_loader):
    optimizer.zero_grad()
    output = model(data)
    loss = criterion(output, target)
    loss.backward()
    optimizer.step()

def evaluate(model, loader):
    model.eval()
    correct = 0
    with torch.no_grad():
        for data, target in loader:
            output = model(data)
            pred = output.argmax(dim=1, keepdim=True)
            correct += pred.eq(target.view_as(pred)).sum().item()
    return 100. * correct / len(loader.dataset)

print(f"Float32 Accuracy (with bias): {evaluate(model, test_loader):.2f}%")

# Create a quantized version
quantized_model = HardwareCNN()
with torch.no_grad():
    # Zero out biases since hardware doesn't use them
    quantized_model.conv1.bias.zero_()
    quantized_model.fc.bias.zero_()
    
    # Quantize Conv1
    conv_w = model.conv1.weight.detach().numpy()
    conv_max = np.max(np.abs(conv_w))
    conv_scale = 127.0 / conv_max if conv_max > 0 else 1.0
    q_conv_w = np.round(conv_w * conv_scale) / conv_scale # Simulated quantization
    quantized_model.conv1.weight.copy_(torch.from_numpy(q_conv_w).float())
    
    # Quantize FC
    fc_w = model.fc.weight.detach().numpy()
    fc_max = np.max(np.abs(fc_w))
    fc_scale = 127.0 / fc_max if fc_max > 0 else 1.0
    q_fc_w = np.round(fc_w * fc_scale) / fc_scale # Simulated quantization
    quantized_model.fc.weight.copy_(torch.from_numpy(q_fc_w).float())

print(f"Quantized INT8 Accuracy (no bias): {evaluate(quantized_model, test_loader):.2f}%")

