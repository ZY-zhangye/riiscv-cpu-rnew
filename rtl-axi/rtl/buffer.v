module buffer_fifo(
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire [31:0] data_addr,
    input  wire [31:0] data_wdata,
    input  wire [3:0]  data_wstrb,
    input  wire        data_ren,
    output wire        empty,
    output wire        full,
    output wire [31:0] q_addr,
    output wire [31:0] q_wdata,
    output wire [3:0]  q_wstrb,
    output wire        q_ren,
    output wire        valid,
    input  wire        rd_en
);

    parameter DEPTH = 8;
    reg [31:0] fifo_addr [0:DEPTH-1];
    reg [31:0] fifo_wdata [0:DEPTH-1];
    reg [3:0]  fifo_wstrb [0:DEPTH-1];
    reg        fifo_ren   [0:DEPTH-1];
    reg [2:0]  wr_ptr, rd_ptr;
    reg [3:0]  fifo_cnt_wr, fifo_cnt_rd;

    // 写时采样条件
    wire sample_en = (|data_wstrb) | data_ren;
    wire load_req = data_ren && !(|data_wstrb);
    wire store_req = |data_wstrb;
    reg        sample_en_d;
    reg        req_pending;
    reg [31:0] data_addr_d;
    reg [31:0] data_wdata_d;
    reg [3:0]  data_wstrb_d;
    reg        data_ren_d;
    wire last_load_req = data_ren_d && !(|data_wstrb_d);
    wire last_store_req = |data_wstrb_d;
    wire same_load_req = load_req && last_load_req && (data_addr == data_addr_d);
    wire same_store_req = store_req && last_store_req &&
                          (data_addr == data_addr_d) &&
                          (data_wstrb == data_wstrb_d) &&
                          (data_wdata == data_wdata_d);
    wire same_req_as_prev = same_load_req | same_store_req;
    wire new_req_seen = sample_en & (!sample_en_d | !same_req_as_prev);
    wire enqueue_fire = req_pending | new_req_seen;

    // 写指针与计数器（写时钟域）
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr <= 0;
            fifo_cnt_wr <= 0;
            sample_en_d <= 0;
            req_pending <= 0;
            data_addr_d <= 32'b0;
            data_wdata_d <= 32'b0;
            data_wstrb_d <= 4'b0;
            data_ren_d <= 1'b0;
        end else begin
            sample_en_d <= sample_en;
            if (sample_en) begin
                data_addr_d <= data_addr;
                data_wdata_d <= data_wdata;
                data_wstrb_d <= data_wstrb;
                data_ren_d <= data_ren;
            end

            if (!sample_en)
                req_pending <= 1'b0;
            else if (enqueue_fire && !full)
                req_pending <= 1'b0;
            else if (new_req_seen)
                req_pending <= 1'b1;

            // 请求有效且与上一拍相比是新请求时入队：
            // 1) 上升沿第一拍；2) 连续有效但内容变化（背靠背不同指令）
            if (enqueue_fire && !full) begin
                fifo_addr[wr_ptr]  <= data_addr;
                fifo_wdata[wr_ptr] <= data_wdata;
                fifo_wstrb[wr_ptr] <= data_wstrb;
                fifo_ren[wr_ptr]   <= data_ren;
                wr_ptr <= wr_ptr + 1'b1;
                fifo_cnt_wr <= fifo_cnt_wr + 1'b1;
            end
        end
    end

    // 读指针与计数器（读时钟域）
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr <= 0;
            fifo_cnt_rd <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr <= rd_ptr + 1'b1;
            fifo_cnt_rd <= fifo_cnt_rd + 1'b1;
        end
    end

    // 简单同步处理（实际异步FIFO需用双口RAM和跨时钟域同步，简化版）
    wire [3:0] fifo_cnt = fifo_cnt_wr - fifo_cnt_rd;

    assign empty = (fifo_cnt == 0);
    assign full  = (fifo_cnt == DEPTH);
    assign valid = !empty;
    assign q_addr  = fifo_addr[rd_ptr];
    assign q_wdata = fifo_wdata[rd_ptr];
    assign q_wstrb = fifo_wstrb[rd_ptr];
    assign q_ren   = fifo_ren[rd_ptr];

