module tb_data_cache;
    reg clk;
    reg rst_n;

    reg  [31:0] addr;
    reg         ren;
    reg         wen;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;

    wire [31:0] rdata;
    wire        rvalid;
    wire        refill_req;
    wire [31:0] refill_addr;
    reg  [255:0] refill_data;
    reg         refill_valid;

    wire        write_back_req;
    wire [31:0] write_back_addr;
    wire [255:0] write_back_data;

    integer err_count;
    integer req_count;
    integer rsp_count;
    reg [31:0] lfsr_state;

    localparam MEM_BYTES = 16384; // 16KB
    reg [7:0] mem [0:MEM_BYTES-1];

    reg refill_req_d;
    reg refill_pending;
    reg [31:0] refill_pending_addr;

    integer i;

    // DUT
    data_cache uut (
        .clk(clk),
        .rst_n(rst_n),
        .addr(addr),
        .ren(ren),
        .wen(wen),
        .wdata(wdata),
        .wstrb(wstrb),
        .rdata(rdata),
        .rvalid(rvalid),
        .refill_req(refill_req),
        .refill_addr(refill_addr),
        .refill_data(refill_data),
        .refill_valid(refill_valid),
        .write_back_req(write_back_req),
        .write_back_addr(write_back_addr),
        .write_back_data(write_back_data)
    );

    // 100MHz
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // 地址限制在16KB且4字节对齐
    function [31:0] norm_addr;
        input [31:0] a;
        begin
            norm_addr = a & 32'h0000_3FFC;
        end
    endfunction

    // LFSR随机
    task get_next_rand;
        output [31:0] rnd;
        reg feedback;
        begin
            feedback   = lfsr_state[31] ^ lfsr_state[21] ^ lfsr_state[1] ^ lfsr_state[0];
            lfsr_state = {lfsr_state[30:0], feedback};
            if (lfsr_state == 32'b0) begin
                lfsr_state = 32'h1ACE_B00C;
            end
            rnd = lfsr_state;
        end
    endtask

    function [31:0] model_read_word;
        input [31:0] a;
        integer idx;
        begin
            idx = {a[13:2], 2'b00};
            model_read_word = {mem[idx+3], mem[idx+2], mem[idx+1], mem[idx+0]};
        end
    endfunction

    task model_write_word;
        input [31:0] a;
        input [31:0] d;
        input [3:0] s;
        integer idx;
        begin
            idx = {a[13:2], 2'b00};
            if (s[0]) mem[idx+0] = d[7:0];
            if (s[1]) mem[idx+1] = d[15:8];
            if (s[2]) mem[idx+2] = d[23:16];
            if (s[3]) mem[idx+3] = d[31:24];
        end
    endtask

    task model_write_line;
        input [31:0] base_addr;
        input [255:0] line_data;
        integer base;
        integer k;
        begin
            base = {base_addr[13:5], 5'b0};
            for (k = 0; k < 32; k = k + 1) begin
                mem[base + k] = line_data[k*8 +: 8];
            end
        end
    endtask

    function [255:0] build_refill_line;
        input [31:0] base_addr;
        begin
            build_refill_line[31:0]    = model_read_word(base_addr + 32'h0);
            build_refill_line[63:32]   = model_read_word(base_addr + 32'h4);
            build_refill_line[95:64]   = model_read_word(base_addr + 32'h8);
            build_refill_line[127:96]  = model_read_word(base_addr + 32'hC);
            build_refill_line[159:128] = model_read_word(base_addr + 32'h10);
            build_refill_line[191:160] = model_read_word(base_addr + 32'h14);
            build_refill_line[223:192] = model_read_word(base_addr + 32'h18);
            build_refill_line[255:224] = model_read_word(base_addr + 32'h1C);
        end
    endfunction

    task wait_idle;
        integer t;
        begin
            t = 0;
            while ((uut.state !== 2'b00) && (t < 120)) begin
                @(posedge clk);
                t = t + 1;
            end
            if (uut.state !== 2'b00) begin
                err_count = err_count + 1;
                $display("ERROR [WAIT_IDLE] timeout waiting DUT IDLE");
            end
            @(posedge clk);
        end
    endtask

    task pulse_read;
        input [31:0] a;
        begin
            @(negedge clk);
            addr  = norm_addr(a);
            ren   = 1'b1;
            wen   = 1'b0;
            wdata = 32'b0;
            wstrb = 4'b0;
            @(posedge clk);
            @(negedge clk);
            ren = 1'b0;
            req_count = req_count + 1;
        end
    endtask

    task pulse_write;
        input [31:0] a;
        input [31:0] d;
        input [3:0] s;
        begin
            @(negedge clk);
            addr  = norm_addr(a);
            ren   = 1'b0;
            wen   = 1'b1;
            wdata = d;
            wstrb = s;
            @(posedge clk);
            @(negedge clk);
            wen   = 1'b0;
            wdata = 32'b0;
            wstrb = 4'b0;
            req_count = req_count + 1;
        end
    endtask

    task read_check;
        input [31:0] a;
        input [127:0] tag;
        reg [31:0] exp;
        integer t;
        begin
            exp = model_read_word(norm_addr(a));
            pulse_read(a);

            t = 0;
            while ((rvalid !== 1'b1) && (t < 120)) begin
                @(posedge clk);
                t = t + 1;
            end

            if (rvalid !== 1'b1) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] timeout waiting rvalid", tag);
            end else if (rdata !== exp) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] data mismatch addr=0x%08h exp=0x%08h got=0x%08h", tag, norm_addr(a), exp, rdata);
            end else begin
                rsp_count = rsp_count + 1;
                $display("PASS  [%0s] addr=0x%08h data=0x%08h", tag, norm_addr(a), rdata);
            end
        end
    endtask

    task write_then_check;
        input [31:0] a;
        input [31:0] d;
        input [3:0] s;
        input [127:0] tag;
        begin
            pulse_write(a, d, s);
            model_write_word(norm_addr(a), d, s);
            wait_idle();
            read_check(a, tag);
        end
    endtask

    task run_directed_read_tests;
        reg [31:0] base;
        begin
            $display("\n========== CASE0_DIRECTED_READ ==========");
            base = 32'h0000_1200;
            read_check(base + 32'h4,  "R_WARMUP_MISS");
            read_check(base + 32'h4,  "R_SAME_ADDR_HIT");
            read_check(base + 32'h0,  "R_SAME_LINE_HIT0");
            read_check(base + 32'h1C, "R_SAME_LINE_HIT1C");
            read_check(base + 32'h20, "R_CROSS_LINE_MISS");
            read_check(base + 32'h24, "R_CROSS_LINE_HIT");
        end
    endtask

    task run_directed_write_tests;
        reg [31:0] a0;
        reg [31:0] a1;
        reg [31:0] a2;
        begin
            $display("\n========== CASE1_DIRECTED_WRITE ==========");
            a0 = 32'h0000_2210;
            a1 = 32'h0000_2A1C;
            a2 = 32'h0000_2B08;

            // 写命中全字
            read_check(a0, "W_HIT_WARMUP");
            wait_idle();
            write_then_check(a0, 32'hDEAD_BEEF, 4'b1111, "W_HIT_FULLWORD");

            // 写命中部分字节（逐种掩码）
            write_then_check(a0, 32'h1122_3344, 4'b0001, "W_HIT_STRB_0001");
            write_then_check(a0, 32'h5566_7788, 4'b0010, "W_HIT_STRB_0010");
            write_then_check(a0, 32'h99AA_BBCC, 4'b0100, "W_HIT_STRB_0100");
            write_then_check(a0, 32'hDDEE_FF00, 4'b1000, "W_HIT_STRB_1000");
            write_then_check(a0, 32'hA1B2_C3D4, 4'b0101, "W_HIT_STRB_0101");
            write_then_check(a0, 32'h1234_5678, 4'b1111, "W_HIT_STRB_1111");

            // 写未命中（单拍写）
            wait_idle();
            write_then_check(a1, 32'hCAFE_BABE, 4'b1111, "W_MISS_ALLOCATE");

            // 写未命中 + 部分字节写（重点覆盖）
            wait_idle();
            write_then_check(a2, 32'h89AB_CDEF, 4'b0101, "W_MISS_STRB_0101");
        end
    endtask

    task run_conflict_replacement_tests;
        reg [31:0] a [0:4];
        integer k;
        begin
            $display("\n========== CASE2_CONFLICT_REPLACEMENT ==========");
            // 同index(11:5相同)，不同tag地址，触发替换路径
            a[0] = 32'h0000_0010;
            a[1] = 32'h0000_1010;
            a[2] = 32'h0000_2010;
            a[3] = 32'h0000_3010;
            a[4] = 32'h0000_4010;

            for (k = 0; k < 5; k = k + 1) begin
                read_check(a[k], "CFR_READ_FILL");
                wait_idle();
                write_then_check(a[k], 32'h1000_0000 + k, 4'b1111, "CFR_WRITE_VERIFY");
            end

            // 回头再读一轮，覆盖替换后命中/未命中恢复
            for (k = 0; k < 5; k = k + 1) begin
                wait_idle();
                read_check(a[k], "CFR_REREAD");
            end
        end
    endtask

    task run_random_mixed_tests;
        input integer total_ops;
        integer n;
        reg [31:0] ra;
        reg [31:0] rd;
        reg [31:0] rs;
        begin
            $display("\n========== CASE3_RANDOM_MIXED_RW ==========");
            for (n = 0; n < total_ops; n = n + 1) begin
                get_next_rand(ra);
                ra = norm_addr(ra);
                get_next_rand(rd);
                get_next_rand(rs);

                if (rs[0]) begin
                    // write
                    // 随机压测中固定全字写，减少噪声；部分字节写由定向用例覆盖
                    pulse_write(ra, rd, 4'b1111);
                    model_write_word(ra, rd, 4'b1111);

                    // 50%概率立刻回读验证
                    if (rs[1]) begin
                        wait_idle();
                        read_check(ra, "RAND_WRITE_THEN_READ");
                    end
                end else begin
                    // read
                    read_check(ra, "RAND_READ");
                end

                wait_idle();
            end
        end
    endtask

    // 连续读命中流：每拍发起一个读请求，期望下一拍返回上一条读数据（仿if_cache连续取指风格）
    task run_back_to_back_read_hit_stream;
        input integer total_req;
        reg [31:0] base;
        reg [31:0] curr_addr;
        reg [31:0] prev_addr;
        integer k;
        reg seen_refill;
        begin
            $display("\n========== CASE4_B2B_READ_HIT_STREAM ==========");
            base = 32'h0000_1C40;
            seen_refill = 1'b0;

            // 先预热一条line，后续请求应全部命中
            read_check(base + 32'h0, "B2B_R_WARMUP");
            wait_idle();

            for (k = 0; k < total_req; k = k + 1) begin
                curr_addr = base + {27'b0, k[2:0], 2'b00};

                @(negedge clk);
                addr  = curr_addr;
                ren   = 1'b1;
                wen   = 1'b0;
                wdata = 32'b0;
                wstrb = 4'b0;

                @(posedge clk);
                req_count = req_count + 1;
                if (refill_req) seen_refill = 1'b1;

                // 从第2拍开始，上一拍读请求应在当前拍返回
                if (k > 0) begin
                    if (!rvalid) begin
                        err_count = err_count + 1;
                        $display("ERROR [B2B_READ] missing pipelined rvalid at k=%0d", k);
                    end else if (rdata !== model_read_word(prev_addr)) begin
                        err_count = err_count + 1;
                        $display("ERROR [B2B_READ] data mismatch at k=%0d exp=0x%08h got=0x%08h", k, model_read_word(prev_addr), rdata);
                    end else begin
                        rsp_count = rsp_count + 1;
                    end
                end

                prev_addr = curr_addr;
            end

            // 结束流后检查最后一条返回
            @(negedge clk);
            ren = 1'b0;
            @(posedge clk);
            if (!rvalid) begin
                err_count = err_count + 1;
                $display("ERROR [B2B_READ] missing last response");
            end else if (rdata !== model_read_word(prev_addr)) begin
                err_count = err_count + 1;
                $display("ERROR [B2B_READ] last response mismatch exp=0x%08h got=0x%08h", model_read_word(prev_addr), rdata);
            end else begin
                rsp_count = rsp_count + 1;
            end

            if (seen_refill) begin
                err_count = err_count + 1;
                $display("ERROR [B2B_READ] unexpected refill_req during hit stream");
            end

            wait_idle();
        end
    endtask

    // 连续读写交替流：本拍写、下拍读（单拍请求），并检查读返回是否正确
    task run_back_to_back_rw_alternate_stream;
        input integer pairs;
        reg [31:0] base;
        reg [31:0] wr_addr;
        reg [31:0] rd_addr;
        reg [31:0] wr_data;
        reg prev_was_read;
        integer p;
        reg seen_refill;
        begin
            $display("\n========== CASE5_B2B_RW_ALTERNATE_STREAM ==========");
            base = 32'h0000_1D00;
            seen_refill = 1'b0;
            prev_was_read = 1'b0;

            // 预热line
            read_check(base + 32'h0, "B2B_RW_WARMUP");
            wait_idle();

            for (p = 0; p < pairs; p = p + 1) begin
                wr_addr = base + {27'b0, p[2:0], 2'b00};
                wr_data = 32'hA500_0000 + p;

                // cycle A: write pulse
                @(negedge clk);
                addr  = wr_addr;
                ren   = 1'b0;
                wen   = 1'b1;
                wdata = wr_data;
                wstrb = 4'b1111;
                model_write_word(wr_addr, wr_data, 4'b1111);

                @(posedge clk);
                req_count = req_count + 1;
                if (refill_req) seen_refill = 1'b1;
                if (prev_was_read) begin
                    if (!rvalid) begin
                        err_count = err_count + 1;
                        $display("ERROR [B2B_RW] missing read response on write cycle p=%0d", p);
                    end else begin
                        rsp_count = rsp_count + 1;
                    end
                end
                prev_was_read = 1'b0;

                // cycle B: read pulse (读刚写的位置)
                rd_addr = wr_addr;
                @(negedge clk);
                addr  = rd_addr;
                ren   = 1'b1;
                wen   = 1'b0;
                wdata = 32'b0;
                wstrb = 4'b0;

                @(posedge clk);
                req_count = req_count + 1;
                if (refill_req) seen_refill = 1'b1;
                prev_was_read = 1'b1;
            end

            // 收尾：最后一条读响应
            @(negedge clk);
            ren = 1'b0;
            wen = 1'b0;
            @(posedge clk);
            if (prev_was_read) begin
                if (!rvalid) begin
                    err_count = err_count + 1;
                    $display("ERROR [B2B_RW] missing tail read response");
                end else begin
                    rsp_count = rsp_count + 1;
                end
            end

            if (seen_refill) begin
                err_count = err_count + 1;
                $display("ERROR [B2B_RW] unexpected refill_req during hit stream");
            end

            // 最终一致性检查：所有交替写入位置都应可读回最新值
            for (p = 0; p < pairs; p = p + 1) begin
                wr_addr = base + {27'b0, p[2:0], 2'b00};
                read_check(wr_addr, "B2B_RW_FINAL_CHECK");
            end

            wait_idle();
        end
    endtask

    // 协议与存储模型驱动
    always @(posedge clk) begin
        refill_valid <= 1'b0;

        // refill_req必须为单拍
        if (rst_n && refill_req && refill_req_d) begin
            err_count <= err_count + 1;
            $display("ERROR [PROTO] refill_req is not single-cycle pulse");
        end
        refill_req_d <= refill_req;

        // 写回到内存模型（若DUT触发）
        if (write_back_req) begin
            model_write_line(write_back_addr, write_back_data);
            $display("Time:%0t WRITE_BACK addr=0x%08h", $time, write_back_addr);
        end

        // 请求后一拍返回refill_valid
        if (refill_pending) begin
            refill_data <= build_refill_line(refill_pending_addr);
            refill_valid <= 1'b1;
            refill_pending <= 1'b0;
            $display("Time:%0t REFILL addr=0x%08h", $time, refill_pending_addr);
        end

        if (refill_req) begin
            refill_pending <= 1'b1;
            refill_pending_addr <= refill_addr;
        end

        if (rvalid) begin
            $display("Time:%0t RVALID data=0x%08h", $time, rdata);
        end
    end

    initial begin
        // init mem pattern
        for (i = 0; i < MEM_BYTES; i = i + 1) begin
            mem[i] = (i[7:0] ^ 8'h5A);
        end

        rst_n = 1'b0;
        addr = 32'b0;
        ren = 1'b0;
        wen = 1'b0;
        wdata = 32'b0;
        wstrb = 4'b0;
        refill_data = 256'b0;
        refill_valid = 1'b0;
        refill_req_d = 1'b0;
        refill_pending = 1'b0;
        refill_pending_addr = 32'b0;
        err_count = 0;
        req_count = 0;
        rsp_count = 0;
        lfsr_state = 32'h20260331;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_directed_read_tests();
        wait_idle();

        run_directed_write_tests();
        wait_idle();

        run_conflict_replacement_tests();
        wait_idle();

        run_back_to_back_read_hit_stream(16);
        wait_idle();

        run_back_to_back_rw_alternate_stream(12);
        wait_idle();

        run_random_mixed_tests(120);
        wait_idle();

        repeat (10) @(posedge clk);

        $display("\n========== TB SUMMARY ==========");
        $display("req_count=%0d, rsp_count=%0d, err_count=%0d", req_count, rsp_count, err_count);

        if (err_count == 0) begin
            $display("TB SUMMARY: PASS");
        end else begin
            $display("TB SUMMARY: FAIL");
        end

        $stop;
    end

endmodule
