`timescale 1ns/1ps
`include "defines.v"

module tb_dcache;
    reg clk;
    reg rst_n;

    // CPU接口
    reg  [31:0] cpu_addr;
    reg         cpu_ren;
    reg  [3:0]  cpu_wen;
    reg  [31:0] cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_rvalid;
    wire        cpu_stall;

    // AXI读请求通道
    wire [3:0] axi_arid;
    wire [31:0] axi_araddr;
    wire [7:0] axi_arlen;
    wire [2:0] axi_arsize;
    wire [1:0] axi_arburst;
    wire [1:0] axi_arlock;
    wire [3:0] axi_arcache;
    wire [2:0] axi_arprot;
    wire       axi_arvalid;
    reg        axi_arready;

    // AXI写请求通道
    wire [3:0] axi_awid;
    wire [31:0] axi_awaddr;
    wire [7:0] axi_awlen;
    wire [2:0] axi_awsize;
    wire [1:0] axi_awburst;
    wire [1:0] axi_awlock;
    wire [3:0] axi_awcache;
    wire [2:0] axi_awprot;
    wire       axi_awvalid;
    reg        axi_awready;

    // AXI写数据通道
    wire [3:0] axi_wid;
    wire [31:0] axi_wdata;
    wire [3:0] axi_wstrb;
    wire       axi_wlast;
    wire       axi_wvalid;
    reg        axi_wready;

    // AXI读数据通道
    reg  [3:0] axi_rid;
    reg  [31:0] axi_rdata;
    reg  [1:0] axi_rresp;
    reg        axi_rlast;
    reg        axi_rvalid;
    wire       axi_rready;

    // AXI写响应通道
    reg  [3:0] axi_bid;
    reg  [1:0] axi_bresp;
    reg        axi_bvalid;
    wire       axi_bready;

    integer err_count;
    integer pass_count;

    localparam [31:0] IO_BASE   = `IO_ADDR_BEGIN;
    localparam [31:0] DRAM_BASE = `DATA_ADDR_BEGIN;

    // DUT
    dcache uut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_ren(cpu_ren),
        .cpu_wen(cpu_wen),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_rvalid(cpu_rvalid),
        .cpu_stall(cpu_stall),
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
        .axi_awid(axi_awid),
        .axi_awaddr(axi_awaddr),
        .axi_awlen(axi_awlen),
        .axi_awsize(axi_awsize),
        .axi_awburst(axi_awburst),
        .axi_awlock(axi_awlock),
        .axi_awcache(axi_awcache),
        .axi_awprot(axi_awprot),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_wid(axi_wid),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wlast(axi_wlast),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_rid(axi_rid),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),
        .axi_bid(axi_bid),
        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready)
    );

    // 100MHz
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check;
        input cond;
        input [255:0] msg;
        begin
            if (!cond) begin
                err_count = err_count + 1;
                $display("ERROR: %0s", msg);
            end else begin
                pass_count = pass_count + 1;
                $display("PASS : %0s", msg);
            end
        end
    endtask

    task do_reset;
        begin
            rst_n = 1'b0;
            cpu_addr = 32'b0;
            cpu_ren = 1'b0;
            cpu_wen = 4'b0;
            cpu_wdata = 32'b0;
            axi_arready = 1'b1;
            axi_awready = 1'b1;
            axi_wready = 1'b1;
            axi_rid = 4'b0;
            axi_rdata = 32'b0;
            axi_rresp = 2'b0;
            axi_rlast = 1'b0;
            axi_rvalid = 1'b0;
            axi_bid = 4'h2;
            axi_bresp = 2'b0;
            axi_bvalid = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    task pulse_io_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0] strb;
        begin
            @(negedge clk);
            cpu_addr  = addr;
            cpu_wdata = data;
            cpu_wen   = strb;
            cpu_ren   = 1'b0;
            @(posedge clk);
            @(negedge clk);
            cpu_wen   = 4'b0;
            cpu_wdata = 32'b0;
            cpu_addr  = 32'b0;
        end
    endtask

    task inject_wb_req;
        input [31:0] addr;
        input [255:0] line_data;
        begin
            @(negedge clk);
            force uut.write_back_addr = addr;
            force uut.write_back_data = line_data;
            force uut.write_back_req  = 1'b1;
            @(posedge clk);
            @(negedge clk);
            release uut.write_back_req;
            release uut.write_back_addr;
            release uut.write_back_data;
        end
    endtask

    task send_bresp_once;
        begin
            @(negedge clk);
            axi_bvalid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            axi_bvalid = 1'b0;
        end
    endtask

    task wait_aw_hs;
        input integer timeout;
        output reg [31:0] got_addr;
        output reg [7:0] got_len;
        integer t;
        begin
            t = 0;
            while (!(axi_awvalid && axi_awready) && (t < timeout)) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t >= timeout) begin
                err_count = err_count + 1;
                $display("ERROR: timeout waiting AW handshake");
                got_addr = 32'hDEAD_DEAD;
                got_len  = 8'hFF;
            end else begin
                got_addr = axi_awaddr;
                got_len  = axi_awlen;
            end
        end
    endtask

    task expect_wbeats;
        input integer beats;
        input [255:0] exp_data;
        input [3:0] exp_strb;
        integer b;
        integer t;
        begin
            for (b = 0; b < beats; b = b + 1) begin
                t = 0;
                while (!(axi_wvalid && axi_wready) && (t < 80)) begin
                    @(posedge clk);
                    t = t + 1;
                end
                if (t >= 80) begin
                    err_count = err_count + 1;
                    $display("ERROR: timeout waiting W beat %0d", b);
                end else begin
                    check(axi_wdata == exp_data[b*32 +: 32], "W beat data matches");
                    check(axi_wstrb == exp_strb, "W beat strb matches");
                    if (b == beats - 1) begin
                        check(axi_wlast == 1'b1, "W last asserted on final beat");
                    end else begin
                        check(axi_wlast == 1'b0, "W last deasserted before final beat");
                    end
                end
                @(posedge clk);
            end
        end
    endtask

    task wait_write_idle;
        integer t;
        begin
            t = 0;
            while ((uut.w_state !== 2'b00) && (t < 100)) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t >= 100) begin
                err_count = err_count + 1;
                $display("ERROR: timeout waiting write FSM idle");
            end
            @(posedge clk);
        end
    endtask

    task case_io_write_single;
        reg [31:0] aw_addr;
        reg [7:0] aw_len;
        begin
            $display("\n=== CASE1: IO single write + B channel pop ===");
            do_reset();

            pulse_io_write(IO_BASE + 32'h0000_0010, 32'hDEAD_BEEF, 4'b1111);

            wait_aw_hs(50, aw_addr, aw_len);
            check(aw_addr == (IO_BASE + 32'h10), "IO AW address matches");
            check(aw_len == 8'd0, "IO AWLEN=0 (single beat)");

            expect_wbeats(1, {8{32'hDEAD_BEEF}}, 4'b1111);

            repeat (3) @(posedge clk);
            check(uut.io_wfifo_count == 3'd1, "IO FIFO not popped before B response");

            send_bresp_once();
            repeat (2) @(posedge clk);
            check(uut.io_wfifo_count == 3'd0, "IO FIFO popped after B response");
        end
    endtask

    task case_wb_write_burst;
        reg [255:0] wb_line;
        reg [31:0] aw_addr;
        reg [7:0] aw_len;
        begin
            $display("\n=== CASE2: WB burst write (8 beats) + B channel pop ===");
            do_reset();
            wb_line = {
                32'h0706_0504, 32'h1716_1514, 32'h2726_2524, 32'h3736_3534,
                32'h4746_4544, 32'h5756_5554, 32'h6766_6564, 32'h7776_7574
            };

            inject_wb_req(DRAM_BASE + 32'h0000_0200, wb_line);

            wait_aw_hs(50, aw_addr, aw_len);
            check(aw_addr == (DRAM_BASE + 32'h200), "WB AW address matches");
            check(aw_len == 8'd7, "WB AWLEN=7 (8 beats)");

            expect_wbeats(8, wb_line, 4'hF);

            repeat (3) @(posedge clk);
            check(uut.wb_wfifo_count == 3'd1, "WB FIFO not popped before B response");

            send_bresp_once();
            repeat (2) @(posedge clk);
            check(uut.wb_wfifo_count == 3'd0, "WB FIFO popped after B response");
        end
    endtask

    task case_io_priority_over_wb;
        reg [255:0] wb_line;
        reg [31:0] aw_addr;
        reg [7:0] aw_len;
        begin
            $display("\n=== CASE3: IO priority over WB ===");
            do_reset();
            wb_line = {8{32'hA5A5_5A5A}};

            // 同拍入队IO和WB，确保仲裁时二者均非空
            @(negedge clk);
            cpu_addr  = IO_BASE + 32'h44;
            cpu_wdata = 32'h1234_5678;
            cpu_wen   = 4'b1111;
            force uut.write_back_addr = DRAM_BASE + 32'h300;
            force uut.write_back_data = wb_line;
            force uut.write_back_req  = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cpu_wen   = 4'b0;
            cpu_wdata = 32'b0;
            cpu_addr  = 32'b0;
            release uut.write_back_req;
            release uut.write_back_addr;
            release uut.write_back_data;

            wait_aw_hs(50, aw_addr, aw_len);
            check(aw_addr == (IO_BASE + 32'h44), "First AW is IO request");
            check(aw_len == 8'd0, "First AWLEN is IO single beat");
            expect_wbeats(1, {8{32'h1234_5678}}, 4'hF);
            send_bresp_once();

            wait_aw_hs(50, aw_addr, aw_len);
            check(aw_addr == (DRAM_BASE + 32'h300), "Second AW is WB request");
            check(aw_len == 8'd7, "Second AWLEN is WB burst");
            expect_wbeats(8, wb_line, 4'hF);
            send_bresp_once();

            wait_write_idle();
        end
    endtask

    task case_both_fifo_full_stall;
        integer i;
        reg [255:0] line_data;
        begin
            $display("\n=== CASE4: both FIFOs full -> cpu_stall ===");
            do_reset();

            // 阻塞总线，避免出队
            axi_awready = 1'b0;
            axi_wready  = 1'b0;
            axi_bvalid  = 1'b0;

            // 填满IO FIFO
            for (i = 0; i < 4; i = i + 1) begin
                pulse_io_write(IO_BASE + (i * 4), 32'h1111_0000 + i, 4'hF);
            end

            // 填满WB FIFO
            for (i = 0; i < 4; i = i + 1) begin
                line_data = {8{(32'h2222_0000 + i)}};
                inject_wb_req(DRAM_BASE + 32'h400 + (i * 32), line_data);
            end

            repeat (2) @(posedge clk);
            check(uut.io_wfifo_count == 3'd4, "IO FIFO full");
            check(uut.wb_wfifo_count == 3'd4, "WB FIFO full");
            check(cpu_stall == 1'b1, "cpu_stall asserted when both FIFOs full");

            // 恢复总线
            axi_awready = 1'b1;
            axi_wready  = 1'b1;
        end
    endtask

    task case_io_full_stall_on_request;
        integer i;
        begin
            $display("\n=== CASE5: IO FIFO full and IO request -> cpu_stall ===");
            do_reset();

            axi_awready = 1'b0;
            axi_wready  = 1'b0;

            for (i = 0; i < 4; i = i + 1) begin
                pulse_io_write(IO_BASE + 32'h100 + i*4, 32'hABCD_0000 + i, 4'hF);
            end

            @(negedge clk);
            cpu_addr  = IO_BASE + 32'h200;
            cpu_wdata = 32'hCAFE_BABE;
            cpu_wen   = 4'hF;
            @(posedge clk);
            check(cpu_stall == 1'b1, "cpu_stall asserted on IO request when IO FIFO full");
            @(negedge clk);
            cpu_wen   = 4'h0;
            cpu_wdata = 32'b0;
            cpu_addr  = 32'b0;

            axi_awready = 1'b1;
            axi_wready  = 1'b1;
        end
    endtask

    task case_wb_full_pending_stall;
        integer i;
        reg [255:0] line_data;
        begin
            $display("\n=== CASE6: WB full + pending and WB request -> cpu_stall ===");
            do_reset();

            axi_awready = 1'b0;
            axi_wready  = 1'b0;

            for (i = 0; i < 4; i = i + 1) begin
                line_data = {8{(32'h3333_0000 + i)}};
                inject_wb_req(DRAM_BASE + 32'h800 + i*32, line_data);
            end

            // 第5条写回进入pending
            line_data = {8{32'h4444_0005}};
            inject_wb_req(DRAM_BASE + 32'h900, line_data);
            repeat (2) @(posedge clk);
            check(uut.wb_pending_valid == 1'b1, "WB pending captured when FIFO full");

            // 第6条在 full + pending 条件下应触发stall
            @(negedge clk);
            force uut.write_back_addr = DRAM_BASE + 32'h920;
            force uut.write_back_data = {8{32'h5555_0006}};
            force uut.write_back_req  = 1'b1;
            @(posedge clk);
            check(cpu_stall == 1'b1, "cpu_stall asserted when WB full and pending already occupied");
            @(negedge clk);
            release uut.write_back_req;
            release uut.write_back_addr;
            release uut.write_back_data;

            axi_awready = 1'b1;
            axi_wready  = 1'b1;
        end
    endtask

    initial begin
        err_count = 0;
        pass_count = 0;

        case_io_write_single();
        case_wb_write_burst();
        case_io_priority_over_wb();
        case_both_fifo_full_stall();
        case_io_full_stall_on_request();
        case_wb_full_pending_stall();

        repeat (20) @(posedge clk);

        $display("\n================ TB_DCACHE SUMMARY ================");
        $display("PASS checks = %0d", pass_count);
        $display("FAIL checks = %0d", err_count);

        if (err_count == 0) begin
            $display("TB_DCACHE RESULT: PASS");
        end else begin
            $display("TB_DCACHE RESULT: FAIL");
        end

        $stop;
    end

endmodule
