// tb_icache.sv
// SystemVerilog testbench for icache.v
`timescale 1ns/1ps
module tb_icache();
    reg clk;
    reg rst_n;
    reg [31:0] cpu_addr;
    reg cpu_ren;
    wire [31:0] cpu_rdata;
    wire cpu_rvalid;
    // AXI signals
    wire [3:0] axi_arid;
    wire [31:0] axi_araddr;
    wire [7:0] axi_arlen;
    wire [2:0] axi_arsize;
    wire [1:0] axi_arburst;
    wire [1:0] axi_arlock;
    wire [3:0] axi_arcache;
    wire [2:0] axi_arprot;
    wire axi_arvalid;
    reg axi_arready;
    reg [3:0] axi_rid;
    reg [31:0] axi_rdata;
    reg [1:0] axi_rresp;
    reg axi_rlast;
    reg axi_rvalid;
    wire axi_rready;

    // Instantiate DUT
    icache dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_ren(cpu_ren),
        .cpu_rdata(cpu_rdata),
        .cpu_rvalid(cpu_rvalid),
        .axi_arid(axi_arid),
        .axi_araddr(axi_araddr),
        .axi_arlen(axi_arlen),
        .axi_arsize(axi_arsize),
        .axi_arburst(axi_arburst),
        .axi_arlock(axi_arlock),
        .axi_arcache(axi_arcache),
        .axi_arprot(axi_arprot),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_rid(axi_rid),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Reset
    initial begin
        rst_n = 0;
        cpu_addr = 0;
        cpu_ren = 0;
        axi_arready = 0;
        axi_rid = 0;
        axi_rdata = 0;
        axi_rresp = 0;
        axi_rlast = 0;
        axi_rvalid = 0;
        #20;
        rst_n = 1;
    end

    // Stimulus
    initial begin
        @(posedge rst_n);
        #10;
        cpu_addr = 32'h0000_1000;
        cpu_ren = 1;
        #10;
        cpu_ren = 0;
        // Wait for AR handshake
        wait(axi_arvalid);
        #2;
        axi_arready = 1;
        #10;
        axi_arready = 0;
        // Simulate AXI R channel burst
        repeat(8) begin
            @(negedge clk);
            axi_rvalid = 1;
            axi_rdata = $random;
            axi_rlast = 0;
            if ($time > 100) axi_rlast = 1; // Last beat
            #10;
        end
        axi_rlast = 1;
        #10;
        axi_rvalid = 0;
        axi_rlast = 0;
        // Wait for cpu_rvalid
        wait(cpu_rvalid);
        $display("CPU read data: %h", cpu_rdata);
        #20;
        $finish;
    end
endmodule
