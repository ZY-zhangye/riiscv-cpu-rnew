module tb_data_cache_write;
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
    integer cycle_cnt;

    reg refill_seen;

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

    // 构造一整行回填数据
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

    // 行内单字期望值（回填图案）
    function [31:0] expected_refill_word;
        input [31:0] a;
        begin
            expected_refill_word = (a & 32'hFFFF_FFE0) ^ 32'hA5A5_0000 ^ {27'b0, a[4:2], 2'b00};
        end
    endfunction

    // 按wstrb进行字节合并
    function [31:0] merge_word;
        input [31:0] old_word;
        input [31:0] new_word;
        input [3:0]  strb;
        begin
            merge_word = old_word;
            if (strb[0]) merge_word[7:0]   = new_word[7:0];
            if (strb[1]) merge_word[15:8]  = new_word[15:8];
            if (strb[2]) merge_word[23:16] = new_word[23:16];
            if (strb[3]) merge_word[31:24] = new_word[31:24];
        end
    endfunction

    // 单周期读请求脉冲
    task pulse_read;
        input [31:0] a;
        begin
            @(negedge clk);
            addr = a & 32'h0000_3FFC;
            ren  = 1'b1;
            wen  = 1'b0;
            @(posedge clk);
            @(negedge clk);
            ren  = 1'b0;
        end
    endtask

    // 等待DUT回到空闲，避免流水残留影响当前用例判断
    task wait_idle;
        integer t;
        begin
            t = 0;
            while ((uut.state !== 2'b00) && (t < 80)) begin
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

    // 单周期写请求脉冲（关键要求：仅1拍）
    task pulse_write;
        input [31:0] a;
        input [31:0] d;
        input [3:0]  s;
        begin
            @(negedge clk);
            addr  = a & 32'h0000_3FFC;
            wdata = d;
            wstrb = s;
            ren   = 1'b0;
            wen   = 1'b1;
            @(posedge clk);
            @(negedge clk);
            wen   = 1'b0;
            wdata = 32'b0;
            wstrb = 4'b0;
        end
    endtask

    // 等待读返回并比对
    task wait_read_check;
        input [31:0] exp;
        input [127:0] tag;
        integer t;
        begin
            t = 0;
            while ((rvalid !== 1'b1) && (t < 80)) begin
                @(posedge clk);
                t = t + 1;
            end

            if (rvalid !== 1'b1) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] timeout waiting rvalid", tag);
            end else if (rdata !== exp) begin
                err_count = err_count + 1;
                $display("ERROR [%0s] readback mismatch exp=0x%08h got=0x%08h", tag, exp, rdata);
            end else begin
                $display("PASS  [%0s] readback=0x%08h", tag, rdata);
            end
        end
    endtask

    // 监测给定周期内是否出现refill_req
    task watch_refill_req;
        input integer max_cycle;
        output reg seen;
        integer k;
        begin
            seen = 1'b0;
            for (k = 0; k < max_cycle; k = k + 1) begin
                @(posedge clk);
                if (refill_req) begin
                    seen = 1'b1;
                end
            end
        end
    endtask

    // 自动回填模型：检测到refill_req后，下一拍给refill_valid=1
    always @(posedge clk) begin
        refill_valid <= 1'b0;
        if (refill_req) begin
            refill_data <= build_refill_line(refill_addr);
            refill_valid <= 1'b1;
            $display("Time:%0t REFILL addr=0x%08h", $time, refill_addr);
        end
    end

    initial begin
        rst_n = 1'b0;
        addr = 32'b0;
        ren = 1'b0;
        wen = 1'b0;
        wdata = 32'b0;
        wstrb = 4'b0;
        refill_data = 256'b0;
        refill_valid = 1'b0;
        err_count = 0;
        cycle_cnt = 0;
        refill_seen = 1'b0;

        // 复位
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n========== CASE1: WRITE HIT FULL WORD ==========");
        wait_idle();
        // 先读触发回填，暖线
        pulse_read(32'h0000_1204);
        wait_read_check(expected_refill_word(32'h0000_1204), "C1_WARMUP_READ");

        // 单拍写命中
        wait_idle();
        pulse_write(32'h0000_1204, 32'hDEAD_BEEF, 4'b1111);

        // 回读验证
        wait_idle();
        pulse_read(32'h0000_1204);
        wait_read_check(32'hDEAD_BEEF, "C1_WRITE_HIT_READBACK");

        $display("\n========== CASE2: WRITE HIT BYTE STROBE ==========");
        wait_idle();
        // 同样先确保该line已在cache
        pulse_read(32'h0000_1210);
        wait_read_check(expected_refill_word(32'h0000_1210), "C2_WARMUP_READ");

        // 单拍部分字节写
        wait_idle();
        pulse_write(32'h0000_1210, 32'h1122_3344, 4'b0101);

        // 预期：byte0/byte2被改写，其余保持原值
        wait_idle();
        pulse_read(32'h0000_1210);
        wait_read_check(
            merge_word(expected_refill_word(32'h0000_1210), 32'h1122_3344, 4'b0101),
            "C2_WRITE_STROBE_READBACK"
        );

        $display("\n========== CASE3: WRITE MISS (SINGLE-CYCLE WRITE PULSE) ==========");
        wait_idle();
        // 选冷地址，先发单拍写请求
        pulse_write(32'h0000_2A1C, 32'hCAFE_BABE, 4'b1111);

        // 观察一段时间是否出现回填请求
        watch_refill_req(30, refill_seen);
        if (!refill_seen) begin
            err_count = err_count + 1;
            $display("ERROR [C3_WRITE_MISS] no refill_req seen after single-cycle write miss");
        end else begin
            $display("PASS  [C3_WRITE_MISS] refill_req seen");
        end

        // 回读验证写未命中结果（若设计支持write-allocate，应读回写入值）
        wait_idle();
        pulse_read(32'h0000_2A1C);
        wait_read_check(32'hCAFE_BABE, "C3_WRITE_MISS_READBACK");

        repeat (5) @(posedge clk);

        if (err_count == 0) begin
            $display("\nTB SUMMARY: PASS (err_count=%0d)", err_count);
        end else begin
            $display("\nTB SUMMARY: FAIL (err_count=%0d)", err_count);
        end

        $stop;
    end

    always @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;
        if (rvalid) begin
            $display("Time:%0t RVALID data=0x%08h", $time, rdata);
        end
        if (write_back_req) begin
            $display("Time:%0t WRITE_BACK addr=0x%08h", $time, write_back_addr);
        end
    end

endmodule
