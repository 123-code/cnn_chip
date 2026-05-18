# Tiny CNN Chip running MNIST in Verilog

A Verilog-based Convolutional Neural Network (CNN) accelerator, designed to process MNIST images. This hardware accelerator takes advantage of parallel processing capabilities in FPGAs/ASICs to speed up inference times for a CNN.

## Overview

## Top level layout:

Host PC (Python Script)
                        ▲   │
             tx_out     │   │ rx_in
            (serial)    │   │ (serial)
                        │   ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ Tang Nano 20K Boundary                                      │
 │                                                             │
 │  ┌────────────┐               ┌──────────────────────────┐  │
 │  │            │rx_byte[7:0]   │                          │  │
 │  │ UART RX/TX ├──────────────▶│     Input Image SRAM     │  │
 │  │            │   write_en    │ (Single-Port, Hard IP)   │  │
 │  └─────▲──────┘               └─────────────▲────────────┘  │
 │        │                                    │               │
 │        │                               read_addr[9:0]       │
 │        │pred_digit[3:0]                     │               │
 │        │tx_start      ┌───────────────┐     │               │
 │        │              │               │─────┘               │
 │        │              │ Main Control  │                     │
 │        │              │      FSM      │rom_addr[15:0],read_en
 │        │              │               │─────┐               │
 │        │              └───────┬───────┘     │               │
 │        │   start_layer (held) │             ▼               │
 │        │   layer_type         │  ┌───────────────────────┐  │
 │        │                      │  │   Weights pROM (IP)   │  │
 │        │      layer_done      │  ├───────────────────────┤  │
 │        │                      ▼  │    Bias pROM (IP)     │  │
 │  ┌─────┴─────────────────────────┴───────────────────────┐  │
 │  │                                                       │  │
 │  │       Compute Pipeline (Conv -> Pool -> FC)           │◀─┼─ weight_val[7:0]
 │  │                                                       │◀─┼─ bias_val[31:0]
 │  └────────────────────────────▲──────────────────────────┘  │
 │                               │                             │
 │                         pixel_val[7:0]                      │
 └─────────────────────────────────────────────────────────────┘

## Compute Pipeline:

[ Input Image SRAM ]                [ Weight pROM ]
          │                                 │
    pixel_val[7:0]                    weight_val[7:0]
          │                                 │
          ▼                                 ▼
       ┌───────────────────────────────────────┐
       │             MULTIPLIER                │ <--- (Only ONE multiplier left)
       └──────────────────┬────────────────────┘
                          │
                   (16-bit signed)
                          │
                          ▼
       ┌───────────────────────────────────────┐
 ┌───▶ │               ADDER                   │ <--- (Replaces the entire 8-adder tree)
 │     └──────────────────┬────────────────────┘
 │                        │
 │                        ▼
 │     ┌───────────────────────────────────────┐
 └─────┤         ACCUMULATOR REGISTER          │
       └──────────────────┬────────────────────┘
                          │
                          │ (Outputs only after 9 tap cycles)
                          ▼
                  [ ReLU & >> 8 ]
                          │
                          ▼
                    conv_out[7:0]


## Compute Pipeline (FC & Bias)

[ Max Pool Pipeline ]               [ Weight pROM ]
          │                                 │
   pool_pixel_val[7:0]                weight_val[7:0]
          │                                 │
          ▼                                 ▼
       ┌───────────────────────────────────────┐
       │             MULTIPLIER                │
       └──────────────────┬────────────────────┘
                          │
                          ▼
       ┌───────────────────────────────────────┐
 ┌───▶ │               ADDER                   │
 │     └──────────────────┬────────────────────┘
 │                        │
 └─────[   FC Accumulator Register (32-bit)    ]
                          │
                          │ (After all 169 FC weights are summed for a digit)
                          ▼
       ┌───────────────────────────────────────┐         [ Bias pROM ]
       │            FINAL BIAS ADDER           │ <───────  bias_val[31:0]
       └──────────────────┬────────────────────┘
                          │
                          ▼
                 (Total Score + Bias)
                          │
                          ▼
       ┌───────────────────────────────────────┐
       │           ARGMAX COMPARATOR           │
       │    (if Score > highest_score)         │ ────▶ [ predicted_digit ]
       └───────────────────────────────────────┘

       
## Simulation & Testing

The project includes testbenches (`tb_top.v`) and can be simulated using Icarus Verilog (`sim.vvp`). Resulting waveforms (`waveform.vcd`) can be viewed using GTKWave.

## Physical Constraints

The `pins.cst` file contains physical constraints, indicating it is likely targeted for a specific FPGA platform (such as Gowin).
