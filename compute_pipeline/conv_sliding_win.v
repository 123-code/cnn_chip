module conv_sliding_win (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    
    input  wire [7:0]  pixel_in,
    input  wire signed [7:0]  weight_in,
    input  wire signed [31:0] bias_in,
    
    output reg  [9:0]  sram_addr_out,
    output reg  [15:0] rom_addr_out,
    
    output wire [7:0]  pixel_out,
    output wire        valid_out,
    output reg         done
);

    // The two PVC delay pipes (28 pixels wide)
    reg [7:0] line_buffer_0 [0:27];
    reg [7:0] line_buffer_1 [0:27];
    
    // The 3x3 Wooden Desk Slots (Registers)
    reg [7:0] r00, r01, r02;
    reg [7:0] r10, r11, r12;
    reg [7:0] r20, r21, r22;
    
    // X and Y counters to track where we are in the 28x28 image
    reg [4:0] x_cnt;
    reg [4:0] y_cnt;
    
    // Valid signal for the MAC array
    reg mac_valid_in;
    
    integer i;

    // Instantiate the Math Engine!
    mac_array_3x3 u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(mac_valid_in),
        .px00(r00), .px01(r01), .px02(r02),
        .px10(r10), .px11(r11), .px12(r12),
        .px20(r20), .px21(r21), .px22(r22),
        .w00(weight_in), .w01(weight_in), .w02(weight_in), // Simplified weight routing for now
        .w10(weight_in), .w11(weight_in), .w12(weight_in),
        .w20(weight_in), .w21(weight_in), .w22(weight_in),
        .bias(bias_in),
        .pixel_out(pixel_out),
        .valid_out(valid_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_addr_out <= 10'd0;
            rom_addr_out  <= 16'd0;
            done          <= 1'b0;
            mac_valid_in  <= 1'b0;
            x_cnt <= 0; y_cnt <= 0;
            
            r00 <= 0; r01 <= 0; r02 <= 0;
            r10 <= 0; r11 <= 0; r12 <= 0;
            r20 <= 0; r21 <= 0; r22 <= 0;
            
            for (i = 0; i < 28; i = i + 1) begin
                line_buffer_0[i] <= 8'd0;
                line_buffer_1[i] <= 8'd0;
            end
        end else if (start) begin
            
            // 1. Shift the 3x3 Window Registers
            r00 <= r01; r01 <= r02; r02 <= line_buffer_1[27];
            r10 <= r11; r11 <= r12; r12 <= line_buffer_0[27];
            r20 <= r21; r21 <= r22; r22 <= pixel_in;
            
            // 2. Shift the Line Buffers
            for (i = 27; i > 0; i = i - 1) begin
                line_buffer_0[i] <= line_buffer_0[i-1];
                line_buffer_1[i] <= line_buffer_1[i-1];
            end
            line_buffer_0[0] <= pixel_in;
            line_buffer_1[0] <= line_buffer_0[27];
            
            // 3. Fetch the next pixel
            if (sram_addr_out < 783) begin
                sram_addr_out <= sram_addr_out + 1'b1;
            end
            
            // 4. Update X/Y Coordinates to trigger the MAC valid signal
            if (x_cnt == 27) begin
                x_cnt <= 0;
                if (y_cnt == 27) begin
                    done <= 1'b1; // Finished image
                end else begin
                    y_cnt <= y_cnt + 1;
                end
            end else begin
                x_cnt <= x_cnt + 1;
                done <= 1'b0;
            end
            
            // Only fire the MAC unit when the 3x3 window is fully populated
            // (Skips the edges to avoid wrapping garbage data)
            if (x_cnt >= 2 && y_cnt >= 2) begin
                mac_valid_in <= 1'b1;
            end else begin
                mac_valid_in <= 1'b0;
            end
            
        end else begin
            mac_valid_in <= 1'b0;
            done <= 1'b0;
            sram_addr_out <= 10'd0;
        end
    end
endmodule