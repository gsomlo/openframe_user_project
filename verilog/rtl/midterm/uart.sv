// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`default_nettype none

// contiguous sequences of system clk cycles make up
//    "tx baud slots" and "rx baud sample" points of the
//    designated (clk_freq/(baudrate[*rx_ovrsmpl])) duration
// output a `baud_slot` signal during the first system clk cycle
//    of each such tx baud slot
// output a `baud_sample` signal during the first system clk cycle
//    of each such rx baud sample point
module baud_clock #(
	parameter CLK_FREQ = 50000000, // 50 MHz
	parameter BAUDRATE =   115200
) (
	output logic baud_slot,
	output logic baud_sample,
	input  logic clk,
	input  logic rst
);

	localparam TX_TICKS_PER_BAUD = CLK_FREQ / BAUDRATE;
	localparam TX_CW             = $clog2(TX_TICKS_PER_BAUD);
	localparam RX_OVERSAMPLE     = 8; // 8x oversampling of RX line
	localparam RX_TICKS_PER_BAUD = CLK_FREQ / (BAUDRATE * RX_OVERSAMPLE);
	localparam RX_CW             = $clog2(RX_TICKS_PER_BAUD);

	logic [TX_CW-1:0] tx_cnt;
	logic [RX_CW-1:0] rx_cnt;

	assign baud_slot   = (tx_cnt == 0);
	assign baud_sample = (rx_cnt == 0);

	always_ff @(posedge clk) begin
		if (rst) begin
			tx_cnt <= 0;
			rx_cnt <= 0;
		end else begin
			if (tx_cnt == TX_TICKS_PER_BAUD[TX_CW-1:0] - 1)
				tx_cnt <= 0;
			else
				tx_cnt <= tx_cnt + 1;
			if (rx_cnt == RX_TICKS_PER_BAUD[RX_CW-1:0] - 1)
				rx_cnt <= 0;
			else
				rx_cnt <= rx_cnt + 1;
		end
	end

endmodule: baud_clock

module uart_tx (
	// rs232 interface (external facing)
	output logic txd, // TX data
	input  logic rts, // remote ready to receive data

	// uart input pipeline (internal facing, to be transmitted externally)
	input  logic [7:0] data_in,
	input  logic       data_in_valid,
	output logic       data_in_ready,

	input logic baud_slot,
	input logic clk,
	input logic rst
);

	// data register:
	logic [7:0] d_reg, d_regNext;
	// bit counter:
	logic [2:0] b_cnt, b_cntNext;

	// FSM states:
	enum logic [1:0] {Idle, Slotwait, Start, Data} state, stateNext;

	// `Idle` state is *special* (must be updated on each `clk` cycle):
	logic is_idle;

	always_comb begin
		// keep sequential registers steady by default:
		d_regNext = d_reg;
		b_cntNext = b_cnt;
		stateNext = state;

		// are we in `Idle` ?
		is_idle = (state == Idle);

		// if in `Idle`, accept new data for TX:
		data_in_ready = is_idle;

		// serial `txd` is high by default
		// (during `Idle` and `Slotwait`):
		txd = 1;

		unique case (state)
		Idle: begin
			if (data_in_valid) begin
				d_regNext = data_in;
				stateNext = Slotwait;
			end
		end
		// NOTE: Idle+Slotwait also serve to ensure that a full
		// stop bit (high) is sent at the end of each data byte!
		Slotwait: begin
			if (rts) begin
				stateNext = Start;
			end
		end
		Start: begin
			txd = 0; // send start bit (space, low)
			b_cntNext = 0;
			stateNext = Data;
		end
		Data: begin
			txd = d_reg[0]; // send current data bit
			b_cntNext = b_cnt + 1;
			d_regNext = d_reg >> 1;
			if (&b_cnt) begin
				stateNext = Idle;
			end
		end
		endcase
	end

	// advance state only when idle or at the start of a "baud slot":
	always_ff @(posedge clk) begin
		if (rst) begin
			d_reg <= 0;
			b_cnt <= 0;
			state <= Idle;
		end else if (is_idle | baud_slot) begin
			d_reg <= d_regNext;
			b_cnt <= b_cntNext;
			state <= stateNext;
		end
	end

