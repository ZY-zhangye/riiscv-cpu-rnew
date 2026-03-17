`timescale 1ns / 1ps
//PLIC地址以及相关含义
//基地址
`define PLIC_BASE_ADDR 16'h8000
`define PLIC_PRIORITY_NUM 16 //PLIC支持的中断源数量
`define PLIC_PRIORITY_WD 8 //每个中断源优先级寄存器宽度
`define PLIC_PENDING_WD 16 //PLIC待处理寄存器宽度，每位对应一个中断源
`define PLIC_ENABLE_WD 16 //PLIC使能寄存器宽度，每位对应一个中断源
`define PLIC_THRESHOLD_WD 8 //PLIC阈值寄存器宽度
`define PLIC_CLAIM_WD 16 //PLIC请求寄存器宽度
`define PLIC_PRIORITY_OFFSET 16'h0000 //PLIC优先级寄存器基地址偏移
`define PLIC_PENDING_OFFSET 16'h1000 //PLIC待处理寄存器基地址偏移
`define PLIC_ENABLE_OFFSET 16'h2000 //PLIC使能寄存器基地址偏移
`define PLIC_THRESHOLD_OFFSET 16'h2004 //PLIC阈值寄存器基地址偏移
`define PLIC_CLAIM_OFFSET 16'h2008 //PLIC请求寄存器基地址偏移
//PLIC中断号定义
`define UART_RX_INT_ID 1 //UART接收中断号
`define UART_TX_INT_ID 2 //UART发送中断号
`define TIMER_INT_ID 3 //定时器中断号
module tb_plic;
reg clk;
reg rst_n;
reg [15:0] cpu_addr;
reg cpu_wen;
reg [31:0] cpu_wdata;
reg uart_rx_int;
reg uart_tx_int;
reg timer_int;
wire plic_int;
wire [15:0] plic_int_id;
reg cpu_ren;
wire [31:0] cpu_rdata;

PLIC u_plic (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_addr(cpu_addr),
    .cpu_wen(cpu_wen),
    .cpu_wdata(cpu_wdata),
    .cpu_ren(cpu_ren),
    .cpu_rdata(cpu_rdata),
    .uart_rx_int(uart_rx_int),
    .uart_tx_int(uart_tx_int),
    .timer_int(timer_int),
    .plic_int(plic_int),
    .plic_int_id(plic_int_id)
);

task plic_write(input [15:0] addr, input [31:0] data);
    @(negedge clk);
    cpu_addr <= addr;
    cpu_wdata <= data;
    cpu_wen <= 1;
    @(negedge clk);
    cpu_wen <= 0;
endtask
task plic_read(input [15:0] addr, output reg [31:0] data);
    @(negedge clk);
    cpu_addr <= addr;
    cpu_ren <= 1;
    @(negedge clk);
    cpu_ren <= 0;
    data <= cpu_rdata;
endtask

initial begin
    // 产生50MHz时钟信号
    clk = 0;
    forever #(5) clk = ~clk; // 20ns周期=50MHz
end
initial begin
    rst_n = 0;
    cpu_addr = 0;
    cpu_wen = 0;
    cpu_wdata = 0;
    cpu_ren = 0;
    #20;
    rst_n = 1;
end

//测试流程
reg [31:0] read_data;
initial begin
    //等待复位完成
    #30;
    //优先级设置：UART_RX=1, UART_TX=2, TIMER=3
    plic_write((`PLIC_PRIORITY_OFFSET), 32'h00_03_02_01); //设置0~3号中断源的优先级，其他源优先级默认为0
    $display("plic_waddr: %h, plic_wdata: %h", `PLIC_PRIORITY_OFFSET, 32'h00_03_02_01);
    plic_write(`PLIC_ENABLE_OFFSET, 16'b0000_0000_0000_0111); //使能0~2号中断源，其他源保持禁用
    $display("plic_waddr: %h, plic_wdata: %b", `PLIC_ENABLE_OFFSET, 16'b0000_0000_0000_0111);
    plic_write(`PLIC_THRESHOLD_OFFSET, 8'h00); //设置阈值为1，只有优先级大于1的中断才会被响应
    $display("plic_waddr: %h, plic_wdata: %h", `PLIC_THRESHOLD_OFFSET, 8'h00);
    //读取优先级寄存器验证写入
    plic_read((`PLIC_PRIORITY_OFFSET), read_data);
    $display("plic_raddr: %h, plic_rdata: %h", `PLIC_PRIORITY_OFFSET, cpu_rdata);
    //模拟外设中断请求
    #10;
    uart_rx_int = 1; //触发UART接收中断
    uart_tx_int = 1; //触发UART发送中断
    timer_int = 1; //触发定时器中断
    #10;
    uart_rx_int = 0;
    uart_tx_int = 0;
    timer_int = 0;
    #10;
    //测试在有中断时是否会触发中断
    timer_int = 1; //触发定时器中断
    #10;
    timer_int = 0;
    #10;
    //测试完成中断处理后是否会清除中断
    plic_write(`PLIC_CLAIM_OFFSET, plic_int_id); //写入当前处理中断号，表示完成中断处理
    $display("plic_waddr: %h, plic_wdata: %h", `PLIC_CLAIM_OFFSET, plic_int_id);
    #10;
    $stop;
end

initial begin
    $monitor("Time: %0t | plic_int: %b | plic_int_id: %h", $time, plic_int, plic_int_id);
end

endmodule