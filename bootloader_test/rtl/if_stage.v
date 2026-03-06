`include "defines.v"
module if_stage (
    input wire clk,
    input wire rst_n,
    //取指端口
    output wire [31:0] pc_out,
    input wire [31:0] inst_in,
    output wire inst_ren,
    //与译码阶段的握手信号
    input wire ds_allowin,
    output wire fs_to_ds_valid,
    //译码阶段总线
    output wire [`FS_TO_DS_BUS_WD-1:0] if_id_bus_out,
    //分支跳转
    input wire [31:0] br_target,
    input wire br_jmp_flag,
    //异常相关信号
    output wire [5:0] exception_code_fd,
    output wire [31:0] exception_mtval_fd,
    input wire exception_flag,
    input wire [31:0] exception_addr
);

    localparam nop_inst = 32'h0000_0013; // addi x0, x0, 0
    wire [31:0] seq_pc;
    wire [31:0] next_pc;
    reg [31:0] fs_pc;
    wire [31:0] fs_inst;

    assign seq_pc = fs_pc + 4;
    assign next_pc = exception_flag ? exception_addr :
                     br_jmp_flag ? br_target :
                     seq_pc;

    //握手协议
    reg fs_valid;
    wire fs_ready_go = 1'b1;
    wire fs_allowin = !fs_valid || fs_ready_go && ds_allowin;
    assign fs_to_ds_valid = fs_valid && fs_ready_go;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fs_valid <= 1'b0;
        end else if (fs_allowin) begin
            fs_valid <= 1'b1;
        end
        if (!rst_n) begin
            fs_pc <= 32'hffff_fffc; // -4，确保第一个pc_out为0
        end else if (fs_allowin) begin
            fs_pc <= next_pc;
        end
    end
    //读指令端口输出
    assign pc_out = next_pc;
    assign fs_inst = inst_in;
    assign inst_ren = fs_allowin; 

    //输出到译码阶段的总线
    assign if_id_bus_out = {fs_inst, fs_pc};

    //异常相关输出
    wire exception_iam = pc_out[1:0] != 2'b00 && fs_allowin; // 判断是否为非4字节对齐的地址
    assign exception_code_fd = exception_iam ? 6'b100000 : 6'b000000; // 未对齐地址异常代码为4，其他异常代码为0
    assign exception_mtval_fd = pc_out; // 异常mtval字段为异常地址

endmodule

