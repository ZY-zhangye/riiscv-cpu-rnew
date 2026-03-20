`include "defines.v"
module exe_stage (
    input wire clk,
    input wire rst_n,
    //握手信号
    input wire ds_to_es_valid,
    output wire es_allowin,
    output wire es_to_ms_valid,
    input wire ms_allowin,
    //来自译码阶段的总线
    input wire [`DS_TO_ES_BUS_WD-1:0] id_exe_bus_in,
    //输出到访存阶段的总线
    output wire [`ES_TO_MS_BUS_WD-1:0] exe_mem_bus_out,
    //数据存储器接口
    output wire data_sram_en,
    output wire [3:0] data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    // 与buffer耦合的阻塞信号（FIFO满时阻塞访存指令）
    input wire data_stall,
    //数据前递路径
    output wire [31:0] exe_id_data,
    output wire [4:0] exe_id_waddr,
    output wire exe_id_we,
    output wire exe_id_es_valid,
    output wire exe_load_valid,
    output wire [31:0] exe_id_csr_wdata,
    output wire exe_id_csr_we,
    output wire [11:0] exe_id_csr_addr,
    //跳转指令与分支指令的目标地址与信号
    output wire [31:0] br_target,
    output wire br_taken,
    //异常相关信号
    input wire [5:0] exception_code_de,
    input wire [31:0] exception_mtval_de,
    output wire [5:0] exception_code_em,
    output wire [31:0] exception_mtval_em,
    output wire exception_iam_em,
    output wire exception_lam_em,
    output wire exception_sam_em,
    output wire [31:0] exception_addr_mtval_em,
    output wire [31:0] exception_iam_mtval_em,
    input wire exception_flag,
    //单独乘法器可能造成的数据冒险前递接口
    input wire [31:0] mult_result
);

wire mem_req;
reg es_valid;
wire es_ready_go = !(es_valid && mem_req && data_stall); // EXE 阶段无内部停顿，始终准备好
assign exe_id_es_valid = es_valid; // 将EXE阶段的有效信号传递给ID阶段，用于数据前递和冒险检测
assign es_allowin = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid = es_valid && es_ready_go;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        es_valid <= 1'b0;
    end else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end
end

// 从译码阶段传来的控制与数据信号
reg [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus_r;
reg [5:0] exception_code_reg;
reg [31:0] exception_mtval_reg;
reg flush_es; // 标志: 当前指令需要被冲掉（异常或分支跳转）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ds_to_es_bus_r <= 0;
        exception_code_reg <= 0;
        exception_mtval_reg <= 0;
        flush_es <= 1'b0;
    end else if (es_allowin && ds_to_es_valid) begin
        ds_to_es_bus_r <= id_exe_bus_in; // 正常传递控制与数据
        exception_code_reg <= exception_code_de;
        exception_mtval_reg <= exception_mtval_de;
        if (exception_flag) begin
            flush_es <= 1'b1; // 发生异常，标记当前指令需要被冲掉
        end else begin
            flush_es <= 1'b0;
        end
    end
end

// 从打包总线中解包出的控制与数据信号
wire flush_ds; // 来自ID阶段的指令冲掉标志
wire [31:0] exe_pc;
wire [31:0] exe_imm;
wire [31:0] exe_rs1_data;
wire [31:0] exe_rs2_data;
wire [3:0] exe_op1_sel;
wire [2:0] exe_op2_sel;
wire [11:0] exe_alu_op;
// one-hot分支类型，每位对应一种分支
wire exe_br_beq;
wire exe_br_bne;
wire exe_br_blt;
wire exe_br_bge;
wire exe_br_bltu;
wire exe_br_bgeu;
wire exe_jmp_flag;
wire exe_rd_wen;
wire [4:0] exe_rd_addr;
wire [2:0] exe_wb_sel;
wire [3:0] exe_csr_cmd;
wire exe_csr_we;
wire [11:0] exe_csr_addr;
wire [31:0] csr_rdata;
wire exe_mem_we;
wire exe_mem_re;
wire [2:0] exe_mem_size;
assign {
    flush_ds,        // 1-bit 来自ID阶段的指令冲掉标志
    exe_pc,
    exe_imm,
    exe_rs1_data,
    exe_rs2_data,
    exe_op1_sel,
    exe_op2_sel,
    exe_alu_op,
    exe_br_beq,
    exe_br_bne,
    exe_br_blt,
    exe_br_bge,
    exe_br_bltu,
    exe_br_bgeu,
    exe_jmp_flag,
    exe_rd_wen,
    exe_rd_addr,
    exe_wb_sel,
    exe_csr_cmd,
    exe_csr_we,
    exe_csr_addr,
    csr_rdata,
    exe_mem_we,
    exe_mem_re,
    exe_mem_size
} = ds_to_es_bus_r;

assign mem_req = exe_mem_we || exe_mem_re; // 访存请求信号，供EXE阶段内部使用

// ALU操作数选择
// 先做一次轻量预选择：若需要则从乘法结果旁路rs1，随后各功能组继续独立选择，
// 保持“分组拆分”的时序优化目标，避免回退到全局大mux链。
wire [31:0] real_rs1_data = exe_op1_sel[3] ? mult_result : exe_rs1_data;
wire [31:0] real_rs2_data = exe_rs2_data;
wire [31:0] op1_data;

// 按功能分组的操作数选择：避免所有运算共享同一套“超大mux链”
wire [31:0] arith_src1 = exe_op1_sel[2] ? real_rs1_data :
                        exe_op1_sel[1] ? exe_pc :
                        exe_op1_sel[0] ? exe_imm : 32'b0;
wire [31:0] arith_src2 = exe_op2_sel[1] ? real_rs2_data :
                        exe_op2_sel[0] ? exe_imm : 32'b0;

wire [31:0] logic_src1 = real_rs1_data;
wire [31:0] logic_src2 = exe_op2_sel[0] ? exe_imm : real_rs2_data;

wire [31:0] shift_src1 = real_rs1_data;
wire [4:0] shift_amt = exe_op2_sel[0] ? exe_imm[4:0] : real_rs2_data[4:0];

wire [31:0] cmp_src1 = real_rs1_data;
wire [31:0] cmp_src2 = exe_op2_sel[0] ? exe_imm : real_rs2_data;

// CSR路径单独分离，减少与普通ALU路径耦合
wire [31:0] csr_src_old = csr_rdata;
wire [31:0] csr_src_op1 = exe_op1_sel[2] ? real_rs1_data :
                         exe_op1_sel[0] ? exe_imm : 32'b0;

// 兼容现有后续逻辑保留的统一操作数（用于少量非关键路径逻辑）
assign op1_data = exe_op1_sel[2] ? real_rs1_data :
                  exe_op1_sel[1] ? exe_pc :
                  exe_op1_sel[0] ? exe_imm : 32'b0;

// ALU计算结果
wire ALU_ADD;          //加法       
wire ALU_SUB;           //减法
wire ALU_AND;           //按位与
wire ALU_OR;            //按位或
wire ALU_XOR;           //按位异或
wire ALU_SLL;           //逻辑左移
wire ALU_SRL;           //逻辑右移
wire ALU_SRA;           //算术右移
wire ALU_SLT;           //有符号比较小于
wire ALU_SLTU;          //无符号比较小于
wire ALU_JALR;          //JALR指令的ALU操作（计算跳转地址）
wire ALU_COPY1;         //仅将第一个操作数传递到EXE阶段（用于CSR指令，ALU不进行计算）
assign {ALU_ADD,  ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
        ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU,
        ALU_JALR, ALU_COPY1} = exe_alu_op;


wire [31:0] alu_add = arith_src1 + arith_src2;
wire [31:0] alu_sub = arith_src1 - arith_src2;
wire [31:0] alu_and = logic_src1 & logic_src2;
wire [31:0] alu_or  = logic_src1 | logic_src2;
wire [31:0] alu_xor = logic_src1 ^ logic_src2;
wire [31:0] alu_sll = shift_src1 << shift_amt;
wire [31:0] alu_srl = shift_src1 >> shift_amt;
wire [31:0] alu_sra = $signed(shift_src1) >>> shift_amt;
wire [31:0] alu_slt = ($signed(cmp_src1) < $signed(cmp_src2)) ? 32'd1 : 32'd0;
wire [31:0] alu_sltu = (cmp_src1 < cmp_src2) ? 32'd1 : 32'd0;
wire [31:0] alu_jalr = (arith_src1 + arith_src2) & ~32'd1;
wire [31:0] alu_copy1 = csr_src_old;
wire [31:0] mem_addr = real_rs1_data + exe_imm;
wire [1:0] mem_addr_low = mem_addr[1:0];
// 专用分支比较单元：与ALU主路径独立，直接产生比较标志，消除与alu_result的串联
wire cmp_eq   = (real_rs1_data == exe_rs2_data);
wire cmp_lt_s = ($signed(real_rs1_data) < $signed(exe_rs2_data));
wire cmp_lt_u = (real_rs1_data < exe_rs2_data);
wire [31:0] alu_csrrc = csr_src_old & ~csr_src_op1;
wire [31:0] alu_csrrs = csr_src_old | csr_src_op1;

reg [31:0] alu_result;
always @(*) begin
    // 先组内选择，再组间选择，降低大范围case选择链深度
    if (ALU_SUB) begin
        alu_result = alu_sub;
    end else if (ALU_JALR) begin
        alu_result = alu_jalr;
    end else if (ALU_ADD) begin
        alu_result = alu_add;
    end else if (ALU_AND) begin
        alu_result = alu_and;
    end else if (ALU_OR) begin
        alu_result = alu_or;
    end else if (ALU_XOR) begin
        alu_result = alu_xor;
    end else if (ALU_SLL) begin
        alu_result = alu_sll;
    end else if (ALU_SRL) begin
        alu_result = alu_srl;
    end else if (ALU_SRA) begin
        alu_result = alu_sra;
    end else if (ALU_SLT) begin
        alu_result = alu_slt;
    end else if (ALU_SLTU) begin
        alu_result = alu_sltu;
    end else if (ALU_COPY1) begin
        alu_result = alu_copy1;
    end else begin
        alu_result = 32'b0;
    end
end

// 分支判断：one-hot方式，每种分支直接与对应比较标志相与，去掉编码译码选择链
assign br_taken = (exe_jmp_flag
                | (exe_br_beq  & cmp_eq)
                | (exe_br_bne  & (~cmp_eq))
                | (exe_br_blt  & cmp_lt_s)
                | (exe_br_bge  & (~cmp_lt_s))
                | (exe_br_bltu & cmp_lt_u)
                | (exe_br_bgeu & (~cmp_lt_u))) && !flush_ds && !flush_es; // 发生指令冲掉时，不执行分支跳转
assign br_target = exe_jmp_flag ? alu_jalr : alu_result;

//访存信号
assign data_sram_en = exe_mem_re && ~(|exception_code_reg) && (!flush_es && !flush_ds); // 仅在访存指令且无异常时使能数据SRAM
assign data_sram_wen = (exe_mem_we && es_allowin && ~(|exception_code_reg) && (!flush_es && !flush_ds)) ? 
                        ((exe_mem_size[0] && exe_mem_size[1]) ? (4'b0001 << mem_addr_low) : // 8位访存（字节次序反转）
                        (exe_mem_size[0] && !exe_mem_size[1]) ? (mem_addr_low[1] ? 4'b1100 : 4'b0011) : // 16位访存（低/高半字交换）
                        (!exe_mem_size[0]) ? 4'b1111 : // 32位访存
                        4'b0000) : 4'b0000; // 非写操作时，写使能全为0
assign data_sram_addr = mem_addr;
assign data_sram_wdata = (exe_mem_size[0] && !exe_mem_size[1]) ? {exe_rs2_data[15:0],exe_rs2_data[15:0]} : // 16位访存，数据复制到高16位
                        (exe_mem_size[0] && exe_mem_size[1]) ? {exe_rs2_data[7:0], exe_rs2_data[7:0], exe_rs2_data[7:0], exe_rs2_data[7:0]} : // 8位访存，数据复制到所有字节
                        exe_rs2_data; // 32位访存
wire [4:0] exe_to_mem_size;
assign exe_to_mem_size = {mem_addr_low, exe_mem_size};

//数据前递
assign exe_id_data = alu_result;
assign exe_id_waddr = exe_rd_addr;
assign exe_id_we = exe_rd_wen && (!flush_es && !flush_ds); // 仅在目的寄存器写使能且无异常时，前递数据给ID阶段
assign exe_load_valid = es_valid && exe_mem_re;

//csr写数据
wire [31:0] exe_csr_wdata = (exe_csr_cmd == 4'b0001) ? op1_data : // CSRRW
                            (exe_csr_cmd == 4'b0010) ? alu_csrrs : // CSRRS
                            (exe_csr_cmd == 4'b0011) ? alu_csrrc : // CSRRC
                            (exe_csr_cmd == 4'b0101) ? op1_data : // CSRRWI
                            (exe_csr_cmd == 4'b0110) ? alu_csrrs : // CSRRSI
                            (exe_csr_cmd == 4'b0111) ? alu_csrrc :
                        32'b0; // 其他情况写入0（如不涉及CSR操作的指令）
assign exe_id_csr_wdata = exe_csr_wdata;
assign exe_id_csr_we = exe_csr_we && (!flush_es && !flush_ds); // 仅在CSR写使能且无异常时，前递CSR写数据给ID阶段
assign exe_id_csr_addr = exe_csr_addr;

// 输出到访存阶段的总线打包
assign exe_mem_bus_out = {
    (flush_es || flush_ds),
    exe_to_mem_size, // [4:0] 送往访存阶段的访存大小和地址偏移信息
    exe_pc,         // [31:0] 当前指令地址
    alu_result,     // [31:0] ALU计算结果
    exe_rd_addr,    // [4:0] 目的寄存器地址
    exe_rd_wen,     // 1-bit 目的寄存器写使能
    exe_wb_sel,     // [2:0] 写回数据选择信号
    exe_csr_we,     // 1-bit CSR写使能
    exe_csr_addr,   // [11:0] CSR地址
    exe_csr_wdata   // [31:0] CSR写数据
};

// 输出异常相关信号
wire exception_iam = br_taken && (br_target[1:0] != 2'b00); // 判断分支跳转目标地址是否为非4字节对齐
wire exception_lam = ((!exe_mem_size[0] && mem_addr_low != 2'b00 && exe_mem_re) ||
                    (exe_mem_size[0] && !exe_mem_size[1] && mem_addr_low[0] != 1'b0 && exe_mem_re)); // 32位访存时，地址必须为4字节对齐;16位访存时，地址必须为2字节对齐
wire exception_sam = (exe_mem_we && !exe_mem_size[0] && mem_addr_low != 2'b00) || (exe_mem_we && exe_mem_size[0] && !exe_mem_size[1] && mem_addr_low[0] != 1'b0); // 8位访存时，地址必须为4字节对齐;16位访存时，地址必须为2字节对齐
// EXE只负责异常检测与候选值产生，最终异常编码/mtval选择在MEM阶段完成
assign exception_code_em = (exception_code_reg == 6'b111111) ? 6'b111111 :
                            (!flush_es && !flush_ds) ? exception_code_reg : 6'b0; // 冲刷时不输出异常
assign exception_mtval_em = exception_mtval_reg;
assign exception_iam_em = exception_iam;
assign exception_lam_em = exception_lam;
assign exception_sam_em = exception_sam;
assign exception_addr_mtval_em = mem_addr;
assign exception_iam_mtval_em = br_target;

endmodule