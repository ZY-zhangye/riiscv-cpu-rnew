`define MEM_HEX_PATH "C:\\Users\\ZY\\Desktop\\riscv-cpu-rnew\\hex\\riscv-tests\\rv32-p-riscv.hex"
// 加载内存文件
/*# 定义【标准整数运算指令集】数组 - RV32I 基础指令全集
UI_INSTS=(sw lw add addi sub and andi or ori xor xori 
          sll srl sra slli srli srai slt slti sltu sltiu 
          beq bne blt bge bltu bgeu jal jalr lui auipc lh lhu sh sb lb lbu)
# 定义【特殊系统指令集】数组 - 包含特权指令/系统调用指令
MI_INSTS=(csr scall sbreak ma_fetch)*/
//乘法指令
// UM_INSTS=(mul mulh mulhu mulhsu)

module tb_top;
reg clk;
reg rst_n;
wire [31:0] debug_wb_pc;
wire debug_wb_rf_wen;
wire [4:0] debug_wb_rf_wnum;
wire [31:0] debug_wb_rf_wdata;
wire [31:0] debug_data;
wire [3:0] led;
wire [31:0] imem_addr;

my_cpu  #(
    .MEM_HEX_PATH(`MEM_HEX_PATH)
) u_my_cpu(
    .clk(clk),
    .rst_n(rst_n),
    .debug_inst_pc(imem_addr),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .debug_data(debug_data),
    .led(led)
);

initial begin
    clk = 0;
    rst_n = 0;
    #100 rst_n = 1;
end

always #5 clk = ~clk; // 100MHz

initial begin
    $display("Starting simulation...");
    $dumpfile("tb_top.vcd");    // 指定波形文件名
    $dumpvars(0, u_my_cpu);   // 0表示tb_top模块及其所有子模块
    #25000; // 设定最大结束时间，避免仿真无限进行
    $display("----------------------------------------------");
    $display("Simulation timeout.");
    $stop;
end

always @ (posedge clk) begin
    if (rst_n) begin
        $display("---------------------------------------------");
        $display("Time: %0t", $time);
        $display("debug_inst_pc: %h", imem_addr);
        $display("debug_wb_pc: %h", debug_wb_pc);
        $display("debug_wb_rf_wen: %b", debug_wb_rf_wen);
        $display("debug_wb_rf_wnum: %h", debug_wb_rf_wnum);
        $display("debug_wb_rf_wdata: %h", debug_wb_rf_wdata);
        $display("debug_data: %h", debug_data);
    end
end

always @ (posedge clk) begin
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
end
endmodule