endmodule: uart_tx

module uart_rx (
	// rs232 interface (external facing)
	input  logic rxd, // RX data
	output logic cts, // ready to receive from remote

	// uart output pipeline (internal facing, relay received data)
	output logic [7:0] data_out,
	output logic       data_out_valid,
	input  logic       data_out_ready,

	input logic baud_sample, // 8x oversampling of the baud rate
	input logic clk,
	input logic rst
);

	// ready to receive if consumer is ready:
	assign cts = data_out_ready;

	// next values for (registered) `data_out[_valid]` outputs:
	logic       data_out_validNext;
	logic [7:0] data_outNext;

	// we need a 3-bit sample counter (8x oversampling is hard-coded
	// into this design), and also a 3-bit bit-position counter for
	// the 8 data bits per received byte:
	logic [2:0] sample_ct, sample_ctNext;
	logic [2:0] bit_ct, bit_ctNext;

	// keep 4-most-recent samples of `rxd` in a shift register:
	logic [3:0] rxd_hold_reg, rxd_hold_regNext;

	// To avoid potential metastability issues, the raw `rxd` input
	// should never be used directly; The LSB of the shift register,
	// `rxd_hold_reg[0]`, serves as an intermediate debouncing step;
	// The first signal considered usable within the `clk` system clock
	// domain will be `rxd_hold_reg[1]`, a.k.a. `crt_rxd`, i.e., the
	// "most recent" or "current" rxd signal sample; To help verify
	// required rxd signal hold times, we also keep track of whether
	// the two previous samples were all-high:
	logic crt_rxd, prv2_rxd_hi;
	assign crt_rxd     = rxd_hold_reg[1];
	assign prv2_rxd_hi = &(rxd_hold_reg[3:2]);

	// data handshake (hand-over) to inward-facing consumer:
	logic data_out_handshake;
	assign data_out_handshake = (data_out_ready & data_out_valid);

	// FSM state register:
	enum logic [1:0] {Edge, Start, Data, Stop} state, stateNext;

	always_comb begin
	    // de-assert `data_out_valid` immediately upon handshake:
	    data_out_validNext = data_out_handshake ? 0 : data_out_valid;

	    // keep sequential registers steady by default:
	    rxd_hold_regNext = rxd_hold_reg;
	    sample_ctNext    = sample_ct;
	    data_outNext     = data_out;
	    bit_ctNext       = bit_ct;
	    stateNext        = state;

	    // besides de-asserting `data_out_valid` on an arbitrary
	    // `clk` cycle, only update FSM once per `baud_sample`:
	    if (baud_sample) begin

		// record new sample from `rxd` line:
		rxd_hold_regNext = {rxd_hold_reg[2:0], rxd};

		// increment sample counter (unless otherwise specified):
		sample_ctNext = sample_ct + 1;

		unique case (state)
		Edge: begin
		    if (prv2_rxd_hi & ~crt_rxd) begin
			// found a falling edge, possibly start bit;
			sample_ctNext = 1;
			stateNext     = Start;
		    end
		end
		Start: begin
		    if (crt_rxd) begin
			// error: unexpected high rx sample shows failure
			// to meet start bit (low) hold time; go back to
			// waiting for a falling edge to attempt finding
			// a new start bit:
			stateNext = Edge;
		    end else begin
			// at 2 low rx samples past the mid-point of the
			// start bit baud slot, consider hold time met;
			// re-center sample counter around presumptive
			// baud slot mid-point:
			if (&(sample_ct[2:1])) begin // >= 6
				sample_ctNext = 3'h2;
				//bit_ctNext  = 0; // redundant!
				stateNext     = Data;
			end
		    end
		end
		Data: begin
		    // sample new bit from "center" of baud slot:
		    if (&sample_ct) begin // == 7
			// if the consumer failed to complete data
			// handshake by the time the first bit of a
			// new byte is sampled, the previous data byte
			// will be lost:
			data_out_validNext = 0;
			data_outNext       = {crt_rxd, data_out[7:1]};
			bit_ctNext         = bit_ct + 1;
			if (&bit_ct) begin // == 7
				// this was the last data bit:
				stateNext = Stop;
			end
		    end
		end
		Stop: begin
		    // due to potential baud clock drift between local and
		    // remote endpoint, accept transition to the next start
		    // bit any time after stop bit mid-point
		    //
		    // sample_ct >= 4 and stop bit (high) hold time met:
		    if (sample_ct[2] & prv2_rxd_hi) begin
			// once `data_out_valid` is asserted, consumer
			// has at least cca. 12 `baud_sample` intervals
			// to complete data handshake (hand-over):
			//   6 before `Start` enforces low hold
			//   6 before `Data` samples 1st new bit
			data_out_validNext = 1;
			// this is only necessary when transitioning
			// to `Start`, but benign otherwise:
			sample_ctNext = 1;
			// did we already find a falling edge?
			stateNext = crt_rxd ? Edge : Start;
		    end else if (&sample_ct) begin
			// sample_ct == 8 w/o meeting stop bit (high)
			// hold time: glitching `rxd` line, failure to
			// detect valid incoming stop bit (high);
			// start over from scratch:
			stateNext = Edge;
		    end
		end
		endcase
	    end // if (baud_sample)
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			data_out_valid <= 0;
			rxd_hold_reg   <= 0;
			sample_ct      <= 0;
			data_out       <= 0;
			bit_ct         <= 0;
			state          <= Edge;
		end else begin
			data_out_valid <= data_out_validNext;
			rxd_hold_reg   <= rxd_hold_regNext;
			sample_ct      <= sample_ctNext;
			data_out       <= data_outNext;
			bit_ct         <= bit_ctNext;
			state          <= stateNext;
		end
	end

