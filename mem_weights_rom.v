module mem_weights_rom (
    input  wire        clk,
    input  wire [15:0] read_addr,
    
    output reg signed [7:0]  weight_out,
    output reg signed [31:0] bias_out
);

    // Create an array large enough to hold all weights
    // (e.g., 2000 bytes. Adjust size based on your final PyTorch model)
    reg [7:0] rom_array [0:1999]; 

    // Simulation-only initialization
    initial begin
        // Loads a hex file into the array. 
        // You will generate this file later with Python!
        $readmemh("weights.hex", rom_array);
    end

    // Synchronous Read
    always @(posedge clk) begin
        // In a real design, biases might be in a separate ROM or a specific offset.
        // For simulation, we'll output the weight, and just hardcode bias to 0 for now
        // until we know exactly how many biases your PyTorch model outputs.
        weight_out <= rom_array[read_addr];
        bias_out   <= 32'd0; 
    end

endmodule