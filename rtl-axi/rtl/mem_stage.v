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
    input wire data_sram_rvalid,
    //CSR相关信号
    output wire csr_we,
    output wire [11:0] csr_addr,
    output wire [31:0] csr_wdata,
    //数据前递路径
    output wire [31:0] mem_id_data,
    output wire [4:0] mem_id_waddr,
    output wire mem_id_we,
    // 给ID阶段的load阻塞信息（AXI可变延迟场景）
    output wire mem_load_pending,
    output wire [4:0] mem_load_rd,
    //异常相关信号
    input wire [5:0] exception_code_em,
    input wire [31:0] exception_mtval_em,
    input wire exception_iam_em,
    input wire exception_lam_em,
    input wire exception_sam_em,
    input wire [31:0] exception_addr_mtval_em,
    input wire [31:0] exception_iam_mtval_em,
    input wire exception_flag,
    output wire [5:0] exception_code,
    output wire [31:0] exception_mtval,
    //单独乘法器模块的计算结果
    input wire [31:0] mul_result,
    //AXI4-Lite接口的访存结果的数据前递接口
    output wire [31:0] mem_result
);

reg ms_valid;
wire load_req; // 访存请求标志
reg mem_data_valid;
wire ms_ready_go = !ms_valid || !load_req || mem_data_valid;
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
reg exception_iam_em_r;
reg exception_lam_em_r;
reg exception_sam_em_r;
reg [31:0] exception_addr_mtval_em_r;
reg [31:0] exception_iam_mtval_em_r;
reg flush_ms; // 来自EXE阶段的流水线冲刷信号
wire flush_es;
wire [4:0] mem_size; // 访存数据大小信号（从EXE阶段传来）
wire [31:0] mem_pc;
wire [31:0] alu_result;
wire [4:0] rd_out;
wire rd_wen;
wire [2:0] wb_sel;
wire mem_csr_we;
wire [11:0] mem_csr_addr;
wire [31:0] mem_csr_wdata;
assign {
    flush_es,       // 1-bit 来自EXE阶段的流水线冲刷信号
    mem_size,
    mem_pc,         // [31:0] 当前指令地址
    alu_result,     // [31:0] ALU计算结果
    rd_out,         // [4:0] 目的寄存器地址
    rd_wen,         // 1-bit 目的寄存器写使能
    wb_sel,         // [2:0] 写回数据选择信号
    mem_csr_we,     // 1-bit CSR写使能
    mem_csr_addr,       // [11:0] CSR地址
    mem_csr_wdata       // [31:0] CSR写数据
} = exe_mem_bus_r;

assign load_req = (wb_sel == 3'b001) && !flush_es && !flush_ms; // 访存指令标志
assign mem_load_pending = ms_valid && load_req && !mem_data_valid;
assign mem_load_rd = rd_out;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        exe_mem_bus_r <= 0;
        exception_code_em_r <= 0;
        exception_mtval_em_r <= 0;
        exception_iam_em_r <= 1'b0;
        exception_lam_em_r <= 1'b0;
        exception_sam_em_r <= 1'b0;
        exception_addr_mtval_em_r <= 32'b0;
        exception_iam_mtval_em_r <= 32'b0;
    end else if (ms_allowin && es_to_ms_valid) begin
        exe_mem_bus_r <= exe_mem_bus_in; // 正常传递控制与数据
        exception_code_em_r <= exception_code_em;
        exception_mtval_em_r <= exception_mtval_em;
        exception_iam_em_r <= exception_iam_em;
        exception_lam_em_r <= exception_lam_em;
        exception_sam_em_r <= exception_sam_em;
        exception_addr_mtval_em_r <= exception_addr_mtval_em;
        exception_iam_mtval_em_r <= exception_iam_mtval_em;
        if (exception_flag) begin
            flush_ms <= 1'b1; // 发生异常时，冲刷MEM阶段指令
        end else begin
            flush_ms <= 1'b0;
        end
    end
end

// 从数据存储器读取的结果
reg [31:0] mem_data;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_data <= 32'b0;
        mem_data_valid <= 1'b0;
    end else if (ms_allowin && es_to_ms_valid) begin
        mem_data_valid <= 1'b0;
    end else if (data_sram_rvalid) begin
        mem_data <= data_sram_rdata;
        mem_data_valid <= 1'b1;
    end else if (!ms_valid) begin
        mem_data_valid <= 1'b0;
    end
end
wire [1:0] data_offest = mem_size[4:3]; // 从mem_size中提取地址偏移信息
wire [7:0] selected_byte = mem_data >> (data_offest * 8); // 根据地址偏移选择正确的字节
wire [15:0] selected_half = mem_data >> (data_offest[1] * 16); // 根据地址偏移选择正确的半字
wire [31:0] mem_rd_data = (mem_size[0] && mem_size[1]) ? (mem_size[2] ? {{24{selected_byte[7]}}, selected_byte} : {24'b0, selected_byte})
                        : (mem_size[0] && !mem_size[1]) ? (mem_size[2] ? {{16{selected_half[15]}}, selected_half} : {16'b0, selected_half})
                        : mem_data; // 32位访存直接使用原数据
assign mem_result = mem_rd_data; // 访存结果

// 最终写回的数据选择
wire [31:0] ms_final_result = (wb_sel == 3'b000) ? alu_result : // ALU结果
                             (wb_sel == 3'b001) ? mem_result : // 访存结果
                             (wb_sel == 3'b010) ? mem_pc + 4 : // PC+4
                             (wb_sel == 3'b100) ? mul_result : // 单独乘法器结果
                             32'b0; // 其他情况写入0（如不涉及写回的指令）

// 输出到写回阶段的总线打包
wire [5:0] exception_code_final = (exception_code_em_r == 6'b111111) ? 6'b111111 : // 优先输出来自EXE阶段的异常
                                  (flush_es || flush_ms) ? 6'b0 : // 冲刷时不输出异常
                                  exception_iam_em_r ? 6'b100000 :
                                  exception_lam_em_r ? 6'b100100 :
                                  exception_sam_em_r ? 6'b100110 :
                                  exception_code_em_r;
wire [31:0] exception_mtval_final = exception_iam_em_r ? exception_iam_mtval_em_r :
                                    (exception_lam_em_r || exception_sam_em_r) ? exception_addr_mtval_em_r :
                                    exception_mtval_em_r;

assign mem_wb_bus_out = {
    (rd_wen && !exception_code_final[5:0] && !flush_ms && !flush_es),         // 1-bit 寄存器写使能
    rd_out,         // [4:0] 目的寄存器地址
    ms_final_result, // [31:0] 最终写回数据
    mem_pc          // [31:0] 当前指令地址
};
    
// 输出异常相关信号
assign exception_code = exception_code_final;
assign exception_mtval = exception_mtval_final;

// 输出CSR相关信号
assign csr_we = mem_csr_we && !exception_code_final[5:0] && !flush_ms && !flush_es; // 发生异常时不写CSR
assign csr_addr = mem_csr_addr;
assign csr_wdata = exception_code_final[5] ? mem_pc : mem_csr_wdata; // 出现异常，复用CSR写数据为当前指令地址，便于异常处理程序获取异常发生的指令地址

// 数据前递路径输出
assign mem_id_data = ms_final_result;
assign mem_id_waddr = rd_out;
assign mem_id_we = rd_wen && !exception_code_final[5:0] && !flush_ms && !flush_es; // 发生异常时不前递数据

endmodule