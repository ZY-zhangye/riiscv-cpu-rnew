`include "defines.v"
module cpu_top #(
    parameter IF_MAX_CONSECUTIVE_GRANTS = 8,
    parameter MEM_HEX_PATH = "C:\\Users\\ZY\\Desktop\\riiscv-cpu-rnew\\hex\\riscv-tests\\rv32ui-p-lui.hex"
)
(
    input wire clk,
    input rst_n,
    input wire clk_uart,
`ifdef DEBUG_EN
    //debug接口
    output wire [31:0] debug_inst_pc,
    output wire [31:0] debug_wb_pc,
    output wire debug_wb_rf_wen,
    output wire [4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    output wire [31:0] debug_data,
`endif
    //外设接口
    input wire rx,
    output wire tx,
    output reg [3:0] led
);

wire [31:0] axi_araddr;
wire        axi_arvalid;
wire        axi_arready;
wire [31:0] axi_rdata;
wire [1:0]  axi_rresp;
wire        axi_rvalid;
wire        axi_rready;
wire [31:0] axi_awaddr;
wire        axi_awvalid;
wire        axi_awready;
wire [31:0] axi_wdata;
wire [3:0]  axi_wstrb;
wire        axi_wvalid;
wire        axi_wready;
wire [1:0]  axi_bresp;
wire        axi_bvalid;
wire        axi_bready;
wire plic_int;
wire [15:0] plic_int_id;

my_cpu #(
    .IF_MAX_CONSECUTIVE_GRANTS(IF_MAX_CONSECUTIVE_GRANTS)
) u_my_cpu (
    .clk(clk),
    .rst_n(rst_n),
`ifdef DEBUG_EN
    .debug_inst_pc(debug_inst_pc),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .debug_data(debug_data),
`endif
    .axi_araddr(axi_araddr),
    .axi_arvalid(axi_arvalid),
    .axi_arready(axi_arready),
    .axi_rdata(axi_rdata),
    .axi_rresp(axi_rresp),
    .axi_rvalid(axi_rvalid),
    .axi_rready(axi_rready),
    .axi_awaddr(axi_awaddr),
    .axi_awvalid(axi_awvalid),
    .axi_awready(axi_awready),
    .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb),
    .axi_wvalid(axi_wvalid),
    .axi_wready(axi_wready),
    .axi_bresp(axi_bresp),
    .axi_bvalid(axi_bvalid),
    .axi_bready(axi_bready),
    .plic_int(plic_int),
    .plic_int_id(plic_int_id)
);

bridge #(
    .MEM_HEX_PATH(MEM_HEX_PATH)
) u_bridge (
    .clk(clk),
    .rst_n(rst_n),
    .clk_uart(clk_uart),
    .axi_araddr(axi_araddr),
    .axi_arvalid(axi_arvalid),
    .axi_arready(axi_arready),
    .axi_rdata(axi_rdata),
    .axi_rresp(axi_rresp),
    .axi_rvalid(axi_rvalid),
    .axi_rready(axi_rready),
    .axi_awaddr(axi_awaddr),
    .axi_awvalid(axi_awvalid),
    .axi_awready(axi_awready),
    .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb),
    .axi_wvalid(axi_wvalid),
    .axi_wready(axi_wready),
    .axi_bresp(axi_bresp),
    .axi_bvalid(axi_bvalid),
    .axi_bready(axi_bready),
    .led(led),
    .rx(rx),
    .tx(tx),
    .plic_int(plic_int),
    .plic_int_id(plic_int_id)
);

endmodule