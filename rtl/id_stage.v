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
    //数据前递路径--执行阶段
    input wire exe_data_wen,
    input wire [4:0] exe_data_addr,
    input wire [31:0] exe_data,
    //跳转控制信号
    input wire br_jmp_flag
);

localparam nop = 32'h00000013; // addi x0, x0, 0
//握手协议
reg ds_valid;
wire ds_ready_go = 1'b1; 
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
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_id_bus_reg <= 0;
    end else if (ds_allowin && fs_to_ds_valid) begin
        if (br_jmp_flag) begin
            if_id_bus_reg <= {nop, if_id_bus_in[31:0]}; // 只保留PC，指令置为NOP
        end else begin
            if_id_bus_reg <= if_id_bus_in;
        end
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
wire f7_0000100 = (funct7 == 7'b0000100);

//load指令
wire inst_lw = is_load && f3_010;

//store指令
wire inst_sw = is_store && f3_010;

//branch指令

//jal指令

//jalr指令

//op-imm指令

//op-reg指令

//lui指令

//auipc指令

//system指令

//fence指令
wire inst_fence = is_fence;

//立即数选择
wire IMI_valid = inst_lw;
wire IMS_valid = inst_sw;
wire IMB_valid = 0; // 目前没有分支指令
wire IMJ_valid = 0; // 目前没有跳转指令
wire IMZ_valid = 0; // 目前没有立即数指令
wire IMU_valid = 0; // 目前没有上半立即数指令
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
                    (exe_data_wen && reg_addr1 == exe_data_addr) ? exe_data :
                    (mem_data_wen && reg_addr1 == mem_data_addr) ? mem_data :
                    (wb_data_wen && reg_addr1 == wb_data_addr) ? wb_data :
                    reg_data1;
assign rs2_data = (reg_addr2 == 5'b0) ? 32'b0 :
                    (exe_data_wen && reg_addr2 == exe_data_addr) ? exe_data :
                    (mem_data_wen && reg_addr2 == mem_data_addr) ? mem_data :
                    (wb_data_wen && reg_addr2 == wb_data_addr) ? wb_data :
                    reg_data2;

//控制信号生成
wire [2:0] op1_sel; // 送往EXE的第一个操作数选择信号
wire [1:0] op2_sel; // 送往EXE的第二个操作数选择信号
wire op1_rs1 = (is_op_imm || is_load || is_store) ? 1'b1 : 1'b0;
wire op1_pc = (is_auipc || is_jal || is_jalr) ? 1'b1 : 1'b0;
wire op1_imm = (is_lui) ? 1'b1 : 1'b0;
assign op1_sel = {op1_rs1, op1_pc, op1_imm};
wire op2_rs2 = (is_op_reg) ? 1'b1 : 1'b0;
wire op2_imm = (is_op_imm || is_load || is_store) ? 1'b1 : 1'b0;
assign op2_sel = {op2_rs2, op2_imm};
wire rd_wen = (is_op_reg || is_op_imm || is_load || is_lui || is_auipc) ? 1'b1 : 1'b0;

//ALU操作类型
wire ALU_ADD = inst_lw || inst_sw;          //加法
wire ALU_ADDI = 0;                  //加法（立即数）        
wire ALU_SUB = 0;           //减法
wire ALU_AND = 0;           //按位与
wire ALU_OR = 0;            //按位或
wire ALU_XOR = 0;           //按位异或
wire ALU_SLL = 0;           //逻辑左移
wire ALU_SRL = 0;           //逻辑右移
wire ALU_SRA = 0;           //算术右移
wire ALU_SLT = 0;           //有符号比较小于
wire ALU_SLTU = 0;          //无符号比较小于
wire ALU_JALR = 0;          //JALR指令的ALU操作（计算跳转地址）
wire ALU_COPY1 = 0;         //仅将第一个操作数传递到EXE阶段（用于CSR指令，ALU不进行计算）
wire ALU_MUL = 0;           //乘法指令标志（MUL/MULH/MULHU/MULHSU）
wire ALU_MULH = 0;          
wire ALU_MULHU = 0;
wire ALU_MULHSU = 0;
wire [16:0] alu_op = {ALU_ADD, ALU_ADDI, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
                   ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU,
                   ALU_JALR, ALU_COPY1,
                   ALU_MUL, ALU_MULH, ALU_MULHU, ALU_MULHSU};

//跳转与分支指令标志
wire [2:0] br_type; // 送往EXE的分支类型信号
wire jmp_flag =0;
assign br_type = 0;

//写回寄存器相关
wire [1:0] wb_sel; 
wire wb_sel_mem = is_load ? 1'b1 : 1'b0;
wire wb_sel_pc = (is_jal || is_jalr) ? 1'b1 : 1'b0;
assign wb_sel = {wb_sel_pc, wb_sel_mem};
wire [4:0] rd_out = rd_addr;

//CSR指令相关
wire [3:0] csr_cmd; // 送往EXE的CSR操作类型信号
wire csr_we = is_system ? 1'b1 : 1'b0;
wire [11:0] csr_waddr = csr_raddr; 
wire [31:0] csr_rdata_out = csr_rdata; // 直接将CSR寄存器的读出数据送往EXE阶段
assign csr_cmd = 0; // 目前没有具体的CSR指令实现，先将命令信号置为0

//访存指令相关
wire mem_we = is_store ? 1'b1 : 1'b0;
wire mem_re = is_load ? 1'b1 : 1'b0;
wire [2:0] mem_size; // 送往EXE的访存数据大小信号
assign mem_size = 0;

//异常相关
wire [31:0] exception_mtval; // 送往EXE的异常相关信息（如指令地址、异常类型等）
assign exception_mtval = 0;

//总线打包
assign id_exe_bus_out = {
    id_pc,         // [31:0] 指令地址
    imm,        // [31:0] 立即数
    rs1_data,   // [31:0] rs1_data
    rs2_data,   // [31:0] rs2_data
    {op1_sel, op2_sel}, // [4:0] 操作数选择信号
    alu_op,     // [16:0] ALU操作类型信号
    {br_type, jmp_flag}, //[3:0] 分支类型和跳转标志
    rd_wen,         // 送往EXE的寄存器写使能
    rd_out,         //[4:0] 目的寄存器地址
    wb_sel,         //[1:0] 送往EXE的写回数据选择信号
    csr_cmd,        //[3:0] 送往EXE的CSR操作类型信号
    csr_we,         // 送往EXE的CSR写使能
    csr_waddr,      //[11:0] 送往EXE的CSR写地址
    csr_rdata_out,  //[31:0] 直接送往EXE阶段的CSR寄存器读出数据
    mem_we,     //store写使能
    mem_re,     //load读使能
    mem_size,   //[2:0] 非对齐访存的字节数
    exception_mtval //[31:0] // 送往EXE的异常相关信息
};

endmodule