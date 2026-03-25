module inst_ram #(
    parameter MEM_HEX_PATH = "C:\\Users\\ZY\\Desktop\\riscv-cpu-rnew\\hex\\riscv-tests\\rv32-p-riscv.hex"
)
(
    input wire clk,
    input wire rst_n,
    //指令寄存器接口
    input wire inst_ram_ren,
    input wire [31:0] inst_ram_addr,
    output reg [31:0] inst_ram_rdata,
    input wire inst_ram_wen,
    input wire [31:0] inst_ram_wdata
);

reg [31:0] mem [0:3000];
initial begin
    $readmemh(MEM_HEX_PATH, mem);
end

always @ (posedge clk) begin
    if (inst_ram_ren) begin
        inst_ram_rdata <= mem[inst_ram_addr[31:2]]; // 按字对齐访问
    end
    if (inst_ram_wen) begin
        mem[inst_ram_addr[31:2]] <= inst_ram_wdata; // 按字对齐访问
    end
end

endmodule