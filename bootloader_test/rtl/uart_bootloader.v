module uart_bootloader(
    input clk,
    input rst_n,
    input rx,
    input baud_tick,
    output wire [52:0] dmem_write_bus,
    output wire [48:0] imem_write_bus,
    output wire reset,
    output wire mem_valid
);

wire [7:0] uart_data_out;
wire uart_data_valid;
wire [7:0] fifo_data;
wire fifo_empty;
wire fifo_full;
wire fifo_read_en;
wire [7:0] type_out;
wire [15:0] addr_out;
wire [31:0] data_out_frame;
wire frame_valid;

uart uart_inst (
    .clk(clk),
    .rst_n(rst_n),
    .baud_tick(baud_tick),
    .rx(rx),
    .data_out(uart_data_out),
    .data_valid(uart_data_valid)
);

uart_fifo #(
    .DEPTH(16)
) fifo_inst (
    .clk(clk),
    .rst_n(rst_n),
    .data_in(uart_data_out),
    .data_valid_in(uart_data_valid),
    .read_en(fifo_read_en),
    .data_out(fifo_data),
    .empty(fifo_empty),
    .full(fifo_full)
);

uart_frame_parse frame_parse_inst (
    .clk(clk),
    .rst_n(rst_n),
    .fifo_data(fifo_data),
    .fifo_empty(fifo_empty),
    .fifo_full(fifo_full),
    .fifo_read_en(fifo_read_en),
    .type_out(type_out),
    .addr_out(addr_out),
    .data_out(data_out_frame),
    .frame_valid(frame_valid)
);

bootloader bootloader_inst (
    .clk(clk),
    .rst_n(rst_n),
    .type_in(type_out),
    .addr_in(addr_out),
    .data_in(data_out_frame),
    .frame_valid(frame_valid),
    .dmem_write_bus(dmem_write_bus),
    .imem_write_bus(imem_write_bus),
    .reset(reset),
    .mem_valid(mem_valid)
);

endmodule