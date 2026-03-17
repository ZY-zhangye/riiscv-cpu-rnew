`include "../defines.v"

module UART (
    input wire clk,
    input wire rst_n,
    input wire clk_uart, // UART时钟  115200Hz
    input wire [15:0] addr, // 地址总线
    input wire [31:0] wdata, // 写数据总线
    input wire we, // 写使能
    input wire re, // 读使能
    output reg [31:0] rdata, // 读数据总线
    output reg tx, // UART发送线
    input wire rx, // UART接收线
    output reg tx_int, // 发送中断信号
    output reg rx_int // 接收中断信号
);

// 8 字节收发 FIFO，接口侧按字访问，但实际只使用最低 8 位有效数据。
localparam FIFO_DEPTH = 4'd8;

// 发送状态机：空闲 -> 起始位 -> 8 位数据 -> 停止位。
localparam TX_IDLE  = 2'd0;
localparam TX_START = 2'd1;
localparam TX_DATA  = 2'd2;
localparam TX_STOP  = 2'd3;

// 接收状态机：检测起始位 -> 接收 8 位数据 -> 校验停止位。
localparam RX_IDLE  = 2'd0;
localparam RX_START = 2'd1;
localparam RX_DATA  = 2'd2;
localparam RX_STOP  = 2'd3;

// 内部寄存器镜像：DATA 用于最近一次读写字节，STATUS 为组合信号。
reg [31:0] uart_data;
wire [31:0] uart_status;
reg [31:0] uart_ctrl;
reg [31:0] uart_baud;

// STATUS 寄存器字段。
reg tx_empty;
reg rx_ready;
reg tx_full;
reg rx_full;
wire parity_error;
reg overflow_error;

wire rx_int_en;
wire tx_int_en;
wire uart_en;
wire uart_rst;
wire boundary_on;

// 波特率分频计数器，仅在 boundary_on=1 时生效。
reg [31:0] baud_cnt;
wire baud_tick;

// 异步输入同步到 clk 域，避免直接采样产生亚稳态。
reg clk_uart_sync0;
reg clk_uart_sync1;
reg clk_uart_sync2;
reg rx_sync0;
reg rx_sync1;
reg rx_sync2;

reg [7:0] tx_buffer [0:7];
reg [7:0] rx_buffer [0:7];
reg [2:0] tx_head;
reg [2:0] tx_tail;
reg [2:0] rx_head;
reg [2:0] rx_tail;
// 计数器使用 4 位，便于表达 0 到 8 的满深度。
reg [3:0] tx_count;
reg [3:0] rx_count;

// 串口收发过程中的位计数与移位寄存器。
reg [1:0] tx_state;
reg [1:0] rx_state;
reg [2:0] tx_bit_idx;
reg [2:0] rx_bit_idx;
reg [7:0] tx_shift;
reg [7:0] rx_shift;

wire clk_uart_tick;
wire uart_tick;
wire rx_falling;

wire write_data_req;
wire write_status_req;
wire write_ctrl_req;
wire write_baud_req;
wire read_data_req;
wire soft_reset_req;
wire tx_push;
wire tx_pop;
wire rx_pop;
wire rx_push;

// 暂未实现奇偶校验，相关状态位固定为 0。
assign parity_error = 1'b0;
// CTRL[4:0] = {boundary_on, uart_rst, uart_en, tx_int_en, rx_int_en}。
assign {boundary_on, uart_rst, uart_en, tx_int_en, rx_int_en} = uart_ctrl[4:0];
// STATUS 仅低位有效，其余位清零。
assign uart_status = {24'b0, rx_int, tx_int, overflow_error, parity_error, rx_full, tx_full, rx_ready, tx_empty};

// uart_tick 是整个模块收发状态机前进的统一节拍。
// boundary_on=1 时使用内部分频；否则把外部 clk_uart 当作单周期脉冲源。
assign baud_tick = boundary_on && uart_en && (baud_cnt == uart_baud);
assign clk_uart_tick = clk_uart_sync1 && !clk_uart_sync2;
assign uart_tick = boundary_on ? baud_tick : (clk_uart_tick && uart_en);
// RX 下降沿用于发现起始位。
assign rx_falling = rx_sync2 && !rx_sync1;

// 寄存器访问译码。
assign write_data_req = we && (addr == `UART_RT_DATA);
assign write_status_req = we && (addr == `UART_RT_STATUS);
assign write_ctrl_req = we && (addr == `UART_RT_CTRL);
assign write_baud_req = we && (addr == `UART_RT_BAUD);
assign read_data_req = re && (addr == `UART_RT_DATA);
// CTRL 写入时，uart_rst 作为软件复位脉冲使用，只在本次写入周期生效。
assign soft_reset_req = write_ctrl_req && wdata[3];

