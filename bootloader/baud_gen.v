// -------------------------------------------------------------
// Baud rate tick generator (one-clock pulse at baud frequency)
// Parameters: system clock freq (Hz) and baud rate.
// Generates baud_tick high for 1 clk every BAUD_CNT_MAX cycles.
// -------------------------------------------------------------
module baud_gen #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input  wire clk,
    input  wire rst_n,
    output reg  baud_tick
);
    localparam integer BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE;
    reg [$clog2(BAUD_CNT_MAX):0] baud_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b0;
        end else if (baud_cnt == BAUD_CNT_MAX - 1) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 1;
            baud_tick <= 1'b0;
        end
    end
endmodule
