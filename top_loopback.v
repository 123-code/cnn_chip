// LOOPBACK TEST — replaces top_mnist_accel temporarily.
// Whatever byte the PC sends should come back unchanged.
// If this works, BL616 UART bridge is OK and our chip is the problem.
// If silent, BL616 bridge is broken (need different USB serial path).

module top_mnist_accel (
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin
);
    assign uart_tx_pin = uart_rx_pin;
endmodule
