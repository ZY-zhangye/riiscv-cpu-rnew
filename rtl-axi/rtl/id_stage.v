`include "defines.v"
module id_stage (
    input wire clk,
    input wire rst_n,
    //来自取指阶段的总线
    input wire [`FS_TO_DS_BUS_WD-1:0] if_id_bus_in,
    //握手信号
    input wire fs_to_ds_valid,
    output wire ds_allowin,
    output wire ds_to_es_valid,
    input wire es_allowin,
    //输出到执行阶段的总线
    output wire [`DS_TO_ES_BUS_WD-1:0] id_exe_bus_out,
    //regfile读取端口
    output wire [4:0] reg_addr1,
    output wire [4:0] reg_addr2,
    input wire [31:0] reg_data1,
    input wire [31:0] reg_data2,
    //CSR寄存器读取端口
    output wire [11:0] csr_raddr,
    input wire [31:0] csr_rdata,
    //数据前递路径--写回
    input wire wb_data_wen,
    input wire [4:0] wb_data_addr,
    input wire [31:0] wb_data,
    //数据前递路径--访存阶段
    input wire mem_data_wen,
    input wire [4:0] mem_data_addr,
    input wire [31:0] mem_data,
    input wire mem_load_pending,
    input wire [4:0] mem_load_rd,
    //数据前递路径--执行阶段
    input wire exe_data_wen,
    input wire [4:0] exe_data_addr,
    input wire [31:0] exe_data,
    input wire exe_id_es_valid,
    input wire exe_load_valid,
    input wire [31:0] exe_id_csr_wdata,
    input wire exe_id_csr_we,
    input wire [11:0] exe_id_csr_addr,
    //跳转控制信号
    input wire br_jmp_flag,
    //异常相关信号
    input wire [5:0] exception_code_fd,
    input wire [31:0] exception_mtval_fd,
    input wire exception_flag,
    output wire [5:0] exception_code_de,
    output wire [31:0] exception_mtval_de,
    //单独的乘法模块接口（优化时序；结果输出值mem阶段，不阻挡后续指令）
    output wire [31:0] a,
    output wire [31:0] b,
    output wire [3:0] op,
    //中断采样接口（exe和mem阶段可能因为AXI访问等待而停顿，无法及时响应中断，因此在id阶段采样中断信号，并将中断相关信息传递到exe和mem阶段）
    input wire plic_int,
    input wire [15:0] plic_int_id
);

localparam nop = 32'h00000013; // addi x0, x0, 0
//握手协议
reg ds_valid;
wire load_use_hazard; // load-use数据冒险检测标志
wire ds_ready_go = !load_use_hazard;
assign ds_allowin = !ds_valid || ds_ready_go && es_allowin;
assign ds_to_es_valid = ds_valid && ds_ready_go;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ds_valid <= 1'b0;
    end else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid;
    end
end

//保存从取指阶段传来的指令和PC
reg [`FS_TO_DS_BUS_WD-1:0] if_id_bus_reg;
reg [5:0] exception_code_reg;
reg [31:0] exception_mtval_reg;
reg plic_int_reg;
reg [15:0] plic_int_id_reg;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_id_bus_reg <= 0;
        exception_code_reg <= 0;
        exception_mtval_reg <= 0;
    end else if (ds_allowin && fs_to_ds_valid) begin
        if (br_jmp_flag || exception_flag) begin
            if_id_bus_reg <= {nop, if_id_bus_in[31:0]}; // 只保留PC，指令置为NOP
            exception_code_reg <= 0;
            exception_mtval_reg <= 0;
        end else begin
            if_id_bus_reg <= if_id_bus_in;
            exception_code_reg <= exception_code_fd;
            exception_mtval_reg <= exception_mtval_fd;
        end
    end
end
always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        plic_int_reg <= 1'b0;
        plic_int_id_reg <= 16'b0;
    end else if (plic_int) begin
        plic_int_reg <= plic_int;
        plic_int_id_reg <= plic_int_id;
    end else if (ds_to_es_valid) begin
        plic_int_reg <= 1'b0; // 在指令正常流转到ID阶段时清除中断标志，避免重复响应同一个中断
        plic_int_id_reg <= 16'b0;
    end
end
wire [31:0] id_inst;
wire [31:0] id_pc;
assign {id_inst,id_pc} = if_id_bus_reg;

