// Orchestrates the conv -> pool -> fc data flow.
//
// PARALLEL_CONV selects between:
//   0 = legacy 1-multiplier serial conv (conv_serial.v)
//   1 = v2 9-multiplier parallel conv  (conv_sliding_win.v + mac_array_3x3.v)
// Default is the parallel build. Set the parameter to 0 in instantiations
// (e.g. tb_top_v1.v) to retain v1 behavior.

module compute_pipeline #(
    parameter PARALLEL_CONV = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_layer,

    input  wire [7:0]  pixel_in,
    input  wire signed [7:0]  weight_in,
    input  wire signed [31:0] bias_in,

    output wire [9:0]  sram_addr_out,
    output wire [15:0] rom_addr_out,
    output wire [3:0]  bias_addr_out,
    output wire        layer_done,
    output wire [3:0]  predicted_digit
);

    wire [7:0] conv_pixel_out;
    wire       conv_valid_out;
    wire       conv_done;

    wire [7:0] pool_pixel_out;
    wire       pool_valid_out;

    wire       fc_done;

    wire [9:0]  conv_sram_addr;
    wire [15:0] conv_rom_addr;
    wire [15:0] fc_rom_addr;
    wire [3:0]  fc_bias_addr;

    assign layer_done    = fc_done;
    assign sram_addr_out = conv_sram_addr;
    assign rom_addr_out  = conv_done ? fc_rom_addr  : conv_rom_addr;
    assign bias_addr_out = conv_done ? fc_bias_addr : 4'd0;

    generate
        if (PARALLEL_CONV == 0) begin : g_serial
            conv_serial u_conv (
                .clk(clk), .rst_n(rst_n),
                .start(start_layer),
                .pixel_in(pixel_in),
                .weight_in(weight_in),
                .sram_addr_out(conv_sram_addr),
                .rom_addr_out(conv_rom_addr),
                .pixel_out(conv_pixel_out),
                .valid_out(conv_valid_out),
                .done(conv_done)
            );
        end else begin : g_parallel
            conv_sliding_win u_conv (
                .clk(clk), .rst_n(rst_n),
                .start(start_layer),
                .pixel_in(pixel_in),
                .weight_in(weight_in),
                .sram_addr_out(conv_sram_addr),
                .rom_addr_out(conv_rom_addr),
                .pixel_out(conv_pixel_out),
                .valid_out(conv_valid_out),
                .done(conv_done)
            );
        end
    endgenerate

    max_pool_2x2 u_pool (
        .clk(clk), .rst_n(rst_n),
        .start(start_layer),
        .pixel_in(conv_pixel_out),
        .valid_in(conv_valid_out),
        .pixel_out(pool_pixel_out),
        .valid_out(pool_valid_out),
        .done()
    );

    fc_layer u_fc (
        .clk(clk), .rst_n(rst_n),
        .start(start_layer),
        .feature_in(pool_pixel_out),
        .valid_in(pool_valid_out),
        .weight_in(weight_in),
        .bias_in(bias_in),
        .rom_addr_out(fc_rom_addr),
        .bias_addr_out(fc_bias_addr),
        .predicted_digit(predicted_digit),
        .done(fc_done)
    );

endmodule
