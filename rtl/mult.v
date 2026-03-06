//乘法器模块，多周期实现，用于优化时序
module mult(
    input wire clk,
    input wire rst_n,
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [3:0] op, //操作码，区分乘法类型
    output reg [31:0] result
);
reg [31:0] multiplicand; //被乘数
reg [31:0] multiplier;   //乘数
reg [3:0] op_reg; //操作码寄存器

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        multiplicand <= 0;
        multiplier <= 0;
        op_reg <= 0;
    end else begin
        multiplicand <= a;
        multiplier <= b;
        op_reg <= op;
    end
end

wire ALU_MUL;
wire ALU_MULH;         
wire ALU_MULHU;
wire ALU_MULHSU;
assign {ALU_MUL,ALU_MULH,ALU_MULHU,ALU_MULHSU} = op_reg;
wire [63:0] mul_full,mul_full_hsu,mul_full_hu;
assign mul_full = $signed(multiplicand) * $signed(multiplier);
assign mul_full_hsu = $signed(multiplicand) * $signed({1'b0, multiplier});
assign mul_full_hu = $unsigned(multiplicand) * $unsigned(multiplier);
wire [31:0] alu_mul = mul_full[31:0];
wire [31:0] alu_mulh = mul_full[63:32];
wire [31:0] alu_mulhu = mul_full_hu[63:32];
wire [31:0] alu_mulhsu = mul_full_hsu[63:32];

reg [31:0] alu_result;
always @ (*) begin
    case (1'b1)
        ALU_MUL:   alu_result <= alu_mul;
        ALU_MULH:  alu_result <= alu_mulh;
        ALU_MULHU: alu_result <= alu_mulhu;
        ALU_MULHSU:alu_result <= alu_mulhsu;
        default: alu_result <= 0;
    endcase
end

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        result <= 0;
    end else begin
        result <= alu_result;
    end
end

endmodule
