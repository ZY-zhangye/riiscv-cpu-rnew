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
    output wire [`FS_TO_DS_BUS_WD-1:0] if_id_bus_out
);

    localparam nop_inst = 32'h0000_0013; // addi x0, x0, 0
    wire [31:0] seq_pc;
    wire [31:0] next_pc;
    reg [31:0] fs_pc;
    wire [31:0] fs_inst;

    assign seq_pc = fs_pc + 4;
    assign next_pc = seq_pc; 

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

endmodule

