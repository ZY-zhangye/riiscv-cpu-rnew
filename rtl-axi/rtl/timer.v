`include "defines.v"
module timer(
    input wire clk,
    input wire rst_n,
    input wire [15:0] addr,
    input wire [31:0] wdata,
    input wire we,
    input wire re,
    output reg [31:0] rdata,
    output reg timer_int
);

reg [31:0] timer_load;
reg [31:0] timer_value;
reg [31:0] timer_ctrl;
reg [31:0] timer_intclr;
reg [31:0] timer_prescaler;
reg [31:0] prescaler_count;

wire timer_enable = timer_ctrl[0];
wire timer_int_enable = timer_ctrl[1];
wire timer_mode = timer_ctrl[2]; // 0: one-shot, 1: periodic
wire timer_reload = timer_ctrl[3]; // 0: no reload, 1: reload on timeout
wire timer_prescaler_enable = timer_ctrl[4]; // 0: no prescaler, 1: use prescaler

//分频逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prescaler_count <= 0;
    end else if (timer_prescaler_enable) begin
        if (prescaler_count >= timer_prescaler) begin
            prescaler_count <= 0;
        end else begin
            prescaler_count <= prescaler_count + 1;
        end
    end else begin
        prescaler_count <= 0;
    end
end
wire timer_tick = (prescaler_count == timer_prescaler) && timer_enable;
wire timer_clk = timer_prescaler_enable ? timer_tick : clk;

//定时器计数逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        timer_value <= 0;
    end else if (we && addr == `TIMER_LOAD) begin
        timer_value <= wdata; // 写入装载值
    end else if (timer_clk && timer_enable) begin
        if (timer_value > 0) begin
            timer_value <= timer_value - 1;
        end else if (timer_value == 0) begin
            if (timer_mode && timer_reload) begin
                timer_value <= timer_load; // 周期模式且需要重载，重新装载计数器
            end
        end
    end
end
//中断逻辑
reg [31:0] timer_value_reg;
always @ (posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    timer_value_reg <= 0;
  end else begin
    timer_value_reg <= timer_value;
  end
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        timer_int <= 0;
    end else if (timer_value == 0 && timer_enable && timer_value_reg == 1) begin
        if (timer_int_enable) begin
            timer_int <= 1; // 计数器到0且定时器使能，触发中断
        end
    end else if (we && addr == `TIMER_INTCLR) begin
        timer_int <= 0; // 写1清除中断
    end else if (we && addr == `TIMER_INTCLR) begin
        timer_int <= 0; // 修改控制寄存器时清除中断
    end
end
//寄存器读写逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        timer_load <= 0;
        timer_ctrl <= 0;
        timer_intclr <= 0;
        timer_prescaler <= 0;
    end else if (re) begin
        case (addr)
            `TIMER_LOAD: rdata = timer_load;
            `TIMER_VALUE: rdata = timer_value;
            `TIMER_CTRL: rdata = timer_ctrl;
            `TIMER_INTCLR: rdata = timer_intclr;
            `TIMER_PRESCALER: rdata = timer_prescaler;
            default: rdata = 0;
        endcase
    end else if (we) begin
        case (addr)
            `TIMER_LOAD: timer_load <= wdata;
            `TIMER_CTRL: timer_ctrl <= wdata;
            `TIMER_INTCLR: timer_intclr <= wdata; // 写1清除中断
            `TIMER_PRESCALER: timer_prescaler <= wdata;
        endcase
    end
end

endmodule
