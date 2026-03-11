/*
 * AXI4-Lite 读通道双主仲裁器（取指优先，可配置防饥饿）
 *
 * 设计要点：
 * 1) 在发出AR后到握手完成前，锁存并保持 owner + araddr 稳定，避免地址漂移。
 * 2) R通道严格按owner回传，防止取指数据误送到数据访存通路（或反之）。
 * 3) 支持"取指优先 + 连续授权上限"，避免Data侧长期饥饿。
 */
// -----------------------------------------------------------------------------
// AXI4-Lite 读通道双主仲裁器（取指优先，可配置防饥饿）
//
// 设计要点：
// 1) 在发出AR后到握手完成前，锁存并保持 owner + araddr 稳定，避免地址漂移。
// 2) R通道严格按owner回传，防止取指数据误送到数据访存通路（或反之）。
// 3) 支持"取指优先 + 连续授权上限"，避免Data侧长期饥饿。
//
// 主要仲裁策略：
// - IF（取指）优先，除非连续授权次数达到上限（IF_MAX_CONSECUTIVE_GRANTS），此时强制切换给Data侧。
// - 通过if_grant_cnt计数，记录IF连续获授权次数。
// - 只要Data侧有请求且IF已达上限，则Data优先，否则IF优先。
// -----------------------------------------------------------------------------
module axi_read_arbiter #(
    parameter IF_MAX_CONSECUTIVE_GRANTS = 8
) (
    input  wire        clk,
    input  wire        rst_n,

    // Master0: IF侧（高优先级）
    input  wire [31:0] m0_araddr,
    input  wire        m0_arvalid,
    output wire        m0_arready,
    output wire [31:0] m0_rdata,
    output wire [1:0]  m0_rresp,
    output wire        m0_rvalid,
    input  wire        m0_rready,

    // Master1: Data侧
    input  wire [31:0] m1_araddr,
    input  wire        m1_arvalid,
    output wire        m1_arready,
    output wire [31:0] m1_rdata,
    output wire        m1_rvalid,
    input  wire        m1_rready,

    // AXI从设备侧读通道
    output wire [31:0] axi_araddr,
    output wire        axi_arvalid,
    input  wire        axi_arready,
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rvalid,
    output wire        axi_rready
);

    // 连续IF授权计数器位宽
    localparam integer IF_GRANT_CNT_W = $clog2(IF_MAX_CONSECUTIVE_GRANTS + 1);

    reg [IF_GRANT_CNT_W-1:0] if_grant_cnt;   // IF连续授权计数器
    reg ar_pending;                          // AR通道请求挂起标志
    reg r_pending;                           // R通道等待标志
    reg owner_if;                            // 当前事务归属（1:IF, 0:Data）
    reg [31:0] araddr_latched;               // 锁存的AR地址
    reg sel_both_req;                        // 本次仲裁时，是否两侧都请求

    // 仲裁信号
    wire both_req  = m0_arvalid && m1_arvalid; // 两侧都请求
    // 达到IF连续授权上限时，强制切换给Data侧
    wire force_m1  = both_req && (if_grant_cnt >= IF_MAX_CONSECUTIVE_GRANTS);
    // 取指优先：只要IF有请求且未强制切换，优先IF
    wire pick_m0   = m0_arvalid && !force_m1;
    // Data侧：IF无请求或被强制切换时才选中
    wire pick_m1   = m1_arvalid && (!m0_arvalid || force_m1);

    // AR通道握手成功
    wire ar_hs = ar_pending && axi_arready;
    // R通道握手成功
    wire r_hs  = r_pending && axi_rvalid && axi_rready;

    // AXI从设备侧接口
    assign axi_arvalid = ar_pending;
    assign axi_araddr  = araddr_latched;

    // IF侧AR握手响应，仅在本次事务归属IF时拉高
    assign m0_arready = ar_hs && owner_if;
    // Data侧AR握手响应，仅在本次事务归属Data时拉高
    assign m1_arready = ar_hs && !owner_if;

    // IF侧R通道响应，仅在本次事务归属IF且R有效时拉高
    assign m0_rvalid = r_pending && owner_if && axi_rvalid;
    assign m0_rdata  = axi_rdata;
    assign m0_rresp  = axi_rresp;

    // Data侧R通道响应，仅在本次事务归属Data且R有效时拉高
    assign m1_rvalid = r_pending && !owner_if && axi_rvalid;
    // Data侧仅在正常响应时回传数据，否则返回0
    assign m1_rdata  = (axi_rresp == 2'b00) ? axi_rdata : 32'b0;

    // R通道ready信号，按owner分发到对应主机
    assign axi_rready = r_pending ? (owner_if ? m0_rready : m1_rready) : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_grant_cnt   <= {IF_GRANT_CNT_W{1'b0}};
            ar_pending     <= 1'b0;
            r_pending      <= 1'b0;
            owner_if       <= 1'b0;
            araddr_latched <= 32'b0;
            sel_both_req   <= 1'b0;
        end else begin
            // -----------------------------------------------------------------
            // 空闲时发起一笔新AR请求，并锁存owner与地址
            // 取指优先：只要IF有请求且未达上限，优先IF，否则Data
            // -----------------------------------------------------------------
            if (!ar_pending && !r_pending && (pick_m0 || pick_m1)) begin
                ar_pending     <= 1'b1;
                owner_if       <= pick_m0; // 1:IF优先，0:Data
                araddr_latched <= pick_m0 ? m0_araddr : m1_araddr;
                sel_both_req   <= both_req;
            end

            // -----------------------------------------------------------------
            // AR握手完成后进入R等待
            // 若本次为IF侧且两侧都请求，则计数+1，否则清零
            // 达到上限后，下一次两侧都请求时强制切换给Data
            // -----------------------------------------------------------------
            if (ar_hs) begin
                ar_pending <= 1'b0;
                r_pending  <= 1'b1;

                // 连续IF授权计数
                if (sel_both_req && owner_if) begin
                    if (if_grant_cnt < IF_MAX_CONSECUTIVE_GRANTS)
                        if_grant_cnt <= if_grant_cnt + 1'b1;
                end else begin
                    if_grant_cnt <= {IF_GRANT_CNT_W{1'b0}};
                end
            end

            // -----------------------------------------------------------------
            // R握手完成后本次读事务结束
            // -----------------------------------------------------------------
            if (r_hs) begin
                r_pending <= 1'b0;
            end
        end
    end

endmodule
