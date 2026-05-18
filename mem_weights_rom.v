module mem_weights_rom (
    input  wire        clk,
    input  wire [15:0] read_addr,       // weight address (0..1698)
    input  wire [3:0]  bias_addr,       // bias address  (0..10; 0 unused, 1..10 = FC biases)

    output reg signed [7:0]  weight_out,
    output reg signed [31:0] bias_out
);

    // 1699 weight bytes (conv kernel at 0..8, FC weights at 9..1698).
    reg [7:0]  weight_rom [0:2047];

    // 11 32-bit biases (addr 0 is a zero placeholder; FC biases at 1..10).
    reg [31:0] bias_rom   [0:15];

    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1) weight_rom[i] = 8'h00;
        for (i = 0; i < 16;   i = i + 1) bias_rom[i]   = 32'h0;
        $readmemh("weights.hex", weight_rom);
        $readmemh("bias.hex",    bias_rom);
    end

    // 1-cycle synchronous read on both ports (matches Gowin pROM bypass mode).
    always @(posedge clk) begin
        weight_out <= weight_rom[read_addr];
        bias_out   <= bias_rom[bias_addr];
    end

endmodule
