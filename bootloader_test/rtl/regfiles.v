module regfiles (
    input wire clk,
    input wire rst_n,
    //写端口
    input wire we,
    input wire [4:0] waddr,
    input wire [31:0] wdata,
    //读端口1
    input wire [4:0] raddr1,
    output wire [31:0] rdata1,
    //读端口2
    input wire [4:0] raddr2,
    output wire [31:0] rdata2,
    //debug端口
    output wire [31:0] debug_data
);

    reg [31:0] regs[31:0];
    integer i;
    //写操作
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else if (we && waddr != 5'b0) begin
            regs[waddr] <= wdata;
        end
    end
    //读操作，x0寄存器始终为0
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : regs[raddr2];

    assign debug_data = regs[3]; // 例如输出x3寄存器的值作为调试信息

endmodule