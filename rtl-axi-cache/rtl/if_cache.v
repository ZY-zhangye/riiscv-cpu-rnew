module if_cache (
    input wire clk,
    input wire rst_n,
    input wire [31:0] if_addr,
    input wire if_ren,
    output reg [31:0] if_rdata,
    output reg if_rvalid,
    // 接往AXI总线的信号，由另外的模块负责连接
    output reg refill_req,
    output reg [31:0] refill_addr,
    input wire [255:0] refill_data,
    input wire refill_valid
);

    //定义cache_tag和cache_data的接口信号及地址解析
    wire [255:0] cache_data_out [0:3]; // 四路组相联，每路32字
    wire [31:0] cache_tag_out [0:3]; // 四路组相联，每路32位
    wire cache_valid_out [0:3]; // 四路组相联，每路有效位
    reg [255:0] cache_data_in; // 写入数据
    reg [32:0] cache_tag_in; // 写入标签（32位标签+1位有效位）
    reg cache_data_wen [0:3]; // 写使能信号
    reg cache_tag_wen [0:3]; // 写使能信号
    // RAM读取索引：支持命中流水时预取下一条请求地址
    wire [6:0] index;
    reg [1:0] lru [0:127]; // 存储LRU信息，128行，每行2位
    reg [3:0] hit_way; // 命中路，4位表示4路组相联
    reg any_hit; // 是否命中

    // ICache状态机与请求锁存（if_stage风格：单在途请求）
    localparam IDLE = 2'b00;
    localparam LOOKUP = 2'b01;
    localparam MISS = 2'b10;
    reg [1:0] state, state_next;

    reg [31:0] req_addr;     // 当前在途请求地址（LOOKUP使用）
    reg [31:0] miss_addr;    // MISS回填地址
    integer i;

    wire [6:0] req_index = req_addr[11:5];
    wire [2:0] req_offset = req_addr[4:2];
    wire [19:0] req_tag = req_addr[31:12];
    wire [6:0] miss_index = miss_addr[11:5];
    wire [2:0] miss_offset = miss_addr[4:2];
    wire [19:0] miss_tag = miss_addr[31:12];

    assign index = (state == IDLE) ? if_addr[11:5] :
                   (state == MISS) ? ((refill_valid && if_ren) ? if_addr[11:5] : miss_index) :
                                     ((any_hit && if_ren) ? if_addr[11:5] : req_index);


    // 实例化cache_tag和cache_data模块
    cache_data cache_data1 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .data_out(cache_data_out[0]),
        .data_in(cache_data_in),
        .write_en(cache_data_wen[0])
    );
    cache_data cache_data2 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .data_out(cache_data_out[1]),
        .data_in(cache_data_in),
        .write_en(cache_data_wen[1])
    );
    cache_data cache_data3 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .data_out(cache_data_out[2]),
        .data_in(cache_data_in),
        .write_en(cache_data_wen[2])
    );
    cache_data cache_data4 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .data_out(cache_data_out[3]),
        .data_in(cache_data_in),
        .write_en(cache_data_wen[3])
    );

    cache_tag cache_tag1 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .tag_out({cache_valid_out[0], cache_tag_out[0]}),
        .tag_in(cache_tag_in),
        .write_en(cache_tag_wen[0])
    );
    cache_tag cache_tag2 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .tag_out({cache_valid_out[1], cache_tag_out[1]}),
        .tag_in(cache_tag_in),
        .write_en(cache_tag_wen[1])
    );
    cache_tag cache_tag3 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .tag_out({cache_valid_out[2], cache_tag_out[2]}),
        .tag_in(cache_tag_in),
        .write_en(cache_tag_wen[2])
    );
    cache_tag cache_tag4 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .tag_out({cache_valid_out[3], cache_tag_out[3]}),
        .tag_in(cache_tag_in),
        .write_en(cache_tag_wen[3])
    );

    // 状态机转移逻辑（组合逻辑）
    always @(*) begin
        case (state)
            IDLE: begin
                if (if_ren) begin
                    state_next = LOOKUP;
                end else begin
                    state_next = IDLE;
                end
            end
            LOOKUP: begin
                if (any_hit && if_ren) begin
                    state_next = LOOKUP;
                end else if (any_hit) begin
                    state_next = IDLE;
                end else begin
                    state_next = MISS;
                end
            end
            MISS: begin
                if (refill_valid) begin
                    if (if_ren) begin
                        state_next = LOOKUP;
                    end else begin
                        state_next = IDLE;
                    end
                end else begin
                    state_next = MISS;
                end
            end
            default: state_next = IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            req_addr <= 32'b0;
            miss_addr <= 32'b0;
            for (i = 0; i < 128; i = i + 1) begin
                lru[i] <= 2'b00;
            end
        end else begin
            state <= state_next;

            // 请求发射：IDLE接收首条请求
            if (state == IDLE && if_ren) begin
                req_addr <= if_addr;
            end

            // 命中流水：在返回当前命中结果的同拍，接收下一条请求
            if (state == LOOKUP && any_hit && if_ren) begin
                req_addr <= if_addr;
            end

            // LOOKUP未命中，锁存MISS地址
            if (state == LOOKUP && !any_hit) begin
                miss_addr <= req_addr;
            end

            // MISS结束时若有新请求，直接进入下一拍LOOKUP
            if (state == MISS && refill_valid && if_ren) begin
                req_addr <= if_addr;
            end

            // MISS回填成功后更新替换路信息
            if (state == MISS && refill_valid) begin
                lru[miss_index] <= lru[miss_index] + 2'b01;
            end
        end
    end

    // ICache的命中逻辑
    always @(*) begin
        if ((state == LOOKUP) && cache_valid_out[0] && (cache_tag_out[0][19:0] == req_tag)) begin
            hit_way = 4'b0001;
            any_hit = 1'b1;
        end else if ((state == LOOKUP) && cache_valid_out[1] && (cache_tag_out[1][19:0] == req_tag)) begin
            hit_way = 4'b0010;
            any_hit = 1'b1;
        end else if ((state == LOOKUP) && cache_valid_out[2] && (cache_tag_out[2][19:0] == req_tag)) begin
            hit_way = 4'b0100;
            any_hit = 1'b1;
        end else if ((state == LOOKUP) && cache_valid_out[3] && (cache_tag_out[3][19:0] == req_tag)) begin
            hit_way = 4'b1000;
            any_hit = 1'b1;
        end else begin
            hit_way = 4'b0000;
            any_hit = 1'b0;
        end
    end

    // ICache的读数据输出和重填请求逻辑
    always @(*) begin
        case (state)
            IDLE: begin
                if_rdata = 32'b0;
                if_rvalid = 1'b0;
                refill_req = 1'b0;
                refill_addr = 32'b0;
            end
            LOOKUP: begin
                if (any_hit) begin
                    case (hit_way)
                        4'b0001: if_rdata = cache_data_out[0][req_offset * 32 +: 32];
                        4'b0010: if_rdata = cache_data_out[1][req_offset * 32 +: 32];
                        4'b0100: if_rdata = cache_data_out[2][req_offset * 32 +: 32];
                        4'b1000: if_rdata = cache_data_out[3][req_offset * 32 +: 32];
                        default: if_rdata = 32'b0;
                    endcase
                    if_rvalid = 1'b1;
                    refill_req = 1'b0;
                    refill_addr = 32'b0;
                end else begin
                    if_rdata = 32'b0;
                    if_rvalid = 1'b0;
                    refill_req = 1'b1;
                    refill_addr = {req_addr[31:5], 5'b0};
                end
            end
            MISS: begin
                if (refill_valid) begin
                    if_rdata = refill_data[miss_offset * 32 +: 32];
                    if_rvalid = 1'b1;
                    refill_req = 1'b0;
                    refill_addr = 32'b0;
                end else begin
                    if_rdata = 32'b0;
                    if_rvalid = 1'b0;
                    refill_req = 1'b0;
                    refill_addr = 32'b0;
                end
            end
            default: begin
                if_rdata = 32'b0;
                if_rvalid = 1'b0;
                refill_req = 1'b0;
                refill_addr = 32'b0;
            end
        endcase
    end

    // Icache数据重填和标签更新逻辑
    always @(*) begin
        cache_data_in = 256'b0;
        cache_tag_in = 33'b0;
        cache_data_wen[0] = 1'b0;
        cache_data_wen[1] = 1'b0;
        cache_data_wen[2] = 1'b0;
        cache_data_wen[3] = 1'b0;
        cache_tag_wen[0] = 1'b0;
        cache_tag_wen[1] = 1'b0;
        cache_tag_wen[2] = 1'b0;
        cache_tag_wen[3] = 1'b0;

        if (state == MISS && refill_valid) begin
            cache_data_in = refill_data;
            cache_tag_in = {1'b1, 12'b0, miss_tag};
            case (lru[miss_index])
                2'b00: begin
                    cache_data_wen[0] = 1'b1;
                    cache_tag_wen[0] = 1'b1;
                end
                2'b01: begin
                    cache_data_wen[1] = 1'b1;
                    cache_tag_wen[1] = 1'b1;
                end
                2'b10: begin
                    cache_data_wen[2] = 1'b1;
                    cache_tag_wen[2] = 1'b1;
                end
                2'b11: begin
                    cache_data_wen[3] = 1'b1;
                    cache_tag_wen[3] = 1'b1;
                end
                default: begin
                    cache_data_wen [0] = 1'b0;
                    cache_tag_wen [0] = 1'b0;
                    cache_data_wen [1] = 1'b0;
                    cache_tag_wen [1] = 1'b0;
                    cache_data_wen [2] = 1'b0;
                    cache_tag_wen [2] = 1'b0;
                    cache_data_wen [3] = 1'b0;
                    cache_tag_wen [3] = 1'b0;
                end
            endcase
        end
    end

endmodule