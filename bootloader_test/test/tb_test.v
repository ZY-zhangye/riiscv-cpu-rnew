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
    wire [3:0] led; // 监控LED输出
    // UART参数定义，与被测模块保持一致
    parameter CLK_FREQ = 50000000;   // 仿真时钟频率（Hz）
    parameter BAUD_RATE = 115200;    // 仿真波特率
    localparam BAUD_PERIOD = 1_000_000_000 / BAUD_RATE; // 一个比特周期，单位ns
    wire baud_tick;

    // 用于批量写inst_ram的变量声明
    integer i;
    reg [31:0] inst_mem [0:511];
    //debug 接口监控信号
    wire [31:0] debug_inst_pc;
    wire [31:0] debug_wb_pc;
    wire debug_wb_rf_wen;
    wire [4:0] debug_wb_rf_wnum;
    wire [31:0] debug_wb_rf_wdata;
    wire [31:0] debug_data;

    reg boot_loader_flag; //bootloader完成标志
    wire reset; //监控CPU复位状态

    // 实例化被测UART模块
    baud_gen #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) baud_gen_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_tick(baud_tick)
    );
    my_cpu u_my_cpu (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .baud_tick(baud_tick),
        .led(led),
        .debug_inst_pc(debug_inst_pc),
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata),
        .debug_data(debug_data),
        .reset(reset)
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

    // 通用帧发送任务：固定SOF(8'hA5)和EOF(8'h5A)，只传中间7字节
    task uart_send_frame_middle;
        input [7:0] b1; // type
        input [7:0] b2; // addr高
        input [7:0] b3; // addr低
        input [7:0] b4; // data[31:24]
        input [7:0] b5; // data[23:16]
        input [7:0] b6; // data[15:8]
        input [7:0] b7; // data[7:0]
        begin
            uart_send_byte(8'hA5); // SOF
            uart_send_byte(b1);
            uart_send_byte(b2);
            uart_send_byte(b3);
            uart_send_byte(b4);
            uart_send_byte(b5);
            uart_send_byte(b6);
            uart_send_byte(b7);
            uart_send_byte(8'h5A); // EOF
        end
    endtask

    // type=8'h01 写data_ram
    task uart_send_write_data_ram;
        input [15:0] addr;
        input [31:0] data;
        begin
            uart_send_frame_middle(
                8'h01,
                addr[15:8],
                addr[7:0],
                data[31:24],
                data[23:16],
                data[15:8],
                data[7:0]
            );
        end
    endtask

    // type=8'h02 写inst_ram
    task uart_send_write_inst_ram;
        input [15:0] addr;
        input [31:0] data;
        begin
            uart_send_frame_middle(
                8'h02,
                addr[15:8],
                addr[7:0],
                data[31:24],
                data[23:16],
                data[15:8],
                data[7:0]
            );
        end
    endtask

    // type=8'h04 启动运行
    task uart_send_start;
        input [15:0] addr;
        input [31:0] data;
        begin
            uart_send_frame_middle(
                8'h04,
                addr[15:8],
                addr[7:0],
                data[31:24],
                data[23:16],
                data[15:8],
                data[7:0]
            );
            boot_loader_flag = 1; //设置bootloader完成标志，开始监控CPU运行状态
        end
    endtask

    // type=8'h08 停止运行并重新进入bootloader
    task uart_send_stop;
        input [15:0] addr;
        input [31:0] data;
        begin
            uart_send_frame_middle(
                8'h08,
                addr[15:8],
                addr[7:0],
                data[31:24],
                data[23:16],
                data[15:8],
                data[7:0]
            );
        end
    endtask

    // 初始化rx为高，空闲状态
    initial begin
        rx = 1;
    end

    // 主测试流程
    // 1. 等待复位结束
    // 2. 发送不同type的帧，调用不同任务
    initial begin
        @(posedge rst_n); // 等待复位结束
        boot_loader_flag = 0; //复位后bootloader未完成
        #1000;
        #100000;
        // 2. 批量写inst_ram，数据来自inst.hex（Intel HEX格式）
        $readmemh("C:\\Users\\ZY\\Desktop\\riscv-cpu-rnew\\bootloader_test\\hex\\rv32mi-p-csr.hex", inst_mem);
        for (i = 0; i < 512; i = i + 1) begin // inst.hex共2055条指令
            uart_send_write_inst_ram({i[13:0],2'b00}, inst_mem[i]);//地址按字对齐
            #20000;
        end
        #100000;
        // 3. 启动运行
        uart_send_start(16'h0000, 32'h00000000);
        #100000;
        // 4. 停止运行并重新进入bootloader
        //uart_send_stop(16'h0000, 32'h00000000);
        //#100000;
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
    /*always @(posedge clk)begin
        if (mem_valid) begin
            $display($time, "dmem_write_we=%b, dmem_write_wmask=%b, dmem_write_addr=%h, dmem_write_data=%h", dmem_write_bus[52], dmem_write_bus[51:48], dmem_write_bus[47:32], dmem_write_bus[31:0]);
            $display($time, "imem_write_we=%b, imem_write_addr=%h, imem_write_data=%h", imem_write_bus[48], imem_write_bus[47:32], imem_write_bus[31:0]);
            $display($time, "CPU Reset=%b", reset);
        end
    end*/
    initial begin
        $monitor($time, " LED Output: %b", led);
    end
    initial begin
        $monitor($time, "reset: %b", reset);
    end
    initial begin
        $monitor($time, "bootloader flag: %b", boot_loader_flag);
    end

    always @(posedge clk) begin
        if (boot_loader_flag) begin //仅在bootloader完成后监控CPU运行状态
            $display($time, " debug_inst_pc=%h, debug_wb_pc=%h, debug_wb_rf_wen=%b, debug_wb_rf_wnum=%h, debug_wb_rf_wdata=%h, debug_data=%h",
                debug_inst_pc, debug_wb_pc, debug_wb_rf_wen, debug_wb_rf_wnum, debug_wb_rf_wdata, debug_data);
        end
    end

    /*initial begin
        if (boot_loader_flag) begin
            #1000000; //运行一段时间后停止仿真
            $stop;
        end
    end*/

endmodule

