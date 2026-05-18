# Open the hex file we generated way back at the start
with open("test_image.hex", "r") as f:
    lines = [l.strip() for l in f if l.strip()]

# Write the strict Gowin .mi format
with open("image.mi", "w") as f:
    f.write("#File_format=Hex\n")
    f.write("#Address_depth=784\n")
    f.write("#Data_width=8\n")
    for val in lines:
        f.write(val + "\n")
        
print("Success! image.mi created.")
