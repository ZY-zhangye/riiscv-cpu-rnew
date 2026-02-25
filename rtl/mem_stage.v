`include "defines.v"
module mem_stage (
    input wire clk,
    input wire rst_n,
    //握手信号
    input wire es_to_ms_valid,
    output wire ms_allowin,
    output wire ms_to_ws_valid,
    input wire ws_allowin,
    //来自执行阶段的总线
    input wire [`ES_TO_MS_BUS_WD-1:0] exe_mem_bus_in,
    //输出到写回阶段的总线
    output wire [`MS_TO_WS_BUS_WD-1:0] mem_wb_bus_out,
    //数据存储器接口
    input wire [31:0] data_sram_rdata,
    //CSR相关信号
    output wire csr_we,
    output wire [11:0] csr_addr,
    output wire [31:0] csr_wdata,
    //数据前递路径
    output wire [31:0] mem_id_data,
    output wire [4:0] mem_id_waddr,
    output wire mem_id_we,
    //异常相关信号
    input wire [5:0] exception_code_em,
    input wire [31:0] exception_mtval_em,
    input wire exception_flag,
    output wire [5:0] exception_code,
    output wire [31:0] exception_mtval
);

wire ms_ready_go = 1'b1; // MEM 阶段无内部停顿，始终准备好
reg ms_valid;
assign ms_allowin = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = ms_valid && ms_ready_go;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ms_valid <= 1'b0;
    end else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end
end

// 从执行阶段传来的控制与数据信号
reg [`ES_TO_MS_BUS_WD-1:0] exe_mem_bus_r;
reg [5:0] exception_code_em_r;
reg [31:0] exception_mtval_em_r;
wire [31:0] mem_pc;
wire [31:0] alu_result;
wire [4:0] rd_out;
wire rd_wen;
wire [1:0] wb_sel;
wire mem_csr_we;
wire [11:0] mem_csr_addr;
wire [31:0] mem_csr_wdata;
assign {
    mem_pc,         // [31:0] 当前指令地址
    alu_result,     // [31:0] ALU计算结果
    rd_out,         // [4:0] 目的寄存器地址
    rd_wen,         // 1-bit 目的寄存器写使能
    wb_sel,         // [1:0] 写回数据选择信号
    mem_csr_we,     // 1-bit CSR写使能
    mem_csr_addr,       // [11:0] CSR地址
    mem_csr_wdata       // [31:0] CSR写数据
} = exe_mem_bus_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        exe_mem_bus_r <= 0;
        exception_code_em_r <= 0;
        exception_mtval_em_r <= 0;
    end else if (ms_allowin && es_to_ms_valid) begin
        if (exception_flag) begin
            exe_mem_bus_r <= 0; // 发生异常时，MEM阶段输出NOP
            exception_code_em_r <= 0;
            exception_mtval_em_r <= 0;
        end else begin
            exe_mem_bus_r <= exe_mem_bus_in; // 正常传递控制与数据
            exception_code_em_r <= exception_code_em;
            exception_mtval_em_r <= exception_mtval_em;
        end
    end
end

// 从数据存储器读取的结果
wire [31:0] mem_result = data_sram_rdata;

// 最终写回的数据选择
wire [31:0] ms_final_result = (wb_sel == 2'b00) ? alu_result : // ALU结果
                             (wb_sel == 2'b01) ? mem_result : // 访存结果
                             (wb_sel == 2'b10) ? mem_pc + 4 : // PC+4
                             32'b0; // 其他情况写入0（如不涉及写回的指令）

// 输出到写回阶段的总线打包
assign mem_wb_bus_out = {
    (rd_wen && !exception_flag),         // 1-bit 寄存器写使能
    rd_out,         // [4:0] 目的寄存器地址
    ms_final_result, // [31:0] 最终写回数据
    mem_pc          // [31:0] 当前指令地址
};
    
// 输出异常相关信号
assign exception_code = exception_code_em_r;
assign exception_mtval = exception_mtval_em_r;

// 输出CSR相关信号
assign csr_we = mem_csr_we && !exception_flag; // 发生异常时不写CSR
assign csr_addr = mem_csr_addr;
assign csr_wdata = exception_code_em_r[5] ? mem_pc : mem_csr_wdata; // 出现异常，复用CSR写数据为当前指令地址，便于异常处理程序获取异常发生的指令地址

// 数据前递路径输出
assign mem_id_data = ms_final_result;
assign mem_id_waddr = rd_out;
assign mem_id_we = rd_wen;

endmodule