endmodule

module buffer(
    input wr_clk,
    input wr_rst_n,
    input rd_clk,
    input rd_rst_n,
    //CPU端输入接口
    input [31:0] data_addr,
    input [31:0] data_wdata,
    input [3:0]  data_wstrb,
    input        data_ren,
    //CPU端stall信号
    output wire       stall,
    //CPU端输出接口
    output reg [31:0] q_data,
    output reg        q_valid,
    //AXI端读地址通道
    output reg [31:0] axi_araddr,
    output reg        axi_arvalid,
    input         axi_arready,
    //AXI端读数据通道
    input  [31:0] axi_rdata,
    input         axi_rvalid,
    output reg       axi_rready,
    //AXI端写地址通道
    output reg [31:0] axi_awaddr,
    output reg        axi_awvalid,
    input         axi_awready,
    //AXI端写数据通道
    output reg [31:0] axi_wdata,
    output reg [3:0]  axi_wstrb,
    output reg        axi_wvalid,
    input         axi_wready,
    //AXI端写响应通道
    input         axi_bvalid,
    output reg       axi_bready
);

    // 实例化FIFO
    wire fifo_empty, fifo_full, fifo_valid;
    wire [31:0] fifo_q_addr, fifo_q_wdata;
    wire [3:0]  fifo_q_wstrb;
    wire        fifo_q_ren;
    reg rd_en;
    assign stall = fifo_full;  // 当FIFO满时，CPU端stall信号有效
    buffer_fifo u_buffer_fifo (
        .wr_clk(wr_clk),
        .wr_rst_n(wr_rst_n),
        .rd_clk(rd_clk),
        .rd_rst_n(rd_rst_n),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_wstrb(data_wstrb),
        .data_ren(data_ren),
        .empty(fifo_empty),
        .full(fifo_full),
        .q_addr(fifo_q_addr),
        .q_wdata(fifo_q_wdata),
        .q_wstrb(fifo_q_wstrb),
        .q_ren(fifo_q_ren),
        .valid(fifo_valid),
        .rd_en(rd_en)
    );

    //状态转移寄存器
    reg [2:0] axi_state, axi_next_state;
    // AXI状态定义
    localparam AXI_IDLE = 3'b000;
    localparam AXI_READ_ADDR = 3'b001;
    localparam AXI_READ_DATA = 3'b010;
    localparam AXI_WRITE_DATA = 3'b011;
    localparam AXI_WRITE_DOWN = 3'b100;

    // 读fifo逻辑：使用 axi_state 来替代独立的 AXI_READ/AXI_WRITE 标志
    wire fifo_pop_valid = fifo_valid && (axi_state == AXI_IDLE) && (axi_next_state != AXI_IDLE);
    
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_en <= 0;
        end else begin
            // rd_en 必须是单拍脉冲，在即将启动 AXI 事务时拉高
            rd_en <= fifo_pop_valid;
        end
    end

    // AXI4-Lite接口逻辑

    // ============ AXI-Lite状态机：控制信号 ============
    always @ (*) begin
        case (axi_state)
            AXI_IDLE: begin
                if (fifo_valid) begin
                    if (fifo_q_ren)
                        axi_next_state = AXI_READ_ADDR;
                    else
                        axi_next_state = AXI_WRITE_DATA;
                end else begin
                    axi_next_state = AXI_IDLE;
                end
            end
            AXI_READ_ADDR: begin
                if (axi_arvalid && axi_arready)
                    axi_next_state = AXI_READ_DATA;
                else
                    axi_next_state = AXI_READ_ADDR;
            end
            AXI_READ_DATA: begin
                if (axi_rvalid && axi_rready)
                    axi_next_state = AXI_IDLE;
                else
                    axi_next_state = AXI_READ_DATA;
            end
            AXI_WRITE_DATA: begin
                if (axi_awvalid && axi_awready && axi_wvalid && axi_wready)
                    axi_next_state = AXI_WRITE_DOWN;
                else
                    axi_next_state = AXI_WRITE_DATA;
            end
            AXI_WRITE_DOWN: begin
                if (axi_bvalid && axi_bready)
                    axi_next_state = AXI_IDLE;
                else
                    axi_next_state = AXI_WRITE_DOWN;
            end
        endcase
    end
    // ============ AXI-Lite状态机：时序逻辑（状态更新） ============
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            axi_state <= AXI_IDLE;  // 复位时回到空闲状态
        else
            axi_state <= axi_next_state;
    end
    // ============ AXI-Lite接口信号控制 ============
    // 读地址通道
    always @ (posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            axi_araddr <= 32'b0;
            axi_arvalid <= 1'b0;
        end else begin
            case (axi_state)
                AXI_IDLE: begin
                    if (fifo_valid && fifo_q_ren) begin
                        axi_araddr <= {4'h6, fifo_q_addr[27:0]}; // 强制最高4位为6
                        axi_arvalid <= 1'b1; // 发起读地址请求
                    end else begin
                        axi_arvalid <= 1'b0;
                    end
                end
                AXI_READ_ADDR: begin
                    if (axi_arvalid && axi_arready)
                        axi_arvalid <= 1'b0; // 地址握手完成，拉低arvalid
                end
                default: axi_arvalid <= 1'b0;
            endcase
        end
    end
    // 读数据通道
    always @ (posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            axi_rready <= 1'b0;
            q_data <= 32'b0;
            q_valid <= 1'b0;
        end else begin
            case (axi_state)
                AXI_IDLE: begin
                    axi_rready <= 1'b0;
                    q_valid <= 1'b0;
                end
                AXI_READ_ADDR: begin
                    if (axi_arvalid && axi_arready)
                        axi_rready <= 1'b1; // 地址握手完成，准备接收数据
                end
                AXI_READ_DATA: begin
                    if (axi_rvalid && axi_rready) begin
                        q_data <= axi_rdata; // 接收数据
                        q_valid <= 1'b1; // 数据有效
                        axi_rready <= 1'b0; // 完成数据接收，拉低rready
                    end
                end
                default: begin
                    axi_rready <= 1'b0;
                    q_valid <= 1'b0;
                end
            endcase
        end
    end
    // 写地址通道和写数据通道，源数据同时产生，此处同时推出
    always @ (posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            axi_awaddr <= 32'b0;
            axi_awvalid <= 1'b0;
            axi_wdata <= 32'b0;
            axi_wstrb <= 4'b0;
            axi_wvalid <= 1'b0;
        end else begin
            case (axi_state)
                AXI_IDLE: begin
                    if (fifo_valid && !fifo_q_ren) begin
                        axi_awaddr <= {4'h6, fifo_q_addr[27:0]}; // 强制最高4位为8
                        axi_wdata <= fifo_q_wdata; // 直接从FIFO捕获数据
                        axi_wstrb <= fifo_q_wstrb; // 直接从FIFO捕获写使能
                        axi_awvalid <= 1'b1; // 发起写地址请求
                        axi_wvalid <= 1'b1; // 发起写数据请求
                    end else begin
                        axi_awvalid <= 1'b0;
                        axi_wvalid <= 1'b0;
                    end
                end
                AXI_WRITE_DATA: begin
                    if (axi_awvalid && axi_awready && axi_wvalid && axi_wready) begin
                        axi_awvalid <= 1'b0; // 地址握手完成，拉低awvalid
                        axi_wvalid <= 1'b0; // 数据握手完成，拉低wvalid
                    end
                end
                default: begin
                    axi_awvalid <= 1'b0;
                    axi_wvalid <= 1'b0;
                end
            endcase
        end
    end
    // 写响应通道
    always @ (posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            axi_bready <= 1'b0;
        end else begin
            case (axi_state)
                AXI_WRITE_DATA: begin
                    if (axi_awvalid && axi_awready && axi_wvalid && axi_wready)
                        axi_bready <= 1'b1; // 写请求完成，准备接收写响应
                end
                AXI_WRITE_DOWN: begin
                    if (axi_bvalid && axi_bready)
                        axi_bready <= 1'b0; // 写响应接收完成，拉低bready
                end
                default: axi_bready <= 1'b0;
            endcase
        end
    end

endmodule
