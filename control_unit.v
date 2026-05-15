module control_unit (
    input  wire clk,
    input  wire rst_n,
    
    input  wire rx_byte_valid,
    input  wire layer_done,
    input  wire tx_done,
    
    output wire sram_write_en,
    output reg  start_layer,
    output reg  tx_start
);

    // Combinational: write happens on the SAME cycle as rx_byte_valid,
    // so byte_counter (pre-edge) is the correct write address.
    assign sram_write_en = rx_byte_valid;

    localparam [1:0] S_IDLE      = 2'd0,
                     S_LOAD_IMG  = 2'd1,
                     S_COMPUTE   = 2'd2,
                     S_TX_RESULT = 2'd3;

    reg [1:0] current_state, next_state;
    reg [9:0] byte_counter; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            byte_counter  <= 10'd0;
        end else begin
            current_state <= next_state;
            if (rx_byte_valid) byte_counter <= byte_counter + 1'b1;
            if (current_state == S_TX_RESULT && tx_done) byte_counter <= 10'd0; 
        end
    end

    always @(*) begin
        next_state = current_state; 
        case (current_state)
            S_IDLE:      if (rx_byte_valid) next_state = S_LOAD_IMG;
            S_LOAD_IMG:  if (byte_counter == 10'd783 && rx_byte_valid) next_state = S_COMPUTE;
            S_COMPUTE:   if (layer_done) next_state = S_TX_RESULT;
            S_TX_RESULT: if (tx_done) next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_layer <= 1'b0; tx_start <= 1'b0;
        end else begin
            start_layer <= 1'b0; tx_start <= 1'b0;

            case (next_state)
                S_COMPUTE:   start_layer <= 1'b1; // Turns ON the whole pipeline
                S_TX_RESULT: if (current_state != S_TX_RESULT) tx_start <= 1'b1;
            endcase
        end
    end
endmodule