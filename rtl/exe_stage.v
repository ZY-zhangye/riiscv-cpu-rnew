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
    //数据前递路径
    output wire [31:0] exe_id_data,
    output wire [4:0] exe_id_waddr,
    output wire exe_id_we,
    output wire exe_id_es_valid,
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
    input wire exception_flag,
    //单独乘法器可能造成的数据冒险前递接口
    input wire [31:0] mult_result,
    //AXI4-Lite接口可能造成的数据冒险前递接口
    input wire [31:0] mem_result
);

wire es_ready_go = 1'b1; // EXE 阶段无内部停顿，始终准备好
reg es_valid;
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
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ds_to_es_bus_r <= 0;
        exception_code_reg <= 0;
        exception_mtval_reg <= 0;
    end else if (es_allowin && ds_to_es_valid) begin
        if (exception_flag || br_taken) begin
            ds_to_es_bus_r <= 0; // 发生异常时，EXE阶段输出NOP
            exception_code_reg <= 0;
            exception_mtval_reg <= 0;
        end else begin
            ds_to_es_bus_r <= id_exe_bus_in; // 正常传递控制与数据
            exception_code_reg <= exception_code_de;
            exception_mtval_reg <= exception_mtval_de;
        end
    end
end

// 从打包总线中解包出的控制与数据信号
wire [31:0] exe_pc;
wire [31:0] exe_imm;
wire [31:0] exe_rs1_data;
wire [31:0] exe_rs2_data;
wire [3:0] exe_op1_sel;
wire [2:0] exe_op2_sel;
wire [12:0] exe_alu_op;
wire [2:0] exe_br_type;
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
wire [1:0] exe_lw_rs_dependency; // 从ID阶段传来的加载相关数据冒险检测结果
assign {
    exe_pc,
    exe_imm,
    exe_rs1_data,
    exe_rs2_data,
    exe_op1_sel,
    exe_op2_sel,
    exe_alu_op,
    exe_br_type,
    exe_jmp_flag,
    exe_rd_wen,
    exe_rd_addr,
    exe_wb_sel,
    exe_csr_cmd,
    exe_lw_rs_dependency,
    exe_csr_we,
    exe_csr_addr,
    csr_rdata,
    exe_mem_we,
    exe_mem_re,
    exe_mem_size
} = ds_to_es_bus_r;

// ALU操作数选择
wire [31:0] real_rs1_data = exe_lw_rs_dependency[0] ? mem_result : exe_rs1_data;
wire [31:0] real_rs2_data = exe_lw_rs_dependency[1] ? mem_result : exe_rs2_data;
wire [31:0] op1_data;
wire [31:0] op2_data;
assign op1_data = exe_op1_sel[3] ? mult_result :
                  exe_op1_sel[2] ? real_rs1_data :
                  exe_op1_sel[1] ? exe_pc :
                  exe_op1_sel[0] ? exe_imm : 32'b0;
assign op2_data = |exe_csr_cmd ? csr_rdata :
                  exe_op2_sel[2] ? mult_result :
                  exe_op2_sel[1] ? real_rs2_data :
                  exe_op2_sel[0] ? exe_imm : 32'b0;

// ALU计算结果
wire ALU_ADD;          //加法
wire ALU_ADDI;                  //加法（有符号）        
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
assign {ALU_ADD, ALU_ADDI, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
        ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU,
        ALU_JALR, ALU_COPY1} = exe_alu_op;


wire [31:0] alu_add = op1_data + op2_data;
wire [31:0] alu_addi = $signed(op1_data) + $signed(op2_data);
wire [31:0] alu_sub = op1_data - op2_data;
wire [31:0] alu_and = op1_data & op2_data;
wire [31:0] alu_or  = op1_data | op2_data;
wire [31:0] alu_xor = op1_data ^ op2_data;
wire [31:0] alu_sll = op1_data << op2_data[4:0];
wire [31:0] alu_srl = op1_data >> op2_data[4:0];
wire [31:0] alu_sra = ({{32{op1_data[31]}}, op1_data} >> op2_data[4:0]);
wire [31:0] alu_slt = ($signed(op1_data) < $signed(op2_data)) ? 32'd1 : 32'd0;
wire [31:0] alu_sltu = (op1_data < op2_data) ? 32'd1 : 32'd0;
wire [31:0] alu_jalr = (op1_data + op2_data) & ~32'd1;
wire [31:0] alu_copy1 = csr_rdata;
wire alu_beq = (exe_rs1_data == exe_rs2_data) ? 1'b1 : 1'b0;
wire alu_blt = ($signed(exe_rs1_data) < $signed(exe_rs2_data)) ? 1'b1 : 1'b0;
wire alu_bltu = (exe_rs1_data < exe_rs2_data) ? 1'b1 : 1'b0;
wire [31:0] alu_csrrc = op2_data & ~op1_data; 

