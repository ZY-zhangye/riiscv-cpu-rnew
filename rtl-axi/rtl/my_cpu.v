module my_cpu #(
    parameter MEM_HEX_PATH = "C:\\Users\\ZY\\Desktop\\riiscv-cpu-rnew\\hex\\riscv-tests\\rv32ui-p-auipc.hex",
    parameter IF_MAX_CONSECUTIVE_GRANTS = 8
)
(
    input wire clk,
    input wire rst_n,
    //debug接口
    output wire [31:0] debug_inst_pc,
    output wire [31:0] debug_wb_pc,
    output wire debug_wb_rf_wen,
    output wire [4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    output wire [31:0] debug_data,
    //单套AXI4-Lite接口（仲裁后输出）
    output wire [31:0] axi_araddr,
    output wire        axi_arvalid,
    input  wire        axi_arready,
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rvalid,
    output wire        axi_rready,
    output wire [31:0] axi_awaddr,
    output wire        axi_awvalid,
    input  wire        axi_awready,
    output wire [31:0] axi_wdata,
    output wire [3:0]  axi_wstrb,
    output wire        axi_wvalid,
    input  wire        axi_wready,
    input  wire [1:0]  axi_bresp,
    input  wire        axi_bvalid,
    output wire        axi_bready,
    //外设接口
    output reg [3:0] led
);
wire [31:0] imem_addr;
wire [31:0] imem_rdata;
wire imem_rvalid;
wire imem_ren;
wire [31:0] dmem_addr;
wire [31:0] dmem_wdata;
wire [3:0] dmem_wen;
wire [31:0] dmem_rdata;
wire dmem_rvalid;
wire dmem_stall;
wire dmem_en;

assign debug_inst_pc = imem_addr - 4;

top u_top(
    .clk(clk),
    .rst_n(rst_n),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .debug_data(debug_data),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .imem_rvalid(imem_rvalid),
    .imem_ren(imem_ren),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_wen(dmem_wen),
    .dmem_rdata(dmem_rdata),
    .dmem_rvalid(dmem_rvalid),
    .dmem_stall(dmem_stall),
    .dmem_en(dmem_en)
);

// ============ IF AXI adapter ============
// 后续接入Icache时：可将 u_if_axi_if 替换为 icache 控制器，
// 对 top 仍保持 imem_addr/imem_ren/imem_rdata/imem_rvalid 这一抽象接口不变。
wire [31:0] if_axi_araddr;
wire if_axi_arvalid;
wire if_axi_arready;
wire [31:0] if_axi_rdata;
wire [1:0] if_axi_rresp;
wire if_axi_rvalid;
wire if_axi_rready;

if_axi_if u_if_axi_if (
    .clk(clk),
    .rst_n(rst_n),
    .if_addr(imem_addr),
    .if_ren(imem_ren),
    .if_rdata(imem_rdata),
    .if_rvalid(imem_rvalid),
    .axi_araddr(if_axi_araddr),
    .axi_arvalid(if_axi_arvalid),
    .axi_arready(if_axi_arready),
    .axi_rdata(if_axi_rdata),
    .axi_rresp(if_axi_rresp),
    .axi_rvalid(if_axi_rvalid),
    .axi_rready(if_axi_rready)
);

// ============ Data AXI buffer ============
// 后续接入Dcache时：可将 u_buffer 替换为 dcache miss/写回控制器，
// 对 top 仍保持 dmem_* 抽象接口不变。
wire [31:0] buf_axi_araddr;
wire        buf_axi_arvalid;
wire        buf_axi_arready;
wire [31:0] buf_axi_rdata;
wire        buf_axi_rvalid;
wire        buf_axi_rready;
wire [31:0] buf_axi_awaddr;
wire        buf_axi_awvalid;
wire        buf_axi_awready;
wire [31:0] buf_axi_wdata;
wire [3:0]  buf_axi_wstrb;
wire        buf_axi_wvalid;
wire        buf_axi_wready;
wire        buf_axi_bvalid;
wire        buf_axi_bready;

buffer u_buffer (
    .wr_clk(clk),
    .wr_rst_n(rst_n),
    .rd_clk(clk),
    .rd_rst_n(rst_n),
    .data_addr(dmem_addr),
    .data_wdata(dmem_wdata),
    .data_wstrb(dmem_wen),
    .data_ren(dmem_en),
    .stall(dmem_stall),
    .q_data(dmem_rdata),
    .q_valid(dmem_rvalid),
    .axi_araddr(buf_axi_araddr),
    .axi_arvalid(buf_axi_arvalid),
    .axi_arready(buf_axi_arready),
    .axi_rdata(buf_axi_rdata),
    .axi_rvalid(buf_axi_rvalid),
    .axi_rready(buf_axi_rready),
    .axi_awaddr(buf_axi_awaddr),
    .axi_awvalid(buf_axi_awvalid),
    .axi_awready(buf_axi_awready),
    .axi_wdata(buf_axi_wdata),
    .axi_wstrb(buf_axi_wstrb),
    .axi_wvalid(buf_axi_wvalid),
    .axi_wready(buf_axi_wready),
    .axi_bvalid(buf_axi_bvalid),
    .axi_bready(buf_axi_bready)
);

// ============ 读通道仲裁（取指优先） ============
axi_read_arbiter #(
    .IF_MAX_CONSECUTIVE_GRANTS(IF_MAX_CONSECUTIVE_GRANTS)
) u_axi_read_arbiter (
    .clk(clk),
    .rst_n(rst_n),
    .m0_araddr(if_axi_araddr),
    .m0_arvalid(if_axi_arvalid),
    .m0_arready(if_axi_arready),
    .m0_rdata(if_axi_rdata),
    .m0_rresp(if_axi_rresp),
    .m0_rvalid(if_axi_rvalid),
    .m0_rready(if_axi_rready),
    .m1_araddr(buf_axi_araddr),
    .m1_arvalid(buf_axi_arvalid),
    .m1_arready(buf_axi_arready),
    .m1_rdata(buf_axi_rdata),
    .m1_rvalid(buf_axi_rvalid),
    .m1_rready(buf_axi_rready),
    .axi_araddr(axi_araddr),
    .axi_arvalid(axi_arvalid),
    .axi_arready(axi_arready),
    .axi_rdata(axi_rdata),
    .axi_rresp(axi_rresp),
    .axi_rvalid(axi_rvalid),
    .axi_rready(axi_rready)
);

// 响应错误标志（预留给后续异常处理/中断上报）
reg axi_if_rresp_err_sticky;
reg axi_data_rresp_err_sticky;
reg axi_data_bresp_err_sticky;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        axi_if_rresp_err_sticky <= 1'b0;
        axi_data_rresp_err_sticky <= 1'b0;
        axi_data_bresp_err_sticky <= 1'b0;
    end else begin
        // 读响应错误记录
        if (if_axi_rvalid && if_axi_rready && (if_axi_rresp != 2'b00))
            axi_if_rresp_err_sticky <= 1'b1;

        if (buf_axi_rvalid && buf_axi_rready && (axi_rresp != 2'b00))
            axi_data_rresp_err_sticky <= 1'b1;

        // 写响应错误记录
        if (axi_bvalid && axi_bready && (axi_bresp != 2'b00))
            axi_data_bresp_err_sticky <= 1'b1;
    end
end

// ============ 写通道（仅Data buffer使用） ============
assign axi_awaddr  = buf_axi_awaddr;
assign axi_awvalid = buf_axi_awvalid;
assign buf_axi_awready = axi_awready;

assign axi_wdata   = buf_axi_wdata;
assign axi_wstrb   = buf_axi_wstrb;
assign axi_wvalid  = buf_axi_wvalid;
assign buf_axi_wready = axi_wready;

// 非OKAY也需要通知buffer事务结束，避免写通道死锁
assign buf_axi_bvalid = axi_bvalid;
assign axi_bready = buf_axi_bready;

// ============ 简单IO示例：LED映射 ============
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        led <= 4'b1111;
    else if ((|dmem_wen) && (dmem_addr[31:28] == 4'h8))
        led <= dmem_wdata[3:0];
end

endmodule