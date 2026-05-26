Tiny CNN Chip running MNIST in Verilog
End-to-end MNIST digit-classifier on a Tang Nano 20K (Gowin GW2AR-18) FPGA. A tiny CNN — one 3×3 conv channel, ReLU, 2×2 max-pool, and a 169→10 fully connected layer — runs entirely on-chip in fixed-point INT8 arithmetic. Trained in PyTorch, quantized, and loaded into on-chip BSRAM/pROM blocks.

Demo

https://github.com/123-code/cnn_chip/raw/main/media/demo.mov

The terminal shows the input image as ASCII art, then the FPGA's LEDs light up to spell the predicted digit in binary (active-low: lit LED = 1 bit). See demo_flash.sh to reproduce.

Two flavors of the design live in this repo, sharing the same compute datapath:

LED version — image baked into the bitstream; result shown on six on-board LEDs. Headless "power on → see the answer" demo.
UART version — image streamed in over UART at runtime; result sent back as one byte. Used for development and batch verification from a host PC.
Two versions of the convolution itself ship in this repo, selectable via a Verilog parameter:

v1 (main) — 1-multiplier serial scan. ~27 cycles per output pixel. The original design that shipped to silicon.
v2 (v2-parallel-conv) — 9-multiplier streaming MAC array with 2×28 line buffers and a 3×3 register window. 1 output pixel per cycle. Bit-identical to v1 at the FC output; validated in iverilog (8.25× fewer compute cycles on the same test image) and flashed to the live board.
Accuracy

Model	Test set	Accuracy
PyTorch float32 (CPU)	MNIST test (10000)	91.80%
PyTorch float32 (CPU)	50 sampled images	96.0%
FPGA chip (INT8 quantized, fixed-point)	50 sampled images	94.0%
The chip accuracy was produced by a bit-accurate simulator (model/hw_sim.py) that performs the exact same fixed-point operations the FPGA does and reads the exact same .mi byte streams the FPGA loads into its ROMs at config time. We separately validated the simulator against the real hardware: the live FPGA classifies each individual image to the same digit the simulator predicts. See model/batch_meta.json for the full per-image breakdown.

The quantization gap (chip 94.0% vs CPU 96.0% on the same 50 images) is the cost of compressing the model to INT8 weights + an acc >> 8 activation scale that fits in a acc[15:8] output byte. Larger models with more channels could close this gap.

Top level layout

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
Conv pipeline — v1 (serial scan, 1 multiplier)

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

  ~27 cycles / output pixel · 9 MACs serialized · 0 line-buffer storage
Conv pipeline — v2 (parallel 9-MAC, streaming window)

                  [ Weight pROM ]
                          │
                          ▼
              ┌───────────────────────┐
              │ Preload FSM (~10 cyc) │ — fetch weights[0..8]
              └───────────┬───────────┘
                          ▼
                 w[0..8] (registered)
                          │
[ Input Image SRAM ]      │
          │               │
    pixel_in[7:0]         │
          │               │
          ▼               │
  ┌────────────────┐      │
  │ Line buffer 0  │ (28 deep)
  └────────┬───────┘      │
           ▼              │
  ┌────────────────┐      │
  │ Line buffer 1  │ (28 deep)
  └────────┬───────┘      │
           ▼              │
  ┌────────────────────┐  │
  │ 3×3 register window │ ─┐
  └────────┬────────────┘  │
           ▼               ▼
       ┌──────────────────────────┐
       │   9 PARALLEL MULTIPLIERS │
       └────────────┬─────────────┘
                    │ 9 × 16-bit products
                    ▼
       ┌──────────────────────────┐
       │   8-input ADDER TREE     │ (combinational)
       └────────────┬─────────────┘
                    │
                    ▼
            [ ReLU & >>> 8 ]
                    │
                    ▼
              conv_out[7:0]

  1 cycle / output pixel · 9 parallel MACs · 2 × 28-byte line buffers
  Total conv: ~786 cycles for 26×26 output (vs ~17,000 in v1)
FC pipeline (per-digit dot product + bias + argmax)

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
Memory layout