endmodule: uart_rx

// RS-232 8-N-1 transceiver
module uart #(
	parameter CLK_FREQ = 50000000, // 50 MHz
	parameter BAUDRATE = 115200
) (
	// rs232 interface (external facing)
	input  logic rxd, // RX data
	output logic txd, // TX data
	input  logic rts, // remote ready to receive data
	output logic cts, // ready to receive from remote

	// uart input pipeline (from design, for external TX)
	input  logic [7:0] data_in,
	input  logic       data_in_valid,
	output logic       data_in_ready,

	// uart output pipeline (to design, from external RX)
	output logic [7:0] data_out,
	output logic       data_out_valid,
	input  logic       data_out_ready,

	input logic clk,
	input logic rst
);

	// start of each tx "baud slot", rx "baud sample" intervals:
	logic baud_slot, baud_sample;

	baud_clock #(
		.CLK_FREQ(CLK_FREQ),
		.BAUDRATE(BAUDRATE)
	) inst_baud_clock (
		.baud_slot(baud_slot),
		.baud_sample(baud_sample),
		.clk(clk),
		.rst(rst)
	);

	// uart tx path:
	uart_tx inst_uart_tx (
		.txd(txd),
		.rts(rts),
		.data_in(data_in),
		.data_in_valid(data_in_valid),
		.data_in_ready(data_in_ready),
		.baud_slot(baud_slot),
		.clk(clk),
		.rst(rst)
	);

	// uart rx path:
	uart_rx inst_uart_rx (
		.rxd(rxd),
		.cts(cts),
		.data_out(data_out),
		.data_out_valid(data_out_valid),
		.data_out_ready(data_out_ready),
		.baud_sample(baud_sample),
		.clk(clk),
		.rst(rst)
	);

endmodule: uart

