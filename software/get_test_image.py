import torch
from torchvision import datasets, transforms
import numpy as np

# Load the test dataset
transform = transforms.Compose([transforms.ToTensor()])
test_dataset = datasets.MNIST(root='./data', train=False, download=True, transform=transform)

# Grab the very first image in the test set
image, label = test_dataset[0]

# Convert the 0.0-1.0 floats back to 0-255 integers
pixels = (image.squeeze().numpy() * 255).astype(int)

# Save to a hex file
with open("../test_image.hex", "w") as f:
    for p in pixels.flatten():
        f.write(format(p, '02X') + "\n")

print(f"Saved test_image.hex to the root folder!")
print(f"SPOILER ALERT: The image is a handwritten '{label}'.")
