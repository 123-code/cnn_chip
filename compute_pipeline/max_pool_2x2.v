module max_pool_2x2 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    
    input  wire [7:0] pixel_in,
    input  wire       valid_in,
    
    output reg  [7:0] pixel_out,
    output reg        valid_out,
    output reg        done
);

    // ==========================================
    // 1. The 26-Pixel Line Buffer & Registers
    // ==========================================
    // Creates an array of 26 8-bit registers
    reg [7:0] line_buffer [0:25]; 
    
    reg [7:0] r00, r01; // Top row
    reg [7:0] r10, r11; // Bottom row
    
    // Stride counters
    reg [4:0] x_cnt; // 0 to 25
    reg [4:0] y_cnt; // 0 to 25

    integer i;

    wire [7:0] max_top = (r00 > r01) ? r00 : r01;
    wire [7:0] max_bot = (r10 > r11) ? r10 : r11;

    // ==========================================
    // 2. The Sliding Window Logic
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r00 <= 0; r01 <= 0; r10 <= 0; r11 <= 0;
            x_cnt <= 0; y_cnt <= 0;
            valid_out <= 0;
            done <= 0;
            for (i = 0; i < 26; i = i + 1) line_buffer[i] <= 8'd0;
        end else if (start && valid_in) begin
            
            // Shift the 2x2 Window
            r11 <= pixel_in;                  // Fresh pixel into bottom right
            r10 <= r11;                       // Shift bottom row left
            r01 <= line_buffer[25];           // Pixel pops out of the delay tube
            r00 <= r01;                       // Shift top row left
            
            // Shift the Line Buffer
            for (i = 25; i > 0; i = i - 1) begin
                line_buffer[i] <= line_buffer[i-1];
            end
            line_buffer[0] <= r11; // Push a copy of the fresh pixel into the tube
            
            // Manage the X and Y Coordinates
            if (x_cnt == 25) begin
                x_cnt <= 0;
                if (y_cnt == 25) begin
                    y_cnt <= 0;
                    done  <= 1'b1; // Finished the whole image!
                end else begin
                    y_cnt <= y_cnt + 1;
                end
            end else begin
                x_cnt <= x_cnt + 1;
                done  <= 1'b0;
            end
            
            // ==========================================
            // 3. The Comparator Tree & Stride Control
            // ==========================================
            // Only output a valid pixel on ODD X and ODD Y coordinates (Stride 2)
            if (x_cnt[0] == 1'b1 && y_cnt[0] == 1'b1) begin
                // Compare the Winners
                pixel_out <= (max_top > max_bot) ? max_top : max_bot;
                
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
            
        end else begin
            valid_out <= 1'b0;
            done <= 1'b0;
        end
    end

endmodule