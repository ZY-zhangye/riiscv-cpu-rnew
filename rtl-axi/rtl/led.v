`include "defines.v"
module led(
    input wire clk,
    input wire rst_n,
    input wire [15:0] addr,
    input wire [31:0] wdata,
    input wire we,
    input wire re,
    output reg [31:0] rdata,
    output reg [3:0] led
);

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led <= 4'b1111; // 复位时所有LED熄灭
        rdata <= 32'b0;
    end else if (we) begin
        led <= wdata[3:0]; // 写入LED状态
    end else if (re) begin
        rdata <= {28'b0, led}; // 读取LED状态
    end
end

endmodule