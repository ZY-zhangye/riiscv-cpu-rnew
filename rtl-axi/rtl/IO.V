`include "defines.v"
module IO(
    input wire clk,
    input wire rst_n,
    input wire clk_uart,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    input wire ren,
    output wire [31:0] rdata,
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
    wire [15:0] io_addr = addr[15:0]; // 16字节对齐
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


    reg uart_ren_d; // 延迟一个时钟周期的UART读使能信号
    reg timer_ren_d; // 延迟一个时钟周期的定时器读使能信号
    reg led_ren_d; // 延迟一个时钟周期的LED读使能
    reg plic_ren_d; // 延迟一个时钟周期的PLIC读使能信号
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_ren_d <= 0;
            timer_ren_d <= 0;
            led_ren_d <= 0;
            plic_ren_d <= 0;
        end else begin
            uart_ren_d <= uart_ren;
            timer_ren_d <= timer_ren;
            led_ren_d <= led_ren;
            plic_ren_d <= plic_ren;
        end
    end

    assign rdata = uart_ren_d ? uart_rdata :
                   timer_ren_d ? timer_rdata :
                   led_ren_d ? led_rdata :
                   plic_ren_d ? plic_rdata :
                   32'b0; // 默认读数据为0


    //实例化外设模块
    UART u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .clk_uart(clk_uart),
        .addr(io_addr), // 16字节对齐
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
        .addr(io_addr), // 16字节对齐
        .wdata(wdata),
        .we(timer_wen),
        .re(timer_ren),
        .rdata(timer_rdata),
        .timer_int(timer_int)
    );

    led u_led (
        .clk(clk),
        .rst_n(rst_n),
        .addr(io_addr), // 16字节对齐
        .wdata(wdata),
        .we(led_wen),
        .re(led_ren),
        .rdata(led_rdata),
        .led(led)
    );

    PLIC u_plic (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(io_addr), // 16字节对齐
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