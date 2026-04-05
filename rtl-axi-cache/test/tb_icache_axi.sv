// tb_icache_axi.sv
// SystemVerilog testbench for icache.v，重点测试AXI突发和if_cache功能
`timescale 1ns/1ps
module tb_icache_axi;
    reg clk;
    reg rst_n;
    reg [31:0] cpu_addr;
    reg cpu_ren;
    wire [31:0] cpu_rdata;
    wire cpu_rvalid;
    // AXI接口信号
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

    // 实例化 DUT
    icache dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(cpu_addr), .cpu_ren(cpu_ren),
        .cpu_rdata(cpu_rdata), .cpu_rvalid(cpu_rvalid),
        .axi_arid(axi_arid), .axi_araddr(axi_araddr), .axi_arlen(axi_arlen), .axi_arsize(axi_arsize),
        .axi_arburst(axi_arburst), .axi_arlock(axi_arlock), .axi_arcache(axi_arcache), .axi_arprot(axi_arprot),
        .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rid(axi_rid), .axi_rdata(axi_rdata), .axi_rresp(axi_rresp), .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid), .axi_rready(axi_rready)
    );

    // 时钟生成
    initial clk = 0;
    always #5 clk = ~clk;

    // 统计
    integer err_count = 0;
    integer burst_rsp_cnt;

    // 构造一整行回填数据（与tb_icache.v一致）
    function [255:0] build_refill_line;
        input [31:0] base_addr;
        begin
            build_refill_line[31:0]    = (base_addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ 32'h0000_0000;
            build_refill_line[63:32]   = (base_addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ 32'h0000_0004;
            build_refill_line[95:64]   = (base_addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ 32'h0000_0008;
            build_refill_line[127:96]  = (base_addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ 32'h0000_000C;
            build_refill_line[159:128] = (base_addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ 32'h0000_0010;
            build_refill_line[191:160] = (base_addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ 32'h0000_0014;
            build_refill_line[223:192] = (base_addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ 32'h0000_0018;
            build_refill_line[255:224] = (base_addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ 32'h0000_001C;
        end
    endfunction
    function [31:0] expected_word;
        input [31:0] addr;
        begin
            expected_word = (addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ {27'b0, addr[4:2], 2'b00};
        end
    endfunction

    // AXI突发仿真任务
    task automatic axi_burst_respond;
        input [31:0] base_addr;
        integer i;
        reg [255:0] burst_data;
        begin
            burst_data = build_refill_line(base_addr);
            burst_rsp_cnt = 0;
            // 等待AR握手
            wait(axi_arvalid);
            @(negedge clk);
            axi_arready = 1;
            @(negedge clk);
            axi_arready = 0;
            // 8-beat突发返回
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk);
                axi_rvalid = 1;
                axi_rid = 0;
                axi_rdata = burst_data[31:0];
                burst_data = burst_data >> 32;
                axi_rresp = 0;
                axi_rlast = (i == 7);
                burst_rsp_cnt = burst_rsp_cnt + 1;
                // 等待ready
                wait(axi_rready);
            end
            @(negedge clk);
            axi_rvalid = 0;
            axi_rlast = 0;
        end
    endtask

    // 单次请求并检查
    task automatic access_once_check;
        input [31:0] addr_in;
        input integer expect_refill;
        input integer expect_hit_1cyc;
        input string case_name;
        reg [31:0] req_addr;
        reg [31:0] exp_data;
        integer seen_refill;
        integer got_rsp;
        integer cycle_cnt;
        integer rsp_latency;
        begin
            req_addr = addr_in & 32'h0000_3FFC;
            exp_data = expected_word(req_addr);
            seen_refill = 0;
            got_rsp = 0;
            cycle_cnt = 0;
            rsp_latency = -1;
            // 发起请求
            @(negedge clk);
            cpu_addr = req_addr;
            cpu_ren = 1;
            @(posedge clk);
            cpu_ren = 0;
            // 检查响应
            while ((got_rsp == 0) && (cycle_cnt < 80)) begin
                @(posedge clk);
                cycle_cnt = cycle_cnt + 1;
                if (axi_arvalid) seen_refill = 1;
                if (cpu_rvalid) begin
                    got_rsp = 1;
                    rsp_latency = cycle_cnt;
                    $display("[%0s] req=0x%08h data=0x%08h refill_seen=%0d latency=%0d", case_name, req_addr, cpu_rdata, seen_refill, rsp_latency);
                    if (cpu_rdata !== exp_data) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] data mismatch! exp=0x%08h got=0x%08h", case_name, exp_data, cpu_rdata);
                    end
                    if ((expect_refill == 1) && (seen_refill == 0)) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] expected MISS(refill), but no refill_req seen", case_name);
                    end
                    if ((expect_refill == 0) && (seen_refill == 1)) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] expected HIT(no refill), but refill_req seen", case_name);
                    end
                    if ((expect_hit_1cyc == 1) && (rsp_latency != 1)) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] expected HIT latency=1, got latency=%0d", case_name, rsp_latency);
                    end
                end
            end
            if (got_rsp == 0) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] timeout waiting cpu_rvalid, req=0x%08h", case_name, req_addr);
            end
        end
    endtask

    // 指令cache突发功能测试
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
        err_count = 0;
        burst_rsp_cnt = 0;
        #20;
        rst_n = 1;
        @(posedge clk);
        // 1. 首次访问MISS，触发AXI突发
        fork
            begin
                access_once_check(32'h0000_1000, 1, 0, "FIRST_MISS");
            end
            begin
                axi_burst_respond(32'h0000_1000 & 32'hFFFF_FFE0);
            end
        join
        // 2. 命中测试
        access_once_check(32'h0000_1000, 0, 1, "FIRST_HIT");
        access_once_check(32'h0000_1004, 0, 1, "SAME_LINE_HIT");
        // 3. 跨line MISS
        fork
            begin
                access_once_check(32'h0000_1020, 1, 0, "CROSS_LINE_MISS");
            end
            begin
                axi_burst_respond(32'h0000_1020 & 32'hFFFF_FFE0);
            end
        join
        // 4. 命中流测试
        for (int j = 0; j < 4; j++) begin
            access_once_check(32'h0000_1000 + 4*j, 0, 1, $sformatf("HIT_STREAM_%0d", j));
        end
        // 5. 多次跨line突发
        for (int i = 0; i < 3; i++) begin
            fork
                begin
                    access_once_check(32'h0000_2000 + i*32, 1, 0, $sformatf("MULTI_LINE_MISS_%0d", i));
                end
                begin
                    axi_burst_respond((32'h0000_2000 + i*32) & 32'hFFFF_FFE0);
                end
            join
        end
        $display("\nAll tests done. err_count=%0d", err_count);
        #20;
        $finish;
    end
endmodule
