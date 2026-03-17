`timescale 1ns/1ps
`include "rtl/defines.v"

module tb_uart;

logic clk;
logic rst_n;
logic clk_uart;
logic [15:0] addr;
logic [31:0] wdata;
logic we;
logic re;
logic uart_rx;
logic [31:0] rdata;
logic uart_tx;
logic tx_int;
logic rx_int;

byte rx_data;
logic [31:0] status_word;

UART dut (
	.clk(clk),
	.rst_n(rst_n),
	.clk_uart(clk_uart),
	.addr(addr),
	.wdata(wdata),
	.we(we),
	.re(re),
	.rdata(rdata),
	.tx(uart_tx),
	.rx(uart_rx),
	.tx_int(tx_int),
	.rx_int(rx_int)
);

always #5 clk = ~clk;

task automatic host_write(input logic [15:0] reg_addr, input logic [31:0] reg_data);
	begin
		@(negedge clk);
		addr <= reg_addr;
		wdata <= reg_data;
		we <= 1'b1;
		re <= 1'b0;
		@(negedge clk);
		we <= 1'b0;
		addr <= '0;
		wdata <= '0;
	end
endtask

task automatic host_read(input logic [15:0] reg_addr, output logic [31:0] reg_data);
	begin
		@(negedge clk);
		addr <= reg_addr;
		re <= 1'b1;
		we <= 1'b0;
		#1;
		reg_data = rdata;
		@(posedge clk);
		@(negedge clk);
		re <= 1'b0;
		addr <= '0;
	end
endtask

task automatic uart_tick_once;
	begin
		clk_uart <= 1'b1;
		repeat (3) @(posedge clk);
		clk_uart <= 1'b0;
		repeat (3) @(posedge clk);
	end
endtask

task automatic expect_tx_frame(input byte expected);
	int bit_idx;
	begin
		uart_tick_once();
		if (uart_tx !== 1'b0) begin
			$fatal(1, "TX start bit error, got %b", uart_tx);
		end

		for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
			uart_tick_once();
			if (uart_tx !== expected[bit_idx]) begin
				$fatal(1, "TX data bit %0d error, expected %b got %b", bit_idx, expected[bit_idx], uart_tx);
			end
		end

		uart_tick_once();
		if (uart_tx !== 1'b1) begin
			$fatal(1, "TX stop bit error, got %b", uart_tx);
		end

		uart_tick_once();
		if (uart_tx !== 1'b1) begin
			$fatal(1, "TX idle level error after frame, got %b", uart_tx);
		end
	end
endtask

task automatic inject_rx_frame(input byte payload);
	int bit_idx;
	begin
		uart_rx <= 1'b1;
		repeat (2) @(posedge clk);

		uart_rx <= 1'b0;
		repeat (3) @(posedge clk);
		uart_tick_once();

		for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
			uart_rx <= payload[bit_idx];
			repeat (3) @(posedge clk);
			uart_tick_once();
		end

		uart_rx <= 1'b1;
		repeat (3) @(posedge clk);
		uart_tick_once();
		repeat (3) @(posedge clk);
	end
endtask

initial begin
		clk = 1'b0;
		rst_n = 1'b0;
		clk_uart = 1'b0;
		addr = '0;
		wdata = '0;
		we = 1'b0;
		re = 1'b0;
		uart_rx = 1'b1;

		repeat (5) @(posedge clk);
		rst_n = 1'b1;
		repeat (2) @(posedge clk);

		host_read(`UART_RT_STATUS, status_word);
		if (status_word[0] !== 1'b1 || status_word[1] !== 1'b0) begin
			$fatal(1, "Reset status mismatch: %08h", status_word);
		end

		host_write(`UART_RT_CTRL, 32'h0000_0007);
		host_read(`UART_RT_CTRL, status_word);
		if (status_word[4:0] !== 5'b0_0_1_1_1) begin
			$fatal(1, "CTRL register mismatch: %08h", status_word);
		end

		host_write(`UART_RT_DATA, 32'h0000_00A5);
		expect_tx_frame(8'hA5);

		host_read(`UART_RT_STATUS, status_word);
		if (status_word[0] !== 1'b1) begin
			$fatal(1, "TX empty flag not asserted after transmit: %08h", status_word);
		end
		if (status_word[6] !== 1'b1) begin
			$fatal(1, "TX interrupt not asserted after transmit: %08h", status_word);
		end

		inject_rx_frame(8'h3C);

		host_read(`UART_RT_STATUS, status_word);
		if (status_word[1] !== 1'b1) begin
			$fatal(1, "RX ready flag not asserted after receive: %08h", status_word);
		end
		if (status_word[7] !== 1'b1) begin
			$fatal(1, "RX interrupt not asserted after receive: %08h", status_word);
		end

		host_read(`UART_RT_DATA, status_word);
		rx_data = status_word[7:0];
		if (rx_data !== 8'h3C) begin
			$fatal(1, "RX data mismatch, expected 3C got %02h", rx_data);
		end

		host_read(`UART_RT_STATUS, status_word);
		if (status_word[1] !== 1'b0) begin
			$fatal(1, "RX ready flag not cleared after read: %08h", status_word);
		end

		$display("----------------------------------------------");
		$display("UART test passed.");
		$display("----------------------------------------------");
		$finish;
	end

	initial begin
		#20000;
		$fatal(1, "UART test timeout");
	end

endmodule
