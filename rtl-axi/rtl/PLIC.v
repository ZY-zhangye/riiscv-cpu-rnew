`include "defines.v"
module PLIC (
    input wire clk,
    input wire rst_n,
    //来自CPU侧bridge的读写请求
    input wire [15:0] cpu_addr,
    input wire cpu_wen,
    input wire [31:0] cpu_wdata,
    input wire cpu_ren,
    output reg [31:0] cpu_rdata,
    //来自外设的中断请求
    input wire uart_rx_int,
    input wire uart_tx_int,
    input wire timer_int,
    //输出给CPU的中断信号
    output reg plic_int,
    //输出给CPU的中断号
    output reg [15:0] plic_int_id
);


reg [31:0] priority_reg [(`PLIC_PRIORITY_NUM/4)-1:0]; //优先级寄存器定义，以32位为单位存储，每个寄存器存储4个中断源的优先级
reg [15:0] pending_reg; //待处理寄存器定义，每位对应一个中断源
reg [15:0] enable_reg; //使能寄存器定义，每位对应一个中断源
reg [7:0] threshold_reg; //阈值寄存器定义
reg [15:0] claim_reg; //请求寄存器定义，存储当前正在处理的中断号，写该地址时表示完成中断处理
// 将所有中断源的电平信号打包为 16-bit 向量
// bit[0] 保留（ID=0不使用），bit[1]=UART_RX，bit[2]=UART_TX，bit[3]=TIMER，其余扩展时在此添加
wire [15:0] int_raw = {13'b0, timer_int, uart_tx_int, uart_rx_int};
// 通过 priority_reg 统一提取任意中断源 id 的优先级（id 范围 0~15）
// priority_reg 每个32位字存4个中断源的8位优先级，按 id/4 索引字，id%4 索引字节
function [7:0] get_priority;
    input [3:0] id;
    get_priority = priority_reg[id[3:2]][id[1:0]*8 +: 8];
endfunction

//中断优先级比较逻辑：遍历所有中断源，选出优先级最高且超过阈值的有效中断
integer i;
reg [7:0] max_priority;
reg [15:0] max_int_id;
reg found_valid;
reg [7:0] cur_priority;

always @(*) begin
    max_priority = 8'd0;
    max_int_id   = 16'd0;
    found_valid  = 1'b0;
    plic_int     = 1'b0;
    plic_int_id  = 16'd0;

    // 从 ID=0 开始遍历（ID=0 保留不使用）
    if (pending_reg == 16'b0 && int_raw != 16'b0) begin
        for (i = 0; i < `PLIC_PRIORITY_NUM; i = i + 1) begin
            cur_priority = get_priority(i[3:0]);
            $display("Checking int_id: %d, valid: %b, priority: %d", i, int_raw[i], cur_priority);
            // 有效 && 优先级超过全局阈值 && 严格大于当前最高优先级 → 更新
            if (int_raw[i] && (cur_priority > threshold_reg)
                    && (!found_valid || cur_priority > max_priority)) begin
                max_priority = cur_priority;
                max_int_id   = i[15:0];
                found_valid  = 1'b1;
            end
        end
    end else begin
        found_valid = 1'b0;
    end

    // 将比较结果输出到CPU
    if (found_valid) begin
        plic_int    = 1'b1;
        plic_int_id = max_int_id;
    end else begin
        plic_int    = 1'b0;
        plic_int_id = 16'd0;
    end
end

//CPU侧寄存器读写逻辑
integer j;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        //复位所有寄存器
        for (j = 0; j < (`PLIC_PRIORITY_NUM/4); j = j + 1) begin
            priority_reg[j] <= 0;
        end
        pending_reg <= 0;
        enable_reg <= 0;
        threshold_reg <= 0;
        claim_reg <= 0;
    end else begin
        if (cpu_ren) begin
            //读寄存器逻辑
            case (cpu_addr)
                `PLIC_PRIORITY_OFFSET + 16'h0000: cpu_rdata <= priority_reg[0];
                `PLIC_PRIORITY_OFFSET + 16'h0004: cpu_rdata <= priority_reg[1];
                `PLIC_PRIORITY_OFFSET + 16'h0008: cpu_rdata <= priority_reg[2];
                `PLIC_PRIORITY_OFFSET + 16'h000C: cpu_rdata <= priority_reg[3];
                `PLIC_PENDING_OFFSET: cpu_rdata <= {16'b0, pending_reg};
                `PLIC_ENABLE_OFFSET: cpu_rdata <= {16'b0, enable_reg};
                `PLIC_THRESHOLD_OFFSET: cpu_rdata <= {24'b0, threshold_reg};
                `PLIC_CLAIM_OFFSET: cpu_rdata <= {16'b0, claim_reg};
                default: cpu_rdata <= 32'b0; //未定义地址返回0
            endcase
        end 
        if (cpu_wen) begin
            //写寄存器逻辑
            case (cpu_addr)
                `PLIC_PRIORITY_OFFSET + 16'h0000: priority_reg[0] <= cpu_wdata;
                `PLIC_PRIORITY_OFFSET + 16'h0004: priority_reg[1] <= cpu_wdata;
                `PLIC_PRIORITY_OFFSET + 16'h0008: priority_reg[2] <= cpu_wdata;
                `PLIC_PRIORITY_OFFSET + 16'h000C: priority_reg[3] <= cpu_wdata;
                `PLIC_ENABLE_OFFSET: enable_reg <= cpu_wdata[15:0];
                `PLIC_THRESHOLD_OFFSET: threshold_reg <= cpu_wdata[7:0];
                `PLIC_CLAIM_OFFSET: claim_reg <= cpu_wdata[15:0]; //写该寄存器表示完成中断处理，清除对应pending位
                default: ; //未定义地址不执行任何操作
            endcase
        end
        //更新pending寄存器，根据外设中断信号更新对应位
        if (plic_int) begin
            pending_reg[plic_int_id] <= 1; //有新的中断请求，设置对应pending位
        end else if (cpu_wen && cpu_addr == `PLIC_CLAIM_OFFSET) begin
            pending_reg[claim_reg] <= 0; //完成中断处理，清除对应pending位
        end
    end
end

endmodule
