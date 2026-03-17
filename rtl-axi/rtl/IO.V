module IO(
    input wire clk,
    input wire rst_n,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    input wire ren,
    output reg [31:0] rdata,
    output reg [3:0] led
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led <= 4'b1111; // 复位时LED全灭
        rdata <= 32'b0;
    end else if (ren && (addr[31:28] == 4'h8)) begin
        rdata <= {28'b0, led}; // 读操作返回LED状态
    end else if (|wstrb && (addr[31:28] == 4'h8)) begin
        // 写操作更新LED状态（只考虑最低4位）
        if (wstrb[0]) led[0] <= wdata[0];
        if (wstrb[1]) led[1] <= wdata[1];
        if (wstrb[2]) led[2] <= wdata[2];
        if (wstrb[3]) led[3] <= wdata[3];
    end
end

endmodule