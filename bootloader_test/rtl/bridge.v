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
    output reg [3:0] led,
    //bootloader接口
    input [52:0] dmem_write_bus,
    input [48:0] imem_write_bus,
    input mem_valid,
    input reset
);

reg [52:0] dmem_write_bus_reg;
reg [48:0] imem_write_bus_reg;
always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dmem_write_bus_reg <= 53'b0;
        imem_write_bus_reg <= 49'b0;
    end else if (mem_valid) begin
        dmem_write_bus_reg <= dmem_write_bus; // 捕获bootloader的写总线数据
        imem_write_bus_reg <= imem_write_bus;
    end else begin
        dmem_write_bus_reg <= 53'b0; // 非有效周期时总线数据置0，避免误写
        imem_write_bus_reg <= 49'b0;
    end
end
wire boot_dmem_wen = dmem_write_bus_reg[51:48];
wire [15:0] boot_dmem_addr = dmem_write_bus_reg[47:32];
wire [31:0] boot_dmem_wdata = dmem_write_bus_reg[31:0];
wire boot_imem_wen = imem_write_bus_reg[48];
wire [15:0] boot_imem_addr = imem_write_bus_reg[47:32];
wire [31:0] boot_imem_wdata = imem_write_bus_reg[31:0];

// 指令寄存器接口（无修改）
assign inst_ram_ren = imem_ren;
assign inst_ram_addr = reset ? imem_addr : boot_imem_addr; // 复位时正常访问指令地址，非复位时访问bootloader提供的地址
assign imem_rdata = inst_ram_rdata;
assign inst_ram_wen = reset ? 1'b0 : boot_imem_wen; // 复位时不允许写指令寄存器，非复位时根据bootloader信号控制写使能
assign inst_ram_wdata = reset ? 32'b0 : boot_imem_wdata; // 复位时写数据无效，非复位时使用bootloader提供的数据

localparam DATA_HIGH = 4'h6; // 数据寄存器地址最高4位
localparam IO_HIGH = 4'h8; //IO地址最高4位

// 修复1：先判断地址是否匹配，再决定是否传递dmem_wen的4位值
wire addr_match_data = (dmem_addr[31:28] == DATA_HIGH); // 1位条件信号
assign data_ram_ren = dmem_en & addr_match_data; // 修复2：读数据RAM也只在地址匹配时使能（原逻辑漏了）
assign data_ram_addr = reset ? dmem_addr : boot_dmem_addr; // 复位时正常访问数据地址，非复位时访问bootloader提供的地址
assign dmem_rdata = (addr_match_data) ? data_ram_rdata : 32'b0; // 修复3：非数据RAM地址时读数据置0
// 核心修复：4位总线完整传递，地址不匹配时全0
assign data_ram_wen = !reset ? boot_dmem_wen : addr_match_data ? dmem_wen : 4'b0000; 
assign data_ram_wdata = reset ? dmem_wdata : boot_dmem_wdata; // 复位时使用top提供的数据，非复位时使用bootloader提供的数据

//LED控制逻辑（补充：只有写IO地址时才生效，避免误触发）
always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led <= 4'b0000; // 复位时关闭所有LED
    end else if ((|dmem_wen) && (dmem_addr[31:28] == IO_HIGH)) begin // 修复4：判断是否有写使能（|dmem_wen）
        led <= dmem_wdata[3:0]; // 只使用最低4位控制LED
    end
end

endmodule