//译码逻辑
wire [6:0] opcode = id_inst[6:0];
wire [2:0] funct3 = id_inst[14:12];
wire [6:0] funct7 = id_inst[31:25];
assign reg_addr1 = id_inst[19:15];
assign reg_addr2 = id_inst[24:20];
assign csr_raddr = id_inst[31:20];
wire [4:0] rd_addr = id_inst[11:7];

wire [11:0] imm_i = id_inst[31:20];
wire [11:0] imm_s = {id_inst[31:25], id_inst[11:7]};
wire [12:0] imm_b = {id_inst[31], id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
wire [19:0] imm_u = id_inst[31:12];
wire [20:0] imm_j = {id_inst[31], id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};
wire [4:0]  imm_z = id_inst[19:15];

wire [31:0] imm_i_ext = {{20{imm_i[11]}}, imm_i};
wire [31:0] imm_s_ext = {{20{imm_s[11]}}, imm_s};
wire [31:0] imm_b_ext = {{19{imm_b[12]}}, imm_b};
wire [31:0] imm_u_ext = {imm_u, 12'b0};
wire [31:0] imm_j_ext = {{11{imm_j[20]}}, imm_j};
wire [31:0] imm_z_ext = {{27{1'b0}}, imm_z};

//指令定义
wire is_load   = (opcode == 7'b0000011);
wire is_store  = (opcode == 7'b0100011);
wire is_branch = (opcode == 7'b1100011);
wire is_jal    = (opcode == 7'b1101111);
wire is_jalr   = (opcode == 7'b1100111);
wire is_op_imm  = (opcode == 7'b0010011);
wire is_op_reg  = (opcode == 7'b0110011);
wire is_lui    = (opcode == 7'b0110111);
wire is_auipc  = (opcode == 7'b0010111);
wire is_system = (opcode == 7'b1110011);
wire is_fence  = (opcode == 7'b0001111);

wire f3_000 = (funct3 == 3'b000);
wire f3_001 = (funct3 == 3'b001);
wire f3_010 = (funct3 == 3'b010);
wire f3_011 = (funct3 == 3'b011);
wire f3_100 = (funct3 == 3'b100);
wire f3_101 = (funct3 == 3'b101);
wire f3_110 = (funct3 == 3'b110);
wire f3_111 = (funct3 == 3'b111);

wire f7_0000000 = (funct7 == 7'b0000000);
wire f7_0100000 = (funct7 == 7'b0100000);
wire f7_0000001 = (funct7 == 7'b0000001);
wire f7_0011000 = (funct7 == 7'b0011000);

//load指令 (opcode=0000011)
wire inst_lw = is_load && f3_010;
wire inst_lb = is_load && f3_000;
wire inst_lh = is_load && f3_001;
wire inst_lbu = is_load && f3_100;
wire inst_lhu = is_load && f3_101;

//store指令 (opcode=0100011)
wire inst_sw = is_store && f3_010;
wire inst_sb = is_store && f3_000;
wire inst_sh = is_store && f3_001;

//branch指令 (opcode=1100011)
wire inst_beq = is_branch && f3_000;
wire inst_bne = is_branch && f3_001;
wire inst_blt = is_branch && f3_100;
wire inst_bge = is_branch && f3_101;
wire inst_bltu = is_branch && f3_110;
wire inst_bgeu = is_branch && f3_111;

//jal指令 (opcode=1101111)
wire inst_jal = is_jal;

//jalr指令 (opcode=1100111)
wire inst_jalr = is_jalr;

//op-imm指令 (opcode=0010011)
wire inst_addi = is_op_imm && f3_000;
wire inst_slti = is_op_imm && f3_010;
wire inst_sltiu = is_op_imm && f3_011;
wire inst_xori = is_op_imm && f3_100;
wire inst_ori  = is_op_imm && f3_110;
wire inst_andi = is_op_imm && f3_111;
wire inst_slli = is_op_imm && f3_001 && f7_0000000;
wire inst_srli = is_op_imm && f3_101 && f7_0000000;
wire inst_srai = is_op_imm && f3_101 && f7_0100000;

//op-reg指令 (opcode=0110011)
wire inst_add = is_op_reg && f3_000 && f7_0000000;
wire inst_sub = is_op_reg && f3_000 && f7_0100000;
wire inst_sll = is_op_reg && f3_001 && f7_0000000;
wire inst_slt = is_op_reg && f3_010 && f7_0000000;
wire inst_sltu = is_op_reg && f3_011 && f7_0000000;
wire inst_xor = is_op_reg && f3_100 && f7_0000000;
wire inst_srl = is_op_reg && f3_101 && f7_0000000;
wire inst_sra = is_op_reg && f3_101 && f7_0100000;
wire inst_or  = is_op_reg && f3_110 && f7_0000000;
wire inst_and = is_op_reg && f3_111 && f7_0000000;
wire inst_mul = is_op_reg && f3_000 && f7_0000001;
wire inst_mulh = is_op_reg && f3_001 && f7_0000001;
wire inst_mulhu = is_op_reg && f3_011 && f7_0000001;
wire inst_mulhsu = is_op_reg && f3_010 && f7_0000001;

//lui指令 (opcode=0110111)
wire inst_lui = is_lui;

//auipc指令 (opcode=0010111)
wire inst_auipc = is_auipc;

//system指令 (opcode=1110011)
wire inst_ecall = is_system && f3_000 && id_inst[25:20] == 6'b000000;
wire inst_ebreak = is_system && f3_000 && id_inst[25:20] == 6'b000001;
wire inst_mret = is_system && f3_000 && f7_0011000;
wire inst_csrrw = is_system && f3_001;
wire inst_csrrs = is_system && f3_010;
wire inst_csrrc = is_system && f3_011;
wire inst_csrrwi = is_system && f3_101;
wire inst_csrrsi = is_system && f3_110;
wire inst_csrrci = is_system && f3_111;

//fence指令 (opcode=0001111)
wire inst_fence = is_fence;

//立即数选择
wire IMI_valid = is_load || inst_addi || inst_slti || inst_sltiu || inst_xori || inst_ori || inst_andi || inst_slli || inst_srli || inst_srai || inst_jalr;
wire IMS_valid = is_store;
wire IMB_valid = inst_beq || inst_bne || inst_blt || inst_bge || inst_bltu || inst_bgeu; // 分支指令
wire IMJ_valid = is_jal; // 跳转指令
wire IMZ_valid = inst_csrrwi || inst_csrrsi || inst_csrrci; // CSR立即数指令
wire IMU_valid = inst_lui || inst_auipc; // 上半立即数指令
wire [31:0] imm = IMI_valid ? imm_i_ext :
                  IMS_valid ? imm_s_ext :
                  IMB_valid ? imm_b_ext :
                  IMJ_valid ? imm_j_ext :
                  IMZ_valid ? imm_z_ext :
                  IMU_valid ? imm_u_ext : 32'b0;

//rs数据选择
wire [31:0] rs1_data;
wire [31:0] rs2_data;
assign rs1_data = (reg_addr1 == 5'b0) ? 32'b0 :
                    (exe_data_wen && reg_addr1 == exe_data_addr && exe_id_es_valid) ? exe_data :
                    (mem_data_wen && reg_addr1 == mem_data_addr) ? mem_data :
                    (wb_data_wen && reg_addr1 == wb_data_addr) ? wb_data :
                    reg_data1;
assign rs2_data = (reg_addr2 == 5'b0) ? 32'b0 :
                    (exe_data_wen && reg_addr2 == exe_data_addr && exe_id_es_valid) ? exe_data :
                    (mem_data_wen && reg_addr2 == mem_data_addr) ? mem_data :
                    (wb_data_wen && reg_addr2 == wb_data_addr) ? wb_data :
                    reg_data2;

//控制信号生成
wire [3:0] op1_sel; // 送往EXE的第一个操作数选择信号
wire [2:0] op2_sel; // 送往EXE的第二个操作数选择信号
wire op1_rs1 = (is_op_imm || is_load || is_store || is_jalr || inst_csrrw || inst_csrrs || inst_csrrc || is_op_reg) ? 1'b1 : 1'b0;
wire op1_pc = (is_auipc || is_jal || is_jalr || is_branch) ? 1'b1 : 1'b0;
wire op1_imm = (is_lui || inst_csrrwi || inst_csrrsi || inst_csrrci) ? 1'b1 : 1'b0;
wire op1_mult; //多周期乘法指令一旦出现，并且出现写后读数据冒险时，需要将mem阶段才可以产生的乘法指令的结果前递至exe阶段以解除数据冒险的同时不会停顿流水线
assign op1_sel = {op1_mult, op1_rs1, op1_pc, op1_imm};
wire op2_rs2 = (is_op_reg) ? 1'b1 : 1'b0;
wire op2_imm = (is_op_imm || is_load || is_store || is_jal || is_jalr || is_branch || is_auipc) ? 1'b1 : 1'b0;
wire op2_mult; //同上具体产生条件见下
assign op2_sel = {op2_mult, op2_rs2, op2_imm};
wire rd_wen = (is_op_reg || is_op_imm || is_load || is_lui || is_auipc || is_system || is_jal || is_jalr) ? 1'b1 : 1'b0;

// load-use 数据冒险检测：对load结果使用1拍气泡，避免MEM->EXE同拍超长前递路径
wire need_rs1 = is_op_reg || is_op_imm || is_load || is_store || is_branch || is_jalr ||
                inst_csrrw || inst_csrrs || inst_csrrc;
wire need_rs2 = is_op_reg || is_store || is_branch;
wire exe_load_hazard = exe_load_valid && (exe_data_addr != 5'b0) &&
                       ((need_rs1 && (reg_addr1 == exe_data_addr)) ||
                        (need_rs2 && (reg_addr2 == exe_data_addr)));
wire mem_load_hazard = mem_load_pending && (mem_load_rd != 5'b0) &&
                       ((need_rs1 && (reg_addr1 == mem_load_rd)) ||
                        (need_rs2 && (reg_addr2 == mem_load_rd)));
assign load_use_hazard = ds_valid && (exe_load_hazard || mem_load_hazard);

//ALU操作类型
wire ALU_ADD = is_load || is_store || inst_add || inst_lui || inst_auipc || is_jal || is_branch || inst_addi;          //加法
wire ALU_SUB = inst_sub;           //减法
wire ALU_AND = inst_and || inst_andi;           //按位与
wire ALU_OR = inst_or || inst_ori;            //按位或
wire ALU_XOR = inst_xor || inst_xori;           //按位异或
wire ALU_SLL = inst_sll || inst_slli;           //逻辑左移
wire ALU_SRL = inst_srl || inst_srli;           //逻辑右移
wire ALU_SRA = inst_sra || inst_srai;           //算术右移
wire ALU_SLT = inst_slt || inst_slti;           //有符号比较小于
wire ALU_SLTU = inst_sltu || inst_sltiu;          //无符号比较小于
wire ALU_JALR = is_jalr;          //JALR指令的ALU操作（计算跳转地址）
wire ALU_COPY1 = is_system ? 1'b1 : 1'b0;         //仅将第一个操作数传递到EXE阶段（用于CSR指令，ALU不进行计算）
wire [11:0] alu_op = {ALU_ADD,  ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
                   ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU,
                   ALU_JALR, ALU_COPY1};

//跳转与分支指令标志
// one-hot分支类型：每位对应一种分支，EXE直接与比较结果做与运算，消除编码译码选择链
wire br_beq  = inst_beq;
wire br_bne  = inst_bne;
wire br_blt  = inst_blt;
wire br_bge  = inst_bge;
wire br_bltu = inst_bltu;
wire br_bgeu = inst_bgeu;
wire jmp_flag = is_jal || is_jalr; // 跳转指令标志

//写回寄存器相关
wire [2:0] wb_sel; 
wire wb_sel_mul = (inst_mul || inst_mulh || inst_mulhu || inst_mulhsu) ? 1'b1 : 1'b0; // 来自单独乘法器的结果
wire wb_sel_mem = is_load ? 1'b1 : 1'b0;
wire wb_sel_pc = (is_jal || is_jalr) ? 1'b1 : 1'b0;
assign wb_sel = {wb_sel_mul, wb_sel_pc, wb_sel_mem};
wire [4:0] rd_out = rd_addr;

//CSR指令相关
wire [3:0] csr_cmd; // 送往EXE的CSR操作类型信号
wire csr_we = is_system ? 1'b1 : 1'b0;
wire [11:0] csr_waddr = csr_raddr; 
wire [31:0] csr_rdata_out = (exe_id_es_valid && exe_id_csr_we && exe_id_csr_addr == csr_raddr) ? exe_id_csr_wdata : csr_rdata; // 如果EXE阶段正在写同一个CSR寄存器，则前递该数据，否则使用CSR寄存器读出的数据
assign csr_cmd = inst_csrrw ? 4'b0001 :
                 inst_csrrs ? 4'b0010 :
                 inst_csrrc ? 4'b0011 :
                 inst_csrrwi ? 4'b0101 :
                 inst_csrrsi ? 4'b0110 :
                 inst_csrrci ? 4'b0111 : 4'b0000;

//访存指令相关
wire mem_we = is_store ? 1'b1 : 1'b0;
wire mem_re = is_load ? 1'b1 : 1'b0;
wire [2:0] mem_size; // 送往EXE的访存数据大小信号
// mem_size信号定义
// 0: 非对齐访存（lb/lbu/lh/lhu/sb/sh为1，lw/sw为0）
// 1: 1为8位，0为16位（lb/lbu/sb为1，lh/lhu/sh为0）
// 2: 1为符号扩展，0为补0（lb/lh为1，lbu/lhu为0，写指令为0）
assign mem_size [0] = inst_lb || inst_lbu || inst_lh || inst_lhu || inst_sb || inst_sh; // 非对齐访存
assign mem_size [1] = inst_lb || inst_lbu || inst_sb; // 8位访存
assign mem_size [2] = inst_lb || inst_lh; // 符号扩展

//总线打包
assign id_exe_bus_out = {
    id_pc,         // [31:0] 指令地址
    imm,        // [31:0] 立即数
    rs1_data,   // [31:0] rs1_data
    rs2_data,   // [31:0] rs2_data
    {op1_sel, op2_sel}, // [4:0] 操作数选择信号
    alu_op,     // [11:0] ALU操作类型信号
    {br_beq, br_bne, br_blt, br_bge, br_bltu, br_bgeu, jmp_flag}, //[6:0] one-hot分支类型 + 跳转标志
    rd_wen,         // 送往EXE的寄存器写使能
    rd_out,         //[4:0] 目的寄存器地址
    wb_sel,         //[1:0] 送往EXE的写回数据选择信号
    csr_cmd,        //[3:0] 送往EXE的CSR操作类型信号
    csr_we,         // 送往EXE的CSR写使能
    csr_waddr,      //[11:0] 送往EXE的CSR写地址
    csr_rdata_out,  //[31:0] 直接送往EXE阶段的CSR寄存器读出数据
    mem_we,     //store写使能
    mem_re,     //load读使能
    mem_size   //[2:0] 非对齐访存的字节数
};


//异常相关输出
assign exception_code_de =  plic_int_reg ? 6'b111111
                            : (inst_ecall && ds_allowin) ? 6'b101011 
                            : (inst_ebreak && ds_allowin) ? 6'b100011
                            : (inst_mret && ds_allowin) ? 6'b011111
                            : exception_code_reg; 
assign exception_mtval_de = plic_int_reg ? {16'b0, plic_int_id_reg} // 将中断号放在mtval的低16位，高16位清零
                            : (inst_ecall && ds_allowin) ? 32'b0 
                            : (inst_ebreak && ds_allowin) ? 32'b0
                            : (inst_mret && ds_allowin) ? 32'b0
                            : exception_mtval_reg;

//单独的乘法模块接口
assign a = rs1_data;
assign b = rs2_data;
assign op = {inst_mul, inst_mulh, inst_mulhu, inst_mulhsu};

//处理单独乘法器可能造成的数据冒险
reg prev_mul; // 上一条指令是否为乘法指令
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prev_mul <= 1'b0;
    end else if (ds_allowin) begin
        prev_mul <= inst_mul || inst_mulh || inst_mulhu || inst_mulhsu;
    end
end
assign op1_mult = prev_mul && (reg_addr1 != 5'b0) && (reg_addr1 == exe_data_addr) && exe_id_es_valid && op1_rs1; // 如果当前指令的rs1与上一条乘法指令的目的寄存器相同，并且上一条指令正在EXE阶段有效，则需要将乘法结果前递到EXE阶段作为第一个操作数
assign op2_mult = prev_mul && (reg_addr2 != 5'b0) && (reg_addr2 == exe_data_addr) && exe_id_es_valid && op2_rs2; // 如果当前指令的rs2与上一条乘法指令的目的寄存器相同，并且上一条指令正在EXE阶段有效，则需要将乘法结果前递到EXE阶段作为第二个操作数


endmodule