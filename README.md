# Tiny CNN Chip running MNIST in Verilog

End-to-end MNIST digit-classifier on a **Tang Nano 20K** (Gowin GW2AR-18) FPGA. A tiny CNN — one 3×3 conv channel, ReLU, 2×2 max-pool, and a 169→10 fully connected layer — runs entirely on-chip in fixed-point INT8 arithmetic. Trained in PyTorch, quantized, and loaded into on-chip BSRAM/pROM blocks.

## Demo

https://github.com/123-code/cnn_chip/raw/main/media/demo.mov

The terminal shows the input image as ASCII art, then the FPGA's LEDs light up to spell the predicted digit in binary (active-low: lit LED = 1 bit). See `demo_flash.sh` to reproduce.

Two flavors of the design live in this repo, sharing the same compute datapath:

- **LED version** — image baked into the bitstream; result shown on six on-board LEDs. Headless "power on → see the answer" demo.
- **UART version** — image streamed in over UART at runtime; result sent back as one byte. Used for development and batch verification from a host PC.

## Accuracy

| Model                                                    | Test set         | Accuracy |
|----------------------------------------------------------|------------------|---------:|
| PyTorch float32 (CPU)                                    | MNIST test (10000) | **91.80%** |
| PyTorch float32 (CPU)                                    | 50 sampled images  | 96.0%      |
| **FPGA chip** (INT8 quantized, fixed-point)              | 50 sampled images  | **94.0%**  |

The chip accuracy was produced by a bit-accurate simulator (`model/hw_sim.py`) that performs the *exact same* fixed-point operations the FPGA does and reads the *exact same* `.mi` byte streams the FPGA loads into its ROMs at config time. We separately validated the simulator against the real hardware: the live FPGA classifies each individual image to the same digit the simulator predicts. See `model/batch_meta.json` for the full per-image breakdown.

The quantization gap (chip 94.0% vs CPU 96.0% on the same 50 images) is the cost of compressing the model to INT8 weights + an `acc >> 8` activation scale that fits in a `acc[15:8]` output byte. Larger models with more channels could close this gap.

---

## Top level layout

```
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
```

## Conv pipeline (serial scan, 1 multiplier)

```
[ Input Image SRAM ]                [ Weight pROM ]
          │                                 │
    pixel_val[7:0]                    weight_val[7:0]
          │                                 │
          ▼                                 ▼
       ┌───────────────────────────────────────┐
       │             MULTIPLIER                │ ◀── (Only ONE multiplier)
       └──────────────────┬────────────────────┘
                          │
                   (16-bit signed)
                          │
                          ▼
       ┌───────────────────────────────────────┐
 ┌───▶ │               ADDER                   │ ◀── (Replaces an 8-adder tree)
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
```

## FC pipeline (per-digit dot product + bias + argmax)

```
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
                          │ (After all 169 FC weights summed for one digit)
                          ▼
       ┌───────────────────────────────────────┐         [ Bias pROM ]
       │            FINAL BIAS ADDER           │ ◀───────  bias_val[31:0]
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
```

---

## Memory layout

