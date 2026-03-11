/*
 * IF侧AXI4-Lite读适配模块
 * 将 if_stage 的简化取指请求/响应接口转换为AXI4-Lite读通道。
 *
 * 说明：
 * 1) 该模块可直接替换为I-Cache miss refill接口（保持 if_addr/if_ren/if_rdata/if_rvalid 不变）
 * 2) 对AXI RRESP做了错误检测：非OKAY时返回NOP，避免前端死锁
 */
module if_axi_if (
    input  wire        clk,
    input  wire        rst_n,

    // ============ 来自if_stage的请求 ============
    input  wire [31:0] if_addr,
    input  wire        if_ren,

    // ============ 返回给if_stage的响应 ============
    output reg  [31:0] if_rdata,
    output reg         if_rvalid,

    // ============ AXI4-Lite读地址通道 ============
    output reg  [31:0] axi_araddr,
    output reg         axi_arvalid,
    input  wire        axi_arready,

    // ============ AXI4-Lite读数据通道 ============
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rvalid,
    output reg         axi_rready
);

    localparam AXI_IDLE = 2'b00;
    localparam AXI_ADDR = 2'b01;
    localparam AXI_DATA = 2'b10;

    reg [1:0] axi_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_state  <= AXI_IDLE;
            axi_araddr <= 32'b0;
            axi_arvalid <= 1'b0;
            axi_rready <= 1'b0;
            if_rdata <= 32'b0;
            if_rvalid <= 1'b0;
        end else begin
            // 默认响应有效为单拍
            if_rvalid <= 1'b0;

            case (axi_state)
                AXI_IDLE: begin
                    axi_arvalid <= 1'b0;
                    axi_rready  <= 1'b0;

                    if (if_ren) begin
                        axi_araddr  <= if_addr;
                        axi_arvalid <= 1'b1;
                        axi_state   <= AXI_ADDR;
                    end
                end

                AXI_ADDR: begin
                    if (axi_arvalid && axi_arready) begin
                        axi_arvalid <= 1'b0;
                        axi_rready  <= 1'b1;
                        axi_state   <= AXI_DATA;
                    end
                end

                AXI_DATA: begin
                    if (axi_rvalid && axi_rready) begin
                        // RRESP=2'b00表示OKAY；异常时返回NOP并继续前进，防止流水线卡死
                        if_rdata  <= (axi_rresp == 2'b00) ? axi_rdata : 32'h0000_0013;
                        if_rvalid <= 1'b1;
                        axi_rready <= 1'b0;
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
