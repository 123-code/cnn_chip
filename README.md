# CNN Chip

A Verilog-based Convolutional Neural Network (CNN) accelerator, designed to process MNIST images. This hardware accelerator takes advantage of parallel processing capabilities in FPGAs/ASICs to speed up inference times for a CNN.

## Overview

The `cnn_chip` project implements a hardware pipeline for CNN inference. The main components are:

- **Top Level (`top_mnist_accel.v`)**: The primary wrapper for the design, integrating memory, the compute pipeline, UART, and the control unit.
- **Compute Pipeline (`compute_pipeline/`)**: The core arithmetic logic for the neural network.
  - `compute_pipeline.v`: Orchestrates the neural network layers.
  - `conv_sliding_win.v`: Manages the sliding window mechanism for convolutional layers.
  - `mac_array_3x3.v`: A 3x3 Multiply-Accumulate (MAC) array for performing 2D convolutions efficiently.
  - `max_pool_2x2.v`: Applies 2x2 max pooling to downsample feature maps.
  - `fc_layer.v`: A fully connected layer for final classification based on extracted features.
- **Control Unit (`control_unit.v`)**: State machine that orchestrates data flow and pipeline execution.
- **Memory (`mem_image_ram.v`, `mem_weights_rom.v`)**: Modules for storing input images (RAM) and network weights (ROM).
- **UART Interface (`uart_rx.v`, `uart_tx.v`)**: Provides a serial communication interface to send images to the chip and receive predictions back to a host PC.

## Simulation & Testing

The project includes testbenches (`tb_top.v`) and can be simulated using Icarus Verilog (`sim.vvp`). Resulting waveforms (`waveform.vcd`) can be viewed using GTKWave.

## Physical Constraints

The `pins.cst` file contains physical constraints, indicating it is likely targeted for a specific FPGA platform (such as Gowin).
