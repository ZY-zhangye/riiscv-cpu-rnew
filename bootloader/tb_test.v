`timescale 1ns/1ps
// -------------------------------------------------------------
// UART模块测试平台（Testbench）
// 主要功能：
// 1. 产生时钟和复位信号
// 2. 通过task独立发送UART数据，便于后续扩展
// 3. 监控UART接收输出
// -------------------------------------------------------------
module tb_test;
    // 时钟信号
    reg clk;
    // 复位信号，低有效
    reg rst_n;
    // UART串口输入信号
    reg rx;
    wire [52:0] dmem_write_bus; // 从bootloader输出的数据存储器写总线
    wire [48:0] imem_write_bus; // 从bootloader输出的指令存储器写总线
    wire reset; // 从bootloader输出的CPU复位信号
    wire mem_valid; // 从bootloader输出的写寄存器有效信号
    // UART参数定义，与被测模块保持一致
    parameter CLK_FREQ = 50000000;   // 仿真时钟频率（Hz）
    parameter BAUD_RATE = 115200;    // 仿真波特率
    localparam BAUD_PERIOD = 1_000_000_000 / BAUD_RATE; // 一个比特周期，单位ns
    wire baud_tick;

    // 实例化被测UART模块
    baud_gen #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) baud_gen_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_tick(baud_tick)
    );

    uart_bootloader uart_bootloader_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .baud_tick(baud_tick),
        .dmem_write_bus(dmem_write_bus),
        .imem_write_bus(imem_write_bus),
        .reset(reset),
        .mem_valid(mem_valid)
    );

    // 产生50MHz时钟信号
    initial begin
        clk = 0;
        forever #(10) clk = ~clk; // 20ns周期=50MHz
    end

    // 产生复位信号，仿真开始后拉低100ns再拉高
    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

    // UART发送一个字节的任务
    // 格式：1位起始位（低），8位数据（低位先发），1位停止位（高）
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            rx = 0;              // 起始位
            #(BAUD_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];    // 低位先发
                #(BAUD_PERIOD);
            end
            rx = 1;              // 停止位
            #(BAUD_PERIOD);
        end
    endtask

    // 发送一帧（9字节）：SOF | type | addr[15:8] | addr[7:0] | data[31:24] | data[23:16] | data[15:8] | data[7:0] | EOF
    // 后续可按需要填入具体字节
    task uart_send_frame;
        input [7:0] b0;
        input [7:0] b1;
        input [7:0] b2;
        input [7:0] b3;
        input [7:0] b4;
        input [7:0] b5;
        input [7:0] b6;
        input [7:0] b7;
        input [7:0] b8;
        begin
            uart_send_byte(b0);
            uart_send_byte(b1);
            uart_send_byte(b2);
            uart_send_byte(b3);
            uart_send_byte(b4);
            uart_send_byte(b5);
            uart_send_byte(b6);
            uart_send_byte(b7);
            uart_send_byte(b8);
        end
    endtask

    // 初始化rx为高，空闲状态
    initial begin
        rx = 1;
    end

    // 主测试流程
    // 1. 等待复位结束
    // 2. 发送两个不同的数据字节
    // 3. 可根据需要扩展更多测试
    initial begin
        @(posedge rst_n); // 等待复位结束
        #1000;
        uart_send_frame(
            8'hA5, // SOF
            8'h01, // type: 写data_ram
            8'h00, // addr高字节
            8'h10, // addr低字节
            8'h12, // data[31:24]
            8'h34, // data[23:16]
            8'h56, // data[15:8]
            8'h78, // data[7:0]
            8'h5A  // EOF
        );
        #100000;
        uart_send_frame(
            8'hA5, // SOF
            8'h02, // type: 写inst_ram
            8'h00, // addr高字节
            8'h10, // addr低字节
            8'h12, // data[31:24]
            8'h34, // data[23:16]
            8'h56, // data[15:8]
            8'h78, // data[7:0]
            8'h5A  // EOF
        );
        #100000;
        uart_send_frame(
            8'hA5, // SOF
            8'h04, // type: 启动运行
            8'h00, // addr高字节
            8'h10, // addr低字节
            8'h12, // data[31:24]
            8'h34, // data[23:16]
            8'h56, // data[15:8]
            8'h78, // data[7:0]
            8'h5A  // EOF
        );
        #100000;
        uart_send_frame(
            8'hA5, // SOF
            8'h08, // type: 停止运行并重新进入bootloader
            8'h00, // addr高字节
            8'h10, // addr低字节
            8'h12, // data[31:24]
            8'h34, // data[23:16]
            8'h56, // data[15:8]
            8'h78, // data[7:0]
            8'h5A  // EOF
        );
        #100000;
        uart_send_frame(
            8'hA5, // SOF
            8'h01, // type: 写data_ram
            8'h00, // addr高字节
            8'h10, // addr低字节
            8'h12, // data[31:24]
            8'h34, // data[23:16]
            8'h56, // data[15:8]
            8'h78, // data[7:0]
            8'h5A  // EOF
        );
        #100000;
        $stop; // 停止仿真
    end

    // 监控输出，实时打印data_out和data_valid
    /*always @(posedge clk) begin
        if (data_valid) begin
            $display($time, " data_out=%h, data_valid=%b", data_out, data_valid);
        end
    end

    always @(posedge clk) begin
        if (frame_valid) begin
            $display($time, " Frame Parsed: type=%h, addr=%h, data=%h", type_out, addr_out, data_out_frame);
        end
    end*/
    always @(posedge clk)begin
        if (mem_valid) begin
            $display($time, "dmem_write_we=%b, dmem_write_wmask=%b, dmem_write_addr=%h, dmem_write_data=%h", dmem_write_bus[52], dmem_write_bus[51:48], dmem_write_bus[47:32], dmem_write_bus[31:0]);
            $display($time, "imem_write_we=%b, imem_write_addr=%h, imem_write_data=%h", imem_write_bus[48], imem_write_bus[47:32], imem_write_bus[31:0]);
            $display($time, "CPU Reset=%b", reset);
        end
    end

endmodule

