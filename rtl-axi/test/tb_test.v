`timescale 1ns/1ps
`define MEM_HEX_PATH "C:\\Users\\ZY\\Desktop\\riscv-cpu-rnew\\hex\\uart.hex"
// 加载内存文件
/*# 定义【标准整数运算指令集】数组 - RV32I 基础指令全集
UI_INSTS=(sw lw add addi sub and andi or ori xor xori 
          sll srl sra slli srli srai slt slti sltu sltiu 
          beq bne blt bge bltu bgeu jal jalr lui auipc lh lhu sh sb lb lbu)
# 定义【特殊系统指令集】数组 - 包含特权指令/系统调用指令
MI_INSTS=(csr scall sbreak ma_fetch)*/
//乘法指令
// UM_INSTS=(mul mulh mulhu mulhsu)

module tb_test;
reg clk;
reg rst_n;
wire [31:0] debug_wb_pc;
wire [31:0] debug_inst_pc;
wire debug_wb_rf_wen;
wire [4:0] debug_wb_rf_wnum;
wire [31:0] debug_wb_rf_wdata;
wire [31:0] debug_data;
wire [3:0] led;
reg clk_uart;
reg rx;
wire tx;

// UART 参数：115200 波特率。
parameter integer UART_BAUD_RATE = 115200;
real UART_BIT_PERIOD_NS;
real UART_HALF_BIT_PERIOD_NS;

// TX 口接收监视结果。
wire [7:0] tx_mon_data;
wire tx_mon_valid;
wire tx_mon_frame_error;
integer tx_mon_count;

initial begin
    UART_BIT_PERIOD_NS = 1_000_000_000.0 / UART_BAUD_RATE;
    UART_HALF_BIT_PERIOD_NS = UART_BIT_PERIOD_NS / 2.0;
end

initial begin
    clk = 0;
    forever #10 clk = ~clk; // 50MHz 时钟
end
initial begin
    clk_uart = 0;
    rx = 1; // UART 接收线默认高电平
    forever #(UART_HALF_BIT_PERIOD_NS) clk_uart = ~clk_uart;
end
initial begin
    rst_n = 0;
    #20 rst_n = 1; // 20ns 后释放复位
end

// 向 DUT 的 rx 发送 1 字节 UART 数据（8N1，LSB first）。
task automatic uart_send_byte;
    input [7:0] data;
    integer i;
    begin
        // 起始位
        rx = 1'b0;
        #(UART_BIT_PERIOD_NS);

        // 数据位（低位先发）
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i];
            #(UART_BIT_PERIOD_NS);
        end

        // 停止位
        rx = 1'b1;
        #(UART_BIT_PERIOD_NS);
    end
endtask

cpu_top #(
   // .MEM_HEX_PATH(`MEM_HEX_PATH),
    .IF_MAX_CONSECUTIVE_GRANTS(8)
) u_cpu_top (
    .clk(clk),
    .rst_n(rst_n),
    .debug_wb_pc(debug_wb_pc),
    .debug_inst_pc(debug_inst_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .debug_data(debug_data),
    .led(led),
    .clk_uart(clk_uart),
    .rx(rx),
    .tx(tx)

);

// 监视 DUT 的 tx，按 115200 波特率解码。
uart_rx_monitor #(
    .BAUD_RATE(UART_BAUD_RATE)
) u_uart_rx_monitor (
    .rx(tx),
    .data(tx_mon_data),
    .data_valid(tx_mon_valid),
    .frame_error(tx_mon_frame_error)
);

initial begin
    tx_mon_count = 0;
end

// 发送测试激励：向 rx 注入若干字节。
initial begin
    @(posedge rst_n);
    #(UART_BIT_PERIOD_NS * 20.0);

    $display("[TB][UART] Start driving RX at 115200 baud...");
    uart_send_byte(8'h55);
    uart_send_byte(8'hAA);
    uart_send_byte(8'h31);
    uart_send_byte(8'h0D);
    $display("[TB][UART] RX stimulus finished.");
end

// 打印 tx 解码结果。
always @(posedge tx_mon_valid) begin
    tx_mon_count = tx_mon_count + 1;
    $display("[TB][UART][TX_MON] time=%0t ns, idx=%0d, byte=0x%02h, frame_error=%0b", $time, tx_mon_count, tx_mon_data, tx_mon_frame_error);
end

initial begin
    $display("Starting simulation...");
    $dumpfile("tb_top.vcd");    // 指定波形文件名
    $dumpvars(0, u_cpu_top);   // 0表示tb_top模块及其所有子模块
    #5000000; // 设定最大结束时间，避免仿真无限进行
    $display("----------------------------------------------");
    $display("Simulation timeout.");
    $stop;
end

/*always @ (posedge clk) begin
    if (rst_n) begin
        $display("---------------------------------------------");
        $display("Time: %0t", $time);
        $display("debug_inst_pc: %h", debug_inst_pc);
        $display("debug_wb_pc: %h", debug_wb_pc);
        $display("debug_wb_rf_wen: %b", debug_wb_rf_wen);
        $display("debug_wb_rf_wnum: %h", debug_wb_rf_wnum);
        $display("debug_wb_rf_wdata: %h", debug_wb_rf_wdata);
        $display("debug_data: %h", debug_data);
    end
end*/

/*always @ (posedge clk_uart) begin
    $display("---------------------------------------------");
    $display("Time: %0t", $time);
    $display("tx: %b", tx);
end*/

/*always @ (posedge clk) begin
    if (rst_n) begin
        if (debug_wb_pc == 32'h00000044) begin
                $display("---------------------------------------------");
                $display("Time: %0t", $time);
                $display("Simulation finished.");
                $display("----------------------------------------------");
            if (debug_data == 32'h00000001) begin
                $display("Test passed.");
            end else begin
                $display("Test failed. Expected 1 in x10, got %08h", debug_data);
            end
            $display("----------------------------------------------");
            $stop;
        end
    end
end*/

endmodule

// -----------------------------------------------------------------------------
// UART 接收监视模块：对输入 rx 进行 8N1 解码。
// -----------------------------------------------------------------------------
module uart_rx_monitor #(
    parameter integer BAUD_RATE = 115200
)(
    input wire rx,
    output reg [7:0] data,
    output reg data_valid,
    output reg frame_error
);
    real BIT_PERIOD_NS;
    reg [7:0] shift;
    integer i;

    initial begin
        BIT_PERIOD_NS = 50_000_000.0 / BAUD_RATE;
        data = 8'h00;
        data_valid = 1'b0;
        frame_error = 1'b0;
        shift = 8'h00;
    end

    always begin
        data_valid = 1'b0;
        @(negedge rx);
        if (rx === 1'b0) begin
            // 到达每个数据位中心点采样。
            #(BIT_PERIOD_NS * 1.5);
            for (i = 0; i < 8; i = i + 1) begin
                shift[i] = rx;
                #(BIT_PERIOD_NS);
            end

            // 采样停止位。
            frame_error = (rx !== 1'b1);
            data = shift;
            data_valid = 1'b1;
            #1;
            data_valid = 1'b0;
        end
    end
endmodule