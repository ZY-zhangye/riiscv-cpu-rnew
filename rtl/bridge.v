module bridge (
    input wire clk,
    input wire rst_n,
    //指令寄存器读写信号
    output inst_ram_ren,
    output [31:0] inst_ram_addr,
    input wire [31:0] inst_ram_rdata,
    output inst_ram_wen,
    output [31:0] inst_ram_wdata,
    //数据寄存器读写信号
    output data_ram_ren,
    output [31:0] data_ram_addr,
    input wire [31:0] data_ram_rdata,
    output [3:0] data_ram_wen,
    output [31:0] data_ram_wdata,
    //来自top的寄存器读写信号
    input wire [31:0] imem_addr,
    output wire [31:0] imem_rdata,
    output wire imem_ren,
    input wire [31:0] dmem_addr,
    input wire [31:0] dmem_wdata,
    input wire [3:0] dmem_wen,
    output wire [31:0] dmem_rdata,
    input wire dmem_en,
    //外设接口
    output reg [3:0] led
);

// 指令寄存器接口
assign inst_ram_ren = imem_ren;
assign inst_ram_addr = imem_addr;
assign imem_rdata = inst_ram_rdata;
assign inst_ram_wen = 1'b0; // 指令寄存器不写
assign inst_ram_wdata = 32'b0; // 不写数据

localparam DATA_HIGH = 4'h6; // 数据寄存器地址最高4位
localparam IO_HIGH = 4'h8; //IO地址，暂时不用
// 数据寄存器接口
assign data_ram_ren = dmem_en;
assign data_ram_addr = dmem_addr;
assign dmem_rdata = data_ram_rdata;
assign data_ram_wen = dmem_wen;
assign data_ram_wdata = dmem_wdata;

//LED控制逻辑
always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led <= 4'b1111; // 复位时关闭所有LED
    end else if (dmem_wen && (dmem_addr[31:28] == IO_HIGH)) begin
        led <= dmem_wdata[3:0]; // 只使用最低4位控制LED
    end
end

endmodule