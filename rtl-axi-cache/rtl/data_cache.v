module data_cache (
    input wire clk,
    input wire rst_n,
    input wire [31:0] addr,
    input wire ren,
    input wire wen,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    output reg [31:0] rdata,
    output reg rvalid,
    // 接往AXI总线的信号，由另外的模块负责连接
    output reg refill_req,
    output reg [31:0] refill_addr,
    input wire [255:0] refill_data,
    input wire refill_valid,
    output reg write_back_req,
    output reg [31:0] write_back_addr,
    output reg [255:0] write_back_data
);

    //定义cache_tag和dcache_data的接口信号及地址解析
    wire [255:0] cache_data_out [0:3]; // 四路组相联，每路32字
    wire [19:0] cache_tag_out [0:3]; // 四路组相联，每路20位标签
    wire cache_valid_out [0:3]; // 四路组相联，每路有效
    wire cache_dirty_out [0:3]; // 四路组相联，每路脏位
    reg [255:0] cache_data_in; // 写入数据
    reg [21:0] cache_tag_in; // 写入标签（20位标签+1位有效位+1位脏位）
    reg cache_data_wen [0:3]; // 写使能信号
    reg cache_tag_wen [0:3]; // 写使能信号
    reg [31:0] byte_wen; // 字节写使能信号，用于写未命中时的部分更新
    // RAM读取索引：支持命中流水时预取下一条请求地址
    wire [6:0] index;
    reg [1:0] lru [0:127]; // 存储LRU信息，128行，每行2位
    reg [3:0] hit_way; // 命中路，4位表示4路组相联
    reg any_hit; // 是否命中
    reg miss_state; //表示是写未命中还是读未命中，写未命中需要要先读出来再写进cache_line

    // DCache状态机与请求锁存
    localparam IDLE = 2'b00;
    localparam LOOKUP = 2'b01;
    localparam MISS = 2'b10;
    localparam WRITEUP = 2'b11;
    reg [1:0] state, state_next;

    reg [31:0] req_addr;     // 当前在途请求地址（LOOKUP使用）
    reg [31:0] miss_addr;    // MISS回填地址
    reg [31:0] miss_wdata;   // MISS回填数据（写未命中时使用）
    reg [31:0] req_wdata;     // 当前在途写数据（WRITEUP使用）
    reg [3:0] req_wstrb;     // 当前在途写使能（WRITEUP使用）
    integer i;

    wire [6:0] req_index = req_addr[11:5];
    wire [2:0] req_offset = req_addr[4:2];
    wire [19:0] req_tag = req_addr[31:12];
    wire [6:0] miss_index = miss_addr[11:5];
    wire [2:0] miss_offset = miss_addr[4:2];
    wire [19:0] miss_tag = miss_addr[31:12];

    assign index = (state == IDLE) ? addr[11:5] :
                   (state == MISS) ? ((refill_valid && ren) ? addr[11:5] : miss_index) :
                                     ((any_hit && ren) ? addr[11:5] : req_index);
                                    
    // 实例化dcache_tag和cache_data模块
    dcache_tag dcache_tag1 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .tag_out({cache_dirty_out[0], cache_valid_out[0], cache_tag_out[0]}),
        .tag_in(cache_tag_in),
        .write_en(cache_tag_wen[0])
    );
    dcache_tag dcache_tag2 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .tag_out({cache_dirty_out[1], cache_valid_out[1], cache_tag_out[1]}),
        .tag_in(cache_tag_in),
        .write_en(cache_tag_wen[1])
    );
    dcache_tag dcache_tag3 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .tag_out({cache_dirty_out[2], cache_valid_out[2], cache_tag_out[2]}),
        .tag_in(cache_tag_in),
        .write_en(cache_tag_wen[2])
    );
    dcache_tag dcache_tag4 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .tag_out({cache_dirty_out[3], cache_valid_out[3], cache_tag_out[3]}),
        .tag_in(cache_tag_in),
        .write_en(cache_tag_wen[3])
    );
    dcache_data cache_data1 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .data_out(cache_data_out[0]),
        .data_in(cache_data_in),
        .write_en(cache_data_wen[0]),
        .byte_en(byte_wen)
    );
    dcache_data cache_data2 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .data_out(cache_data_out[1]),
        .data_in(cache_data_in),
        .write_en(cache_data_wen[1]),
        .byte_en(byte_wen)
    );
    dcache_data cache_data3 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .data_out(cache_data_out[2]),
        .data_in(cache_data_in),
        .write_en(cache_data_wen[2]),
        .byte_en(byte_wen)
    );
    dcache_data cache_data4 (
        .clk(clk),
        .rst_n(rst_n),
        .index(index),
        .data_out(cache_data_out[3]),
        .data_in(cache_data_in),
        .write_en(cache_data_wen[3]),
        .byte_en(byte_wen)
    );

    // DCache状态转移逻辑
    always @(*) begin
        case (state) 
            IDLE: begin
                if (ren) begin
                    state_next = LOOKUP;
                end else if (wen) begin
                    state_next = WRITEUP;
                end else begin
                    state_next = IDLE;
                end
            end
            LOOKUP: begin
                if (any_hit && ren) begin
                    state_next = LOOKUP;
                end else if (any_hit && wen) begin
                    state_next = WRITEUP;
                end else if (any_hit) begin
                    state_next = IDLE;
                end else begin
                    state_next = MISS;
                end
            end
            WRITEUP: begin
                if(any_hit && ren) begin
                    state_next = LOOKUP;
                end else if (any_hit && wen) begin
                    state_next = WRITEUP;
                end else if (any_hit) begin
                    state_next = IDLE;
                end else begin
                    state_next = MISS;
                end
            end
            MISS: begin
                if (refill_valid) begin
                    if (ren) begin
                        state_next = LOOKUP;
                    end else if (wen) begin
                        state_next = WRITEUP;
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
            miss_state <= 0;
            miss_wdata <= 32'b0;
            for (i = 0; i < 128; i = i + 1) begin
                lru[i] <= 2'b00;
            end
        end else begin
            state <= state_next;

            // 请求发射：IDLE接收首条请求
            if (state == IDLE && (ren || wen)) begin
                req_addr <= addr;
                req_wdata <= wdata;
                req_wstrb <= wstrb;
                miss_state <= 1'b0;
            end

            // 命中流水：在返回当前命中结果的同拍，接收下一条请求地址
            if ((state == LOOKUP || state == WRITEUP) && any_hit && (ren || wen)) begin
                req_addr <= addr;
                req_wdata <= wdata;
                req_wstrb <= wstrb;
                miss_state <= 1'b0;
            end

            // LOOKUP未命中，锁存MISS地址
            if (state == LOOKUP && !any_hit) begin
                miss_addr <= req_addr;
                miss_state <= 1'b0;
            end

            // WRITEUP未命中，锁存MISS地址
            if (state == WRITEUP && !any_hit) begin
                miss_addr <= req_addr;
                miss_wdata <= wdata;
                miss_state <= 1'b1;
            end

            // MISS回填完成，更新LRU信息
            if (state == MISS && refill_valid) begin
                lru[miss_index] <= lru[miss_index] + 2'b01;
            end

            // MISS结束时若有新请求，直接进入下一拍LOOKUP或WRITEUP
            if (state == MISS && refill_valid && (ren || wen)) begin
                req_addr <= addr;
                miss_state <= 1'b0;
            end
        end
    end

    //Dcache命中逻辑，采用优先级编码器实现，优先级为0>1>2>3
    always @(*) begin
        if ((state == LOOKUP || state == WRITEUP) && cache_valid_out[0] && cache_tag_out[0] == req_tag) begin
            hit_way = 4'b0001;
            any_hit = 1;
        end else if ((state == LOOKUP || state == WRITEUP) && cache_valid_out[1] && cache_tag_out[1] == req_tag) begin
            hit_way = 4'b0010;
            any_hit = 1;
        end else if ((state == LOOKUP || state == WRITEUP) && cache_valid_out[2] && cache_tag_out[2] == req_tag) begin
            hit_way = 4'b0100;
            any_hit = 1;
        end else if ((state == LOOKUP || state == WRITEUP) && cache_valid_out[3] && cache_tag_out[3] == req_tag) begin
            hit_way = 4'b1000;
            any_hit = 1;
        end else begin
            hit_way = 4'b0000;
            any_hit = 0;
        end
    end

    //Dcache读数据输出和重填请求逻辑（在这里只处理读请求，后续处理写请求）
    wire [255:0] test_data = cache_data_out[0];
    wire [31:0] test_word = cache_data_out[0][req_offset*32 +: 32];
    always @(*) begin
        case (state)
            IDLE: begin
                rdata = 32'b0;
                rvalid = 1'b0;
                refill_req = 1'b0;
                refill_addr = 32'b0;
            end
            LOOKUP: begin
                if (any_hit) begin
                    case (hit_way)
                        4'b0001: rdata = cache_data_out[0][req_offset * 32 +: 32];
                        4'b0010: rdata = cache_data_out[1][req_offset * 32 +: 32];
                        4'b0100: rdata = cache_data_out[2][req_offset * 32 +: 32];
                        4'b1000: rdata = cache_data_out[3][req_offset * 32 +: 32];
                        default: rdata = 32'b0;
                    endcase
                    rvalid = 1'b1;
                    refill_req = 1'b0;
                    refill_addr = 32'b0;
                end else begin
                    rdata = 32'b0;
                    rvalid = 1'b0;
                    refill_req = 1'b1;
                    refill_addr = {req_addr[31:5], 5'b00000}; // 按块地址对齐
                end
            end
            MISS: begin
                if (refill_valid) begin
                    rdata = refill_data[miss_offset*32 +: 32];
                    rvalid = 1'b1;
                    refill_req = 1'b0;
                    refill_addr = 32'b0;
                end else begin
                    rdata = 32'b0;
                    rvalid = 1'b0;
                    refill_req = 1'b0;
                    refill_addr = 32'b0;
                end
            end
            default: begin
                rdata = 32'b0;
                rvalid = 1'b0;
                refill_req = 1'b0;
                refill_addr = 32'b0;
            end
        endcase
    end

    //Dcache写数据逻辑
    always @(*) begin
        case (state)
            IDLE: begin
                byte_wen = 32'b0;
            end
            WRITEUP: begin
                if (any_hit) begin
                    case (hit_way)
                        4'b0001: begin
                            cache_data_in = {req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata}; // 写未命中时需要先读出原数据再写回，因此这里直接用写数据覆盖，实际写入时会根据byte_wen进行部分更新
                            cache_data_wen[0] = 1'b1;
                            cache_tag_wen[0] = 1'b1;
                            byte_wen = req_wstrb << (req_offset * 4); // 根据偏移量计算字节使能
                        end
                        4'b0010: begin
                            cache_data_in = {req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata};
                            cache_data_wen[1] = 1'b1;
                            cache_tag_wen[1] = 1'b1;
                            byte_wen = req_wstrb << (req_offset * 4); // 根据偏移量计算字节使能
                        end
                        4'b0100: begin
                            cache_data_in = {req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata};
                            cache_data_wen[2] = 1'b1;
                            cache_tag_wen[2] = 1'b1;
                            byte_wen = req_wstrb << (req_offset * 4); // 根据偏移量计算字节使能
                        end
                        4'b1000: begin
                            cache_data_in = {req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata,req_wdata};
                            cache_data_wen[3] = 1'b1;
                            cache_tag_wen[3] = 1'b1;
                            byte_wen = req_wstrb << (req_offset * 4); // 根据偏移量计算字节使能
                        end
                    endcase
                    cache_tag_in = {1'b1, 1'b1, req_tag}; // 写操作有效，脏位置1
                end else begin
                    byte_wen = 32'b0;
                end
            end
            LOOKUP, MISS: begin
                byte_wen = 32'b0;
            end
            default: begin
                byte_wen = 32'b0;
            end
            endcase
    end

    // Dcache的数据重填和标签更新以及脏位替换逻辑
    always @ (*) begin
        cache_data_in = 256'b0;
        cache_tag_in = 22'b0;
        byte_wen = 32'b0;
        cache_data_wen[0] = 1'b0;
        cache_data_wen[1] = 1'b0;
        cache_data_wen[2] = 1'b0;
        cache_data_wen[3] = 1'b0;
        cache_tag_wen[0] = 1'b0;
        cache_tag_wen[1] = 1'b0;
        cache_tag_wen[2] = 1'b0;
        cache_tag_wen[3] = 1'b0;

        //数据重填和标签更新逻辑
        if (state == MISS && refill_valid) begin
            if (miss_state) begin //当miss为写未命中时需要将写的数据替换进去
                cache_data_in = refill_data;
                case (miss_offset)
                    3'b000: cache_data_in[31:0] = miss_wdata;
                    3'b001: cache_data_in[63:32] = miss_wdata;
                    3'b010: cache_data_in[95:64] = miss_wdata;
                    3'b011: cache_data_in[127:96] = miss_wdata;
                    3'b100: cache_data_in[159:128] = miss_wdata;
                    3'b101: cache_data_in[191:160] = miss_wdata;
                    3'b110: cache_data_in[223:192] = miss_wdata;
                    3'b111: cache_data_in[255:224] = miss_wdata;
                    default: cache_data_in = refill_data;
                endcase
            end else begin
                cache_data_in = refill_data;
            end
            cache_tag_in = {1'b0, 1'b1, miss_tag}; // 新数据有效，脏位初始为0
            // 根据LRU信息选择替换路
            case (lru[miss_index])
                2'b00: begin
                    cache_data_wen[0] = 1'b1;
                    cache_tag_wen[0] = 1'b1;
                    byte_wen = 32'hFFFFFFFF; // 全字写入
                end
                2'b01: begin
                    cache_data_wen[1] = 1'b1;
                    cache_tag_wen[1] = 1'b1;
                    byte_wen = 32'hFFFFFFFF; // 全字写入
                end
                2'b10: begin
                    cache_data_wen[2] = 1'b1;
                    cache_tag_wen[2] = 1'b1;
                    byte_wen = 32'hFFFFFFFF; // 全字写入
                end
                2'b11: begin
                    cache_data_wen[3] = 1'b1;
                    cache_tag_wen[3] = 1'b1;
                    byte_wen = 32'hFFFFFFFF; // 全字写入
                end
                default: begin
                    cache_data_wen[0] = 1'b0;
                    cache_tag_wen[0] = 1'b0;
                    cache_data_wen[1] = 1'b0;
                    cache_tag_wen[1] = 1'b0;
                    cache_data_wen[2] = 1'b0;
                    cache_tag_wen[2] = 1'b0;
                    cache_data_wen[3] = 1'b0;
                    cache_tag_wen[3] = 1'b0;
                    byte_wen = 32'b0;
                end
            endcase
        end

        //脏位写回逻辑
        if (state == MISS && refill_valid) begin
            if (cache_dirty_out[miss_index]) begin
                write_back_req = 1'b1;
                write_back_addr = {miss_addr[31:5], 5'b00000};
                case (lru[miss_index])
                    2'b00: write_back_data = cache_data_out[0];
                    2'b01: write_back_data = cache_data_out[1];
                    2'b10: write_back_data = cache_data_out[2];
                    2'b11: write_back_data = cache_data_out[3];
                    default: write_back_data = 256'b0;
                endcase
            end else begin
                write_back_req = 1'b0;
                write_back_addr = 32'b0;
                write_back_data = 256'b0;
            end
        end
    end


endmodule