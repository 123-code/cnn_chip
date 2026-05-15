module top_mnist_accel (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin
);

    // ==========================================
    // Internal Copper Wires
    // ==========================================
    wire [7:0] rx_byte;
    wire       rx_valid;
    wire       tx_done;
    wire       tx_start;

    wire       start_layer;
    wire       layer_done;

    wire [7:0]  sram_pixel_out;
    wire [9:0]  sram_read_addr;
    wire        sram_write_en;

    wire [7:0]  rom_weight_out;
    wire [31:0] rom_bias_out;
    wire [15:0] rom_read_addr;

    wire [3:0]  predicted_digit;

    // ==========================================
    // Module Instantiation
    // ==========================================
    control_unit u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .rx_byte_valid(rx_valid),
        .layer_done(layer_done),
        .tx_done(tx_done),
        .sram_write_en(sram_write_en),
        .start_layer(start_layer),
        .tx_start(tx_start)
    );

    compute_pipeline u_compute (
        .clk(clk),
        .rst_n(rst_n),
        .start_layer(start_layer),
        .pixel_in(sram_pixel_out),
        .weight_in(rom_weight_out),
        .bias_in(rom_bias_out),
        .sram_addr_out(sram_read_addr),
        .rom_addr_out(rom_read_addr),
        .layer_done(layer_done),
        .predicted_digit(predicted_digit)
    );

    uart_rx u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx_in(uart_rx_pin),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid)
    );

    uart_tx u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .data_in({4'b0000, predicted_digit}), 
        .tx_out(uart_tx_pin),
        .tx_done(tx_done)
    );

    mem_image_ram u_sram (
        .clk(clk),
        .write_en(sram_write_en),
        .read_addr(sram_read_addr),
        .write_addr(u_fsm.byte_counter), 
        .data_in(rx_byte),
        .data_out(sram_pixel_out)
    );

    mem_weights_rom u_rom (
        .clk(clk),
        .read_addr(rom_read_addr),
        .weight_out(rom_weight_out),
        .bias_out(rom_bias_out)
    );

endmodule