module top_mnist_accel (
    input  wire clk,          // 50 MHz board clock
    input  wire rst_n,        // Active-low reset button
    input  wire uart_rx_pin,  // Physical pin connected to USB RX
    output wire uart_tx_pin   // Physical pin connected to USB TX
);

    // ==========================================
    // 1. The Internal Copper Wires
    // ==========================================
    
    // UART <--> FSM & Memory wires
    wire [7:0] rx_byte;
    wire       rx_valid;
    wire       tx_done;
    wire       tx_start;

    // FSM <--> Compute Pipeline wires
    wire       start_layer;
    wire [1:0] layer_type;
    wire       layer_done;

    // Memory <--> Compute Pipeline wires
    wire [7:0]  sram_pixel_out;
    wire [9:0]  sram_read_addr;
    wire        sram_write_en;

    wire [7:0]  rom_weight_out;
    wire [31:0] rom_bias_out;
    wire [15:0] rom_read_addr;

    // Compute Pipeline <--> UART TX wires
    wire [3:0]  predicted_digit;

    // ==========================================
    // 2. Plugging in the Modules (Instantiation)
    // ==========================================

    // --- The Brain ---
    control_unit u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .rx_byte_valid(rx_valid),
        .layer_done(layer_done),
        .tx_done(tx_done),
        .sram_write_en(sram_write_en),
        .start_layer(start_layer),
        .layer_type(layer_type),
        .tx_start(tx_start)
    );

    // --- The Muscle ---
    compute_pipeline u_compute (
        .clk(clk),
        .rst_n(rst_n),
        .start_layer(start_layer),
        .layer_type(layer_type),
        .pixel_in(sram_pixel_out),
        .weight_in(rom_weight_out),
        .bias_in(rom_bias_out),
        .sram_addr_out(sram_read_addr),
        .rom_addr_out(rom_read_addr),
        .layer_done(layer_done),
        .predicted_digit(predicted_digit)
    );

    // --- The I/O ---
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
        .data_in({4'b0000, predicted_digit}), // Pad 4-bit digit to 8-bit ASCII
        .tx_out(uart_tx_pin),
        .tx_done(tx_done)
    );

    // --- The Memory ---
    // (See the crucial Gowin note below about these modules!)
    mem_image_ram u_sram (
        .clk(clk),
        .write_en(sram_write_en),
        .read_addr(sram_read_addr),
        .write_addr(u_fsm.byte_counter), // Using the FSM's counter for writing
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