// FIFO 出入队条件。
assign tx_push = uart_en && write_data_req && (tx_count < FIFO_DEPTH);
assign tx_pop = uart_en && uart_tick && (tx_state == TX_IDLE) && (tx_count != 0);
assign rx_pop = uart_en && read_data_req && (rx_count != 0);
// RX_STOP 且停止位为高时，说明收到一个完整字节。
assign rx_push = uart_en && uart_tick && (rx_state == RX_STOP) && rx_sync1;

// 时钟同步与分频逻辑。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        baud_cnt <= 32'd0;
        clk_uart_sync0 <= 1'b0;
        clk_uart_sync1 <= 1'b0;
        clk_uart_sync2 <= 1'b0;
        rx_sync0 <= 1'b1;
        rx_sync1 <= 1'b1;
        rx_sync2 <= 1'b1;
    end else begin
        clk_uart_sync0 <= clk_uart;
        clk_uart_sync1 <= clk_uart_sync0;
        clk_uart_sync2 <= clk_uart_sync1;

        rx_sync0 <= rx;
        rx_sync1 <= rx_sync0;
        rx_sync2 <= rx_sync1;

        // UART 关闭、切回外部节拍或软复位时，分频计数器清零。
        if (!uart_en || !boundary_on || soft_reset_req) begin
            baud_cnt <= 32'd0;
        end else if (baud_cnt >= uart_baud) begin
            baud_cnt <= 32'd0;
        end else begin
            baud_cnt <= baud_cnt + 32'd1;
        end
    end
end

// 读寄存器为组合逻辑，读 DATA 时返回当前 RX FIFO 头部字节。
always @(*) begin
    if (!re) begin
        rdata = 32'b0;
    end else begin
        case (addr)
            `UART_RT_DATA: begin
                if (rx_count != 0) begin
                    rdata = {24'b0, rx_buffer[rx_head]};
                end else begin
                    rdata = 32'b0;
                end
            end
            `UART_RT_STATUS: rdata = uart_status;
            `UART_RT_CTRL: rdata = uart_ctrl;
            `UART_RT_BAUD: rdata = uart_baud;
            default: rdata = 32'b0;
        endcase
    end
end

