`timescale 1ns / 1ps // Time unit is 1 nanosecond, precision is 1 picosecond

module tb_top;

    // 1. Declare signals to connect to the top module
    reg clk;
    reg rst_n;
    reg uart_rx_pin;
    wire uart_tx_pin;

    // 2. Instantiate the chip we want to test
    top_mnist_accel u_top (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin)
    );

    // 3. Generate the 50 MHz Clock
    // 50 MHz = 20 nanosecond period. We flip the clock every 10 ns.
    initial begin
        clk = 0;
        forever #10 clk = ~clk; 
    end

    // --- NEW: Array to hold the test image ---
    reg [7:0] test_image [0:783];
    initial begin
        $readmemh("test_image.hex", test_image);
    end

    // 4. UART Byte Sending Task (Acts like your PC's USB port)
    // Baud Rate: 115200 -> 1 bit takes exactly 8680 nanoseconds
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            // Send START Bit (Pull line LOW)
            uart_rx_pin = 0;
            #8680; 
            
            // Send 8 DATA Bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = data[i];
                #8680;
            end
            
            // Send STOP Bit (Pull line HIGH)
            uart_rx_pin = 1;
            #8680;
        end
    endtask

    // 5. The Main Simulation Sequence
    initial begin
        // Setup Waveform Dumping (Crucial for GTKWave)
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_top);

        // Initialize default states
        rst_n = 0;
        uart_rx_pin = 1; // UART rests HIGH

        // Hold reset for 100ns, then release it
        #100;
        rst_n = 1;
        #100;
        
        $display("--- Starting Hardware Simulation ---");

        $display("Injecting 784 real MNIST pixels via UART...");
        for (integer p = 0; p < 784; p = p + 1) begin
            send_uart_byte(test_image[p]); 
        end
        
        $display("Image loaded! Chip FSM should now transition to COMPUTE.");
        
        // Wait for the chip to do all the math
        // In a real scenario, you'd calculate exact cycles. Here we just wait a long time.
        #500000; 

        $display("Simulation timeout reached. Check waveforms for results.");
        $finish; // End the simulation
    end

endmodule