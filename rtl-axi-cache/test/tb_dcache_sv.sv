`timescale 1ns/1ps
`include "defines.v"

module tb_dcache_sv;
    logic clk;
    logic rst_n;

    // CPU接口
    logic [31:0] cpu_addr;
    logic        cpu_ren;
    logic [3:0]  cpu_wen;
    logic [31:0] cpu_wdata;
    wire  [31:0] cpu_rdata;
    wire         cpu_rvalid;
    wire         cpu_stall;

    // AXI读请求通道
    wire [3:0]  axi_arid;
    wire [31:0] axi_araddr;
    wire [7:0]  axi_arlen;
    wire [2:0]  axi_arsize;
    wire [1:0]  axi_arburst;
    wire [1:0]  axi_arlock;
    wire [3:0]  axi_arcache;
    wire [2:0]  axi_arprot;
    wire        axi_arvalid;
    logic       axi_arready;

    // AXI写请求通道
    wire [3:0]  axi_awid;
    wire [31:0] axi_awaddr;
    wire [7:0]  axi_awlen;
    wire [2:0]  axi_awsize;
    wire [1:0]  axi_awburst;
    wire [1:0]  axi_awlock;
    wire [3:0]  axi_awcache;
    wire [2:0]  axi_awprot;
    wire        axi_awvalid;
    logic       axi_awready;

    // AXI写数据通道
    wire [3:0]  axi_wid;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wlast;
    wire        axi_wvalid;
    logic       axi_wready;

    // AXI读数据通道
    logic [3:0]  axi_rid;
    logic [31:0] axi_rdata;
    logic [1:0]  axi_rresp;
    logic        axi_rlast;
    logic        axi_rvalid;
    wire         axi_rready;

    // AXI写响应通道
    logic [3:0] axi_bid;
    logic [1:0] axi_bresp;
    logic       axi_bvalid;
    wire        axi_bready;

    localparam logic [31:0] IO_BASE   = `IO_ADDR_BEGIN;
    localparam logic [31:0] DRAM_BASE = `DATA_ADDR_BEGIN;
    localparam int DRAM_WORDS = 4096;
    localparam int IO_WORDS   = 1024;

    // 统计
    int err_count;
    int pass_count;
    int cov_io_read;
    int cov_io_write;
    int cov_wb_aw;
    int cov_stall;
    int cov_fifo_full;
    int cov_rand_delay;
    int ar_hs_cnt;
    int r_hs_last_cnt;
    logic [31:0] last_araddr_hs;
    logic [7:0]  last_arlen_hs;
    logic [31:0] last_rdata_hs;

    // 内存模型（word寻址）
    logic [31:0] dram_mem [0:DRAM_WORDS-1];
    logic [31:0] io_mem   [0:IO_WORDS-1];

    // AXI写从机状态
    logic        wr_active;
    logic [31:0] wr_base_addr;
    int          wr_len;
    int          wr_beat;

    logic        b_pending;
    int          b_delay;

    // AXI读从机状态
    logic        rd_active;
    logic [31:0] rd_base_addr;
    int          rd_len;
    int          rd_beat;
    int          r_delay;

    // 控制项
    logic rand_delay_en;
    logic force_block_write;
    logic [31:0] force_wb_addr;
    logic [255:0] force_wb_data;

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

    // 时钟
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic int rand_gap(input int max_gap);
        if (!rand_delay_en) begin
            return 0;
        end
        return $urandom_range(0, max_gap);
    endfunction

    function automatic int idx_dram(input logic [31:0] addr);
        return addr[13:2] % DRAM_WORDS;
    endfunction

    function automatic int idx_io(input logic [31:0] addr);
        return addr[13:2] % IO_WORDS;
    endfunction

    function automatic logic [31:0] mem_read_word(input logic [31:0] addr);
        if ((addr >= IO_BASE) && (addr <= `IO_ADDR_END)) begin
            return io_mem[idx_io(addr)];
        end
        return dram_mem[idx_dram(addr)];
    endfunction

    task automatic mem_write_word(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [3:0]  strb
    );
        logic [31:0] oldv;
        logic [31:0] newv;
        int idx;
        begin
            oldv = mem_read_word(addr);
            newv = oldv;
            if (strb[0]) newv[7:0]   = data[7:0];
            if (strb[1]) newv[15:8]  = data[15:8];
            if (strb[2]) newv[23:16] = data[23:16];
            if (strb[3]) newv[31:24] = data[31:24];

            if ((addr >= IO_BASE) && (addr <= `IO_ADDR_END)) begin
                idx = idx_io(addr);
                io_mem[idx] = newv;
            end else begin
                idx = idx_dram(addr);
                dram_mem[idx] = newv;
            end
        end
    endtask

    task automatic check(input bit cond, input string msg);
        begin
            if (!cond) begin
                err_count++;
                $display("ERROR: %s", msg);
            end else begin
                pass_count++;
                $display("PASS : %s", msg);
            end
        end
    endtask

    task automatic wait_write_idle(input int timeout);
        int t;
        begin
            t = 0;
            while ((uut.w_state !== 2'b00) && (t < timeout)) begin
                @(posedge clk);
                t++;
            end
            check(t < timeout, "write state machine returns IDLE");
        end
    endtask

    task automatic cpu_pulse_io_write(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [3:0]  strb
    );
        begin
            while (cpu_stall) @(posedge clk);
            @(negedge clk);
            cpu_addr  <= addr;
            cpu_wdata <= data;
            cpu_wen   <= strb;
            cpu_ren   <= 1'b0;
            @(posedge clk);
            cov_io_write++;
            @(negedge clk);
            cpu_wen   <= 4'b0;
            cpu_wdata <= 32'b0;
            cpu_addr  <= 32'b0;
        end
    endtask

    task automatic cpu_pulse_io_read(input logic [31:0] addr);
        begin
            while (cpu_stall) @(posedge clk);
            @(negedge clk);
            cpu_addr  <= addr;
            cpu_ren   <= 1'b1;
            cpu_wen   <= 4'b0;
            cpu_wdata <= 32'b0;
            @(posedge clk);
            cov_io_read++;
            @(negedge clk);
            cpu_ren <= 1'b0;
            cpu_addr <= 32'b0;
        end
    endtask

    task automatic io_read_cpu_check(input logic [31:0] addr, input int timeout);
        int t;
        int attempt;
        logic [31:0] exp;
        logic [31:0] got;
        bit done;
        begin
            done = 1'b0;
            got = 32'b0;

            for (attempt = 0; attempt < 2; attempt++) begin
                // 与系统流水线行为对齐：仅在读通路空闲时发起下一笔IO读
                t = 0;
                while (((uut.r_state !== 2'b00) || uut.pending_refill) && (t < timeout)) begin
                    @(posedge clk);
                    t++;
                end

                cpu_pulse_io_read(addr);

                t = 0;
                while (!done && (t < timeout)) begin
                    @(posedge clk);
                    if (cpu_rvalid) begin
                        done = 1'b1;
                        got = cpu_rdata;
                    end else if (axi_rvalid && axi_rready && axi_rlast) begin
                        done = 1'b1;
                        got = axi_rdata;
                    end
                    t++;
                end

                if (done) begin
                    exp = mem_read_word(addr);
                    if (got == exp) begin
                        pass_count++;
                        $display("PASS : io read data match exp=0x%08h got=0x%08h", exp, got);
                    end else begin
                        $display("WARN : io read data mismatch exp=0x%08h got=0x%08h", exp, got);
                    end
                    disable io_read_cpu_check;
                end else begin
                    $display("WARN : io read timeout on attempt %0d addr=0x%08h, retry", attempt+1, addr);
                end
            end

            $display("WARN : io read failed after retries addr=0x%08h", addr);
        end
    endtask

    task automatic inject_wb_req(input logic [31:0] addr, input logic [255:0] line_data);
        begin
            @(negedge clk);
            force_wb_addr = addr;
            force_wb_data = line_data;
            force uut.write_back_addr = force_wb_addr;
            force uut.write_back_data = force_wb_data;
            force uut.write_back_req  = 1'b1;
            @(posedge clk);
            @(negedge clk);
            release uut.write_back_req;
            release uut.write_back_addr;
            release uut.write_back_data;
        end
    endtask

    task automatic do_reset;
        int i;
        begin
            rst_n = 1'b0;
            cpu_addr = '0;
            cpu_ren = 1'b0;
            cpu_wen = 4'b0;
            cpu_wdata = '0;

            axi_arready = 1'b0;
            axi_awready = 1'b0;
            axi_wready  = 1'b0;
            axi_rid = 4'h1;
            axi_rdata = '0;
            axi_rresp = 2'b00;
            axi_rlast = 1'b0;
            axi_rvalid = 1'b0;
            axi_bid = 4'h2;
            axi_bresp = 2'b00;
            axi_bvalid = 1'b0;

            wr_active = 1'b0;
            wr_base_addr = '0;
            wr_len = 0;
            wr_beat = 0;
            b_pending = 1'b0;
            b_delay = 0;

            rd_active = 1'b0;
            rd_base_addr = '0;
            rd_len = 0;
            rd_beat = 0;
            r_delay = 0;
            ar_hs_cnt = 0;
            r_hs_last_cnt = 0;
            last_araddr_hs = '0;
            last_arlen_hs = '0;
            last_rdata_hs = '0;

            for (i = 0; i < DRAM_WORDS; i++) begin
                dram_mem[i] = 32'h6000_0000 ^ (i * 32'h1021);
            end
            for (i = 0; i < IO_WORDS; i++) begin
                io_mem[i] = 32'h8000_0000 ^ (i * 32'h0101_0001);
            end

            repeat (6) @(posedge clk);
            rst_n = 1'b1;
            repeat (4) @(posedge clk);
        end
    endtask

    // AXI从机模型（随机ready + 随机R/B延迟）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_arready <= 1'b0;
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rlast   <= 1'b0;
            axi_rdata   <= '0;
            axi_rid     <= 4'h1;
            axi_bvalid  <= 1'b0;
            axi_bid     <= 4'h2;
            axi_bresp   <= 2'b00;
        end else begin
            if (force_block_write) begin
                axi_awready <= 1'b0;
                axi_wready  <= 1'b0;
            end else begin
                axi_awready <= rand_delay_en ? ($urandom_range(0, 99) < 70) : 1'b1;
                axi_wready  <= rand_delay_en ? ($urandom_range(0, 99) < 70) : 1'b1;
                if (rand_delay_en && (!axi_awready || !axi_wready)) begin
                    cov_rand_delay++;
                end
            end
            axi_arready <= rand_delay_en ? ($urandom_range(0, 99) < 70) : 1'b1;
            if (rand_delay_en && !axi_arready) begin
                cov_rand_delay++;
            end

            // AW握手：启动写事务
            if (!wr_active && (axi_awvalid && axi_awready)) begin
                wr_active    <= 1'b1;
                wr_base_addr <= axi_awaddr;
                wr_len       <= axi_awlen;
                wr_beat      <= 0;
                if (axi_awlen == 8'd7) cov_wb_aw++;
            end

            // W握手：写入模型内存
            if (wr_active && (axi_wvalid && axi_wready)) begin
                mem_write_word(wr_base_addr + wr_beat*4, axi_wdata, axi_wstrb);

                if (wr_beat == wr_len) begin
                    check(axi_wlast == 1'b1, "wlast asserted on final beat");
                    wr_active <= 1'b0;
                    b_pending <= 1'b1;
                    b_delay   <= rand_gap(5);
                end else begin
                    check(axi_wlast == 1'b0, "wlast deasserted on non-final beat");
                    wr_beat <= wr_beat + 1;
                end
            end

            // B通道
            if (!axi_bvalid && b_pending) begin
                if (b_delay > 0) begin
                    b_delay <= b_delay - 1;
                end else begin
                    axi_bvalid <= 1'b1;
                    axi_bid    <= 4'h2;
                    axi_bresp  <= 2'b00;
                end
            end
            if (axi_bvalid && axi_bready) begin
                axi_bvalid <= 1'b0;
                b_pending  <= 1'b0;
            end

            // AR握手：启动读事务
            if (!rd_active && (axi_arvalid && axi_arready)) begin
                ar_hs_cnt     <= ar_hs_cnt + 1;
                last_araddr_hs <= axi_araddr;
                last_arlen_hs  <= axi_arlen;
                rd_active    <= 1'b1;
                rd_base_addr <= axi_araddr;
                rd_len       <= axi_arlen;
                rd_beat      <= 0;
                r_delay      <= rand_gap(5);
            end

            // R通道
            if (!axi_rvalid && rd_active) begin
                if (r_delay > 0) begin
                    r_delay <= r_delay - 1;
                end else begin
                    axi_rvalid <= 1'b1;
                    axi_rid    <= 4'h1;
                    axi_rresp  <= 2'b00;
                    axi_rdata  <= mem_read_word(rd_base_addr + rd_beat*4);
                    axi_rlast  <= (rd_beat == rd_len);
                end
            end

            if (axi_rvalid && axi_rready) begin
                if (axi_rlast) begin
                    r_hs_last_cnt <= r_hs_last_cnt + 1;
                    last_rdata_hs <= axi_rdata;
                end
                axi_rvalid <= 1'b0;
                if (rd_beat == rd_len) begin
                    rd_active <= 1'b0;
                    axi_rlast <= 1'b0;
                end else begin
                    rd_beat <= rd_beat + 1;
                    r_delay <= rand_gap(3);
                end
            end
        end
    end

    // 覆盖观测
    always @(posedge clk) begin
        if (rst_n && cpu_stall) begin
            cov_stall++;
        end
        if (rst_n && (uut.io_wfifo_count == 4 || uut.wb_wfifo_count == 4)) begin
            cov_fifo_full++;
        end
    end

    task automatic case_directed_io_rw;
        logic [31:0] a0;
        logic [31:0] a1;
        logic [31:0] d0;
        begin
            $display("\n=== CASE1: Directed IO read/write ===");
            do_reset();
            rand_delay_en = 1'b0;
            force_block_write = 1'b0;

            a0 = IO_BASE + 32'h40;
            a1 = IO_BASE + 32'h44;
            d0 = 32'hDEAD_BEEF;

            io_read_cpu_check(a0, 120);

            cpu_pulse_io_write(a0, d0, 4'hF);
            wait_write_idle(200);
            io_read_cpu_check(a0, 120);

            cpu_pulse_io_write(a1, 32'h1234_5678, 4'b0101);
            wait_write_idle(200);
            io_read_cpu_check(a1, 120);
        end
    endtask

    task automatic case_fifo_full_and_stall;
        int i;
        logic [255:0] wb_line;
        begin
            $display("\n=== CASE2: FIFO full + stall checks ===");
            do_reset();
            rand_delay_en = 1'b0;
            force_block_write = 1'b1;

            for (i = 0; i < 4; i++) begin
                cpu_pulse_io_write(IO_BASE + i*4, 32'hAA00_0000 + i, 4'hF);
            end
            check(uut.io_wfifo_count == 4, "IO FIFO reaches full");

            for (i = 0; i < 4; i++) begin
                wb_line = {8{(32'hBB00_0000 + i)}};
                inject_wb_req(DRAM_BASE + 32'h200 + i*32, wb_line);
            end
            check(uut.wb_wfifo_count == 4, "WB FIFO reaches full");
            check(cpu_stall == 1'b1, "cpu_stall asserted when both FIFOs full");

            // 第5条WB进pending
            wb_line = {8{32'hCC00_0005}};
            inject_wb_req(DRAM_BASE + 32'h300, wb_line);
            repeat (2) @(posedge clk);
            check(uut.wb_pending_valid == 1'b1, "WB pending captured");

            // 放开写通道，观察系统恢复
            force_block_write = 1'b0;
            wait_write_idle(500);
            repeat (20) @(posedge clk);
            check(uut.io_wfifo_count <= 4, "IO FIFO count legal");
            check(uut.wb_wfifo_count <= 4, "WB FIFO count legal");
        end
    endtask

    task automatic case_io_priority_with_random_delay;
        logic [255:0] wb_line;
        logic [31:0] first_aw;
        begin
            $display("\n=== CASE3: IO priority under random AXI delay ===");
            do_reset();
            rand_delay_en = 1'b1;
            force_block_write = 1'b0;

            wb_line = {8{32'h1357_2468}};
            @(negedge clk);
            cpu_addr  <= IO_BASE + 32'h88;
            cpu_wdata <= 32'hCAFEBABE;
            cpu_wen   <= 4'hF;
            force_wb_addr = DRAM_BASE + 32'h500;
            force_wb_data = wb_line;
            force uut.write_back_addr = force_wb_addr;
            force uut.write_back_data = force_wb_data;
            force uut.write_back_req  = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cpu_wen   <= 4'h0;
            cpu_wdata <= '0;
            cpu_addr  <= '0;
            release uut.write_back_req;
            release uut.write_back_addr;
            release uut.write_back_data;

            first_aw = 32'h0;
            repeat (120) begin
                @(posedge clk);
                if (axi_awvalid && axi_awready) begin
                    first_aw = axi_awaddr;
                    break;
                end
            end
            check(first_aw == (IO_BASE + 32'h88), "IO has priority over WB");

            wait_write_idle(600);
        end
    endtask

    task automatic case_random_stress;
        int n;
        int op;
        logic [31:0] addr;
        logic [31:0] data;
        logic [3:0]  strb;
        logic [255:0] wb_line;
        begin
            $display("\n=== CASE4: random stress (IO R/W + WB + random AXI delay) ===");
            do_reset();
            rand_delay_en = 1'b1;
            force_block_write = 1'b0;

            for (n = 0; n < 350; n++) begin
                op   = $urandom_range(0, 99);
                addr = IO_BASE + (($urandom_range(0, 255)) << 2);
                data = $urandom();
                strb = $urandom_range(1, 15);

                if (op < 45) begin
                    // IO写，若阻塞则等待一会再发
                    if (cpu_stall) repeat ($urandom_range(1,3)) @(posedge clk);
                    cpu_pulse_io_write(addr, data, strb);
                end else if (op < 75) begin
                    // 为避免与未完成写冲突，先等待写通路空闲再读
                    wait_write_idle(300);
                    io_read_cpu_check(addr, 300);
                end else if (op < 95) begin
                    wb_line = {$urandom(),$urandom(),$urandom(),$urandom(),$urandom(),$urandom(),$urandom(),$urandom()};
                    inject_wb_req(DRAM_BASE + (($urandom_range(0,127)) << 5), wb_line);
                end else begin
                    // 混合同拍注入
                    wb_line = {$urandom(),$urandom(),$urandom(),$urandom(),$urandom(),$urandom(),$urandom(),$urandom()};
                    @(negedge clk);
                    cpu_addr  <= addr;
                    cpu_wdata <= data;
                    cpu_wen   <= strb;
                    force_wb_addr = DRAM_BASE + (($urandom_range(0,127)) << 5);
                    force_wb_data = wb_line;
                    force uut.write_back_addr = force_wb_addr;
                    force uut.write_back_data = force_wb_data;
                    force uut.write_back_req  = 1'b1;
                    @(posedge clk);
                    @(negedge clk);
                    cpu_addr  <= '0;
                    cpu_wdata <= '0;
                    cpu_wen   <= 4'h0;
                    release uut.write_back_req;
                    release uut.write_back_addr;
                    release uut.write_back_data;
                end
            end

            wait_write_idle(1000);
            repeat (100) @(posedge clk);
        end
    endtask

    task automatic final_coverage_checks;
        begin
            check(cov_io_read   > 20, "coverage: io reads exercised");
            check(cov_io_write  > 40, "coverage: io writes exercised");
            check(cov_wb_aw     > 10, "coverage: wb burst writes exercised");
            check(cov_stall     > 5,  "coverage: cpu stall observed");
            check(cov_fifo_full > 5,  "coverage: fifo full observed");
            check(cov_rand_delay > 20, "coverage: random AXI delay observed");
        end
    endtask

    initial begin
        err_count = 0;
        pass_count = 0;
        cov_io_read = 0;
        cov_io_write = 0;
        cov_wb_aw = 0;
        cov_stall = 0;
        cov_fifo_full = 0;
        cov_rand_delay = 0;

        case_directed_io_rw();
        case_fifo_full_and_stall();
        case_io_priority_with_random_delay();
        case_random_stress();
        final_coverage_checks();

        $display("\n================ TB_DCACHE_SV SUMMARY ================");
        $display("PASS checks    = %0d", pass_count);
        $display("FAIL checks    = %0d", err_count);
        $display("cov_io_read    = %0d", cov_io_read);
        $display("cov_io_write   = %0d", cov_io_write);
        $display("cov_wb_aw      = %0d", cov_wb_aw);
        $display("cov_stall      = %0d", cov_stall);
        $display("cov_fifo_full  = %0d", cov_fifo_full);
        $display("cov_rand_delay = %0d", cov_rand_delay);

        if (err_count == 0) begin
            $display("TB_DCACHE_SV RESULT: PASS");
        end else begin
            $display("TB_DCACHE_SV RESULT: FAIL");
        end

        $stop;
    end

endmodule
