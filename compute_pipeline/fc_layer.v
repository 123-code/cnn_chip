module fc_layer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    
    input  wire [7:0]  feature_in,
    input  wire        valid_in, 
    
    input  wire signed [7:0]  weight_in,
    input  wire signed [31:0] bias_in,
    
    output reg  [15:0] rom_addr_out,
    output wire [3:0]  bias_addr_out,    // NEW: Wire to request the correct bias
    output reg  [3:0]  predicted_digit,
    output reg         done
);

    reg [7:0] buffer [0:168];
    reg [7:0] write_idx;

    reg [10:0] pixel_counter;
    reg [3:0]  digit_counter;

    reg signed [31:0] accumulator;
    reg signed [31:0] highest_score;
    reg [3:0]         winning_digit;

    integer j;

    // ==========================================
    // BIAS ADDRESS ROUTING
    // ==========================================
    // Address 0 is reserved for Conv layer. 
    // FC digits 0-9 use addresses 1 through 10.
    assign bias_addr_out = digit_counter + 4'd1; 

    // A 5-state machine to ensure perfect math sync
    localparam S_CATCH = 3'd0, S_WAIT_ROM = 3'd1, S_CALC = 3'd2, S_EVAL = 3'd3, S_DONE = 3'd4;
    reg [2:0] state;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_addr_out <= 0; predicted_digit <= 0; done <= 0;
            write_idx <= 0; pixel_counter <= 0; digit_counter <= 0;
            accumulator <= 0;
            highest_score <= -2000000000; // Safe minimum to prevent X overflow
            winning_digit <= 4'd0;
            for (j = 0; j < 169; j = j + 1) buffer[j] <= 8'd0;
            state <= S_CATCH;
        end else if (start) begin
            case (state)
                S_CATCH: begin
                    if (valid_in) begin
                        buffer[write_idx] <= feature_in;
                        if (write_idx == 168) begin
                            state <= S_WAIT_ROM;
                            // FC weights start at addr 9 (conv at 0-8).
                            // ROM has 1-cycle latency; S_WAIT_ROM bumps addr to 9,
                            // so the first S_CALC sees data[9] aligned to buffer[0].
                            // (Verified against hw_sim.py which predicts digit 7.)
                            rom_addr_out <= 8;
                        end else begin
                            write_idx <= write_idx + 1;
                        end
                    end
                end
                
                S_WAIT_ROM: begin
                    // Queue up the next address, give ROM 1 cycle to fetch
                    rom_addr_out <= rom_addr_out + 1; 
                    state <= S_CALC;
                end
                
                S_CALC: begin
                    rom_addr_out <= rom_addr_out + 1;
                    
                    // Multiply and Add (Weights only)
                    accumulator <= accumulator + ($signed({1'b0, buffer[pixel_counter]}) * weight_in);
                    
                    if (pixel_counter == 168) begin
                        pixel_counter <= 0;
                        state <= S_EVAL; // Safely check the score on the next cycle
                    end else begin
                        pixel_counter <= pixel_counter + 1;
                    end
                end
                
                S_EVAL: begin
                    // Digit 0 always seeds the score (reset is hardwired off,
                    // so highest_score powers up to 0 instead of -INF — without
                    // this seed, any image where all scores are negative would
                    // leave winning_digit stuck at 0).
                    if (digit_counter == 4'd0 || (accumulator + bias_in) > highest_score) begin
                        highest_score <= accumulator + bias_in;
                        winning_digit <= digit_counter;
                    end
                    
                    if (digit_counter == 9) begin
                        state <= S_DONE;
                    end else begin
                        digit_counter <= digit_counter + 1;
                        accumulator <= 0; // Reset math for next digit
                        state <= S_CALC;
                    end
                end
                
                S_DONE: begin
                    predicted_digit <= winning_digit;
                    done <= 1'b1; 
                end
            endcase
        end
    end
endmodule