reg [31:0] alu_result;
always @(*) begin
    case (1'b1)
        ALU_ADD:   alu_result = alu_add;
        ALU_ADDI:  alu_result = alu_addi;
        ALU_SUB:   alu_result = alu_sub;
        ALU_AND:   alu_result = alu_and;
        ALU_OR:    alu_result = alu_or;
        ALU_XOR:   alu_result = alu_xor;
        ALU_SLL:   alu_result = alu_sll;
        ALU_SRL:   alu_result = alu_srl;
        ALU_SRA:   alu_result = alu_sra;
        ALU_SLT:   alu_result = alu_slt;
        ALU_SLTU:  alu_result = alu_sltu;
        ALU_JALR:  alu_result = alu_jalr;
        ALU_COPY1: alu_result = alu_copy1;
        default:   alu_result = 32'b0;
    endcase
end

// 分支比较结果
wire br_flag = (exe_br_type == 3'b001) ? alu_beq :
               (exe_br_type == 3'b010) ? ~alu_beq :
               (exe_br_type == 3'b011) ? alu_blt :
               (exe_br_type == 3'b100) ? ~alu_blt :
               (exe_br_type == 3'b101) ? alu_bltu :
               (exe_br_type == 3'b110) ? ~alu_bltu : 1'b0;
assign br_taken = exe_jmp_flag || (|exe_br_type && br_flag);
assign br_target = exe_jmp_flag ? alu_jalr : alu_result;

//访存信号
assign data_sram_en = exe_mem_re;
assign data_sram_wen = (exe_mem_we && es_allowin) ? 
                        ((exe_mem_size[0] && exe_mem_size[1]) ? (4'b0001 << alu_result[1:0]) : // 8位访存（字节次序反转）
                        (exe_mem_size[0] && !exe_mem_size[1]) ? (alu_result[1] ? 4'b1100 : 4'b0011) : // 16位访存（低/高半字交换）
                        (!exe_mem_size[0]) ? 4'b1111 : // 32位访存
                        4'b0000) : 4'b0000; // 非写操作时，写使能全为0
assign data_sram_addr = alu_result;
assign data_sram_wdata = (exe_mem_size[0] && !exe_mem_size[1]) ? {exe_rs2_data[15:0],exe_rs2_data[15:0]} : // 16位访存，数据复制到高16位
                        (exe_mem_size[0] && exe_mem_size[1]) ? {exe_rs2_data[7:0], exe_rs2_data[7:0], exe_rs2_data[7:0], exe_rs2_data[7:0]} : // 8位访存，数据复制到所有字节
                        exe_rs2_data; // 32位访存
wire [4:0] exe_to_mem_size;
assign exe_to_mem_size = {alu_result[1:0], exe_mem_size};

//数据前递
assign exe_id_data = alu_result;
assign exe_id_waddr = exe_rd_addr;
assign exe_id_we = exe_rd_wen;

//csr写数据
wire [31:0] exe_csr_wdata = (exe_csr_cmd == 4'b0001) ? op1_data : // CSRRW
                            (exe_csr_cmd == 4'b0010) ? alu_or : // CSRRS
                            (exe_csr_cmd == 4'b0011) ? alu_csrrc : // CSRRC
                            (exe_csr_cmd == 4'b0101) ? op1_data : // CSRRWI
                            (exe_csr_cmd == 4'b0110) ? alu_or : // CSRRSI
                            (exe_csr_cmd == 4'b0111) ? alu_csrrc :
                        32'b0; // 其他情况写入0（如不涉及CSR操作的指令）
assign exe_id_csr_wdata = exe_csr_wdata;
assign exe_id_csr_we = exe_csr_we;
assign exe_id_csr_addr = exe_csr_addr;

// 输出到访存阶段的总线打包
assign exe_mem_bus_out = {
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
wire exception_lam = ((!exe_mem_size[0] && alu_result[1:0] != 2'b00 && exe_mem_re) ||
                    (exe_mem_size[0] && !exe_mem_size[1] && alu_result[0] != 1'b0 && exe_mem_re)); // 32位访存时，地址必须为4字节对齐;16位访存时，地址必须为2字节对齐
wire exception_sam = (exe_mem_we && !exe_mem_size[0] && alu_result[1:0] != 2'b00) || (exe_mem_we && exe_mem_size[0] && !exe_mem_size[1] && alu_result[0] != 1'b0); // 8位访存时，地址必须为4字节对齐;16位访存时，地址必须为2字节对齐
assign exception_code_em = exception_iam ? 6'b100000 :
                           exception_lam ? 6'b100100 :
                           exception_sam ? 6'b100110 :
                           exception_code_reg; 
assign exception_mtval_em = exception_iam ? br_target : 
                            (exception_lam || exception_sam) ? alu_result :
                            exception_mtval_reg;

endmodule