// 主时序逻辑：维护寄存器、FIFO、TX/RX 状态机和中断状态。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_data <= 32'd0;
        uart_ctrl <= 32'd0;
        uart_baud <= 32'd868;
        tx <= 1'b1;
        tx_int <= 1'b0;
        rx_int <= 1'b0;
        tx_empty <= 1'b1;
        rx_ready <= 1'b0;
        tx_full <= 1'b0;
        rx_full <= 1'b0;
        overflow_error <= 1'b0;
        tx_head <= 3'd0;
        tx_tail <= 3'd0;
        rx_head <= 3'd0;
        rx_tail <= 3'd0;
        tx_count <= 4'd0;
        rx_count <= 4'd0;
        tx_state <= TX_IDLE;
        rx_state <= RX_IDLE;
        tx_bit_idx <= 3'd0;
        rx_bit_idx <= 3'd0;
        tx_shift <= 8'd0;
        rx_shift <= 8'd0;
    end else begin
        if (write_ctrl_req) begin
            uart_ctrl <= {wdata[31:4], 1'b0, wdata[2:0]};
        end

        // BAUD 保存分频阈值；在默认 100MHz 时，868 约对应 115200 波特率。
        if (write_baud_req) begin
            uart_baud <= wdata;
        end

        // 允许软件写 STATUS 清除溢出标志。
        if (write_status_req && wdata[5]) begin
            overflow_error <= 1'b0;
        end

        // 软件复位只清内部状态，不改 CTRL/BAUD 配置寄存器。
        if (soft_reset_req) begin
            uart_data <= 32'd0;
            tx <= 1'b1;
            overflow_error <= 1'b0;
            tx_head <= 3'd0;
            tx_tail <= 3'd0;
            rx_head <= 3'd0;
            rx_tail <= 3'd0;
            tx_count <= 4'd0;
            rx_count <= 4'd0;
            tx_state <= TX_IDLE;
            rx_state <= RX_IDLE;
            tx_bit_idx <= 3'd0;
            rx_bit_idx <= 3'd0;
            tx_shift <= 8'd0;
            rx_shift <= 8'd0;
        end else begin
            if (write_data_req) begin
                uart_data <= {24'b0, wdata[7:0]};
                // 启用 UART 但 FIFO 已满时，记录一次溢出。
                if (!tx_push) begin
                    overflow_error <= overflow_error | uart_en;
                end
            end

            // CPU 写 DATA 时压入发送 FIFO。
            if (tx_push) begin
                tx_buffer[tx_tail] <= wdata[7:0];
                tx_tail <= tx_tail + 3'd1;
            end

            // 发送状态机在空闲且节拍到来时，从 FIFO 取出一个字节。
            if (tx_pop) begin
                tx_shift <= tx_buffer[tx_head];
                tx_head <= tx_head + 3'd1;
            end

            // 同一周期既 push 又 pop 时，计数保持不变。
            case ({tx_push, tx_pop})
                2'b10: tx_count <= tx_count + 4'd1;
                2'b01: tx_count <= tx_count - 4'd1;
                default: tx_count <= tx_count;
            endcase

            // TX 按标准 UART 时序依次输出起始位、数据位和停止位。
            case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1;
                    if (tx_pop) begin
                        tx_state <= TX_START;
                        tx_bit_idx <= 3'd0;
                        tx <= 1'b0;
                    end
                end
                TX_START: begin
                    if (uart_tick) begin
                        tx_state <= TX_DATA;
                        tx_bit_idx <= 3'd0;
                        tx <= tx_shift[0];
                    end
                end
                TX_DATA: begin
                    if (uart_tick) begin
                        if (tx_bit_idx == 3'd7) begin
                            tx_state <= TX_STOP;
                            tx <= 1'b1;
                        end else begin
                            tx_bit_idx <= tx_bit_idx + 3'd1;
                            tx <= tx_shift[tx_bit_idx + 3'd1];
                        end
                    end
                end
                TX_STOP: begin
                    if (uart_tick) begin
                        tx_state <= TX_IDLE;
                        tx <= 1'b1;
                    end
                end
                default: begin
                    tx_state <= TX_IDLE;
                    tx <= 1'b1;
                end
            endcase

            // 读 DATA 时弹出接收 FIFO 头部一个字节。
            if (read_data_req) begin
                if (rx_pop) begin
                    uart_data <= {24'b0, rx_buffer[rx_head]};
                    rx_head <= rx_head + 3'd1;
                end else begin
                    uart_data <= 32'd0;
                end
            end

            // 接收完成后写入 RX FIFO；如果已满则置溢出标志。
            if (rx_push && (rx_count < FIFO_DEPTH)) begin
                rx_buffer[rx_tail] <= rx_shift;
                rx_tail <= rx_tail + 3'd1;
            end else if (rx_push) begin
                overflow_error <= 1'b1;
            end

            case ({rx_push && (rx_count < FIFO_DEPTH), rx_pop})
                2'b10: rx_count <= rx_count + 4'd1;
                2'b01: rx_count <= rx_count - 4'd1;
                default: rx_count <= rx_count;
            endcase

            // RX 在检测到下降沿后开始按 uart_tick 采样 8 个数据位。
            case (rx_state)
                RX_IDLE: begin
                    if (rx_falling && uart_en) begin
                        rx_state <= RX_START;
                    end
                end
                RX_START: begin
                    if (uart_tick) begin
                        if (!rx_sync1) begin
                            rx_state <= RX_DATA;
                            rx_bit_idx <= 3'd0;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end
                end
                RX_DATA: begin
                    if (uart_tick) begin
                        rx_shift[rx_bit_idx] <= rx_sync1;
                        if (rx_bit_idx == 3'd7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_idx <= rx_bit_idx + 3'd1;
                        end
                    end
                end
                RX_STOP: begin
                    if (uart_tick) begin
                        rx_state <= RX_IDLE;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end

        // 组合状态在时钟沿更新成寄存器输出，便于软件轮询。
        tx_empty <= (tx_count == 0) && (tx_state == TX_IDLE);
        rx_ready <= (rx_count != 0);
        tx_full <= (tx_count == FIFO_DEPTH);
        rx_full <= (rx_count == FIFO_DEPTH);
        tx_int <= tx_int_en && ((tx_count == 0) && (tx_state == TX_IDLE));
        rx_int <= rx_int_en && (rx_count != 0);
    end
end

endmodule

