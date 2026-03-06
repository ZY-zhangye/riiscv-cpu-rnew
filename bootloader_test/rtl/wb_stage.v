`include "defines.v"
module wb_stage (
    input wire clk,
    input wire rst_n,
    //握手信号
    input wire ms_to_ws_valid,
    output wire ws_allowin,
    //来自访存阶段的总线
    input wire [`MS_TO_WS_BUS_WD-1:0] mem_wb_bus,
    //写回寄存器堆的信号
    output wire rf_we,
    output wire [4:0] rf_waddr,
    output wire [31:0] rf_wdata,
    //调试接口
    output wire [31:0] debug_wb_pc
);

wire ws_ready_go = 1'b1; // WB 阶段无内部停顿，始终准备好
reg ws_valid;
assign ws_allowin = !ws_valid || ws_ready_go && ms_to_ws_valid;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ws_valid <= 1'b0;
    end else if (ws_allowin) begin
        ws_valid <= ms_to_ws_valid;
    end
end

// 从访存阶段传来的控制与数据信号
reg [`MS_TO_WS_BUS_WD-1:0] mem_wb_bus_r;
wire [31:0] wb_pc;
wire [31:0] wb_result;
wire [4:0] wb_dest;
wire wb_gr_we;
assign {wb_gr_we, wb_dest, wb_result, wb_pc} = mem_wb_bus_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_wb_bus_r <= 0;
    end else if (ws_allowin && ms_to_ws_valid) begin
        mem_wb_bus_r <= mem_wb_bus; // 正常传递控制与数据
    end
end

// 写回寄存器堆的信号
assign rf_we = ws_valid && wb_gr_we; // 写使能仅在WB阶段有效且需要写回时才有效
assign rf_waddr = wb_dest; // 写回寄存器地址
assign rf_wdata = wb_result; // 写回数据
assign debug_wb_pc = wb_pc;
endmodule