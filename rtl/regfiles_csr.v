module regfiles_csr (
    input wire clk,
    input wire rst_n,
    //写端口
    input wire csr_we,
    input wire [11:0] csr_waddr,
    input wire [31:0] csr_wdata,
    //读端口
    input wire [11:0] csr_raddr,
    output wire [31:0] csr_rdata,
    //异常相关信号
    input wire [5:0] exception_code,
    input wire [31:0] exception_mtval,
    input wire exception_flag,
    output wire [31:0] exception_addr
);

reg [31:0] mstatus;
reg [31:0] misa;
reg [31:0] mtvec;
reg [31:0] mepc;
reg [31:0] mcause;
reg [31:0] mhartid;
reg [31:0] mie;
reg [31:0] mip;
reg [31:0] mtval;
reg [31:0] mvendorid;
reg [31:0] marchid;
reg [31:0] mimpid;
reg [31:0] mscratch;
wire mret_flag = & exception_code[4:0]; // mret指令的异常代码

//CSR寄存器写操作
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mstatus <= 32'b0;
        misa <= 32'b0;
        mtvec <= 32'b0;
        mepc <= 32'b0;
        mcause <= 32'b0;
        mhartid <= 32'b0;
        mie <= 32'b0;
        mip <= 32'b0;
        mtval <= 32'b0;
        mvendorid <= 32'b0;
        marchid <= 32'b0;
        mimpid <= 32'b0;
        mscratch <= 32'b0;
    end else if (csr_we) begin
        case (csr_waddr)
            12'h300: mstatus <= csr_wdata;
            12'h301: misa <= csr_wdata;
            12'h305: mtvec <= csr_wdata;
            12'h340: mscratch <= csr_wdata;
            12'h341: mepc <= csr_wdata;
            12'h342: mcause <= csr_wdata;
            12'hF14: mhartid <= csr_wdata;
            12'h304: mie <= csr_wdata;
            12'h344: mip <= csr_wdata;
            12'h343: mtval <= csr_wdata;
            12'hF11: mvendorid <= csr_wdata;
            12'hF12: marchid <= csr_wdata;
            12'hF13: mimpid <= csr_wdata;
            default: ; // do nothing
        endcase
    end else begin
        if (exception_code[5]) begin
            $display("CSR: Exception occurred! Code: %b, mtval: %h", exception_code, exception_mtval);
            mepc <= csr_wdata; // 将引起异常的指令地址写入mepc
            mcause <= {27'b0, exception_code[4:0]}; // 将异常代码写入mcause
            mtval <= exception_mtval; // 将引起异常的地址或数据写入mtval
        end else if (mret_flag) begin
            //mret指令，清除异常状态
            mstatus [3] <= mstatus[7]; // 恢复mstatus中MIE位的值
            mstatus [7] <= 1'b1; 
        end
    end
end

//CSR读操作
reg [31:0] csr_rdata_reg;
always @(*) begin
    case (csr_raddr)
        12'h300: csr_rdata_reg = mstatus;
        12'h301: csr_rdata_reg = misa;
        12'h305: csr_rdata_reg = mtvec;
        12'h340: csr_rdata_reg = mscratch;
        12'h341: csr_rdata_reg = mepc;
        12'h342: csr_rdata_reg = mcause;
        12'hF14: csr_rdata_reg = mhartid;
        12'h304: csr_rdata_reg = mie;
        12'h344: csr_rdata_reg = mip;
        12'h343: csr_rdata_reg = mtval;
        12'hF11: csr_rdata_reg = mvendorid;
        12'hF12: csr_rdata_reg = marchid;
        12'hF13: csr_rdata_reg = mimpid;
        default: csr_rdata_reg = 32'b0; // 未定义地址返回0
    endcase
end

//异常标志以及mret指令恢复相关
reg prev_exception_flag;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prev_exception_flag <= 1'b0;
    end else if (exception_code[5]) begin
        prev_exception_flag <= 1'b1; // 记录异常发生
    end else if (mret_flag) begin
        prev_exception_flag <= 1'b0; // mret指令，清除异常标志
    end
end
wire mret_jmp_flag = mret_flag && prev_exception_flag; // 只有在之前发生过异常的情况下，mret指令才会跳转

assign csr_rdata = csr_rdata_reg;
assign exception_flag = exception_code[5] || mret_jmp_flag; // 发生异常或执行mret指令时，exception_flag为1
assign exception_addr = mret_jmp_flag ? mepc : mtvec; // mret指令跳转到mepc，其他异常跳转到mtvec

endmodule