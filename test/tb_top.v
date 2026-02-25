module tb_top;
reg clk;
reg rst_n;
wire [31:0] debug_wb_pc;
wire debug_wb_rf_wen;
wire [4:0] debug_wb_rf_wnum;
wire [31:0] debug_wb_rf_wdata;
wire [31:0] debug_data;
wire [3:0] led;

my_cpu u_my_cpu(
    .clk(clk),
    .rst_n(rst_n),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .debug_data(debug_data),
    .led(led)
);

initial begin
    clk = 0;
    rst_n = 0;
    #100 rst_n = 1;
end

always #5 clk = ~clk; // 100MHz

initial begin
    $display("Starting simulation...");
    $dumpfile("tb_top.vcd");    // 指定波形文件名
    $dumpvars(0, tb_top);   // 0表示tb_top模块及其所有子模块
    #25000; // 设定最大结束时间，避免仿真无限进行
    $display("----------------------------------------------");
    $display("Simulation timeout.");
    $stop;
end

always @ (posedge clk) begin
    if (rst_n) begin
        $display("---------------------------------------------");
        $display("Time: %0t", $time);
        $display("debug_wb_pc: %h", debug_wb_pc);
        $display("debug_wb_rf_wen: %b", debug_wb_rf_wen);
        $display("debug_wb_rf_wnum: %h", debug_wb_rf_wnum);
        $display("debug_wb_rf_wdata: %h", debug_wb_rf_wdata);
        $display("debug_data: %h", debug_data);
    end
end

always @ (posedge clk) begin
    if (rst_n) begin
        if (debug_wb_pc == 32'h00000044) begin
                $display("---------------------------------------------");
                $display("Time: %0t", $time);
                $display("Simulation finished.");
                $display("----------------------------------------------");
            if (debug_data == 32'h00000001) begin
                $display("Test passed.");
            end else begin
                $display("Test failed. Expected 1 in x10, got %08h", debug_data);
            end
            $display("----------------------------------------------");
            $stop;
        end
    end
end
endmodule