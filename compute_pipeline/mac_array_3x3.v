module mac_array_3x3 (
    input wire clk,
    input wire rst_n,

    // Valid signal moving through the pipeline
    input wire valid_in,

    // 9 Pixels from Sliding Window (Unsigned INT8: 0 to 255)
    input wire [7:0] px00, px01, px02,
    input wire [7:0] px10, px11, px12,
    input wire [7:0] px20, px21, px22,

    // 9 Weights from the ROM (Signed INT8: -128 to +127)
    input wire signed [7:0] w00, w01, w02,
    input wire signed [7:0] w10, w11, w12,
    input wire signed [7:0] w20, w21, w22,

    // Bias from the ROM (Signed 32-bit)
    input wire signed [31:0] bias,

    // Output activated pixel (Unsigned INT8: 0 to 255)
    output reg [7:0] pixel_out,
    output reg       valid_out
);

    // ==========================================
    // PIPELINE STAGE 1: Multipliers
    // ==========================================
    // 16-bit signed registers to hold the product of (Pixel * Weight)
    reg signed [15:0] prod0, prod1, prod2;
    reg signed [15:0] prod3, prod4, prod5;
    reg signed [15:0] prod6, prod7, prod8;
    
    // We also need to delay the valid signal by 1 clock cycle to match the math
    reg valid_stage1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod0 <= 0; prod1 <= 0; prod2 <= 0;
            prod3 <= 0; prod4 <= 0; prod5 <= 0;
            prod6 <= 0; prod7 <= 0; prod8 <= 0;
            valid_stage1 <= 0;
        end else if (valid_in) begin
            // Math Magic: {1'b0, px00} turns the unsigned 8-bit pixel into 
            // a strictly positive signed 9-bit number. This prevents Verilog 
            // from accidentally treating a bright pixel (e.g. 255) as a negative number.
            prod0 <= $signed({1'b0, px00}) * w00;
            prod1 <= $signed({1'b0, px01}) * w01;
            prod2 <= $signed({1'b0, px02}) * w02;
            prod3 <= $signed({1'b0, px10}) * w10;
            prod4 <= $signed({1'b0, px11}) * w11;
            prod5 <= $signed({1'b0, px12}) * w12;
            prod6 <= $signed({1'b0, px20}) * w20;
            prod7 <= $signed({1'b0, px21}) * w21;
            prod8 <= $signed({1'b0, px22}) * w22;
            
            valid_stage1 <= 1'b1;
        end else begin
            valid_stage1 <= 1'b0;
        end
    end

    // ==========================================
    // PIPELINE STAGE 2: The Adder Tree & ReLU
    // ==========================================
    // Wires for the intermediate Adder Tree logic (Level 1, 2, and 3)
    // We use wires here because they all evaluate instantly in the same clock cycle
    wire signed [31:0] tree_lvl1_0 = prod0 + prod1;
    wire signed [31:0] tree_lvl1_1 = prod2 + prod3;
    wire signed [31:0] tree_lvl1_2 = prod4 + prod5;
    wire signed [31:0] tree_lvl1_3 = prod6 + prod7;
    // prod8 is left over, we add it later
    
    wire signed [31:0] tree_lvl2_0 = tree_lvl1_0 + tree_lvl1_1;
    wire signed [31:0] tree_lvl2_1 = tree_lvl1_2 + tree_lvl1_3;
    
    wire signed [31:0] tree_lvl3   = tree_lvl2_0 + tree_lvl2_1;
    
    // The massive final addition
    wire signed [31:0] final_sum   = tree_lvl3 + prod8 + bias;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_out <= 8'd0;
            valid_out <= 1'b0;
        end else if (valid_stage1) begin
            
            // --- The ReLU Activation ---
            if (final_sum < 0) begin
                pixel_out <= 8'd0; // If negative, clamp to 0
            end else begin
                // --- Quantization ---
                // FPGAs don't like decimal math. Instead of dividing, we "Bit Shift".
                // Shifting right by 8 (>> 8) is the mathematical equivalent of dividing by 256.
                // We check if the result is larger than 255, and if so, clamp it to 255.
                if ((final_sum >> 8) > 255) 
                    pixel_out <= 8'd255;
                else 
                    pixel_out <= final_sum[15:8]; // Grabs the shifted 8 bits
            end
            
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule