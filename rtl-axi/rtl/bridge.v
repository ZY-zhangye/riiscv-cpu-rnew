//------------------------------
// 该模块实现了一个简单的AXI4-Lite桥接器，用于连接my_cpu和外设与Imenory和Dmemory之间的AXI4-Lite接口。桥接器负责转发my_cpu的AXI4-Lite请求到外设，并将外设的响应转发回my_cpu。桥接器还可以处理一些简单的地址映射和数据转换，以适应不同设备的需求。
// 该桥接器将my_cpu的AXI4-Lite请求转发到外设，并将外设的响应转发回my_cpu
//------------------------------
`include "defines.v"
module bridge #(
    parameter MEM_HEX_PATH = "C:\\Users\\ZY\\Desktop\\riiscv-cpu-rnew\\hex\\riscv-tests\\rv32ui-p-lui.hex"
)
(
    input wire clk,
    input wire rst_n,
    input wire clk_uart,
    //单套AXI4-Lite接口（用于与my_cpu连接）
    input wire [31:0] axi_araddr,
    input wire        axi_arvalid,
    output wire       axi_arready,
    output wire [31:0] axi_rdata,
    output wire [1:0]  axi_rresp,
    output wire       axi_rvalid,
    input wire        axi_rready,
    input wire [31:0] axi_awaddr,
    input wire        axi_awvalid,
    output wire       axi_awready,
    input wire [31:0] axi_wdata,
    input wire [3:0]  axi_wstrb,
    input wire        axi_wvalid,
    output wire       axi_wready,
    output wire [1:0]  axi_bresp,
    output wire       axi_bvalid,
    input wire        axi_bready,
    //外设接口（用于与外设连接）
    output wire [3:0] led,
    input wire rx,
    output wire tx,
    //PLIC中断信号
    output wire plic_int,
    output wire [15:0] plic_int_id
);
localparam INST_HIGH = 4'h0;
localparam DATA_HIGH = 4'h6;
localparam IO_HIGH = 4'h8;

localparam AXI_RESP_OKAY   = 2'b00;
localparam AXI_RESP_SLVERR = 2'b10;
localparam AXI_RESP_DECERR = 2'b11;

localparam TARGET_INST = 2'b00;
localparam TARGET_DATA = 2'b01;
localparam TARGET_IO   = 2'b10;
localparam TARGET_ERR  = 2'b11;

localparam AXI_IDLE       = 3'b000;
localparam AXI_READ_WAIT  = 3'b001;
localparam AXI_READ_RESP  = 3'b010;
localparam AXI_WRITE_WAIT = 3'b011;
localparam AXI_WRITE_RESP = 3'b100;

//inst_ram和data_ram实例
reg [31:0] imem_addr;
wire [31:0] imem_rdata;
reg imem_ren;
reg [31:0] dmem_addr;
reg [31:0] dmem_wdata;
reg [3:0] dmem_wen;
wire [31:0] dmem_rdata;
reg dmem_ren;
reg [31:0] io_addr;
reg [31:0] io_wdata;
reg [3:0] io_wen;
wire [31:0] io_rdata;
reg io_ren;

inst_ram #(
    //.MEM_HEX_PATH(MEM_HEX_PATH)
) u_inst_ram (
    .clk(clk),
    .rst_n(rst_n),
    .inst_ram_ren(imem_ren),
    .inst_ram_addr(imem_addr),
    .inst_ram_rdata(imem_rdata),
    .inst_ram_wen(1'b0), // 不支持写指令内存
    .inst_ram_wdata(32'b0)
);

data_ram #(
    //.MEM_HEX_PATH(MEM_HEX_PATH)
) u_data_ram (
    .clk(clk),
    .rst_n(rst_n),
    .data_ram_ren(dmem_ren),
    .data_ram_addr(dmem_addr),
    .data_ram_rdata(dmem_rdata),
    .data_ram_wen(dmem_wen),
    .data_ram_wdata(dmem_wdata)
);

IO u_io (
    .clk(clk),
    .rst_n(rst_n),
    .clk_uart(clk_uart),
    .addr(io_addr),
    .wdata(io_wdata),
    .wstrb(io_wen),
    .ren(io_ren),
    .rdata(io_rdata),
    .led(led),
    .rx(rx),
    .tx(tx),
    .plic_int(plic_int),
    .plic_int_id(plic_int_id)
);

//定义AXI4-Lite读写状态机
reg [2:0]  axi_state;
reg [1:0]  read_target;
reg [1:0]  write_target;
reg [31:0] axi_rdata_r;
reg [1:0]  axi_rresp_r;
reg        axi_rvalid_r;
reg [1:0]  axi_bresp_r;
reg        axi_bvalid_r;

wire [1:0] read_target_decoded =
    (axi_araddr[31:28] == INST_HIGH) ? TARGET_INST :
    (axi_araddr[31:28] == DATA_HIGH) ? TARGET_DATA :
    (axi_araddr[31:28] == IO_HIGH)   ? TARGET_IO   : TARGET_ERR;

wire [1:0] write_target_decoded =
    (axi_awaddr[31:28] == INST_HIGH) ? TARGET_INST :
    (axi_awaddr[31:28] == DATA_HIGH) ? TARGET_DATA :
    (axi_awaddr[31:28] == IO_HIGH)   ? TARGET_IO   : TARGET_ERR;

wire idle_state = (axi_state == AXI_IDLE);
wire write_req  = axi_awvalid && axi_wvalid;
wire write_fire = idle_state && write_req;
wire read_fire  = idle_state && !write_req && axi_arvalid;

assign axi_arready = idle_state && !write_req;
assign axi_awready = idle_state && axi_wvalid;
assign axi_wready  = idle_state && axi_awvalid;
assign axi_rdata   = axi_rdata_r;
assign axi_rresp   = axi_rresp_r;
assign axi_rvalid  = axi_rvalid_r;
assign axi_bresp   = axi_bresp_r;
assign axi_bvalid  = axi_bvalid_r;

always @(*) begin
    imem_addr  = 32'b0;
    imem_ren   = 1'b0;
    dmem_addr  = 32'b0;
    dmem_wdata = 32'b0;
    dmem_wen   = 4'b0;
    dmem_ren   = 1'b0;
    io_addr    = 32'b0;
    io_wdata   = 32'b0;
    io_wen     = 4'b0;
    io_ren     = 1'b0;

    if (read_fire) begin
        case (read_target_decoded)
            TARGET_INST: begin
                imem_addr = axi_araddr;
                imem_ren  = 1'b1;
            end
            TARGET_DATA: begin
                dmem_addr = axi_araddr;
                dmem_ren  = 1'b1;
            end
            TARGET_IO: begin
                io_addr = axi_araddr;
                io_ren  = 1'b1;
            end
            default: begin
                imem_addr = 32'b0;
            end
        endcase
    end

    if (write_fire) begin
        case (write_target_decoded)
            TARGET_DATA: begin
                dmem_addr  = axi_awaddr;
                dmem_wdata = axi_wdata;
                dmem_wen   = axi_wstrb;
            end
            TARGET_IO: begin
                io_addr  = axi_awaddr;
                io_wdata = axi_wdata;
                io_wen   = axi_wstrb;
            end
            default: begin
                io_addr = 32'b0;
            end
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        axi_state   <= AXI_IDLE;
        read_target <= TARGET_ERR;
        write_target <= TARGET_ERR;
        axi_rdata_r <= 32'b0;
        axi_rresp_r <= AXI_RESP_OKAY;
        axi_rvalid_r <= 1'b0;
        axi_bresp_r <= AXI_RESP_OKAY;
        axi_bvalid_r <= 1'b0;
    end else begin
        case (axi_state)
            AXI_IDLE: begin
                axi_rvalid_r <= 1'b0;
                axi_bvalid_r <= 1'b0;

                if (write_fire) begin
                    write_target <= write_target_decoded;
                    axi_state <= AXI_WRITE_WAIT;
                end else if (read_fire) begin
                    read_target <= read_target_decoded;
                    axi_state <= AXI_READ_WAIT;
                end
            end

            AXI_READ_WAIT: begin
                case (read_target)
                    TARGET_INST: begin
                        axi_rdata_r <= imem_rdata;
                        axi_rresp_r <= AXI_RESP_OKAY;
                    end
                    TARGET_DATA: begin
                        axi_rdata_r <= dmem_rdata;
                        axi_rresp_r <= AXI_RESP_OKAY;
                    end
                    TARGET_IO: begin
                        axi_rdata_r <= io_rdata;
                        axi_rresp_r <= AXI_RESP_OKAY;
                    end
                    default: begin
                        axi_rdata_r <= 32'b0;
                        axi_rresp_r <= AXI_RESP_DECERR;
                    end
                endcase
                axi_rvalid_r <= 1'b1;
                axi_state <= AXI_READ_RESP;
            end

            AXI_READ_RESP: begin
                if (axi_rvalid_r && axi_rready) begin
                    axi_rvalid_r <= 1'b0;
                    axi_state <= AXI_IDLE;
                end
            end

            AXI_WRITE_WAIT: begin
                case (write_target)
                    TARGET_DATA,
                    TARGET_IO: axi_bresp_r <= AXI_RESP_OKAY;
                    TARGET_INST: axi_bresp_r <= AXI_RESP_SLVERR;
                    default: axi_bresp_r <= AXI_RESP_DECERR;
                endcase
                axi_bvalid_r <= 1'b1;
                axi_state <= AXI_WRITE_RESP;
            end

            AXI_WRITE_RESP: begin
                if (axi_bvalid_r && axi_bready) begin
                    axi_bvalid_r <= 1'b0;
                    axi_state <= AXI_IDLE;
                end
            end

            default: begin
                axi_state <= AXI_IDLE;
            end
        endcase
    end
end

endmodule