ROM/RAM	Depth	Width	Contents
mem_image_ram	784	8	28×28 uint8 image
weights_rom	1699	8	Addr 0–8: conv 3×3 kernel · Addr 9–1698: FC weights (169 × 10 digits, row-major)
bias_rom	11	32	Addr 0: unused placeholder · Addr 1–10: FC biases (int32, two's complement)
LED version uses Gowin SP/pROM hard IPs with .mi init files. UART version uses inferred reg-array memories with $readmemh.

Quantization & hardware/software contract

The Python model is float32. The FPGA is fixed-point. To make them match, the training script enforces several constraints that aren't optional:

Constraint	Why
nn.Conv2d(..., bias=False)	Hardware conv MAC chain has no bias adder; a learned conv bias would be silently dropped.
Pixel input scale: float [0,1] → uint8 [0,255]	transforms.ToTensor() gives float; FPGA reads bytes. Implicit ×255 scale.
Conv weight quantization: `round(w * 127/max(	w
Conv output: (acc >> 8) clamped to [0,255] after ReLU	Drops 8 bits ≈ ÷256 — accommodates accumulated 9-MAC range.
FC bias quantization: round(b * fc_scale * conv_scale * 255/256)	FC bias is added to a hardware accumulator that's already at scale conv_scale × fc_scale. Scaling biases by fc_scale alone (the obvious choice) makes them ~100× too small.
v1 → v2: from serial scan to parallel streaming

The chip originally shipped with conv_serial.v — one multiplier, ~27 cycles per output pixel. A parallel conv_sliding_win.v + mac_array_3x3.v design existed in the repo but was set aside; it turned out to contain several real bugs (not polish issues), which is why v1 went with the conservative serial path.

The v2-parallel-conv branch goes back and finishes that work properly:

Bug in the legacy prototype	Fix in v2
mac_array_3x3 added the FC bias into every conv output	Removed — conv has no bias (nn.Conv2d(bias=False))
All 9 weight ports wired to the same weight_in ("simplified for now")	New preload FSM fetches the 9 conv kernel weights into a register file
done fired on the last input pixel — missed the trailing MAC outputs	Explicit 3-cycle drain after last mac_valid_in
No 2-cycle ROM/SRAM latency model — window contents off by one row	All addressing offset for the actual posedge→posedge chain
The new compute_pipeline.v exposes a parameter PARALLEL_CONV (default 1) that selects between the two conv implementations via generate:

compute_pipeline #(.PARALLEL_CONV(1)) u_compute (...);  // v2 (default)
compute_pipeline #(.PARALLEL_CONV(0)) u_compute (...);  // v1
metric (sim, single image)	v1 (serial)	v2 (parallel)
Conv multipliers	1	9
Line-buffer storage	0 B	~56 B
Conv throughput	~27 cyc/px	1 px/cyc
Compute cycles to layer_done	20,632	2,501 (8.25×)
Predicted digit (same image)	5	5 (bit-identical)
For one-shot MNIST inference both finish faster than a human can blink. v2 isn't faster to a user; what it demonstrates is that the parallel datapath actually works on real silicon, end-to-end, with bit-identical math to the serial reference.

Power-on reset (both versions)

The Tang Nano 20K's reset button reads stuck-low on the board we tested. To avoid holding the design in permanent reset, the top module synthesizes its own POR:

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
This matters more than it looks. Without a real reset pulse Gowin's synthesizer leaves some FFs at undefined power-on values — most damagingly fc_layer.highest_score, which needs to start at -2 × 10⁹ for the argmax comparison to work. Standalone initial begin … end blocks turned out to be unreliable on this toolchain; inline-declaration initializers (reg [3:0] x = 4'd0;) and a real reset pulse work.

Repository layout

.
├── top_mnist_accel.v          # UART-version top (this dir is the UART build)
├── control_unit.v             # UART FSM: IDLE → LOAD_IMG → COMPUTE → TX_RESULT
├── compute_pipeline/
│   ├── compute_pipeline.v     # conv + pool + fc orchestration; PARALLEL_CONV parameter selects v1/v2
│   ├── conv_serial.v          # v1: serial 3×3 convolution (1 mul)
│   ├── conv_sliding_win.v     # v2: streaming 3×3 conv (line buffers + 3×3 window)
│   ├── mac_array_3x3.v        # v2: 9-MAC adder tree + ReLU + quantize
│   ├── max_pool_2x2.v         # streaming 2×2 max-pool
│   └── fc_layer.v             # 169→10 FC, argmax with bias
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
LED-version sources live separately under the Gowin project tree. They are the same modules with two differences: the top uses LEDs/baked image instead of UART/streamed image, and the memories are Gowin SP/pROM hard IPs instead of inferred RAM.

Building & running

Train and export weights

python -m venv venv
source venv/bin/activate
pip install torch torchvision numpy
python model/train.py        # writes model/weights.hex and model/bias.mi
Simulate with Icarus Verilog

v1 (serial conv) on main:

iverilog -g2012 -o sim_v1.vvp \
  tb_top.v top_mnist_accel.v control_unit.v \
  compute_pipeline/compute_pipeline.v \
  compute_pipeline/conv_serial.v \
  compute_pipeline/max_pool_2x2.v \
  compute_pipeline/fc_layer.v \
  mem_image_ram.v mem_weights_rom.v \
  uart_rx.v uart_tx.v
vvp sim_v1.vvp
v2 (parallel conv) on v2-parallel-conv:

iverilog -g2012 -o sim_v2.vvp \
  tb_top.v top_mnist_accel.v control_unit.v \
  compute_pipeline/compute_pipeline.v \
  compute_pipeline/conv_serial.v \
  compute_pipeline/conv_sliding_win.v \
  compute_pipeline/mac_array_3x3.v \
  compute_pipeline/max_pool_2x2.v \
  compute_pipeline/fc_layer.v \
  mem_image_ram.v mem_weights_rom.v \
  uart_rx.v uart_tx.v
vvp sim_v2.vvp
tb_top.v prints RESULT predicted_digit=N compute_cycles=N on layer_done. Both builds must predict the same digit on the same image — that's the equivalence check.

model/hw_sim.py runs the same fixed-point math in Python against the same .mi byte streams — useful for verifying what the hardware should predict before reflashing.

Synthesize for Tang Nano 20K

Open the Gowin project — or create a new one targeting GW2AR-LV18QN88C8/I7 with the Verilog sources from this tree and pins.cst.
Regenerate the SP/pROM IPs pointing at image.mi, weights.mi, bias.mi.
Synthesize → Place & Route → Program Device.
Run inference (UART version)

# Opens /dev/tty.usbserial-* at 115200, sends 784 bytes, reads 1 byte back.
python software/send_image.py path/to/digit.png
Run inference (LED version)

Power on. Wait 1 s. Read LEDs:

LED	Meaning
5	Heartbeat (toggles ≈3 Hz; confirms FPGA clocking)
4	Before math: ~fsm_started · After math: ~predicted_digit[3]
3	~math_done (on = math finished)
2:0	~predicted_digit[2:0]
LEDs are active-low — output 0 lights the LED. Example: digit 7 = 0111 → LEDs 0/1/2 ON, 3 ON, 4 OFF, 5 blinking.

Bringup notes

Things that bit us during bringup, preserved here so they don't bite again:

Dead reset paths don't bake INIT values on Gowin. Hardwiring safe_rst_n = 1'b1 makes every if (!rst_n) … else … block dead code, and Gowin won't extract the reset values as FF init attributes. Use a POR counter.
FC weight fetch had a 1-cycle off-by-one. ROM is bypass-mode (1-cycle latency); the FSM was setting rom_addr_out <= 9 and burning a cycle in S_WAIT_ROM, so buffer[0] got multiplied by weights[10] instead of weights[9]. Fix: start at 8.
FC argmax needs to be seeded. Without if (digit_counter == 0 || score > highest_score), an image where all 10 dot products are negative leaves winning_digit stuck at its init value.
The hardware has no conv bias adder. Training with bias=True on nn.Conv2d silently throws away a learned parameter and corrupts ReLU thresholds.
FC bias must be scaled by conv_scale × fc_scale, not just fc_scale, because it adds into an already-scaled accumulator.
predicted_digit is 4 bits but the board has 6 LEDs. Wire the high bit to LED4 (mux'd with fsm_started pre-math) or you can't distinguish 0/8, 1/9, 2/10.
v2 bringup notes

Single-port ROM means the 9 conv weights can't be fetched in parallel. The parallel MAC array needs all 9 weights simultaneously, but mem_weights_rom only delivers one byte per cycle. Solution: a 10-cycle preload FSM that walks ROM addresses 0..8 once at the start of inference and latches into a reg signed [7:0] w [0:8] register file. Streaming then runs from registers, with the ROM idle (free for FC to use later).
The ROM and SRAM both have 2-cycle issue→read latency. Registered output on the memory module + the always-block delay = weight_in(T) = w_rom[rom_addr at end of T-2]. Forgetting this gives every weight an off-by-one and zero correct outputs. The preload schedule has to interleave issues and latches so the first stream cycle sees ram[0] exactly.
Pipeline drain matters. The MAC array has 2 register stages (products → adder tree → output). After the last mac_valid_in pulse, done cannot fire for at least 2 more cycles or the last conv output gets dropped before max-pool can consume it. The current implementation waits 3 cycles to be safe.
Window validity is geometric, not temporal. The 3×3 window's bottom-right corner walks the input in raster order; a valid output requires the corner to be at (row >= 2, col >= 2). When col wraps from 27 → 0 at a row boundary, the leftmost two outputs of the new row are invalid — mac_valid_in must drop. Easy to get wrong by 26 outputs.
Generate-blocks let v1 and v2 coexist. compute_pipeline.v uses a parameter PARALLEL_CONV + generate / if to instantiate either conv_serial or conv_sliding_win. The unused module is optimized out by synthesis — no extra fabric cost — but iverilog still typechecks both branches, so you find dead-code bugs early.
Iverilog testbench at 50 MHz silently breaks UART injection. uart_rx defaults to parameter CLK_FREQ = 27_000_000. The sim testbench clocks the chip at 50 MHz without overriding the parameter, so the receiver samples every bit twice and the FSM transitions to COMPUTE mid-injection with a partially-loaded RAM. Both v1 and v2 sim with this bug, which is why both predict the same "wrong" digit — the v1↔v2 equivalence check works regardless. On real hardware with a 27 MHz clock or the LED-version baked image, the chip predicts correctly.
Physical constraints

The pins.cst file contains the Tang Nano 20K pin mapping (clock at pin 4, LEDs at pins 15–20, UART/reset pins as configured).

License

MIT.
