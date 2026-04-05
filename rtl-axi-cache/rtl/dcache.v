//dcache顶层文件，主要用于分流访问dram和IO的请求，其中访问dram的请求送往data_cache，访问IO的请求直接通过AXI4总线送出去
`include "defines.v"
module dcache (
    input wire clk,
    input wire rst_n,
    // CPU接口
    input wire [31:0] cpu_addr,
    input wire cpu_ren,
    input wire [3:0] cpu_wen,
    input wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,
    output wire cpu_rvalid,
    output wire cpu_stall,
    // AXI接口
    //读请求通道
    output wire [3:0] axi_arid,
    output reg [31:0] axi_araddr,
    output reg [7:0] axi_arlen,
    output reg [2:0] axi_arsize,
    output wire [1:0] axi_arburst,
    output wire [1:0] axi_arlock,
    output wire [3:0] axi_arcache,
    output wire [2:0] axi_arprot,
    output reg axi_arvalid,
    input wire axi_arready,
    //写请求通道
    output wire [3:0] axi_awid,
    output reg [31:0] axi_awaddr,
    output reg [7:0] axi_awlen,
    output reg [2:0] axi_awsize,
    output wire [1:0] axi_awburst,
    output wire [1:0] axi_awlock,
    output wire [3:0] axi_awcache,
    output wire [2:0] axi_awprot,
    output reg axi_awvalid,
    input wire axi_awready,
    //写数据通道
    output reg [3:0] axi_wid,
    output reg [31:0] axi_wdata,
    output reg [3:0] axi_wstrb,
    output reg axi_wlast,
    output reg axi_wvalid,
    input wire axi_wready,
    //读数据通道
    input wire [3:0] axi_rid,
    input wire [31:0] axi_rdata,
    input wire [1:0] axi_rresp,
    input wire axi_rlast,
    input wire axi_rvalid,
    output reg axi_rready,
    //写响应通道
    input wire [3:0] axi_bid,
    input wire [1:0] axi_bresp,
    input wire axi_bvalid,
    output reg axi_bready
);

    //与data_cache的接口信号
    wire refill_req;
    wire [31:0] refill_addr;
    reg [255:0] refill_data;
    reg refill_valid;
    wire write_back_req;
    wire [31:0] write_back_addr;
    wire [255:0] write_back_data;
    wire [31:0] dram_rdata;
    wire dram_rvalid;
    // 实例化data_cache模块
    data_cache u_data_cache (
        .clk(clk),
        .rst_n(rst_n),
        .addr(cpu_addr),
        .ren(cpu_ren && (cpu_addr >= `DATA_ADDR_BEGIN) && (cpu_addr <= `DATA_ADDR_END)),
        .wen((|cpu_wen) && (cpu_addr >= `DATA_ADDR_BEGIN) && (cpu_addr <= `DATA_ADDR_END)),
        .wdata(cpu_wdata),
        .wstrb(cpu_wen),
        .rdata(dram_rdata),
        .rvalid(dram_rvalid),
        .refill_req(refill_req),
        .refill_addr(refill_addr),
        .refill_data(refill_data),
        .refill_valid(refill_valid),
        .write_back_req(write_back_req),
        .write_back_addr(write_back_addr),
        .write_back_data(write_back_data)
    );

    //读写请求通道的一些固定信号
    assign axi_arid = 4'b0001; // 读请求ID固定为1
    assign axi_arburst = 2'b01; // 读请求使用INCR突发类型
    assign axi_arlock = 2'b00; // 读请求不使用锁
    assign axi_arcache = 4'b0000; // 读请求不使用缓存
    assign axi_arprot = 3'b000; // 读请求使用默认保护类型
    assign axi_awid = 4'b0010; // 写请求ID固定为2
    assign axi_awburst = 2'b01; // 写请求使用INCR突发类型
    assign axi_awlock = 2'b00; // 写请求不使用锁
    assign axi_awcache = 4'b0000; // 写请求不使用缓存
    assign axi_awprot = 3'b000; // 写请求使用默认保护类型

    // 根据地址范围判断是访问DRAM还是IO
    wire is_io_access = (cpu_addr >= `IO_ADDR_BEGIN) && (cpu_addr <= `IO_ADDR_END);
    wire is_dram_access = (cpu_addr >= `DATA_ADDR_BEGIN) && (cpu_addr <= `DATA_ADDR_END);

    // 定义访问DRAM和IO的状态机
    // 读请求状态机
    localparam R_IDLE = 2'b00;
    localparam R_SEND = 2'b01;
    localparam R_WAIT = 2'b10;
    localparam R_RECV = 2'b11;
    reg [1:0] r_state;
    reg [1:0] r_state_next;
    // 写请求状态机
    localparam W_IDLE = 2'b00;
    localparam W_SEND = 2'b01;
    localparam W_WAIT = 2'b10;
    localparam W_RESP = 2'b11;
    reg [1:0] w_state;
    reg [1:0] w_state_next;
    //采样data_cache的请求
    reg [31:0] pending_refill_addr;
    reg pending_refill;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_refill_addr <= 0;
            pending_refill <= 0;
        end else begin
            if (refill_req && !pending_refill) begin
                pending_refill_addr <= refill_addr;
                pending_refill <= 1;
            end else if (axi_arvalid && axi_arready) begin
                pending_refill <= 0; // 请求发出后清除待处理标志
            end
        end
    end
    //IO访问直接通过AXI总线发出
    reg pending_io_read;
    reg [31:0] pending_io_addr;
    reg [3:0] io_wen;
    reg [31:0] io_wdata;
    reg r_req_is_refill; // 当前在途读事务类型：1=refill，0=IO读
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_io_read <= 0;
            pending_io_addr <= 0;
            io_wen <= 0;
            io_wdata <= 0;
            r_req_is_refill <= 0;
        end else begin
            // 锁存IO写请求信息（调试/观测用途）
            if (is_io_access && (|cpu_wen)) begin
                io_wen <= cpu_wen;
                io_wdata <= cpu_wdata;
            end

            // AR发射成功后，记录该笔读事务类型（refill或IO）
            if (r_state == R_SEND && axi_arvalid && axi_arready) begin
                r_req_is_refill <= pending_refill;
                if (!pending_refill) begin
                    pending_io_read <= 1'b0;
                end
            end

            // 采样IO读请求（单拍脉冲），忙时挂起，等待读状态机空闲后发出
            if (is_io_access && cpu_ren) begin
                pending_io_read <= 1'b1;
                pending_io_addr <= cpu_addr;
            end

            if (r_state == R_IDLE) begin
                r_req_is_refill <= 1'b0;
            end
        end
    end

    // 写请求FIFO（IO写 + cache写回）
    localparam WFIFO_DEPTH = 4;
    localparam WFIFO_PTR_W = 2;

    // IO写FIFO：单拍写
    reg [31:0] io_wfifo_addr [0:WFIFO_DEPTH-1];
    reg [31:0] io_wfifo_data [0:WFIFO_DEPTH-1];
    reg [3:0] io_wfifo_strb [0:WFIFO_DEPTH-1];
    reg [WFIFO_PTR_W-1:0] io_wfifo_wr_ptr;
    reg [WFIFO_PTR_W-1:0] io_wfifo_rd_ptr;
    reg [WFIFO_PTR_W:0] io_wfifo_count;

    // 写回FIFO：8拍突发写
    reg [31:0] wb_wfifo_addr [0:WFIFO_DEPTH-1];
    reg [255:0] wb_wfifo_data [0:WFIFO_DEPTH-1];
    reg [WFIFO_PTR_W-1:0] wb_wfifo_wr_ptr;
    reg [WFIFO_PTR_W-1:0] wb_wfifo_rd_ptr;
    reg [WFIFO_PTR_W:0] wb_wfifo_count;

    // 写回满时缓存一个待入队请求，避免脉冲丢失
    reg wb_pending_valid;
    reg [31:0] wb_pending_addr;
    reg [255:0] wb_pending_data;

    wire io_write_req = is_io_access && (|cpu_wen);
    wire io_wfifo_full = (io_wfifo_count == WFIFO_DEPTH);
    wire wb_wfifo_full = (wb_wfifo_count == WFIFO_DEPTH);
    wire io_wfifo_empty = (io_wfifo_count == 0);
    wire wb_wfifo_empty = (wb_wfifo_count == 0);

    // 当两个FIFO都满时阻塞；另外在本类请求对应FIFO满时也阻塞，防止写请求丢失
    assign cpu_stall = (io_wfifo_full && wb_wfifo_full) ||
                       (io_write_req && io_wfifo_full) ||
                       (write_back_req && wb_wfifo_full && wb_pending_valid);

    // 写状态机当前选中的请求（IO优先）
    reg w_sel_io;
    reg [31:0] w_req_addr;
    reg [255:0] w_req_data;
    reg [3:0] w_req_strb;
    reg [7:0] w_req_len;
    reg [7:0] w_beat_cnt;

    wire w_pick_io = !io_wfifo_empty;
    wire w_pick_wb = io_wfifo_empty && !wb_wfifo_empty;
    wire w_req_available = w_pick_io || w_pick_wb;
    wire w_data_hs = axi_wvalid && axi_wready;
    wire w_data_last_hs = w_data_hs && axi_wlast;
    wire w_resp_hs = axi_bvalid && axi_bready;
    wire io_fifo_push = io_write_req && !io_wfifo_full;
    wire io_fifo_pop = (w_state == W_RESP) && w_resp_hs && w_sel_io && !io_wfifo_empty;
    wire wb_fifo_pop = (w_state == W_RESP) && w_resp_hs && !w_sel_io && !wb_wfifo_empty;
    wire wb_fifo_push_pending = wb_pending_valid && !wb_wfifo_full;
    wire wb_fifo_push_new = (!wb_pending_valid) && write_back_req && !wb_wfifo_full;

    // FIFO入队/出队管理
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            io_wfifo_wr_ptr <= 0;
            io_wfifo_rd_ptr <= 0;
            io_wfifo_count <= 0;
            wb_wfifo_wr_ptr <= 0;
            wb_wfifo_rd_ptr <= 0;
            wb_wfifo_count <= 0;
            wb_pending_valid <= 0;
            wb_pending_addr <= 0;
            wb_pending_data <= 0;
        end else begin
            // IO写入队
            if (io_fifo_push) begin
                io_wfifo_addr[io_wfifo_wr_ptr] <= cpu_addr;
                io_wfifo_data[io_wfifo_wr_ptr] <= cpu_wdata;
                io_wfifo_strb[io_wfifo_wr_ptr] <= cpu_wen;
                io_wfifo_wr_ptr <= io_wfifo_wr_ptr + 1'b1;
            end

            if (io_fifo_pop) begin
                io_wfifo_rd_ptr <= io_wfifo_rd_ptr + 1'b1;
            end

            case ({io_fifo_push, io_fifo_pop})
                2'b10: io_wfifo_count <= io_wfifo_count + 1'b1;
                2'b01: io_wfifo_count <= io_wfifo_count - 1'b1;
                default: io_wfifo_count <= io_wfifo_count;
            endcase

            // 写回入队：优先把pending请求补入队
            if (wb_fifo_push_pending) begin
                wb_wfifo_addr[wb_wfifo_wr_ptr] <= wb_pending_addr;
                wb_wfifo_data[wb_wfifo_wr_ptr] <= wb_pending_data;
                wb_wfifo_wr_ptr <= wb_wfifo_wr_ptr + 1'b1;
                wb_pending_valid <= 1'b0;
            end else if (wb_fifo_push_new) begin
                wb_wfifo_addr[wb_wfifo_wr_ptr] <= write_back_addr;
                wb_wfifo_data[wb_wfifo_wr_ptr] <= write_back_data;
                wb_wfifo_wr_ptr <= wb_wfifo_wr_ptr + 1'b1;
            end

            // 仅在pending槽为空时才接收新的“满FIFO写回请求”到pending，避免覆盖
            if (!wb_pending_valid && write_back_req && wb_wfifo_full) begin
                wb_pending_valid <= 1'b1;
                wb_pending_addr <= write_back_addr;
                wb_pending_data <= write_back_data;
            end

            // 写响应完成后出队（按当前正在发送的请求类型）
            if (wb_fifo_pop) begin
                    wb_wfifo_rd_ptr <= wb_wfifo_rd_ptr + 1'b1;
            end

            case ({(wb_fifo_push_pending || wb_fifo_push_new), wb_fifo_pop})
                2'b10: wb_wfifo_count <= wb_wfifo_count + 1'b1;
                2'b01: wb_wfifo_count <= wb_wfifo_count - 1'b1;
                default: wb_wfifo_count <= wb_wfifo_count;
            endcase
        end
    end

    // 写状态机与在途请求锁存
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state <= W_IDLE;
            w_sel_io <= 1'b0;
            w_req_addr <= 32'b0;
            w_req_data <= 256'b0;
            w_req_strb <= 4'b0;
            w_req_len <= 8'b0;
            w_beat_cnt <= 8'b0;
        end else begin
            w_state <= w_state_next;

            // 从空闲进入发送时，选取下一条请求（IO优先）
            if (w_state == W_IDLE && w_state_next == W_SEND) begin
                if (w_pick_io) begin
                    w_sel_io <= 1'b1;
                    w_req_addr <= io_wfifo_addr[io_wfifo_rd_ptr];
                    w_req_data <= {8{io_wfifo_data[io_wfifo_rd_ptr]}};
                    w_req_strb <= io_wfifo_strb[io_wfifo_rd_ptr];
                    w_req_len <= 8'd0;
                    w_beat_cnt <= 8'd0;
                end else begin
                    w_sel_io <= 1'b0;
                    w_req_addr <= wb_wfifo_addr[wb_wfifo_rd_ptr];
                    w_req_data <= wb_wfifo_data[wb_wfifo_rd_ptr];
                    w_req_strb <= 4'hF;
                    w_req_len <= 8'd7;
                    w_beat_cnt <= 8'd0;
                end
            end else if (w_state == W_WAIT && w_data_hs) begin
                if (w_beat_cnt < w_req_len) begin
                    w_beat_cnt <= w_beat_cnt + 1'b1;
                end
            end
        end
    end

    //读请求状态机实现
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= R_IDLE;
        end else begin
            r_state <= r_state_next;
        end
    end
    always @ (*) begin
        case (r_state)
            R_IDLE: begin
                if (pending_refill) begin
                    r_state_next = R_SEND;
                end else if (pending_io_read) begin
                    r_state_next = R_SEND;
                end else begin
                    r_state_next = R_IDLE;
                end
            end
            R_SEND: begin
                if (axi_arvalid && axi_arready) begin
                    r_state_next = R_WAIT;
                end else begin
                    r_state_next = R_SEND;
                end
            end
            R_WAIT: begin
                if (axi_rvalid && axi_rlast) begin
                    r_state_next = R_IDLE;
                end else if (axi_rvalid) begin
                    r_state_next = R_RECV;
                end else begin
                    r_state_next = R_WAIT;
                end
            end
            R_RECV: begin
                if (axi_rvalid && axi_rlast) begin
                    r_state_next = R_IDLE;
                end else begin
                    r_state_next = R_RECV;
                end
            end
        endcase
    end

    // 写请求状态机实现
    always @(*) begin
        case (w_state)
            W_IDLE: begin
                if (w_req_available) begin
                    w_state_next = W_SEND;
                end else begin
                    w_state_next = W_IDLE;
                end
            end
            W_SEND: begin
                if (axi_awvalid && axi_awready) begin
                    w_state_next = W_WAIT;
                end else begin
                    w_state_next = W_SEND;
                end
            end
            W_WAIT: begin
                if (w_data_last_hs) begin
                    w_state_next = W_RESP;
                end else begin
                    w_state_next = W_WAIT;
                end
            end
            W_RESP: begin
                if (w_resp_hs) begin
                    w_state_next = W_IDLE;
                end else begin
                    w_state_next = W_RESP;
                end
            end
            default: w_state_next = W_IDLE;
        endcase
    end

    // 写AXI通道控制
    always @(*) begin
        case (w_state)
            W_IDLE: begin
                axi_awvalid = 1'b0;
                axi_awaddr = 32'b0;
                axi_awlen = 8'b0;
                axi_awsize = 3'b0;
                axi_wid = 4'b0010;
                axi_wdata = 32'b0;
                axi_wstrb = 4'b0;
                axi_wlast = 1'b0;
                axi_wvalid = 1'b0;
                axi_bready = 1'b0;
            end
            W_SEND: begin
                axi_awvalid = 1'b1;
                axi_awaddr = w_req_addr;
                axi_awlen = w_req_len;
                axi_awsize = 3'd2; // 32-bit
                axi_wid = 4'b0010;
                axi_wdata = 32'b0;
                axi_wstrb = 4'b0;
                axi_wlast = 1'b0;
                axi_wvalid = 1'b0;
                axi_bready = 1'b0;
            end
            W_WAIT: begin
                axi_awvalid = 1'b0;
                axi_awaddr = 32'b0;
                axi_awlen = 8'b0;
                axi_awsize = 3'b0;
                axi_wid = 4'b0010;
                axi_wdata = w_req_data[w_beat_cnt*32 +: 32];
                axi_wstrb = w_sel_io ? w_req_strb : 4'hF;
                axi_wlast = (w_beat_cnt == w_req_len);
                axi_wvalid = 1'b1;
                axi_bready = 1'b0;
            end
            W_RESP: begin
                axi_awvalid = 1'b0;
                axi_awaddr = 32'b0;
                axi_awlen = 8'b0;
                axi_awsize = 3'b0;
                axi_wid = 4'b0010;
                axi_wdata = 32'b0;
                axi_wstrb = 4'b0;
                axi_wlast = 1'b0;
                axi_wvalid = 1'b0;
                axi_bready = 1'b1;
            end
            default: begin
                axi_awvalid = 1'b0;
                axi_awaddr = 32'b0;
                axi_awlen = 8'b0;
                axi_awsize = 3'b0;
                axi_wid = 4'b0010;
                axi_wdata = 32'b0;
                axi_wstrb = 4'b0;
                axi_wlast = 1'b0;
                axi_wvalid = 1'b0;
                axi_bready = 1'b0;
            end
        endcase
    end
    always @ (*) begin
        case (r_state)
            R_IDLE: begin
                axi_arvalid = 0;
                axi_araddr = 0;
                axi_arlen = 0;
                axi_arsize = 0;
                axi_rready = 0;
            end
            R_SEND: begin
                axi_arvalid = 1;
                axi_araddr = pending_refill ? pending_refill_addr : pending_io_addr;
                axi_arlen = pending_refill ? 7 : 0; // 如果是refill请求则长度为8个数据，否则为1个数据
                axi_arsize = 2; // 固定数据大小为32位
                axi_rready = 0;
            end
            R_WAIT: begin
                axi_arvalid = 0;
                axi_araddr = 0;
                axi_arlen = 0;
                axi_arsize = 0;
                axi_rready = 1; // 等待读数据时保持rready为1
            end
            R_RECV: begin
                axi_arvalid = 0;
                axi_araddr = 0;
                axi_arlen = 0;
                axi_arsize = 0;
                axi_rready = 1; // 接收数据时保持rready为1
            end
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refill_data <= 0;
            refill_valid <= 0;
        end else begin
            case (r_state)
                R_WAIT: begin
                    refill_data <= 0;
                    refill_valid <= 0;
                end
                R_RECV: begin
                    if (axi_rvalid && r_req_is_refill) begin
                        refill_data <= {axi_rdata, refill_data[255:32]}; // 累积接收数据
                        if (axi_rlast) begin
                            refill_valid <= 1; // 最后一个数据到达时标记有效
                        end else begin
                            refill_valid <= 0;
                        end
                    end else begin
                        refill_valid <= 0;
                        refill_data <= refill_data; // 保持当前数据
                    end  
                end
                default: begin
                    refill_data <= 0;
                    refill_valid <= 0;
                end
            endcase
        end
    end
    assign cpu_rdata = dram_rvalid ? dram_rdata : axi_rdata; // 如果是refill请求则返回dram数据，否则返回IO数据
    assign cpu_rvalid = dram_rvalid || (axi_rvalid && !r_req_is_refill); // IO读数据返回时拉高有效


endmodule