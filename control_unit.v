module control_unit (
    input  wire clk,
    input  wire rst_n,
    
    input  wire rx_byte_valid,
    input  wire layer_done,
    input  wire tx_done,
    
    output reg        sram_write_en,
    output reg        start_layer,
    output reg  [1:0] layer_type,
    output reg        tx_start
);

    localparam [2:0] S_IDLE         = 3'd0,
                     S_LOAD_IMG     = 3'd1,
                     S_COMPUTE_CONV = 3'd2,
                     S_COMPUTE_POOL = 3'd3,
                     S_COMPUTE_FC   = 3'd4,
                     S_TX_RESULT    = 3'd5;

    reg [2:0] current_state, next_state;
    reg [9:0] byte_counter; // Made internal again for simulation

    // ==========================================
    // 2. State Memory & Counter
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            byte_counter  <= 10'd0;
        end else begin
            current_state <= next_state;
            
            // THE FIX: Count the byte regardless of what state we are in!
            if (rx_byte_valid)
                byte_counter <= byte_counter + 1'b1;
                
            // Reset the counter when we finish the whole image
            if (current_state == S_TX_RESULT && tx_done)
                byte_counter <= 10'd0; 
        end
    end

    // ==========================================
    // 3. Next State Logic (The MUX)
    // ==========================================
    always @(*) begin
        next_state = current_state; 
        
        case (current_state)
            S_IDLE: begin
                if (rx_byte_valid)
                    next_state = S_LOAD_IMG;
            end
            S_LOAD_IMG: begin
                // Transition to CONV when the 784th byte arrives
                if (byte_counter == 10'd783 && rx_byte_valid)
                    next_state = S_COMPUTE_CONV;
            end
            S_COMPUTE_CONV: begin
                if (layer_done) next_state = S_COMPUTE_POOL;
            end
            S_COMPUTE_POOL: begin
                if (layer_done) next_state = S_COMPUTE_FC;
            end
            S_COMPUTE_FC: begin
                if (layer_done) next_state = S_TX_RESULT;
            end
            S_TX_RESULT: begin
                if (tx_done) next_state = S_IDLE;
            end
            default: next_state = S_IDLE;
        endcase
    end

    // ==========================================
    // 4. Output Control Signals
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_write_en <= 1'b0;
            start_layer   <= 1'b0;
            layer_type    <= 2'd0;
            tx_start      <= 1'b0;
        end else begin
            sram_write_en <= 1'b0;
            start_layer   <= 1'b0;
            tx_start      <= 1'b0;
            
            // THE FIX: Force SRAM to write anytime a byte arrives!
            if (rx_byte_valid) sram_write_en <= 1'b1;
            
            case (next_state)
                S_COMPUTE_CONV: begin
                    layer_type <= 2'd0;
                    if (current_state != S_COMPUTE_CONV) start_layer <= 1'b1;
                end
                S_COMPUTE_POOL: begin
                    layer_type <= 2'd1;
                    if (current_state != S_COMPUTE_POOL) start_layer <= 1'b1;
                end
                S_COMPUTE_FC: begin
                    layer_type <= 2'd2;
                    if (current_state != S_COMPUTE_FC)   start_layer <= 1'b1;
                end
                S_TX_RESULT: begin
                    if (current_state != S_TX_RESULT)    tx_start <= 1'b1;
                end
            endcase
        end
    end
endmodule