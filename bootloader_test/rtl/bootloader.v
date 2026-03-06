module bootloader(
    input clk,
    input rst_n,
    input [7:0] type_in,
    input [15:0] addr_in,
    input [31:0] data_in,
    input frame_valid,
    //数据寄存器写总线
    output reg [52:0] dmem_write_bus,
    //指令寄存器写总线
    output reg [48:0] imem_write_bus,
    //启动信号；使用CPU的复位信号来标志是否完成引导加载
    output reg reset,
    //写寄存器信号
    output reg mem_valid
);

reg [7:0] type_reg; //写data_ram为0x01，写inst_ram为0x02，开始运行为0x04，停止运行重新进入bootloader准备下载程序为0x08
reg [15:0] addr_reg;
reg [31:0] data_reg;
reg read_valid;

localparam TYPE_DMEM_WRITE = 8'h01;
localparam TYPE_IMEM_WRITE = 8'h02;
localparam TYPE_START_RUN  = 8'h04;
localparam TYPE_STOP_RUN   = 8'h08;

wire dmem_write_req = read_valid && (type_reg == TYPE_DMEM_WRITE);
wire imem_write_req = read_valid && (type_reg == TYPE_IMEM_WRITE);
wire start_run_req  = read_valid && (type_reg == TYPE_START_RUN);
wire stop_run_req   = read_valid && (type_reg == TYPE_STOP_RUN);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        type_reg <= 8'd0;
        addr_reg <= 16'd0;
        data_reg <= 32'd0;
        read_valid <= 1'b0;
    end else if (frame_valid) begin
        type_reg <= type_in;
        addr_reg <= addr_in;
        data_reg <= data_in;
        read_valid <= 1'b1; // 只要有新帧就标记有效
    end else begin
        read_valid <= 1'b0; // 没有新帧时无效
    end
end

// 数据存储器写总线生成
// 格式：{we[52], wmask[51:48], addr[47:32], data[31:0]}
// wmask固定全写，addr为16位对齐地址，高位保留零
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dmem_write_bus <= 53'd0;
    end else if (dmem_write_req) begin
        dmem_write_bus <= {1'b1, 4'b1111, addr_reg, data_reg};
    end else begin
        dmem_write_bus <= 53'd0; // 默认不驱动写
    end
end

// 指令存储器写总线生成
// 格式：{we[48], addr[47:32], inst[31:0]}
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        imem_write_bus <= 49'd0;
    end else if (imem_write_req) begin
        imem_write_bus <= {1'b1, addr_reg, data_reg};
    end else begin
        imem_write_bus <= 49'd0;
    end
end

// CPU复位/启动控制：
// 默认保持CPU在复位下（reset=1），收到开始命令释放复位；收到停止命令重新拉低
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reset <= 1'b0;
    end else if (stop_run_req) begin
        reset <= 1'b0;
    end else if (start_run_req) begin
        reset <= 1'b1;
    end
end

// 写寄存器信号控制
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_valid <= 1'b0;
    end else if (dmem_write_req || imem_write_req || stop_run_req || start_run_req) begin
        mem_valid <= 1'b1;
    end else begin
        mem_valid <= 1'b0;
    end
end

endmodule