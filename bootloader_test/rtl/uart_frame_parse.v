// -------------------------------------------------------------
// UART帧解析模块
// 1. 读FIFO内容需延迟1周期采样
// 2. 只有发出读请求fifo_data才有效
// 3. 读请求与状态机分离
// -------------------------------------------------------------
module uart_frame_parse(
    input wire clk,
    input wire rst_n,
    input wire [7:0] fifo_data,
    input wire fifo_empty,
    input wire fifo_full,
    output reg fifo_read_en,
    output reg [7:0] type_out,
    output reg [15:0] addr_out,
    output reg [31:0] data_out,
    output reg frame_valid
);

    localparam SOF = 8'hA5; // 帧起始标志
    localparam EOF = 8'h5A; // 帧结束标志

    // ---------------------------------------------------------
    // 读FIFO状态机（独立于解析逻辑）
    // 约束：一次读操作后，必须空一个时钟周期再发起下一次读
    // read_req由解析状态机提出，rd_data_valid在读出后1个周期给解析机使用
    // ---------------------------------------------------------
    localparam RD_IDLE = 2'd0;
    localparam RD_READ = 2'd1;
    localparam RD_WAIT = 2'd2; // 空1拍并在此拍抓取数据

    reg [1:0] rd_state;
    reg [7:0] rd_data_buf;
    reg rd_data_valid;
    reg read_req;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            fifo_read_en  <= 1'b0;
            rd_data_buf   <= 8'd0;
            rd_data_valid <= 1'b0;
        end else begin
            rd_data_valid <= 1'b0; // 默认拉低
            case (rd_state)
                RD_IDLE: begin
                    fifo_read_en <= 1'b0;
                    if (read_req && !fifo_empty) begin
                        fifo_read_en <= 1'b1; // 发起读请求
                        rd_state <= RD_READ;
                    end
                end
                RD_READ: begin
                    // 本拍拉高read_en，FIFO在此拍更新data_out
                    fifo_read_en <= 1'b0;
                    rd_state <= RD_WAIT; // 留出一个空拍
                end
                RD_WAIT: begin
                    // 空一个周期，并采样上拍FIFO输出的数据
                    fifo_read_en  <= 1'b0;
                    rd_data_buf   <= fifo_data;
                    rd_data_valid <= 1'b1; // 告知解析状态机数据有效
                    rd_state      <= RD_IDLE;
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------
    // 帧解析状态机
    // 帧格式：SOF | type(1B) | addr(2B，高字节在前) | data(4B，高字节在前) | EOF
    // ---------------------------------------------------------
    localparam P_WAIT_SOF = 4'd0;
    localparam P_TYPE     = 4'd1;
    localparam P_ADDR_H   = 4'd2;
    localparam P_ADDR_L   = 4'd3;
    localparam P_DATA3    = 4'd4;
    localparam P_DATA2    = 4'd5;
    localparam P_DATA1    = 4'd6;
    localparam P_DATA0    = 4'd7;
    localparam P_EOF      = 4'd8;

    reg [3:0] p_state;

    // 解析状态机：负责提出read_req并根据rd_data_valid推进
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_state    <= P_WAIT_SOF;
            read_req   <= 1'b0;
            type_out   <= 8'd0;
            addr_out   <= 16'd0;
            data_out   <= 32'd0;
            frame_valid<= 1'b0;
        end else begin
            // 默认信号
            frame_valid <= 1'b0;
            read_req    <= 1'b0;

            case (p_state)
                P_WAIT_SOF: begin
                    // 持续尝试取数据，直到拿到SOF
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        if (rd_data_buf == SOF) begin
                            p_state <= P_TYPE;
                        end else begin
                            p_state <= P_WAIT_SOF; // 丢弃，继续找SOF
                        end
                    end
                end

                P_TYPE: begin
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        type_out <= rd_data_buf;
                        p_state  <= P_ADDR_H;
                    end
                end

                P_ADDR_H: begin
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        addr_out[15:8] <= rd_data_buf;
                        p_state <= P_ADDR_L;
                    end
                end

                P_ADDR_L: begin
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        addr_out[7:0] <= rd_data_buf;
                        p_state <= P_DATA3;
                    end
                end

                P_DATA3: begin
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        data_out[31:24] <= rd_data_buf;
                        p_state <= P_DATA2;
                    end
                end

                P_DATA2: begin
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        data_out[23:16] <= rd_data_buf;
                        p_state <= P_DATA1;
                    end
                end

                P_DATA1: begin
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        data_out[15:8] <= rd_data_buf;
                        p_state <= P_DATA0;
                    end
                end

                P_DATA0: begin
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        data_out[7:0] <= rd_data_buf;
                        p_state <= P_EOF;
                    end
                end

                P_EOF: begin
                    if (rd_state == RD_IDLE && !fifo_empty) read_req <= 1'b1;
                    if (rd_data_valid) begin
                        if (rd_data_buf == EOF) begin
                            frame_valid <= 1'b1;
                        end
                        // 无论EOF对错，都回到等待SOF（可根据需要选择重试）
                        p_state <= P_WAIT_SOF;
                    end
                end

                default: p_state <= P_WAIT_SOF;
            endcase
        end
    end


endmodule
