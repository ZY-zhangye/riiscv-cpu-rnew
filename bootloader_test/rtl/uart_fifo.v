// -------------------------------------------------------------
// UART FIFO模块
// 8位宽度，深度可配置，支持写入、读出、空满标志
// -------------------------------------------------------------
module uart_fifo #(
    parameter DEPTH = 16 // FIFO深度
)(
    input wire clk,
    input wire rst_n,
    input wire [7:0] data_in,
    input wire data_valid_in,
    input wire read_en,
    output reg [7:0] data_out,
    output reg empty,
    output reg full
);

    // 存储器
    reg [7:0] fifo_mem [0:DEPTH-1];
    reg [$clog2(DEPTH)-1:0] wr_ptr; // 写指针
    reg [$clog2(DEPTH)-1:0] rd_ptr; // 读指针
    reg [$clog2(DEPTH):0] cnt;      // 计数器

    // 写入操作
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (data_valid_in && !full) begin
            fifo_mem[wr_ptr] <= data_in;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // 读出操作
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            data_out <= 8'd0;
        end else if (read_en && !empty) begin
            data_out <= fifo_mem[rd_ptr];
            fifo_mem[rd_ptr] <= 8'd0; // 读出后清除数据
            rd_ptr <= rd_ptr + 1;
        end
    end

    // 计数器管理
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
        end else begin
            case ({data_valid_in && !full, read_en && !empty})
                2'b10: if (cnt < DEPTH) cnt <= cnt + 1; // 只写
                2'b01: if (cnt > 0) cnt <= cnt - 1; // 只读且cnt>0才递减
                2'b11: cnt <= cnt;     // 读写同时
                default: cnt <= cnt;   // 无操作
            endcase
        end
    end

    // 空满标志
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            empty <= 1'b1;
            full  <= 1'b0;
        end else begin
            empty <= (cnt == 0);
            full  <= (cnt == DEPTH);
        end
    end

endmodule
