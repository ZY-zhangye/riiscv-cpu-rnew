`timescale 1ns/1ps
`define TIMER_LOAD 16'h0000 //定时器装载寄存器地址
`define TIMER_VALUE 16'h0004 //定时器当前值寄存器地址 只读
`define TIMER_CTRL 16'h0008 //定时器控制寄存器地址
`define TIMER_INTCLR 16'h000C //定时器中断清除寄存器地址 写1清除中断
`define TIMER_PRESCALER 16'h0010 //定时器预分频寄存器地址
module tb_timer;
reg clk;
reg rst_n;
reg [15:0] addr;
reg [31:0] wdata;
reg we;
reg re;
wire [31:0] rdata;
wire timer_int;

logic [31:0] rdata_tmp;

initial begin
    clk = 0;
    rst_n = 0;
    addr = 0;
    wdata = 0;
    we = 0;
    re = 0;
    #20 rst_n = 1; // 20ns后释放复位
end
always #5 clk = ~clk; // 10ns一个周期
timer dut (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .wdata(wdata),
    .we(we),
    .re(re),
    .rdata(rdata),
    .timer_int(timer_int)
);

//读写寄存器的任务
task automatic host_write(input logic [15:0] reg_addr, input logic [31:0] reg_data);
    begin
        @(negedge clk);
        addr <= reg_addr;
        wdata <= reg_data;
        we <= 1'b1;
        re <= 1'b0;
        @(negedge clk);
        we <= 1'b0;
        addr <= '0;
        wdata <= '0;
    end
endtask
task automatic host_read(input logic [15:0] reg_addr, output logic [31:0] reg_data);
    begin
        @(negedge clk);
        addr <= reg_addr;
        re <= 1'b1;
        we <= 1'b0;
        #1;
        reg_data = rdata;
        @(posedge clk);
    end
endtask

//测试流程

initial begin
    //等待复位结束
    @(posedge rst_n);
    #10;
    //测试1：基本功能测试
    $display("Test 1: Basic Functionality Test");
    host_write(`TIMER_LOAD, 32'h0000_0005); //装载5
    host_write(`TIMER_CTRL, 32'b0000_0001); //使能定时器
    repeat (10) @(posedge clk); //等待足够的周期
    host_read(`TIMER_VALUE, rdata_tmp);
    $display("Timer Value after 10 cycles: %d", rdata_tmp);
    if (rdata_tmp != 0) $display("Error: Timer should have counted down to 0");

    //测试2：中断测试
    $display("Test 2: Interrupt Test");
    host_write(`TIMER_LOAD, 32'h0000_0003); //装载3
    host_write(`TIMER_CTRL, 32'b0000_0011); //使能定时器和中断
    repeat (10) @(posedge clk); //等待足够的周期
    if (timer_int) $display("Timer Interrupt Triggered");
    else $display("Error: Timer Interrupt Not Triggered");
    host_write(`TIMER_INTCLR, 32'h0000_0001); //清除中断
    if (!timer_int) $display("Timer Interrupt Cleared");
    else $display("Error: Timer Interrupt Not Cleared");

    //测试3：预分频测试
    $display("Test 3: Prescaler Test");
    host_write(`TIMER_PRESCALER, 32'h0000_0002); //设置预分频为2
    host_write(`TIMER_LOAD, 32'h0000_0004); //装载4
    host_write(`TIMER_CTRL, 32'b0000_1001); //使能定时器和预分频
    repeat (20) @(posedge clk); //等待足够的周期
    host_read(`TIMER_VALUE, rdata_tmp);
    $display("Timer Value after 20 cycles with prescaler: %d", rdata_tmp);

    $stop;
end

endmodule