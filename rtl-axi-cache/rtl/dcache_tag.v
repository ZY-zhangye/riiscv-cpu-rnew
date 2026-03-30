module dcache_tag (
    input wire clk,
    input wire rst_n,
    input wire [6:0] index,
    output reg [21:0] tag_out,
    input wire [21:0] tag_in,
    input wire write_en
);

    reg [21:0] cache_tag [0:127]; // 128行，每行22位，20位标签+1位有效位+1位脏位
    task tag_clean;
     integer i;
         for (i = 0; i < 128; i = i + 1) begin
                cache_tag[i] <= 22'b0;
            end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时清空缓存标签
            tag_clean();
        end else if (write_en) begin
            // 写入标签到缓存
            cache_tag[index] <= tag_in;
        end else begin
            // 读取标签输出
            tag_out <= cache_tag[index];
        end
    end

endmodule