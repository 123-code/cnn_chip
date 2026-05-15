module mem_image_ram (
    input  wire        clk,
    
    // Write Port (Used by the FSM / UART RX)
    input  wire        write_en,
    input  wire [9:0]  write_addr,
    input  wire [7:0]  data_in,
    
    // Read Port (Used by the Compute Pipeline)
    input  wire [9:0]  read_addr,
    output reg  [7:0]  data_out
);

    // Create the memory array: 784 slots, each 8 bits wide
    reg [7:0] ram [0:783];

    // Synchronous Read/Write logic
    always @(posedge clk) begin
        if (write_en) begin
            ram[write_addr] <= data_in;
        end
        
        // The read happens on the clock edge, perfectly matching 
        // the 1-cycle latency of a real hardware BRAM.
        data_out <= ram[read_addr];
    end

endmodule