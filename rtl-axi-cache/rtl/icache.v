//icache.v 连接CPU的取指口和对外的AXI4完整接口，完成指令的缓存功能
module icache (
    input wire clk,
    input wire rst_n,
    // CPU接口
    input wire [31:0] cpu_addr,
    input wire cpu_ren,
    output reg [31:0] cpu_rdata,
    output reg cpu_rvalid,
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
    //读数据通道
    input wire [3:0] axi_rid,
    input wire [31:0] axi_rdata,
    input wire [1:0] axi_rresp,
    input wire axi_rlast,
    input wire axi_rvalid,
    output reg axi_rready
);

    wire refill_req;
    wire [31:0] refill_addr;
    reg [255:0] refill_data;
    reg refill_valid;
    // 实例化if_cache模块
    if_cache u_if_cache (
        .clk(clk),
        .rst_n(rst_n),
        .if_addr(cpu_addr),
        .if_ren(cpu_ren),
        .if_rdata(cpu_rdata),
        .if_rvalid(cpu_rvalid),
        .refill_req(refill_req),
        .refill_addr(refill_addr),
        .refill_data(refill_data),
        .refill_valid(refill_valid)
    );
    //采样if_cache的refill请求
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
    //AXI总线读数据通道状态机
    localparam AR_IDLE = 2'b00;
    localparam AR_SEND = 2'b01;
    localparam R_WAIT = 2'b10;
    localparam R_RECV = 2'b11;
    reg [1:0] ar_state, ar_state_next;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_state <= AR_IDLE;
        end else begin
            ar_state <= ar_state_next;
        end
    end
    always @ (*) begin
        case (ar_state)
            AR_IDLE:begin
                if (refill_req && !pending_refill) begin
                    ar_state_next = AR_SEND;
                end else begin
                    ar_state_next = AR_IDLE;
                end
            end
            AR_SEND:begin
                if (axi_arvalid && axi_arready) begin
                    ar_state_next = R_WAIT;
                end else begin
                    ar_state_next = AR_SEND;
                end
            end
            R_WAIT:begin
                if (axi_rvalid) begin
                    ar_state_next = R_RECV;
                end else begin
                    ar_state_next = R_WAIT;
                end
            end
            R_RECV:begin
                if (axi_rvalid && axi_rlast) begin
                    ar_state_next = AR_IDLE;
                end else begin
                    ar_state_next = R_RECV;
                end
            end
        endcase
    end
    //AR通道信号生成
    assign axi_arid = 4'b0000; // 固定ID
    assign axi_arburst = 2'b01; // INCR突发
    assign axi_arlock = 2'b00; // 非锁定
    assign axi_arcache = 4'b0011; // 内部可缓存
    assign axi_arprot = 3'b000; // 普通访问

    always @(*) begin
        case (ar_state)
            AR_IDLE: begin
                axi_arvalid = 1'b0;
                axi_araddr = 32'b0;
                axi_arlen = 8'b0;
                axi_arsize = 3'b0;
            end
            AR_SEND: begin
                axi_arvalid = 1'b1;
                axi_araddr = {pending_refill_addr[31:5], 5'b0}; // 32字节对齐
                axi_arlen = 8'd7; // 8个数据 beat
                axi_arsize = 3'b010; // 每个 beat 4字节
            end
            default: begin
                axi_arvalid = 1'b0;
                axi_araddr = 32'b0;
                axi_arlen = 8'b0;
                axi_arsize = 3'b0;
            end
        endcase
    end
    //R通道信号生成
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_rready <= 1'b0;
            refill_valid <= 1'b0;
            refill_data <= 256'b0;
        end else begin
            case (ar_state)
                R_WAIT: begin
                    axi_rready <= 1'b0;
                    refill_valid <= 1'b0;
                    refill_data <= 256'b0;
                end
                R_RECV: begin
                    axi_rready <= 1'b1;
                    if (axi_rvalid) begin
                        refill_data <= {axi_rdata, refill_data[255:32]}; // 先到数据放低位，后到数据逐步累积到高位
                        if (axi_rlast) begin
                            refill_valid <= 1'b1; // 最后一个数据到达时标记有效
                        end else begin
                            refill_valid <= 1'b0;
                        end
                    end else begin
                        refill_valid <= 1'b0;
                        refill_data <= refill_data; // 保持当前数据
                    end
                end
                default: begin
                    axi_rready <= 1'b0;
                    refill_valid <= 1'b0;
                    refill_data <= 256'b0;
                end
            endcase
        end
    end

endmodule