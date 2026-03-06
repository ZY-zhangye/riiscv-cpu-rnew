
// -------------------------------------------------------------
// UART串口接收模块
// 可配置时钟频率和波特率，支持1位起始位、8位数据位、1位停止位
// 接收完成后输出数据并拉高data_valid一个周期
// -------------------------------------------------------------
module uart(
    input wire clk,                // 时钟输入
    input wire rst_n,              // 复位信号，低有效
    input wire baud_tick,          // 统一的波特率时钟使能脉冲
    input wire rx,                 // UART串口输入
    output reg [7:0] data_out,     // 并行数据输出
    output reg data_valid          // 数据有效信号，拉高一个周期
);


    // -----------------------------
    // UART接收状态机
    // -----------------------------
    // S_IDLE : 等待起始位
    // S_START: 检测起始位中点
    // S_DATA : 采集8位数据
    // S_STOP : 检测停止位
    // S_DONE : 数据输出并拉高data_valid
    localparam S_IDLE  = 3'd0;
    localparam S_START = 3'd1;
    localparam S_DATA  = 3'd2;
    localparam S_STOP  = 3'd3;
    localparam S_DONE  = 3'd4;

    reg [2:0] state;         // 状态机当前状态
    reg [2:0] bit_idx;       // 数据位计数器
    reg [7:0] data_buf;      // 接收数据缓存
    reg rx_sync0, rx_sync1;  // 输入信号双同步，防止亚稳态

    // 双同步：将异步rx信号同步到clk域，防止亚稳态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
        end
    end

    // 主状态机：按UART协议采样接收数据
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            bit_idx <= 0;
            data_buf <= 8'd0;
            data_out <= 8'd0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0; // 默认拉低
            case (state)
                S_IDLE: begin
                    // 等待起始位（rx为低）
                    if (~rx_sync1)
                        state <= S_START;
                end
                S_START: begin
                    // 起始位中点采样，确认起始位有效
                    if (baud_tick) begin
                        if (~rx_sync1) begin
                            state <= S_DATA;
                            bit_idx <= 0;
                        end else begin
                            state <= S_IDLE; // 起始位丢失，返回空闲
                        end
                    end
                end
                S_DATA: begin
                    // 采集8位数据，低位先收
                    if (baud_tick) begin
                        data_buf[bit_idx] <= rx_sync1;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end
                S_STOP: begin
                    // 检查停止位（应为高）
                    if (baud_tick) begin
                        if (rx_sync1) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_IDLE; // 停止位错误，丢弃数据
                        end
                    end
                end
                S_DONE: begin
                    // 数据输出，并拉高data_valid一个周期
                    data_out <= data_buf;
                    data_valid <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule