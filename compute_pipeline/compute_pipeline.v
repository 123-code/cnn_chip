module compute_pipeline (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control signals from FSM
    input  wire        start_layer,
    input  wire [1:0]  layer_type, // 0=CONV, 1=POOL, 2=FC
    
    // Data from Memory
    input  wire [7:0]  pixel_in,
    input  wire [7:0]  weight_in,
    input  wire [31:0] bias_in,
    
    // Addresses to Memory
    output reg  [9:0]  sram_addr_out,
    output reg  [15:0] rom_addr_out,
    
    // Outputs back to FSM and System
    output reg         layer_done,
    output wire [3:0]  predicted_digit
);

    // ==========================================
    // Internal Copper Wires (The Datapath)
    // ==========================================
    
    // Wires coming out of the Conv Layer
    wire [7:0] conv_pixel_out;
    wire       conv_valid_out;
    wire [9:0] conv_sram_addr;
    wire [15:0] conv_rom_addr;
    wire       conv_done;

    // Wires coming out of the Pool Layer
    wire [7:0] pool_pixel_out;
    wire       pool_valid_out;
    wire       pool_done;

    // Wires coming out of the FC Layer
    wire       fc_done;
    wire [15:0] fc_rom_addr;

// ==========================================
    // Address & Done Signal Routing (Multiplexers)
    // ==========================================
    always @(*) begin
        case (layer_type)
            2'd0: begin // CONV Active
                sram_addr_out = conv_sram_addr;
                rom_addr_out  = conv_rom_addr;
                layer_done    = conv_done;
            end
            2'd1: begin // POOL Active
                // Pooling receives data streaming from Conv, doesn't need SRAM/ROM
                sram_addr_out = 10'd0; 
                rom_addr_out  = 16'd0;
                layer_done    = pool_done;
            end
            2'd2: begin // FC Active
                // FC receives data streaming from Pool, only needs ROM for weights
                sram_addr_out = 10'd0;
                rom_addr_out  = fc_rom_addr;
                layer_done    = fc_done;
            end
            default: begin
                sram_addr_out = 10'd0;
                rom_addr_out  = 16'd0;
                layer_done    = 1'b0;
            end
        endcase
    end

    // ==========================================
    // Instantiating the Sub-Engines
    // ==========================================

    // 1. The 3x3 Sliding Window & Mac Array (Combined Conv Engine)
    conv_sliding_win u_conv (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_layer && (layer_type == 2'd0)),
        .pixel_in(pixel_in),
        .weight_in(weight_in),
        .bias_in(bias_in),
        .sram_addr_out(conv_sram_addr),
        .rom_addr_out(conv_rom_addr),
        .pixel_out(conv_pixel_out), // INT8 output
        .valid_out(conv_valid_out),
        .done(conv_done)
    );

    // 2. The 2x2 Max Pooling Engine
    max_pool_2x2 u_pool (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_layer && (layer_type == 2'd1)),
        .pixel_in(conv_pixel_out), // Plugs directly into Conv output!
        .valid_in(conv_valid_out),
        .pixel_out(pool_pixel_out),
        .valid_out(pool_valid_out),
        .done(pool_done)
    );

    // 3. The Fully Connected Layer (Classifier)
    fc_layer u_fc (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_layer && (layer_type == 2'd2)),
        .feature_in(pool_pixel_out), // Plugs into Pool output!
        .weight_in(weight_in),
        .bias_in(bias_in),
        .rom_addr_out(fc_rom_addr),
        .predicted_digit(predicted_digit), // Final 0-9 output
        .done(fc_done)
    );

endmodule