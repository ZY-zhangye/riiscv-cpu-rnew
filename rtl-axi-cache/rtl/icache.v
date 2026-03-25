module icache (
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
    // 定义ICache的参数
    localparam CACHE_LINE_SIZE = 32; // 每行32字节
    localparam CACHE_LINE_NUM = 128; // 共128行
    localparam WAYS = 4; // 四路组相联

    // 定义ICache的内部结构
    reg [31:0] cache_data [0:CACHE_LINE_NUM-1][0:WAYS-1][0:7]; // 存储数据
    reg [31:0] cache_tag [0:CACHE_LINE_NUM-1][0:WAYS-1]; // 存储标签
    reg valid [0:CACHE_LINE_NUM-1][0:WAYS-1]; // 存储有效位
    reg [1:0] lru [0:CACHE_LINE_NUM-1]; // 存储LRU信息
    // 定义ICache的地址解析逻辑
    wire [6:0] index = if_addr[11:5]; // 7位索引
    wire [2:0] offset = if_addr[4:2]; // 3位块内偏移（8个32bit字）
    wire [19:0] tag = if_addr[31:12]; // 20位标签
    reg [WAYS-1:0] hit_way; // 命中路
    reg [WAYS-1:0] valid_way; // 有效路
    reg [2:0] hit_way_idx; // 命中路的索引（3位用于4路组相联）
    reg any_hit; // 是否命中
    
    // 优先级编码器：将hit_way转换为索引（低位优先）
    always @(*) begin
        hit_way_idx = 0;
        if (hit_way[0]) begin
            hit_way_idx = 0;
        end else if (hit_way[1]) begin
            hit_way_idx = 1;
        end else if (hit_way[2]) begin
            hit_way_idx = 2;
        end else if (hit_way[3]) begin
            hit_way_idx = 3;
        end
    end
    // 定义ICache的状态机
    localparam  IDLE = 2'b00;
    localparam LOOKUP = 2'b01;
    localparam REFILL = 2'b10;
    localparam MISS = 2'b11;
    reg [1:0] state, state_next;
    
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
                state_next = LOOKUP;  // 命中且继续读，保持LOOKUP
            end else if (any_hit && !if_ren) begin
                state_next = IDLE;    // 命中但不读，回到IDLE
            end else begin
                state_next = MISS;    // 没有命中，进入MISS
            end
        end
        MISS: begin
            if (refill_valid) begin
                state_next = REFILL;
            end else begin
                state_next = MISS;
            end
        end
        REFILL: begin
            if (if_ren) begin
                state_next = LOOKUP;
            end else begin
                state_next = IDLE;
            end
        end
        default: state_next = IDLE;
        endcase
    end
    // ICache的命中逻辑
    integer i;
    always @(*) begin
        hit_way = 0;
        valid_way = 0;
        any_hit = 0;
        for (i = 0; i < WAYS; i = i + 1) begin
            if (valid[index][i] && cache_tag[index][i] == tag) begin
                hit_way[i] = 1;
                any_hit = 1;
            end
            if (valid[index][i]) begin
                valid_way[i] = 1;
            end
        end
    end
    // ICache的状态更新（时序逻辑）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= state_next;
        end
    end
    
    // ICache的输出逻辑（组合逻辑，仅数据/有效信号）
    always @(*) begin
        if (!rst_n) begin
            if_rdata = 0;
            if_rvalid = 0;
        end else begin
            case (state)
                IDLE: begin
                    if_rdata = 0;
                    if_rvalid = 0;
                end
                LOOKUP: begin
                    if (any_hit) begin
                        if_rdata = cache_data[index][hit_way_idx][offset];  // 组合逻辑，立即输出
                        if_rvalid = 1;
                    end else begin
                        if_rdata = 0;
                        if_rvalid = 0;
                    end
                end
                MISS: begin
                    if (refill_valid) begin
                        // 回包到达当拍直接返回数据，避免依赖下一拍REFILL再次看到refill_valid
                        case (offset)
                            3'b000: if_rdata = refill_data[31:0];
                            3'b001: if_rdata = refill_data[63:32];
                            3'b010: if_rdata = refill_data[95:64];
                            3'b011: if_rdata = refill_data[127:96];
                            3'b100: if_rdata = refill_data[159:128];
                            3'b101: if_rdata = refill_data[191:160];
                            3'b110: if_rdata = refill_data[223:192];
                            3'b111: if_rdata = refill_data[255:224];
                            default: if_rdata = 0;
                        endcase
                        if_rvalid = 1;
                    end else begin
                        if_rdata = 0;
                        if_rvalid = 0;
                    end
                end
                REFILL: begin
                    if_rdata = 0;
                    if_rvalid = 0;
                end
                default: begin
                    if_rdata = 0;
                    if_rvalid = 0;
                end
            endcase
        end
    end

    // refill请求输出逻辑（时序寄存器）：单拍脉冲 + 稳定地址
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refill_req <= 1'b0;
            refill_addr <= 32'b0;
        end else begin
            // 默认拉低，形成单拍脉冲
            refill_req <= 1'b0;
            // 仅在“将要进入MISS”的这个时钟沿发起一次请求
            if (state != MISS && state_next == MISS) begin
                refill_req <= 1'b1;
                refill_addr <= {tag, index, 5'b00000};
            end
            // 其他周期保持refill_addr不变，直到下一次MISS请求覆盖
        end
    end
    
    // 缓存数据更新逻辑（时序，在MISS收到refill_valid时写入）
    integer way_to_replace;
    integer invalid_way;
    integer j;
    integer s;
    integer w;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            way_to_replace <= 0;
            invalid_way <= 0;
            j <= 0;
            // 关键初始化：避免valid/lru为X导致替换路计算出现X
            for (s = 0; s < CACHE_LINE_NUM; s = s + 1) begin
                lru[s] <= 2'b00;
                for (w = 0; w < WAYS; w = w + 1) begin
                    valid[s][w] <= 1'b0;
                    cache_tag[s][w] <= 32'b0;
                end
            end
        end else if (state == MISS && refill_valid) begin
            // 将数据写入Cache
            
            // 选择要替换的路：优先选择无效路，否则选择LRU路
            invalid_way = -1;
            for (j = 0; j < WAYS; j = j + 1) begin
                if (valid[index][j] == 1'b0) begin
                    invalid_way = j;
                end
            end
            
            if (invalid_way >= 0) begin
                way_to_replace = invalid_way;
            end else begin
                way_to_replace = lru[index][1:0];  // 使用LRU指示的路
            end
            
            cache_data[index][way_to_replace][0] <= refill_data[31:0];
            cache_data[index][way_to_replace][1] <= refill_data[63:32];
            cache_data[index][way_to_replace][2] <= refill_data[95:64];
            cache_data[index][way_to_replace][3] <= refill_data[127:96];
            cache_data[index][way_to_replace][4] <= refill_data[159:128];
            cache_data[index][way_to_replace][5] <= refill_data[191:160];
            cache_data[index][way_to_replace][6] <= refill_data[223:192];
            cache_data[index][way_to_replace][7] <= refill_data[255:224];
            cache_tag[index][way_to_replace] <= tag;
            valid[index][way_to_replace] <= 1;
            
            // 更新LRU：使用简单的循环替换策略
            // 每次替换后，LRU值加1（mod 4）
            lru[index] <= lru[index] + 1;
        end
    end

endmodule