`ifdef TB_BCLK
// // verilator --binary --trace -DTB_BCLK --top tb_baud_clock uart.sv
module tb_baud_clock ();
	localparam CLK_FREQ = 50000000;
	localparam BAUDRATE =   115200;

	// number of cycles to simulate:
	localparam BAUD_TICKS = CLK_FREQ / BAUDRATE;
	localparam N = 100 * BAUD_TICKS;

	logic clk, rst, baud_slot, baud_sample;

	baud_clock #(
		.CLK_FREQ(CLK_FREQ),
		.BAUDRATE(BAUDRATE)
	) inst_baud_clock (
		.baud_slot(baud_slot),
		.baud_sample(baud_sample),
		.clk(clk),
		.rst(rst)
	);

	// generate clock:
	always #5 clk <= ~clk;

	// initialize variables, issue reset:
	initial begin
		clk = 0;
		rst = 1;

		#25 rst = 0;
	end

	// run simulation for N cycles:
	initial begin
		for (int i = 0; i < N; i = i + 1) begin
			@(posedge clk);
		end
		$finish;
	end

	// output waveforms to vcd file:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(2); // go two levels of submodules deep
	end

endmodule: tb_baud_clock
`endif // TB_BCLK

`ifdef TB_TX
// // verilator --binary --trace -DTB_TX --top tb_uart_tx uart.sv valid_ready.sv
module tb_uart_tx ();
	localparam CLK_FREQ = 50000000;
	localparam BAUDRATE = 115200;
	localparam BAUD_TICKS = CLK_FREQ / BAUDRATE;
	// number of cycles to simulate:
	localparam N = 100 * BAUD_TICKS;

	logic clk, rst, baud_slot, baud_sample, rts, txd;
	logic inp_valid, inp_ready, f2t_valid, f2t_ready;
	logic [7:0] inp_data;
	logic [7:0] f2t_data;

/*
	valid_ready_sync_fifo #(
		.DW(8),
		.PW(3)
*/
	valid_ready_bridge #(
		.DW(8)
	) inst_vr_buf (
		.i_data(inp_data),
		.i_valid(inp_valid),
		.i_ready(inp_ready),
		.o_data(f2t_data),
		.o_valid(f2t_valid),
		.o_ready(f2t_ready),
		.clk(clk),
		.rst(rst)
	);

	baud_clock #(
		.CLK_FREQ(CLK_FREQ),
		.BAUDRATE(BAUDRATE)
	) inst_baud_clock (
		.baud_slot(baud_slot),
		.baud_sample(baud_sample),
		.clk(clk),
		.rst(rst)
	);

	uart_tx inst_uart_tx (
		.txd(txd),
		.rts(rts),
		.data_in(f2t_data),
		.data_in_valid(f2t_valid),
		.data_in_ready(f2t_ready),
		.baud_slot(baud_slot),
		.clk(clk),
		.rst(rst)
	);

	// generate clock:
	always #5 clk <= ~clk;

	// initialize variables, issue reset:
	initial begin
		clk = 0;
		rst = 1;
		rts = 1; // hardcode RTS from "remote end" to 1 to "disable"!
		inp_valid = 0;

		#25 rst = 0;
	end

	// run simulation for N cycles:
	initial begin
		for (int i = 0; i < N; i = i + 1) begin
			@(posedge clk);
		end
		$finish;
	end

	// output waveforms to vcd file:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(2); // go two levels of submodules deep
	end

	// write some data into the ready/valid pipeline leading to the uart:
	initial begin
		// wait 5 baud slots for things to settle:
		repeat (5 * BAUD_TICKS) begin
			@(posedge clk);
		end

		// write three values into fifo:
		for (int i = 0; i < 3; i = i + 1) begin
			// wait until space in fifo:
			while (!inp_ready)
				@(posedge clk);

			// drive new data into fifo:
			inp_valid = 1;
			inp_data = 8'b00100101;
			@(posedge clk);
		end

		// pause data production:
		inp_valid = 0;
		inp_data = 0;
		@(posedge clk);


		// pause for 25 baud slots
		repeat (25 * BAUD_TICKS) begin
			@(posedge clk);
		end

		// write three more values into fifo:
		for (int i = 0; i < 3; i = i + 1) begin
			// wait until space in fifo:
			while (!inp_ready)
				@(posedge clk);

			// drive new data into fifo:
			inp_valid = 1;
			inp_data = 8'b10100101;
			@(posedge clk);
		end

		// pause data production again, until the end:
		inp_valid = 0;
		inp_data = 0;
		@(posedge clk);

	end

endmodule: tb_uart_tx
`endif // TB_TX