| ROM/RAM           | Depth | Width | Contents                                      |
|-------------------|-------|-------|-----------------------------------------------|
| `mem_image_ram`   | 784   | 8     | 28×28 uint8 image                             |
| `weights_rom`     | 1699  | 8     | Addr 0–8: conv 3×3 kernel · Addr 9–1698: FC weights (169 × 10 digits, row-major) |
| `bias_rom`        | 11    | 32    | Addr 0: unused placeholder · Addr 1–10: FC biases (int32, two's complement) |

LED version uses Gowin **SP**/**pROM** hard IPs with `.mi` init files. UART version uses inferred `reg`-array memories with `$readmemh`.

## Quantization & hardware/software contract

The Python model is float32. The FPGA is fixed-point. To make them match, the training script enforces several constraints that aren't optional:

| Constraint | Why |
|---|---|
| `nn.Conv2d(..., bias=False)` | Hardware conv MAC chain has no bias adder; a learned conv bias would be silently dropped. |
| Pixel input scale: float [0,1] → uint8 [0,255] | `transforms.ToTensor()` gives float; FPGA reads bytes. Implicit ×255 scale. |
| Conv weight quantization: `round(w * 127/max(|w|))` to int8 | Symmetric per-tensor INT8. |
| Conv output: `(acc >> 8)` clamped to [0,255] after ReLU | Drops 8 bits ≈ ÷256 — accommodates accumulated 9-MAC range. |
| FC bias quantization: `round(b * fc_scale * conv_scale * 255/256)` | FC bias is added to a hardware accumulator that's already at scale `conv_scale × fc_scale`. Scaling biases by `fc_scale` alone (the obvious choice) makes them ~100× too small. |

## Why a serial conv instead of a sliding-window MAC array

An earlier prototype (`compute_pipeline/conv_sliding_win.v` + `mac_array_3x3.v`, kept in the repo for reference) used two 28-deep line buffers, a 3×3 register window, and 9 parallel multipliers — 1 output pixel per cycle. The current `conv_serial.v` walks the output grid sequentially with a single multiplier and an address-based pixel fetch — ~27 cycles per output pixel.

|                     | Sliding-window     | Serial scan        |
|---------------------|--------------------|--------------------|
| Multipliers in conv | 9                  | 1                  |
| Line-buffer storage | ~56 B              | 0                  |
| Conv throughput     | 1 px/cyc           | ~27 cyc/px         |
| Total inference     | ~few k cycles      | ~10–30 k cycles    |
| At 27 MHz           | ~100 µs            | ~700 µs            |

For one-shot MNIST inference on a tiny FPGA, both finish faster than a human can blink. The serial design wins because it costs roughly 10× less fabric.

## Power-on reset (both versions)

The Tang Nano 20K's reset button reads stuck-low on the board we tested. To avoid holding the design in permanent reset, the top module synthesizes its own POR:

```verilog
reg [3:0] por_cnt = 4'd0;
reg       safe_rst_n_r = 1'b0;
always @(posedge clk) begin
    if (por_cnt != 4'd15) begin
        por_cnt      <= por_cnt + 4'd1;
        safe_rst_n_r <= 1'b0;
    end else begin
        safe_rst_n_r <= 1'b1;
    end
end
wire safe_rst_n = safe_rst_n_r;
```

This matters more than it looks. Without a real reset pulse Gowin's synthesizer leaves some FFs at undefined power-on values — most damagingly `fc_layer.highest_score`, which needs to start at `-2 × 10⁹` for the argmax comparison to work. Standalone `initial begin … end` blocks turned out to be unreliable on this toolchain; inline-declaration initializers (`reg [3:0] x = 4'd0;`) and a real reset pulse work.

---

## Repository layout

```
.
├── top_mnist_accel.v          # UART-version top (this dir is the UART build)
├── control_unit.v             # UART FSM: IDLE → LOAD_IMG → COMPUTE → TX_RESULT
├── compute_pipeline/
│   ├── compute_pipeline.v     # conv + pool + fc orchestration, ROM/SRAM muxing
│   ├── conv_serial.v          # serial 3×3 convolution
│   ├── max_pool_2x2.v         # streaming 2×2 max-pool
│   ├── fc_layer.v             # 169→10 FC, argmax with bias
│   ├── conv_sliding_win.v     # legacy parallel conv (unused, kept for reference)
│   └── mac_array_3x3.v        # legacy 9-mul MAC tree (unused)
├── mem_image_ram.v            # 784×8 inferred RAM (UART writes, compute reads)
├── mem_weights_rom.v          # 1699×8 weights + 11×32 biases, $readmemh
├── uart_rx.v · uart_tx.v      # 115200-baud serial peripherals
├── pins.cst                   # Tang Nano 20K pin mapping
├── tb_top.v                   # iverilog testbench (sends 784 bytes via UART)
├── weights.hex / weights.mi   # quantized weight ROM (.hex for $readmemh, .mi for Gowin IP)
├── bias.hex / model/bias.mi   # quantized FC bias ROM
├── image.mi                   # currently-loaded test image (28×28 bytes)
├── model/
│   ├── train.py               # PyTorch model + quantization + ROM export
│   └── hw_sim.py              # Python hardware-accurate inference simulator
└── software/
    └── send_image.py          # host-side serial driver for the UART version
```

LED-version sources live separately under the Gowin project tree. They are the same modules with two differences: the top uses LEDs/baked image instead of UART/streamed image, and the memories are Gowin SP/pROM hard IPs instead of inferred RAM.

---

## Building & running

### Train and export weights

```bash
python -m venv venv
source venv/bin/activate
pip install torch torchvision numpy
python model/train.py        # writes model/weights.hex and model/bias.mi
```

### Simulate with Icarus Verilog

```bash
iverilog -g2012 -o sim.vvp \
  tb_top.v top_mnist_accel.v control_unit.v \
  compute_pipeline/compute_pipeline.v \
  compute_pipeline/conv_serial.v \
  compute_pipeline/max_pool_2x2.v \
  compute_pipeline/fc_layer.v \
  mem_image_ram.v mem_weights_rom.v \
  uart_rx.v uart_tx.v
vvp sim.vvp
gtkwave waveform.vcd
```

`model/hw_sim.py` runs the same fixed-point math in Python against the same `.mi` byte streams — useful for verifying *what the hardware should predict* before reflashing.

### Synthesize for Tang Nano 20K

1. Open the Gowin project — or create a new one targeting `GW2AR-LV18QN88C8/I7` with the Verilog sources from this tree and `pins.cst`.
2. Regenerate the SP/pROM IPs pointing at `image.mi`, `weights.mi`, `bias.mi`.
3. Synthesize → Place & Route → Program Device.

### Run inference (UART version)

```bash
# Opens /dev/tty.usbserial-* at 115200, sends 784 bytes, reads 1 byte back.
python software/send_image.py path/to/digit.png
```

### Run inference (LED version)

Power on. Wait 1 s. Read LEDs:

| LED | Meaning                                          |
|-----|--------------------------------------------------|
| 5   | Heartbeat (toggles ≈3 Hz; confirms FPGA clocking)|
| 4   | Before math: `~fsm_started` · After math: `~predicted_digit[3]` |
| 3   | `~math_done` (on = math finished)               |
| 2:0 | `~predicted_digit[2:0]`                          |

LEDs are active-low — output `0` lights the LED. Example: digit 7 = `0111` → LEDs 0/1/2 ON, 3 ON, 4 OFF, 5 blinking.

---

## Bringup notes

Things that bit us during bringup, preserved here so they don't bite again:

- **Dead reset paths don't bake INIT values on Gowin.** Hardwiring `safe_rst_n = 1'b1` makes every `if (!rst_n) … else …` block dead code, and Gowin won't extract the reset values as FF init attributes. Use a POR counter.
- **FC weight fetch had a 1-cycle off-by-one.** ROM is bypass-mode (1-cycle latency); the FSM was setting `rom_addr_out <= 9` and burning a cycle in `S_WAIT_ROM`, so `buffer[0]` got multiplied by `weights[10]` instead of `weights[9]`. Fix: start at `8`.
- **FC argmax needs to be seeded.** Without `if (digit_counter == 0 || score > highest_score)`, an image where all 10 dot products are negative leaves `winning_digit` stuck at its init value.
- **The hardware has no conv bias adder.** Training with `bias=True` on `nn.Conv2d` silently throws away a learned parameter and corrupts ReLU thresholds.
- **FC bias must be scaled by `conv_scale × fc_scale`**, not just `fc_scale`, because it adds into an already-scaled accumulator.
- **`predicted_digit` is 4 bits but the board has 6 LEDs.** Wire the high bit to LED4 (mux'd with `fsm_started` pre-math) or you can't distinguish 0/8, 1/9, 2/10.

---

## Physical constraints

The `pins.cst` file contains the Tang Nano 20K pin mapping (clock at pin 4, LEDs at pins 15–20, UART/reset pins as configured).

## License

MIT.
