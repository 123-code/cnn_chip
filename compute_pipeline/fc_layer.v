module fc_layer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    
    input  wire [7:0]  feature_in, // From Max Pool
    input  wire signed [7:0]  weight_in,  // From ROM
    input  wire signed [31:0] bias_in,    // From ROM
    
    output reg  [15:0] rom_addr_out,
    output reg  [3:0]  predicted_digit,
    output reg         done
);

    // 169 features * 10 digits = 1690 total MAC operations
    reg [10:0] pixel_counter; 
    reg [3:0]  digit_counter; // 0 to 9
    
    // The Accumulator (Holds the score for the current digit)
    reg signed [31:0] accumulator;
    
    // ArgMax variables (To remember which digit had the highest score)
    reg signed [31:0] highest_score;
    reg [3:0]         winning_digit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_addr_out  <= 16'd0;
            predicted_digit <= 4'd0;
            done          <= 1'b0;
            
            pixel_counter <= 11'd0;
            digit_counter <= 4'd0;
            accumulator   <= 32'd0;
            highest_score <= -32'sd2147483648; // Minimum possible signed number
            winning_digit <= 4'd0;
        end else if (start) begin
            
            // Multiply and Accumulate (The MAC operation)
            // {1'b0, feature_in} keeps the pixel strictly positive!
            accumulator <= accumulator + ($signed({1'b0, feature_in}) * weight_in);
            
            // We read one weight per clock cycle
            rom_addr_out <= rom_addr_out + 1'b1;
            
            if (pixel_counter == 168) begin
                // We finished all 169 pixels for THIS digit!
                pixel_counter <= 0;
                
                // Add the bias to the final score
                // ARGMAX: Is this score the new high score?
                if ((accumulator + bias_in) > highest_score) begin
                    highest_score <= accumulator + bias_in;
                    winning_digit <= digit_counter;
                end
                
                // Move to the next digit
                if (digit_counter == 9) begin
                    // We checked all 10 digits!
                    predicted_digit <= winning_digit;
                    done <= 1'b1;
                end else begin
                    digit_counter <= digit_counter + 1'b1;
                    accumulator <= 32'd0; // Reset accumulator for the next digit
                end
                
            end else begin
                pixel_counter <= pixel_counter + 1'b1;
                done <= 1'b0;
            end
        end else begin
            done <= 1'b0;
        end
    end

endmodule