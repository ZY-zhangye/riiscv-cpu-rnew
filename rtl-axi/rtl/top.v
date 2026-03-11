`include "defines.v"
module top (
    input wire clk,
    input wire rst_n,
    //指令存储器接口
    output wire [31:0] imem_addr,
    input wire [31:0] imem_rdata,
    output wire imem_ren,
    input wire imem_rvalid,
    //数据存储器接口
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0] dmem_wen,
    input wire [31:0] dmem_rdata,
    output wire dmem_en,
    input wire dmem_stall,
    input wire dmem_rvalid,
    //调试接口
    output wire [31:0] debug_wb_pc,
    output wire  debug_wb_rf_wen,
    output wire [4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    output wire [31:0] debug_data
);
// IF 阶段
wire fs_to_ds_valid;
wire ds_allowin;
wire [`FS_TO_DS_BUS_WD-1:0] if_id_bus;
wire [5:0] exception_code_fd;
wire [31:0] exception_mtval_fd;
wire exception_flag;
wire [31:0] exception_addr;
// ID 阶段
wire ds_to_es_valid;
wire es_allowin;
wire [`DS_TO_ES_BUS_WD-1:0] id_exe_bus;
wire [4:0] reg_addr1;
wire [4:0] reg_addr2;
wire [31:0] reg_data1;
wire [31:0] reg_data2;
wire [11:0] csr_raddr;
wire [31:0] csr_rdata;
wire [5:0] exception_code_de;
wire [31:0] exception_mtval_de;
// EXE 阶段
wire es_to_ms_valid;
wire ms_allowin;
wire [`ES_TO_MS_BUS_WD-1:0] exe_mem_bus;
wire [31:0] exe_id_data;
wire [4:0] exe_id_waddr;
wire exe_id_we;
wire exe_id_es_valid;
wire exe_load_valid;
wire [31:0] exe_id_csr_wdata;
wire exe_id_csr_we;
wire [11:0] exe_id_csr_addr;
wire [31:0] br_target;
wire br_taken;
wire [5:0] exception_code_em;
wire [31:0] exception_mtval_em;
wire exception_iam_em;
wire exception_lam_em;
wire exception_sam_em;
wire [31:0] exception_addr_mtval_em;
wire [31:0] exception_iam_mtval_em;
// MEM 阶段
wire ms_to_ws_valid;
wire ws_allowin;
wire [`MS_TO_WS_BUS_WD-1:0] mem_wb_bus;
wire [31:0] mem_id_data;
wire [4:0] mem_id_waddr;
wire mem_id_we;
wire mem_load_pending;
wire [4:0] mem_load_rd;
wire csr_we;
wire [11:0] csr_addr;
wire [31:0] csr_wdata;
wire [5:0] exception_code;
wire [31:0] exception_mtval;
wire timer_interrupt_flag;
wire [4:0] interrupt_code;
wire [31:0] mem_result; // 从数据存储器前递的结果
// WB 阶段
wire rf_we;
wire [4:0] rf_waddr;
wire [31:0] rf_wdata;
//单独乘法器模块接口
wire [31:0] mul_result;
wire [31:0] a;
wire [31:0] b;
wire [3:0] op;

//debug接口
assign debug_wb_rf_wen = rf_we;
assign debug_wb_rf_wnum = rf_waddr;
assign debug_wb_rf_wdata = rf_wdata;

if_stage u_if_stage (
    .clk(clk),
    .rst_n(rst_n),
    .pc_out(imem_addr),
    .inst_in(imem_rdata),
    .inst_valid(imem_rvalid),
    .inst_ren(imem_ren),
    .ds_allowin(ds_allowin),
    .fs_to_ds_valid(fs_to_ds_valid),
    .if_id_bus_out(if_id_bus),
    .br_target(br_target),
    .br_jmp_flag(br_taken),
    .exception_code_fd(exception_code_fd),
    .exception_mtval_fd(exception_mtval_fd),
    .exception_flag(exception_flag),
    .exception_addr(exception_addr)
);

id_stage u_id_stage (
    .clk(clk),
    .rst_n(rst_n),
    .if_id_bus_in(if_id_bus),
    .fs_to_ds_valid(fs_to_ds_valid),
    .ds_allowin(ds_allowin),
    .ds_to_es_valid(ds_to_es_valid),
    .es_allowin(es_allowin),
    .id_exe_bus_out(id_exe_bus),
    .reg_addr1(reg_addr1),
    .reg_addr2(reg_addr2),
    .reg_data1(reg_data1),
    .reg_data2(reg_data2),
    .csr_raddr(csr_raddr),
    .csr_rdata(csr_rdata),
    .wb_data_wen(rf_we),
    .wb_data_addr(rf_waddr),
    .wb_data(rf_wdata),
    .mem_data_wen(mem_id_we),
    .mem_data_addr(mem_id_waddr),
    .mem_data(mem_id_data),
    .mem_load_pending(mem_load_pending),
    .mem_load_rd(mem_load_rd),
    .exe_data_wen(exe_id_we),
    .exe_data_addr(exe_id_waddr),
    .exe_data(exe_id_data),
    .exe_id_es_valid(exe_id_es_valid),
    .exe_load_valid(exe_load_valid),
    .exe_id_csr_wdata(exe_id_csr_wdata),
    .exe_id_csr_we(exe_id_csr_we),
    .exe_id_csr_addr(exe_id_csr_addr),
    .br_jmp_flag(br_taken),
    .exception_code_de(exception_code_de),
    .exception_mtval_de(exception_mtval_de),
    .exception_flag(exception_flag),
    .exception_code_fd(exception_code_fd),
    .exception_mtval_fd(exception_mtval_fd),
    .a(a), // 从寄存器文件读取的第一个操作数
    .b(b), // 从寄存器文件读取的第二个操作数
    .op(op) // 传递操作码到乘法器模块
);

exe_stage u_exe_stage (
    .clk(clk),
    .rst_n(rst_n),
    .ds_to_es_valid(ds_to_es_valid),
    .ms_allowin(ms_allowin),
    .es_to_ms_valid(es_to_ms_valid),
    .id_exe_bus_in(id_exe_bus),
    .es_allowin(es_allowin),
    .exe_mem_bus_out(exe_mem_bus),
    .data_sram_en(dmem_en),
    .data_sram_wen(dmem_wen),
    .data_sram_addr(dmem_addr),
    .data_sram_wdata(dmem_wdata),
    .data_stall(dmem_stall),
    .exe_id_data(exe_id_data),
    .exe_id_waddr(exe_id_waddr),
    .exe_id_we(exe_id_we),
    .exe_id_es_valid(exe_id_es_valid),
    .exe_load_valid(exe_load_valid),
    .exe_id_csr_wdata(exe_id_csr_wdata),
    .exe_id_csr_we(exe_id_csr_we),
    .exe_id_csr_addr(exe_id_csr_addr),
    .br_target(br_target),
    .br_taken(br_taken),
    .exception_code_de(exception_code_de),
    .exception_mtval_de(exception_mtval_de),
    .exception_code_em(exception_code_em),
    .exception_mtval_em(exception_mtval_em),
    .exception_iam_em(exception_iam_em),
    .exception_lam_em(exception_lam_em),
    .exception_sam_em(exception_sam_em),
    .exception_addr_mtval_em(exception_addr_mtval_em),
    .exception_iam_mtval_em(exception_iam_mtval_em),
    .exception_flag(exception_flag),
    .mult_result(mul_result) // 从单独乘法器模块接收计算结果
);

mem_stage u_mem_stage (
    .clk(clk),
    .rst_n(rst_n),
    .es_to_ms_valid(es_to_ms_valid),
    .ms_allowin(ms_allowin),
    .ms_to_ws_valid(ms_to_ws_valid),
    .ws_allowin(ws_allowin),
    .exe_mem_bus_in(exe_mem_bus),
    .mem_wb_bus_out(mem_wb_bus),
    .data_sram_rdata(dmem_rdata),
    .data_sram_rvalid(dmem_rvalid),
    .csr_we(csr_we),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .mem_id_data(mem_id_data),
    .mem_id_waddr(mem_id_waddr),
    .mem_id_we(mem_id_we),
    .mem_load_pending(mem_load_pending),
    .mem_load_rd(mem_load_rd),
    .exception_code_em(exception_code_em),
    .exception_mtval_em(exception_mtval_em),
    .exception_iam_em(exception_iam_em),
    .exception_lam_em(exception_lam_em),
    .exception_sam_em(exception_sam_em),
    .exception_addr_mtval_em(exception_addr_mtval_em),
    .exception_iam_mtval_em(exception_iam_mtval_em),
    .exception_flag(exception_flag),
    .exception_code(exception_code),
    .exception_mtval(exception_mtval),
    .timer_interrupt_flag(timer_interrupt_flag),
    .interrupt_code(interrupt_code),
    .mul_result(mul_result), // 从单独乘法器模块接收计算结果
    .mem_result(mem_result) // 从数据存储器前递的结果
);

wb_stage u_wb_stage (
    .clk(clk),
    .rst_n(rst_n),
    .ms_to_ws_valid(ms_to_ws_valid),
    .ws_allowin(ws_allowin),
    .mem_wb_bus(mem_wb_bus),
    .rf_we(rf_we),
    .rf_waddr(rf_waddr),
    .rf_wdata(rf_wdata),
    .debug_wb_pc(debug_wb_pc)
);

regfiles u_regfiles (
    .clk(clk),
    .rst_n(rst_n),
    .we(rf_we),
    .waddr(rf_waddr),
    .wdata(rf_wdata),
    .raddr1(reg_addr1),
    .rdata1(reg_data1),
    .raddr2(reg_addr2),
    .rdata2(reg_data2),
    .debug_data(debug_data)
);

regfiles_csr u_regfiles_csr (
    .clk(clk),
    .rst_n(rst_n),
    .csr_we(csr_we),
    .csr_waddr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_raddr(csr_raddr),
    .csr_rdata(csr_rdata),
    .exception_code(exception_code),
    .exception_mtval(exception_mtval),
    .exception_flag(exception_flag),
    .exception_addr(exception_addr),
    .timer_interrupt_flag(timer_interrupt_flag),
    .interrupt_code(interrupt_code)
);

mult u_mult (
    .clk(clk),
    .rst_n(rst_n),
    .a(a), // 从寄存器文件读取的第一个操作数
    .b(b), // 从寄存器文件读取的第二个操作数
    .op(op), // 从ID阶段传来的操作码，区分乘法类型
    .result(mul_result) // 计算结果输出到EXE阶段
);

endmodule