`ifdef TB_RX
// // verilator --binary --trace -DTB_RX --top tb_uart_txrx  uart.sv
module tb_uart_txrx ();

	localparam CLK_FREQ = 50000000;
	localparam BAUDRATE = 115200;
	localparam BAUD_TICKS = CLK_FREQ / BAUDRATE;
	// number of cycles to simulate:
	localparam N = 200 * BAUD_TICKS;

	logic clk, rst, rxd, txd, rts, cts, i_valid, i_ready, o_valid, o_ready;
	logic [7:0] i_data, o_data;

	// simulate transmission delay (connect rxd to delay_buf[0]):
	logic [2047:0] delay_buf;
	always @(posedge clk) begin
		delay_buf <= {txd, delay_buf[2047:1]};
	end

	// loop txd back into rxd, so we "receive" the data we sent:
	assign rxd = delay_buf[0];
	//assign rxd = txd; // no delay
	assign rts = cts;

	uart #(
		.CLK_FREQ(CLK_FREQ),
		.BAUDRATE(BAUDRATE)
	) inst_uart (
		.rxd(rxd),
		.txd(txd),
		.rts(rts),
		.cts(cts),
		.data_in(i_data),
		.data_in_valid(i_valid),
		.data_in_ready(i_ready),
		.data_out(o_data),
		.data_out_valid(o_valid),
		.data_out_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// generate clock:
	always #5 clk <= ~clk;

	// initialize variables, issue reset:
	initial begin
		clk     = 0;
		rst     = 1;
		i_valid = 0;
		o_ready = 0;

		#25 rst = 0;
	end

	// simulate for N cycles:
	initial begin
		for (int i = 0; i < N; i = i + 1) begin
			@(posedge clk);
		end
		$finish;
	end

	// waveforms to vcd file:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(3); // go three submodule layers deep
	end

	// writer:
	initial begin
		// wait 5 baud ticks for things to settle:
		repeat (5 * BAUD_TICKS) begin
			@(posedge clk);
		end

		for (int i = 0; i < 40; i = i + 1) begin

			// Wait until there is space in fifo
			while (!i_ready) begin
				i_valid = 0;
				@(posedge clk);
				//$display("[%0t] FULL, wait 4 reads", $time);
			end;

			// Drive new values into FIFO
			i_valid = 1; // $random[0];
			i_data  = $random[7:0];
			if (i_valid) begin
				$display("[%0t] clk i=%0d i_data=0x%0h",
					 $time, i, i_data);
			end
			// Wait for next clock edge
			@(posedge clk);

/*
			// optional -- space out writes to test edge detection:
			repeat (20 * BAUD_TICKS) begin
				i_valid = 0;
				@(posedge clk);
			end
*/
		end
	end

	// reader:
	initial begin
		@(posedge clk);

		while (1) begin

			// Wait until there is data in fifo
			while (!o_valid) begin
				o_ready = 0;
				//$display("[%0t] EMPTY, wait 4 writes", $time);
				@(posedge clk);
			end;

			// Sample new values from FIFO at random pace
			o_ready = $random[0];
			if (o_ready) begin
				$display("[%0t] clk o_data=0x%0h ",
					 $time, o_data);
			end

			@(posedge clk);
		end
	end

endmodule: tb_uart_txrx
`endif // TB_RX
