`include "defines.v"
module IO(
    input wire clk,
    input wire rst_n,
    input wire clk_uart,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    input wire ren,
    output reg [31:0] rdata,
    output wire [3:0] led,
    input wire rx,
    output wire tx,
    output wire plic_int,
    output wire [15:0] plic_int_id
);

    wire uart_wen;
    wire uart_ren;
    wire [31:0] uart_rdata;

    wire timer_wen;
    reg timer_ren;
    wire [31:0] timer_rdata;

    wire led_wen;
    wire led_ren;
    wire [31:0] led_rdata;

    wire plic_wen;
    wire plic_ren;
    wire [31:0] plic_rdata;

    wire uart_rx_int;
    wire uart_tx_int;
    wire timer_int;

    wire [15:0] IO_ADDR_BASE = addr[31:16]; // 16位地址线用于外设地址解码
    reg IO_UART;
    reg IO_TIMER;
    reg IO_LED;
    reg IO_PLIC;


    //地址解码逻辑
    always @(*) begin
        if (!rst_n) begin
            IO_UART = 0;
            IO_TIMER = 0;
            IO_LED = 0;
            IO_PLIC = 0;
        end else begin
            case (IO_ADDR_BASE)
                `UART_BASE_ADDR: begin
                    IO_UART = 1;
                    IO_TIMER = 0;
                    IO_LED = 0;
                    IO_PLIC = 0;
                end
                `TIMER_BASE_ADDR: begin
                    IO_UART = 0;
                    IO_TIMER = 1;
                    IO_LED = 0;
                    IO_PLIC = 0;
                end
                `LEDS_BASE_ADDR: begin
                    IO_UART = 0;
                    IO_TIMER = 0;
                    IO_LED = 1;
                    IO_PLIC = 0;
                end
                `PLIC_BASE_ADDR: begin
                    IO_UART = 0;
                    IO_TIMER = 0;
                    IO_LED = 0;
                    IO_PLIC = 1;
                end
                default: begin
                    IO_UART = 0;
                    IO_TIMER = 0;
                    IO_LED = 0;
                    IO_PLIC = 0;
                end
            endcase
        end 
    end

    //外设读写使能信号生成
    assign uart_wen = IO_UART && (|wstrb) && !ren; // UART写使能
    assign uart_ren = IO_UART && ren; // UART读使能

    assign timer_wen = IO_TIMER && (|wstrb) && !ren; // 定时器写使能
    assign timer_ren = IO_TIMER && ren; // 定时器读使能

    assign led_wen = IO_LED && (|wstrb) && !ren; // LED写使能
    assign led_ren = IO_LED && ren; // LED读使能

    assign plic_wen = IO_PLIC && (|wstrb) && !ren; // PLIC写使能
    assign plic_ren = IO_PLIC && ren; // PLIC读使能

    //实例化外设模块
    UART u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .clk_uart(clk_uart),
        .addr(addr[17:2]), // 16字节对齐，地址最低2位不参与解码
        .wdata(wdata),
        .we(uart_wen),
        .re(uart_ren),
        .rdata(uart_rdata),
        .rx(rx),
        .tx(tx),
        .rx_int(uart_rx_int),
        .tx_int(uart_tx_int)
    );

    timer u_timer (
        .clk(clk),
        .rst_n(rst_n),
        .addr(addr[17:2]), // 16字节对齐，地址最低2位不参与解码
        .wdata(wdata),
        .we(timer_wen),
        .re(timer_ren),
        .rdata(timer_rdata),
        .timer_int(timer_int)
    );

    led u_led (
        .clk(clk),
        .rst_n(rst_n),
        .addr(addr[17:2]), // 16字节对齐，地址最低2位不参与解码
        .wdata(wdata),
        .we(led_wen),
        .re(led_ren),
        .rdata(led_rdata),
        .led(led)
    );

    PLIC u_plic (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(addr[17:2]), // 16字节对齐，地址最低2位不参与解码
        .cpu_wdata(wdata),
        .cpu_wen(plic_wen),
        .cpu_ren(plic_ren),
        .cpu_rdata(plic_rdata),
        .uart_rx_int(uart_rx_int),
        .uart_tx_int(uart_tx_int),
        .timer_int(timer_int),
        .plic_int(plic_int),
        .plic_int_id(plic_int_id)
    );

endmodule