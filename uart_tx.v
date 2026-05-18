module uart_tx #(
    parameter CLK_FREQ = 27000000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] data_in,
    output reg        tx_out,
    output reg        tx_done
);

    localparam BIT_TICK = CLK_FREQ / BAUD_RATE;

    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state;
    reg [15:0] tick_counter;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tick_counter <= 0;
            bit_index <= 0;
            shift_reg <= 0;
            tx_out <= 1'b1; // UART line rests HIGH
            tx_done <= 0;
        end else begin
            tx_done <= 0;

            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    if (tx_start) begin
                        state <= START;
                        shift_reg <= data_in;
                        tick_counter <= 0;
                    end
                end
                
                START: begin
                    tx_out <= 1'b0; // Start bit is LOW
                    if (tick_counter == BIT_TICK - 1) begin
                        state <= DATA;
                        tick_counter <= 0;
                        bit_index <= 0;
                    end else begin
                        tick_counter <= tick_counter + 1;
                    end
                end
                
                DATA: begin
                    tx_out <= shift_reg[bit_index]; // Send LSB first
                    if (tick_counter == BIT_TICK - 1) begin
                        tick_counter <= 0;
                        if (bit_index == 7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        tick_counter <= tick_counter + 1;
                    end
                end
                
                STOP: begin
                    tx_out <= 1'b1; // Stop bit is HIGH
                    if (tick_counter == BIT_TICK - 1) begin
                        state <= IDLE;
                        tx_done <= 1'b1;
                    end else begin
                        tick_counter <= tick_counter + 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule