module dcache_data(
    input wire clk,
    input wire rst_n,
    input wire [6:0] index,
    output reg [255:0] data_out,
    input wire [255:0] data_in,
    input wire write_en,
    input wire [31:0] byte_en
);

    reg [255:0] cache_data [0:127]; // 128行，每行256位
    integer j;
    task data_clean;
        integer i;
            for (i = 0; i < 128; i = i + 1) begin
                cache_data[i] <= 256'b0;
            end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时清空缓存数据
            data_clean();
        end else if (write_en) begin
            // 写入数据到缓存，支持按字节写入
            for (j = 0; j < 8; j = j + 1) begin
                if (byte_en[j]) begin
                    cache_data[index][j*32 +: 32] <= data_in[j*32 +: 32];
                end
            end
        end else begin
            // 读取数据输出
            data_out <= cache_data[index];
        end
    end
endmodule