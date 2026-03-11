`define MEM_HEX_PATH "C:\\Users\\ZY\\Desktop\\riscv-cpu-axi-test\\hex\\riscv-tests\\rv32ui-p-add.hex"
// 加载内存文件
/*# 定义【标准整数运算指令集】数组 - RV32I 基础指令全集
UI_INSTS=(sw lw add addi sub and andi or ori xor xori 
          sll srl sra slli srli srai slt slti sltu sltiu 
          beq bne blt bge bltu bgeu jal jalr lui auipc lh lhu sh sb lb lbu)
# 定义【特殊系统指令集】数组 - 包含特权指令/系统调用指令
MI_INSTS=(csr scall sbreak ma_fetch)*/
//乘法指令
// UM_INSTS=(mul mulh mulhu mulhsu)

module tb_top;
reg clk;
reg rst_n;
wire [31:0] debug_wb_pc;
wire debug_wb_rf_wen;
wire [4:0] debug_wb_rf_wnum;
wire [31:0] debug_wb_rf_wdata;
wire [31:0] debug_data;
wire [3:0] led;
wire [31:0] imem_addr;

// AXI-Lite总线
wire [31:0] axi_araddr;
wire        axi_arvalid;
reg         axi_arready;
reg  [31:0] axi_rdata;
reg  [1:0]  axi_rresp;
reg         axi_rvalid;
wire        axi_rready;
wire [31:0] axi_awaddr;
wire        axi_awvalid;
reg         axi_awready;
wire [31:0] axi_wdata;
wire [3:0]  axi_wstrb;
wire        axi_wvalid;
reg         axi_wready;
reg  [1:0]  axi_bresp;
reg         axi_bvalid;
wire        axi_bready;

reg [31:0] mem [0:3000];
reg [31:0] read_data_hold;
reg        read_pending;

my_cpu  #(
    .MEM_HEX_PATH(`MEM_HEX_PATH)
) u_my_cpu(
    .clk(clk),
    .rst_n(rst_n),
    .debug_inst_pc(imem_addr),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_wen(debug_wb_rf_wen),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .debug_data(debug_data),
    .axi_araddr(axi_araddr),
    .axi_arvalid(axi_arvalid),
    .axi_arready(axi_arready),
    .axi_rdata(axi_rdata),
    .axi_rresp(axi_rresp),
    .axi_rvalid(axi_rvalid),
    .axi_rready(axi_rready),
    .axi_awaddr(axi_awaddr),
    .axi_awvalid(axi_awvalid),
    .axi_awready(axi_awready),
    .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb),
    .axi_wvalid(axi_wvalid),
    .axi_wready(axi_wready),
    .axi_bresp(axi_bresp),
    .axi_bvalid(axi_bvalid),
    .axi_bready(axi_bready),
    .led(led)
);

initial begin
    $readmemh(`MEM_HEX_PATH, mem);
    $display("mem[2051]: %08h", mem[2051]);

    axi_arready = 1'b0;
    axi_rdata = 32'b0;
    axi_rresp = 2'b00;
    axi_rvalid = 1'b0;
    axi_awready = 1'b0;
    axi_wready = 1'b0;
    axi_bresp = 2'b00;
    axi_bvalid = 1'b0;
    read_data_hold = 32'b0;
    read_pending = 1'b0;
end

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        axi_arready <= 1'b0;
        axi_rvalid <= 1'b0;
        axi_rdata <= 32'b0;
        axi_rresp <= 2'b00;
        axi_awready <= 1'b0;
        axi_wready <= 1'b0;
        axi_bresp <= 2'b00;
        axi_bvalid <= 1'b0;
        read_pending <= 1'b0;
    end else begin
        // 默认ready随机回压
        axi_arready <= ($urandom_range(0, 99) < 80);
        axi_awready <= ($urandom_range(0, 99) < 85);
        axi_wready  <= ($urandom_range(0, 99) < 85);

        // 读地址握手后准备返回数据
        if (!read_pending && axi_arvalid && axi_arready) begin
            read_data_hold <= mem[axi_araddr[31:2]];
            read_pending <= 1'b1;
        end

        // 读数据通道
        if (axi_rvalid && axi_rready) begin
            axi_rvalid <= 1'b0;
        end else if (read_pending && !axi_rvalid) begin
            axi_rdata <= read_data_hold;
            axi_rresp <= 2'b00;
            axi_rvalid <= 1'b1;
            read_pending <= 1'b0;
        end

        // 写地址+数据同拍握手
        if (axi_awvalid && axi_awready && axi_wvalid && axi_wready) begin
            if (axi_wstrb[0]) mem[axi_awaddr[31:2]][7:0]   <= axi_wdata[7:0];
            if (axi_wstrb[1]) mem[axi_awaddr[31:2]][15:8]  <= axi_wdata[15:8];
            if (axi_wstrb[2]) mem[axi_awaddr[31:2]][23:16] <= axi_wdata[23:16];
            if (axi_wstrb[3]) mem[axi_awaddr[31:2]][31:24] <= axi_wdata[31:24];
            axi_bresp <= 2'b00;
            axi_bvalid <= 1'b1;
        end else if (axi_bvalid && axi_bready) begin
            axi_bvalid <= 1'b0;
        end
    end
end

initial begin
    clk = 0;
    rst_n = 0;
    #100 rst_n = 1;
end

always #5 clk = ~clk; // 100MHz

initial begin
    $display("Starting simulation...");
    $dumpfile("tb_top.vcd");    // 指定波形文件名
    $dumpvars(0, u_my_cpu);   // 0表示tb_top模块及其所有子模块
    #50000; // 设定最大结束时间，避免仿真无限进行
    $display("----------------------------------------------");
    $display("Simulation timeout.");
    $stop;
end

always @ (posedge clk) begin
    if (rst_n) begin
        $display("---------------------------------------------");
        $display("Time: %0t", $time);
        $display("debug_inst_pc: %h", imem_addr);
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