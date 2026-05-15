module uart_rx #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_in,
    output reg  [7:0] rx_byte,
    output reg        rx_valid
);

    localparam BIT_TICK = CLK_FREQ / BAUD_RATE;
    localparam HALF_TICK = BIT_TICK / 2;

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
            rx_byte <= 0;
            rx_valid <= 0;
        end else begin
            rx_valid <= 0; // Default to 0, only pulse high for 1 cycle

            case (state)
                IDLE: begin
                    if (rx_in == 1'b0) begin // Start bit detected
                        state <= START;
                        tick_counter <= 0;
                    end
                end
                
                START: begin
                    if (tick_counter == HALF_TICK) begin
                        if (rx_in == 1'b0) begin // Confirm it's still 0
                            state <= DATA;
                            tick_counter <= 0;
                            bit_index <= 0;
                        end else begin
                            state <= IDLE; // False alarm
                        end
                    end else begin
                        tick_counter <= tick_counter + 1;
                    end
                end
                
                DATA: begin
                    if (tick_counter == BIT_TICK - 1) begin
                        tick_counter <= 0;
                        shift_reg[bit_index] <= rx_in; // Sample data
                        
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
                    if (tick_counter == BIT_TICK - 1) begin
                        state <= IDLE;
                        rx_byte <= shift_reg;
                        rx_valid <= 1'b1; // Output valid byte
                    end else begin
                        tick_counter <= tick_counter + 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule