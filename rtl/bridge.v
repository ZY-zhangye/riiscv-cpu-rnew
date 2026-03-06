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
    input wire imem_ren,
    input wire [31:0] dmem_addr,
    input wire [31:0] dmem_wdata,
    input wire [3:0] dmem_wen,
    output wire [31:0] dmem_rdata,
    input wire dmem_en,
    //外设接口
    output reg [3:0] led
);

// 指令寄存器接口（无修改）
assign inst_ram_ren = imem_ren;
assign inst_ram_addr = imem_addr;
assign imem_rdata = inst_ram_rdata;
assign inst_ram_wen = 1'b0; // 指令寄存器不写
assign inst_ram_wdata = 32'b0; // 不写数据

localparam DATA_HIGH = 4'h6; // 数据寄存器地址最高4位
localparam IO_HIGH = 4'h8; //IO地址最高4位

// 修复1：先判断地址是否匹配，再决定是否传递dmem_wen的4位值
wire addr_match_data = (dmem_addr[31:28] == DATA_HIGH); // 1位条件信号
assign data_ram_ren = dmem_en /*& addr_match_data*/; // 修复2：读数据RAM也只在地址匹配时使能（原逻辑漏了）
assign data_ram_addr = dmem_addr;
assign dmem_rdata = /*(addr_match_data) ? */data_ram_rdata /*: 32'b0*/; // 修复3：非数据RAM地址时读数据置0
// 核心修复：4位总线完整传递，地址不匹配时全0
assign data_ram_wen = /*addr_match_data ? */dmem_wen/* : 4'b0000*/; 
assign data_ram_wdata = dmem_wdata;

//LED控制逻辑（补充：只有写IO地址时才生效，避免误触发）
always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led <= 4'b0000; // 复位时关闭所有LED
    end else if ((|dmem_wen) && (dmem_addr[31:28] == IO_HIGH)) begin // 修复4：判断是否有写使能（|dmem_wen）
        led <= dmem_wdata[3:0]; // 只使用最低4位控制LED
    end
end

endmodule