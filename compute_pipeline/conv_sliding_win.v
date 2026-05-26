// Streaming 3x3 conv with 9 parallel MACs.
//
// Phases:
//   S_IDLE     -> request weight ROM addr 0; queue preload.
//   S_PRELOAD  -> walk ROM addrs 0..8, latch into w[0..8] regs (~10 cycles).
//   S_STREAM   -> walk SRAM addrs 0..783 in raster order, push pixels
//                 through 2 x 28-deep line buffers + 3x3 register window.
//                 Fire mac_valid_in when the window center is at a valid
//                 (row >= 2, col >= 2) position. 784 cycles.
//   S_DRAIN    -> wait for the MAC's 2-stage pipeline to emit the last
//                 output (~3 cycles).
//   S_DONE     -> hold done high.
//
// Latency model (matches mem_image_ram.v and mem_weights_rom.v):
//   At cycle T's posedge, the FSM sees weight_in / pixel_in = the value
//   that was at the corresponding RAM/ROM address at the end of cycle T-2.

module conv_sliding_win (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    input  wire [7:0]         pixel_in,
    input  wire signed [7:0]  weight_in,

    output reg  [9:0]   sram_addr_out,
    output reg  [15:0]  rom_addr_out,

    output wire [7:0]   pixel_out,
    output wire         valid_out,
    output reg          done
);

    localparam S_IDLE    = 3'd0;
    localparam S_PRELOAD = 3'd1;
    localparam S_STREAM  = 3'd2;
    localparam S_DRAIN   = 3'd3;
    localparam S_DONE    = 3'd4;
    reg [2:0] state;

    // Conv kernel weights: 9 signed INT8 values, latched once at start.
    reg signed [7:0] w [0:8];

    reg [3:0] pp;        // preload step counter
    reg [4:0] row_arr;   // row of the pixel arriving in r22 THIS cycle
    reg [4:0] col_arr;   // col of same
    reg [1:0] drain_cnt;

    // 3x3 window registers (post-shift, r22 is the freshest pixel).
    reg [7:0] r00, r01, r02;
    reg [7:0] r10, r11, r12;
    reg [7:0] r20, r21, r22;

    // Two 28-deep line buffers: lb0 delays by 28 pixels (1 row),
    // lb1 delays by another 28 (2 rows total).
    reg [7:0] lb0 [0:27];
    reg [7:0] lb1 [0:27];
    wire [7:0] lb0_tail = lb0[27];
    wire [7:0] lb1_tail = lb1[27];

    reg mac_valid_in;

    integer i;

    mac_array_3x3 u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(mac_valid_in),
        .px00(r00), .px01(r01), .px02(r02),
        .px10(r10), .px11(r11), .px12(r12),
        .px20(r20), .px21(r21), .px22(r22),
        .w00(w[0]), .w01(w[1]), .w02(w[2]),
        .w10(w[3]), .w11(w[4]), .w12(w[5]),
        .w20(w[6]), .w21(w[7]), .w22(w[8]),
        .pixel_out(pixel_out),
        .valid_out(valid_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            sram_addr_out <= 10'd0;
            rom_addr_out  <= 16'd0;
            pp            <= 4'd0;
            row_arr       <= 5'd0;
            col_arr       <= 5'd0;
            drain_cnt     <= 2'd0;
            done          <= 1'b0;
            mac_valid_in  <= 1'b0;
            r00 <= 0; r01 <= 0; r02 <= 0;
            r10 <= 0; r11 <= 0; r12 <= 0;
            r20 <= 0; r21 <= 0; r22 <= 0;
            for (i = 0; i < 28; i = i + 1) begin
                lb0[i] <= 8'd0;
                lb1[i] <= 8'd0;
            end
            for (i = 0; i < 9; i = i + 1) w[i] <= 8'sd0;
        end else if (start) begin
            mac_valid_in <= 1'b0;  // default for non-streaming cycles

            case (state)
                S_IDLE: begin
                    rom_addr_out  <= 16'd0;
                    sram_addr_out <= 10'd0;
                    pp            <= 4'd0;
                    done          <= 1'b0;
                    state         <= S_PRELOAD;
                end

                // pp 0  1  2  3  4  5  6  7  8  9
                // rom 1  2  3  4  5  6  7  8  -  -    (issue)
                // wt  0  -  1  2  3  4  5  6  7  8    (latch index)
                // pp=0: weight_in already = w[0] (rom was 0 since reset).
                // pp=1: weight_in still = w[0] (rom_addr only became 1 at end of pp=0).
                S_PRELOAD: begin
                    if (pp <= 4'd7) rom_addr_out <= {12'd0, pp + 4'd1};

                    if (pp == 4'd0)
                        w[0] <= weight_in;
                    else if (pp >= 4'd2 && pp <= 4'd9)
                        w[pp - 4'd1] <= weight_in;

                    // Pre-warm sram_addr so S_STREAM ss=0 sees ram[0].
                    if (pp == 4'd8) sram_addr_out <= 10'd0;
                    if (pp == 4'd9) sram_addr_out <= 10'd1;

                    if (pp == 4'd9) begin
                        state   <= S_STREAM;
                        row_arr <= 5'd0;
                        col_arr <= 5'd0;
                    end else begin
                        pp <= pp + 4'd1;
                    end
                end

                S_STREAM: begin
                    // Shift 3x3 window left; bring fresh column from line buffers.
                    r00 <= r01; r01 <= r02; r02 <= lb1_tail;
                    r10 <= r11; r11 <= r12; r12 <= lb0_tail;
                    r20 <= r21; r21 <= r22; r22 <= pixel_in;

                    // Shift both 28-deep line buffers by one slot.
                    for (i = 27; i > 0; i = i - 1) begin
                        lb0[i] <= lb0[i-1];
                        lb1[i] <= lb1[i-1];
                    end
                    lb0[0] <= pixel_in;
                    lb1[0] <= lb0_tail;

                    // MAC gets fired this cycle iff the just-shifted window is
                    // a valid 3x3 output position (row >= 2, col >= 2 means the
                    // bottom-right corner is at input (>=2, >=2), so the center
                    // is over a real input pixel).
                    mac_valid_in <= (row_arr >= 5'd2) && (col_arr >= 5'd2);

                    // Issue next SRAM address (always 2 ahead of the data we
                    // act on, due to the 2-cycle RAM latency).
                    if (sram_addr_out < 10'd783)
                        sram_addr_out <= sram_addr_out + 10'd1;

                    // Advance (row, col) tracking for next cycle.
                    if (row_arr == 5'd27 && col_arr == 5'd27) begin
                        // Last pixel just shifted in -> drain pipeline.
                        state     <= S_DRAIN;
                        drain_cnt <= 2'd0;
                    end else if (col_arr == 5'd27) begin
                        col_arr <= 5'd0;
                        row_arr <= row_arr + 5'd1;
                    end else begin
                        col_arr <= col_arr + 5'd1;
                    end
                end

                // Two MAC pipeline stages remain to flush after the last
                // mac_valid_in pulse. Three drain cycles is safe.
                S_DRAIN: begin
                    mac_valid_in <= 1'b0;
                    if (drain_cnt == 2'd2) begin
                        state <= S_DONE;
                    end else begin
                        drain_cnt <= drain_cnt + 2'd1;
                    end
                end

                S_DONE: begin
                    mac_valid_in <= 1'b0;
                    done         <= 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end else begin
            state         <= S_IDLE;
            mac_valid_in  <= 1'b0;
            done          <= 1'b0;
            pp            <= 4'd0;
            drain_cnt     <= 2'd0;
            row_arr       <= 5'd0;
            col_arr       <= 5'd0;
            sram_addr_out <= 10'd0;
            rom_addr_out  <= 16'd0;
        end
    end

endmodule
