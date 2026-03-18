module data_ram #(
    parameter MEM_HEX_PATH = "C:\\Users\\ZY\\Desktop\\riiscv-cpu-rnew\\hex\\riscv-tests\\rv32ui-p-lui.hex"
)
 (
    input wire clk,
    input wire rst_n,
    //数据寄存器接口
    input wire data_ram_ren,
    input wire [31:0] data_ram_addr,
    output reg [31:0] data_ram_rdata,
    input wire [3:0] data_ram_wen,
    input wire [31:0] data_ram_wdata
);

reg [31:0] mem [0:3000];
integer i;
initial begin
    for (i = 0; i < 3001; i = i + 1) begin
        mem[i] = 32'b0; // 初始化内存为0
    end
    //$readmemh(MEM_HEX_PATH, mem);
end
always @ (posedge clk) begin
    if (|data_ram_wen) begin // 只要有一个写使能位被置位，就进行写操作
        if (data_ram_wen[0]) mem[data_ram_addr[23:2]][7:0] <= data_ram_wdata[7:0]; // 写入最低8位
        if (data_ram_wen[1]) mem[data_ram_addr[23:2]][15:8] <= data_ram_wdata[15:8]; // 写入次低8位
        if (data_ram_wen[2]) mem[data_ram_addr[23:2]][23:16] <= data_ram_wdata[23:16]; // 写入次高8位
        if (data_ram_wen[3]) mem[data_ram_addr[23:2]][31:24] <= data_ram_wdata[31:24]; // 写入最高8位
        $display("Data Write: Addr=%08h Data=%08h Strb=%04b", data_ram_addr, data_ram_wdata, data_ram_wen);
    end
end

always @ (posedge clk) begin
    if (data_ram_ren) begin
        if (|data_ram_wen) begin
            // 如果当前周期有写操作，并且地址匹配，则返回写入的数据（考虑写使能）
            data_ram_rdata <= {
                data_ram_wen[3] ? data_ram_wdata[31:24] : mem[data_ram_addr[23:2]][31:24],
                data_ram_wen[2] ? data_ram_wdata[23:16] : mem[data_ram_addr[23:2]][23:16],
                data_ram_wen[1] ? data_ram_wdata[15:8]  : mem[data_ram_addr[23:2]][15:8],
                data_ram_wen[0] ? data_ram_wdata[7:0]   : mem[data_ram_addr[23:2]][7:0]
            };
        end else begin
            data_ram_rdata <= mem[data_ram_addr[23:2]]; // 按字对齐访问
        end
        $display("Data Read: Addr=%08h Data=%08h", data_ram_addr, mem[data_ram_addr[23:2]]);
    end else begin
        data_ram_rdata <= 32'b0; // 不读时输出0
    end
end
endmodule