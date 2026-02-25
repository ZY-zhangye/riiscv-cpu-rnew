`define MEM_HEX_PATH "C:\\Users\\ZY\\Desktop\\riiscv-cpu-rnew\\hex\\riscv-tests\\rv32ui-p-addi.hex"
// 加载内存文件
/*# 定义【标准整数运算指令集】数组 - RV32I 基础指令全集
UI_INSTS=(sw lw add addi sub and andi or ori xor xori 
          sll srl sra slli srli srai slt slti sltu sltiu 
          beq bne blt bge bltu bgeu jal jalr lui auipc lh lhu sh sb lb lbu)
# 定义【特殊系统指令集】数组 - 包含特权指令/系统调用指令
MI_INSTS=(csr scall sbreak ma_fetch)*/
//乘法指令
// UM_INSTS=(mul mulh mulhu mulhsu)

module my_cpu (
    input wire clk,
    input wire rst_n,
    //debug接口
    output wire [31:0] debug_wb_pc,
    output wire debug_wb_rf_wen,
    output wire [4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    output wire [31:0] debug_data,
    //外设接口
    output wire [3:0] led
);
wire [31:0] imem_addr;
wire [31:0] imem_rdata;
wire imem_ren;
wire [31:0] dmem_addr;
wire [31:0] dmem_wdata;
wire [3:0] dmem_wen;
wire [31:0] dmem_rdata;
wire dmem_en;

wire inst_ram_ren;
wire [31:0] inst_ram_addr;
wire [31:0] inst_ram_rdata;
wire inst_ram_wen;
wire [31:0] inst_ram_wdata;
wire data_ram_ren;
wire [31:0] data_ram_addr;
wire [31:0] data_ram_rdata;
wire [3:0]  data_ram_wen;
wire [31:0] data_ram_wdata;

top u_top(
    .clk(clk),
    .rst_n(rst_n),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .debug_data(debug_data),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .imem_ren(imem_ren),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_wen(dmem_wen),
    .dmem_rdata(dmem_rdata),
    .dmem_en(dmem_en)
);

bridge u_bridge(
    .clk(clk),
    .rst_n(rst_n),
    .inst_ram_ren(inst_ram_ren),
    .inst_ram_addr(inst_ram_addr),
    .inst_ram_rdata(inst_ram_rdata),
    .inst_ram_wen(inst_ram_wen),
    .inst_ram_wdata(inst_ram_wdata),
    .data_ram_ren(data_ram_ren),
    .data_ram_addr(data_ram_addr),
    .data_ram_rdata(data_ram_rdata),
    .data_ram_wen(data_ram_wen),
    .data_ram_wdata(data_ram_wdata),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .imem_ren(imem_ren),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_wen(dmem_wen),
    .dmem_rdata(dmem_rdata),
    .dmem_en(dmem_en),
    .led(led)
);

inst_ram  #(
    .MEM_HEX_PATH(`MEM_HEX_PATH)
)u_inst_ram
(
    .clk(clk),
    .rst_n(rst_n),
    .inst_ram_ren(inst_ram_ren),
    .inst_ram_addr(inst_ram_addr),
    .inst_ram_rdata(inst_ram_rdata),
    .inst_ram_wen(inst_ram_wen),
    .inst_ram_wdata(inst_ram_wdata)
);

data_ram  #(
    .MEM_HEX_PATH(`MEM_HEX_PATH)
)u_data_ram
(
    .clk(clk),
    .rst_n(rst_n),
    .data_ram_ren(data_ram_ren),
    .data_ram_addr(data_ram_addr),
    .data_ram_rdata(data_ram_rdata),
    .data_ram_wen(data_ram_wen),
    .data_ram_wdata(data_ram_wdata)
);

endmodule