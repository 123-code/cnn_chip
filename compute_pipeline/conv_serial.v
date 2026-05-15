module conv_serial (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    input  wire [7:0]         pixel_in,    // From SRAM (1-cycle latency)
    input  wire signed [7:0]  weight_in,   // From ROM  (1-cycle latency)

    output reg  [9:0]   sram_addr_out,
    output reg  [15:0]  rom_addr_out,

    output reg  [7:0]   pixel_out,
    output reg          valid_out,
    output reg          done
);

    // Output position over the 26x26 feature map
    reg [4:0] ox, oy;     // 0..25

    // Tap index within the 3x3 kernel (0..8)
    reg [3:0] tap;

    // Accumulator for one output pixel
    reg signed [31:0] acc;

    localparam S_IDLE  = 3'd0,
               S_FETCH = 3'd1,  // issue SRAM/ROM addresses
               S_WAIT  = 3'd2,  // 1-cycle memory latency
               S_MAC   = 3'd3,  // multiply-accumulate
               S_EMIT  = 3'd4,  // ReLU + quantize + emit
               S_DONE  = 3'd5;
    reg [2:0] state;

    // Decompose tap into (kx, ky)
    wire [1:0] kx = (tap == 4'd0 || tap == 4'd3 || tap == 4'd6) ? 2'd0 :
                    (tap == 4'd1 || tap == 4'd4 || tap == 4'd7) ? 2'd1 : 2'd2;
    wire [1:0] ky = (tap < 4'd3) ? 2'd0 :
                    (tap < 4'd6) ? 2'd1 : 2'd2;

    // SRAM address: (oy+ky)*28 + (ox+kx)
    wire [9:0] tap_sram_addr =
        ({5'd0, oy} + {8'd0, ky}) * 10'd28 + ({5'd0, ox} + {8'd0, kx});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            ox            <= 5'd0;
            oy            <= 5'd0;
            tap           <= 4'd0;
            acc           <= 32'sd0;
            sram_addr_out <= 10'd0;
            rom_addr_out  <= 16'd0;
            pixel_out     <= 8'd0;
            valid_out     <= 1'b0;
            done          <= 1'b0;
        end else if (start) begin
            case (state)
                S_IDLE: begin
                    // Issue the very first address (tap 0 at output (0,0))
                    ox            <= 5'd0;
                    oy            <= 5'd0;
                    tap           <= 4'd0;
                    acc           <= 32'sd0;
                    sram_addr_out <= 10'd0;          // (0+0)*28+(0+0)=0
                    rom_addr_out  <= 16'd0;          // kernel[0]
                    valid_out     <= 1'b0;
                    done          <= 1'b0;
                    state         <= S_WAIT;
                end

                S_FETCH: begin
                    sram_addr_out <= tap_sram_addr;
                    rom_addr_out  <= {12'd0, tap};
                    valid_out     <= 1'b0;
                    state         <= S_WAIT;
                end

                S_WAIT: begin
                    // Memories are reading; data is valid after this cycle's edge
                    state <= S_MAC;
                end

                S_MAC: begin
                    acc <= acc + ($signed({1'b0, pixel_in}) * weight_in);
                    if (tap == 4'd8) begin
                        state <= S_EMIT;
                    end else begin
                        tap   <= tap + 4'd1;
                        state <= S_FETCH;
                    end
                end

                S_EMIT: begin
                    // ReLU + quantization (divide by 256 via >>8, clamp to 0..255)
                    if (acc < 32'sd0)
                        pixel_out <= 8'd0;
                    else if ((acc >>> 8) > 32'sd255)
                        pixel_out <= 8'd255;
                    else
                        pixel_out <= acc[15:8];

                    valid_out <= 1'b1;

                    // Reset accumulator + tap for next output pixel
                    acc <= 32'sd0;
                    tap <= 4'd0;

                    // Walk the 26x26 output grid in raster order
                    if (ox == 5'd25) begin
                        ox <= 5'd0;
                        if (oy == 5'd25) begin
                            state <= S_DONE;
                        end else begin
                            oy    <= oy + 5'd1;
                            state <= S_FETCH;
                        end
                    end else begin
                        ox    <= ox + 5'd1;
                        state <= S_FETCH;
                    end
                end

                S_DONE: begin
                    valid_out <= 1'b0;
                    done      <= 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end else begin
            valid_out <= 1'b0;
            done      <= 1'b0;
            state     <= S_IDLE;
        end
    end
endmodule
