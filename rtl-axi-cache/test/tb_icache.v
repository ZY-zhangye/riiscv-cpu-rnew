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

    localparam RANDOM_CASE1_REQ_NUM = 40;
    localparam RANDOM_CASE2_REQ_NUM = 60;

    // 实例化ICache模块
    icache uut (
        .clk(clk),
        .rst_n(rst_n),
        .if_addr(if_addr),
        .if_ren(if_ren),
        .if_rdata(if_rdata),
        .if_rvalid(if_rvalid),
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

    task access_once_check;
        input [31:0] addr_in;
        input integer expect_refill;
        input [127:0] case_name;
        integer cycle_cnt;
        integer seen_refill;
        integer got_rsp;
        reg [31:0] exp_data;
        begin
            if_addr = addr_in & 32'h0000_3FFC;
            if_ren = 1'b1;
            exp_data = expected_word(if_addr);
            seen_refill = 0;
            got_rsp = 0;
            cycle_cnt = 0;

            while ((got_rsp == 0) && (cycle_cnt < 80)) begin
                @(posedge clk);
                cycle_cnt = cycle_cnt + 1;
                if (refill_req) begin
                    seen_refill = 1;
                end
                if (if_rvalid) begin
                    got_rsp = 1;
                    $display("Time:%0t [%0s] addr=0x%08h data=0x%08h refill_seen=%0d", $time, case_name, if_addr, if_rdata, seen_refill);
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
                end
            end

            if (got_rsp == 0) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] timeout waiting if_rvalid, addr=0x%08h", case_name, if_addr);
            end

            // 拉低一拍，清晰分隔事务
            @(posedge clk);
            if_ren = 1'b0;
        end
    endtask

    task run_directed_hit_tests;
        reg [31:0] base_line;
        begin
            $display("\n========== DIRECTED_HIT_TESTS ==========");
            // 选择低16KB内、32B对齐的line基地址
            base_line = 32'h0000_12A0;

            // A. 同地址重复访问：首次MISS，后续应HIT
            access_once_check(base_line + 32'h0000_0004, 1, "SAME_ADDR_WARMUP_MISS");
            access_once_check(base_line + 32'h0000_0004, 0, "SAME_ADDR_HIT_1");
            access_once_check(base_line + 32'h0000_0004, 0, "SAME_ADDR_HIT_2");

            // B. 同一line内临近地址：都应HIT（line已被warmup）
            access_once_check(base_line + 32'h0000_0000, 0, "NEAR_ADDR_SAME_LINE_HIT_0");
            access_once_check(base_line + 32'h0000_0008, 0, "NEAR_ADDR_SAME_LINE_HIT_8");
            access_once_check(base_line + 32'h0000_001C, 0, "NEAR_ADDR_SAME_LINE_HIT_1C");

            // C. 跨line对照：跨32B边界应MISS，再次访问同line应HIT
            access_once_check(base_line + 32'h0000_0020, 1, "CROSS_LINE_MISS");
            access_once_check(base_line + 32'h0000_0024, 0, "CROSS_LINE_THEN_HIT");

            $display("========== DIRECTED_HIT_TESTS DONE, err_count=%0d ==========", err_count);
        end
    endtask

    task run_random_issue_on_rvalid;
        input integer total_req;
        input [127:0] case_name;
        reg [31:0] next_addr;
        begin
            $display("\n========== %0s ==========" , case_name);
            req_count = 0;
            rsp_count = 0;

            // 先发第一拍请求，后续在if_rvalid高时立刻切换下一个地址
            get_next_rand_addr(next_addr);
            if_addr = next_addr;
            if_ren = 1'b1;
            req_count = 1;
            $display("Time:%0t [REQ%0d] addr=0x%08h", $time, req_count, if_addr);

            // 跑到收齐响应
            while (rsp_count < total_req) begin
                @(posedge clk);
                if (if_rvalid) begin
                    rsp_count = rsp_count + 1;
                    $display("Time:%0t [RSP%0d] addr=0x%08h data=0x%08h", $time, rsp_count, if_addr, if_rdata);

                    // 关键：if_rvalid高时，立刻推出下一个地址（随机）
                    if (req_count < total_req) begin
                        get_next_rand_addr(next_addr);
                        if_addr = next_addr;
                        req_count = req_count + 1;
                        $display("Time:%0t [REQ%0d] addr=0x%08h (issue on if_rvalid)", $time, req_count, if_addr);
                    end else begin
                        if_ren = 1'b0;
                    end
                end
            end

            // 留几个周期观察尾部
            repeat (5) @(posedge clk);
            if_ren = 1'b0;
            $display("========== %0s DONE, req=%0d rsp=%0d ==========" , case_name, req_count, rsp_count);
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
            $display("Time: %0t, Address: 0x%08h, Data: 0x%08h", $time, if_addr, if_rdata);
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