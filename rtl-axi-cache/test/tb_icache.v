module tb_icache;
    reg clk;
    reg rst_n;
    reg [31:0] if_addr;
    reg if_ren;
    wire [31:0] if_rdata;
    wire if_rvalid;
    wire refill_req;
    wire [31:0] refill_addr;
    reg [255:0] refill_data;
    reg refill_valid;
    integer req_count;
    integer rsp_count;
    integer err_count;
    reg [31:0] lfsr_state;

    reg wen;
    reg [31:0] wdata;
    reg [3:0] wstrb;

    localparam RANDOM_CASE1_REQ_NUM = 40;
    localparam RANDOM_CASE2_REQ_NUM = 60;

    // 实例化ICache模块
    data_cache uut (
        .clk(clk),
        .rst_n(rst_n),
        .addr(if_addr),
        .ren(if_ren),
        .wen(wen),
        .wdata(wdata),
        .wstrb(wstrb),
        .rdata(if_rdata),
        .rvalid(if_rvalid),
        .refill_req(refill_req),
        .refill_addr(refill_addr),
        .refill_data(refill_data),
        .refill_valid(refill_valid)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz时钟
    end
    initial begin
        wen = 0;
        wdata = 32'b0;
        wstrb = 4'b0;
    end

    // 构造一整行回填数据：每个32bit字都可从地址推导，便于观察
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

    // 单字期望值（与build_refill_line一致）
    function [31:0] expected_word;
        input [31:0] addr;
        begin
            expected_word = (addr & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ {27'b0, addr[4:2], 2'b00};
        end
    endfunction

    // 简单LFSR随机源（x^32 + x^22 + x^2 + x + 1）
    task get_next_rand_addr;
        output [31:0] addr_out;
        reg feedback;
        begin
            feedback   = lfsr_state[31] ^ lfsr_state[21] ^ lfsr_state[1] ^ lfsr_state[0];
            lfsr_state = {lfsr_state[30:0], feedback};
            if (lfsr_state == 32'b0) begin
                lfsr_state = 32'h1ACE_B00C;
            end
            // 地址范围限制在低16KB（cache容量），且4字节对齐
            addr_out = lfsr_state & 32'h0000_3FFC;
        end
    endtask

    // 单拍请求（if_stage风格）：if_ren仅拉高1个周期
    task issue_req_pulse;
        input [31:0] addr_in;
        begin
            @(negedge clk);
            if_addr = addr_in & 32'h0000_3FFC;
            if_ren  = 1'b1;
            @(posedge clk); // 请求在该上升沿被采样
            @(negedge clk);
            if_ren  = 1'b0;
        end
    endtask

    // 发一个请求并检查返回
    task access_once_check;
        input [31:0] addr_in;
        input integer expect_refill;
        input integer expect_hit_1cyc;
        input [127:0] case_name;
        integer cycle_cnt;
        integer seen_refill;
        integer got_rsp;
        integer rsp_latency;
        reg [31:0] req_addr;
        reg [31:0] exp_data;
        begin
            req_addr = addr_in & 32'h0000_3FFC;
            exp_data = expected_word(req_addr);
            seen_refill = 0;
            got_rsp = 0;
            cycle_cnt = 0;
            rsp_latency = -1;

            issue_req_pulse(req_addr);

            while ((got_rsp == 0) && (cycle_cnt < 80)) begin
                @(posedge clk);
                cycle_cnt = cycle_cnt + 1;
                if (refill_req) begin
                    seen_refill = 1;
                end
                if (if_rvalid) begin
                    got_rsp = 1;
                    rsp_latency = cycle_cnt;
                    $display("Time:%0t [%0s] req=0x%08h data=0x%08h refill_seen=%0d latency=%0d", $time, case_name, req_addr, if_rdata, seen_refill, rsp_latency);
                    if (if_rdata !== exp_data) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] data mismatch! exp=0x%08h got=0x%08h", case_name, exp_data, if_rdata);
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
                $display("ERROR [%0s] timeout waiting if_rvalid, req=0x%08h", case_name, req_addr);
            end
        end
    endtask

    task run_directed_hit_tests;
        reg [31:0] base_line;
        begin
            $display("\n========== DIRECTED_HIT_TESTS ==========");
            // 选择低16KB内、32B对齐的line基地址
            base_line = 32'h0000_12A0;

            // A. 同地址重复访问：首次MISS，后续应HIT
            access_once_check(base_line + 32'h0000_0004, 1, 0, "SAME_ADDR_WARMUP_MISS");
            access_once_check(base_line + 32'h0000_0004, 0, 1, "SAME_ADDR_HIT_1");
            access_once_check(base_line + 32'h0000_0004, 0, 1, "SAME_ADDR_HIT_2");

            // B. 同一line内临近地址：都应HIT（line已被warmup）
            access_once_check(base_line + 32'h0000_0000, 0, 1, "NEAR_ADDR_SAME_LINE_HIT_0");
            access_once_check(base_line + 32'h0000_0008, 0, 1, "NEAR_ADDR_SAME_LINE_HIT_8");
            access_once_check(base_line + 32'h0000_001C, 0, 1, "NEAR_ADDR_SAME_LINE_HIT_1C");

            // C. 跨line对照：跨32B边界应MISS，再次访问同line应HIT
            access_once_check(base_line + 32'h0000_0020, 1, 0, "CROSS_LINE_MISS");
            access_once_check(base_line + 32'h0000_0024, 0, 1, "CROSS_LINE_THEN_HIT");

            $display("========== DIRECTED_HIT_TESTS DONE, err_count=%0d ==========", err_count);
        end
    endtask

    task run_random_issue_on_rvalid;
        input integer total_req;
        input [127:0] case_name;
        reg [31:0] next_addr;
        reg [31:0] req_addr_q;
        integer waiting_rsp;
        integer latency_cnt;
        begin
            $display("\n========== %0s ==========" , case_name);
            req_count = 0;
            rsp_count = 0;
            waiting_rsp = 0;
            latency_cnt = 0;

            while (rsp_count < total_req) begin
                // 若无在途请求，则发一个单拍请求
                if (waiting_rsp == 0 && req_count < total_req) begin
                    get_next_rand_addr(next_addr);
                    req_addr_q = next_addr;
                    issue_req_pulse(req_addr_q);
                    req_count = req_count + 1;
                    waiting_rsp = 1;
                    latency_cnt = 0;
                    $display("Time:%0t [REQ%0d] addr=0x%08h", $time, req_count, req_addr_q);
                end

                @(posedge clk);
                if (waiting_rsp) begin
                    latency_cnt = latency_cnt + 1;
                end

                if (if_rvalid) begin
                    rsp_count = rsp_count + 1;
                    $display("Time:%0t [RSP%0d] req=0x%08h data=0x%08h latency=%0d", $time, rsp_count, req_addr_q, if_rdata, latency_cnt);
                    if (if_rdata !== expected_word(req_addr_q)) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] random data mismatch req=0x%08h exp=0x%08h got=0x%08h", case_name, req_addr_q, expected_word(req_addr_q), if_rdata);
                    end
                    waiting_rsp = 0;
                end
            end

            repeat (5) @(posedge clk);
            $display("========== %0s DONE, req=%0d rsp=%0d ==========" , case_name, req_count, rsp_count);
        end
    endtask

    // 连续命中流测试：每拍发起新请求，期望下一拍返回上一条结果
    task run_back_to_back_hit_stream;
        input integer total_req;
        input [127:0] case_name;
        reg [31:0] base_line;
        reg [31:0] curr_addr;
        reg [31:0] prev_addr;
        integer k;
        integer seen_refill;
        begin
            $display("\n========== %0s ==========" , case_name);

            // 先暖一条line，确保后续流请求全命中
            base_line = 32'h0000_1C40;
            access_once_check(base_line + 32'h0000_0000, 1, 0, "B2B_WARMUP_MISS");

            prev_addr = 32'b0;
            seen_refill = 0;

            for (k = 0; k < total_req; k = k + 1) begin
                curr_addr = base_line + {27'b0, k[2:0], 2'b00};

                @(negedge clk);
                if_addr = curr_addr;
                if_ren  = 1'b1;

                @(posedge clk);

                if (refill_req) begin
                    seen_refill = 1;
                end

                // 从第2拍开始，上一条请求应当在当前拍返回
                if (k > 0) begin
                    if (!if_rvalid) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] expected if_rvalid=1 at cycle %0d", case_name, k);
                    end else if (if_rdata !== expected_word(prev_addr)) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] pipeline data mismatch at cycle %0d exp=0x%08h got=0x%08h", case_name, k, expected_word(prev_addr), if_rdata);
                    end
                end

                prev_addr = curr_addr;
            end

            // 结束流后撤销请求，检查最后一条返回
            @(negedge clk);
            if_ren = 1'b0;

            @(posedge clk);
            if (!if_rvalid) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] expected last response valid after stream", case_name);
            end else if (if_rdata !== expected_word(prev_addr)) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] last response mismatch exp=0x%08h got=0x%08h", case_name, expected_word(prev_addr), if_rdata);
            end

            if (seen_refill) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] unexpected refill_req during hit stream", case_name);
            end

            repeat (2) @(posedge clk);
            $display("========== %0s DONE ==========" , case_name);
        end
    endtask

    // SV风格用例：连续命中流中周期性插入跨line MISS，并打印统计
    task automatic run_hit_stream_with_periodic_miss_sv;
        input int blocks;
        input int hit_per_block;
        input string case_name;
        reg [31:0] hit_base;
        reg [31:0] miss_base;
        reg [31:0] curr_addr;
        reg [31:0] prev_addr;
        reg [31:0] miss_addr;
        bit prev_valid;
        int blk;
        int h;
        int total_hit_req;
        int total_miss_req;
        int total_rsp;
        begin
            $display("\n========== %0s ==========" , case_name);

            hit_base = 32'h0000_1D00;
            miss_base = 32'h0000_3000;
            total_hit_req = 0;
            total_miss_req = 0;
            total_rsp = 0;

            // 预热命中line
            access_once_check(hit_base + 32'h0000_0000, 1, 0, "SV_WARMUP_HIT_LINE");

            for (blk = 0; blk < blocks; blk = blk + 1) begin
                prev_valid = 0;

                // 1) 命中连续流：每拍发一条
                for (h = 0; h < hit_per_block; h = h + 1) begin
                    curr_addr = hit_base + {27'b0, h[2:0], 2'b00};

                    @(negedge clk);
                    if_addr = curr_addr;
                    if_ren  = 1'b1;

                    @(posedge clk);
                    if (refill_req) begin
                        err_count = err_count + 1;
                        $display("ERROR [%0s] unexpected refill in hit burst blk=%0d h=%0d", case_name, blk, h);
                    end

                    if (prev_valid) begin
                        if (!if_rvalid) begin
                            err_count = err_count + 1;
                            $display("ERROR [%0s] missing pipelined response blk=%0d h=%0d", case_name, blk, h);
                        end else if (if_rdata !== expected_word(prev_addr)) begin
                            err_count = err_count + 1;
                            $display("ERROR [%0s] pipelined data mismatch blk=%0d h=%0d exp=0x%08h got=0x%08h", case_name, blk, h, expected_word(prev_addr), if_rdata);
                        end
                    end

                    prev_addr = curr_addr;
                    prev_valid = 1'b1;
                    total_hit_req = total_hit_req + 1;
                end

                // 2) 冲刷命中流最后一条返回
                @(negedge clk);
                if_ren = 1'b0;
                @(posedge clk);
                if (!if_rvalid) begin
                    err_count = err_count + 1;
                    $display("ERROR [%0s] missing tail response of hit burst blk=%0d", case_name, blk);
                end else if (if_rdata !== expected_word(prev_addr)) begin
                    err_count = err_count + 1;
                    $display("ERROR [%0s] tail response mismatch blk=%0d exp=0x%08h got=0x%08h", case_name, blk, expected_word(prev_addr), if_rdata);
                end
                total_rsp = total_rsp + hit_per_block;

                // 3) 周期性插入跨line MISS（每个block一次）
                miss_addr = (miss_base + (blk << 5)) & 32'h0000_3FE0;
                access_once_check(miss_addr + 32'h0000_0010, 1, 0, "SV_PERIODIC_MISS");
                total_miss_req = total_miss_req + 1;
                total_rsp = total_rsp + 1;
            end

            $display("[%0s] SUMMARY: blocks=%0d, hit_per_block=%0d, hit_req=%0d, miss_req=%0d, total_rsp=%0d, err_count=%0d",
                     case_name, blocks, hit_per_block, total_hit_req, total_miss_req, total_rsp, err_count);
            $display("========== %0s DONE ==========" , case_name);
        end
    endtask

    // 测试流程
    initial begin
        rst_n = 0;
        if_addr = 0;
        if_ren = 0;
        refill_data = 0;
        refill_valid = 0;
        lfsr_state = 32'h20260325;
        err_count = 0;

        req_count = 0;
        rsp_count = 0;

        // 复位ICache
        #20 rst_n = 1;
        repeat (2) @(posedge clk);

        // 用例0：定向命中测试（同地址 + 临近地址 + 跨line对照）
        run_directed_hit_tests();

        // 用例0.5：连续每拍请求（命中流水）
        run_back_to_back_hit_stream(16, "CASE0P5_BACK_TO_BACK_HIT_STREAM");

        // 用例0.75：SV风格命中流夹杂周期性MISS
        run_hit_stream_with_periodic_miss_sv(4, 8, "CASE0P75_SV_PERIODIC_MISS_STREAM");

        // 用例1：中等长度随机请求，if_rvalid高时立刻换下一个地址
        run_random_issue_on_rvalid(RANDOM_CASE1_REQ_NUM, "CASE1_RANDOM_ON_RVALID");

        // 用例2：更长随机流，进一步压测状态切换
        run_random_issue_on_rvalid(RANDOM_CASE2_REQ_NUM, "CASE2_LONG_RANDOM_ON_RVALID");

        // 等待一段时间观察输出
        #100;

        if (err_count == 0) begin
            $display("\nTB SUMMARY: PASS (err_count=%0d)", err_count);
        end else begin
            $display("\nTB SUMMARY: FAIL (err_count=%0d)", err_count);
        end

        $stop;
    end
    always @(posedge clk) begin
        if (if_rvalid) begin
            $display("Time: %0t, Data: 0x%08h", $time, if_rdata);
        end
    end
    always @(posedge clk) begin
        if (refill_req) begin
            $display("Time: %0t, Refill Request for Address: 0x%08h", $time, refill_addr);
            // 模拟AXI总线返回数据
            refill_data <= build_refill_line(refill_addr);
            refill_valid <= 1'b1;
        end else begin
            refill_valid <= 1'b0;
        end
    end
endmodule