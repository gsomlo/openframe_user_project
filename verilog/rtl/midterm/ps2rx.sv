// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`default_nettype none

// signal debouncer
module debounce #(
	parameter CW = 3 // counter width
) (
	input  logic a, // raw input signal
	output logic y, // stable, debounced signal

	input logic clk,
	input logic rst
);

	// 3-bit shift register to keep track of input:
	// NOTE: [2] = "previous", [1] = "current", [0] = "settling"
	logic [2:0] a_reg, a_regNext;

	// keep track of whether input flipped:
	logic a_flip;
	assign a_flip = (a_reg[2] ^ a_reg[1]);

	// debounce counter:
	logic [CW-1:0] deb_ctr, deb_ctrNext;

	// next output value:
	logic yNext;

	// combinationally compute Next values:
	always_comb begin
		// shift in latest sample:
		a_regNext   = {a_reg[1:0], a};
		// start the count over if input flips:
		deb_ctrNext = a_flip ? 0 : deb_ctr + 1;
		// a stable for count-max, pass it through to y:
		yNext       = (&deb_ctr) ? a_reg[2] : y;
	end

	// sequentially update registers:
	always_ff @(posedge clk) begin
		if (rst) begin
			a_reg   <= 0;
			y       <= 0;
			deb_ctr <= 0;
		end else begin
			a_reg   <= a_regNext;
			y       <= yNext;
			deb_ctr <= deb_ctrNext;
		end
	end

endmodule: debounce

// PS/2 raw data receiver
module ps2rx #(
	parameter CLK_FREQ = 50000000 // 50 MHz
) (
	// ps/2 interface (external facing)
	input  logic ps2clk, // ps/2 clock
	input  logic ps2dat, // ps/2 data

	// output ready/valid (producer) interface
	// (to design, from external device)
	output logic [7:0] data_out,
	output logic       data_out_valid,
	input  logic       data_out_ready,

	input logic clk,
	input logic rst
);

	localparam PS2_FREQ = 10000; // 10kHz (worst-case, slow end)
	// clock ticks per ps2 bit (1 ps2 bit = 1 ps2clk tick)
	localparam TICKS_BIT = CLK_FREQ / PS2_FREQ;
	// watchdog count: max. wait for expected falling edge
	localparam TICKS_WDT = 4 * TICKS_BIT;
	// clock ticks per 2us interval (reasonable ps2clk debounce delay)
	localparam TICKS_2US = 2 * CLK_FREQ / 1000000;

	// 11-bit data register [start(LSB), 8-bit data, parity, stop(MSB)]:
	logic [10:0] data_reg, data_regNext;
	assign data_out = data_reg[8:1];

	// 4-bit bit-position counter (count down from 10):
	logic [3:0] bit_ct, bit_ctNext;

	// debounced ps/2 clock signal:
	logic ps2clk_stable;

	// ps/2 clock debouncer (2us, round up to next power of 2):
	debounce #(
		.CW($clog2(TICKS_2US))
	) debounce_inst (
		.a(ps2clk),
		.y(ps2clk_stable),
		.clk(clk),
		.rst(rst)
	);

	// ps/2 clock falling edge detection:
	logic [1:0] edge_detect, edge_detectNext;
	logic is_falling_edge;
	assign is_falling_edge = (edge_detect == 2'b10);

	// ps/2 data stabilized sample:
	logic [1:0] ps2_data, ps2_dataNext;
	logic crt_ps2_data;
	assign crt_ps2_data = ps2_data[1];

	// watchdog counter in case we get stuck waiting for a clock edge
	// (4 slow-end ps/2 clock/bit periods, round up to next power of 2)
	logic [$clog2(TICKS_WDT)-1:0] watch_ct, watch_ctNext;

	// data handshake (hand-over) to inward-facing consumer:
	logic data_out_handshake;
	assign data_out_handshake = (data_out_ready & data_out_valid);

	// next value for data_out_valid:
	logic data_out_validNext;

	// FSM state register:
	enum logic {Idle, DataRx} state, stateNext;

	always_comb begin
	    edge_detectNext    = {edge_detect[0], ps2clk_stable};
	    ps2_dataNext       = {ps2_data[0], ps2dat};
	    data_out_validNext = data_out_handshake ? 0 : data_out_valid;
	    watch_ctNext       = watch_ct + 1;
	    data_regNext       = data_reg;
	    bit_ctNext         = bit_ct;
	    stateNext          = state;

	    unique case (state)
	    Idle: begin
		if (is_falling_edge) begin
			// inhibit prior-data validity (if applicable):
			data_out_validNext = 0;
			// reset watchdog timer:
			watch_ctNext = 0;
			// register start bit:
			data_regNext = {crt_ps2_data, data_reg[10:1]};
			// set bit counter:
			bit_ctNext = 4'h9;
			// move to `DataRx` state:
			stateNext = DataRx;
		end
	    end
	    DataRx: begin
		if (is_falling_edge) begin
			// reset watchdog timer:
			watch_ctNext = 0;
			// register current bit:
			data_regNext = {crt_ps2_data, data_reg[10:1]};
			// decrement bit counter:
			bit_ctNext = bit_ct - 1;
			// did we make it to the stop bit?
			if (bit_ct == 0) begin
				stateNext = Idle;
				// verify start & stop bits, parity:
				// NOTE: `data_reg` shifted by 1 bit
				data_out_validNext =
			    (!data_reg[1] & crt_ps2_data & ^(data_reg[10:2]));
			end
		end else if (&watch_ct) begin
			// watchdog timer expired, we somehow got stuck;
			// abandon everything and start from scratch:
			stateNext = Idle;
		end
	    end
	    endcase
	end

	// advance FSM state:
	always_ff @(posedge clk) begin
		if (rst) begin
			edge_detect    <= 0;
			ps2_data       <= 0;
			data_out_valid <= 0;
			watch_ct       <= 0;
			data_reg       <= 0;
			bit_ct         <= 0;
			state          <= Idle;
		end else begin
			edge_detect    <= edge_detectNext;
			ps2_data       <= ps2_dataNext;
			data_out_valid <= data_out_validNext;
			watch_ct       <= watch_ctNext;
			data_reg       <= data_regNext;
			bit_ct         <= bit_ctNext;
			state          <= stateNext;
		end
	end

endmodule: ps2rx

module byte_to_ascii_hex (
	// consume data bytes read via ps/2
	input  logic [7:0] i_data,
	input  logic       i_valid,
	output logic       i_ready,

	// produce ascii bytes to print out via uart_tx
	output logic [7:0] o_data,
	output logic       o_valid,
	input  logic       o_ready,

	input logic clk,
	input logic rst
);

	// registers containing ASCII hex representation of data byte:
	logic [7:0] hi_b, lo_b, hi_bNext, lo_bNext;

	// FSM states:
	enum logic [1:0] {Idle, Hi, Lo, Sp} state, stateNext;

	always_comb begin
		i_ready   = 0;
		o_valid   = 1;
		o_data    = 0;
		hi_bNext  = hi_b;
		lo_bNext  = lo_b;
		stateNext = state;

		unique case (state)
		Idle: begin // accept and process input byte (no output data)
			i_ready = 1;
			o_valid = 0;
			if (i_valid) begin
				hi_bNext = {4'h0, i_data[7:4]} + 8'h30 +
					 ((i_data[7:4] > 4'h9) ? 8'h07 : 8'h0);
				lo_bNext = {4'h0, i_data[3:0]} + 8'h30 +
					 ((i_data[3:0] > 4'h9) ? 8'h07 : 8'h0);
				stateNext = Hi;
			end
		end
		Hi: begin // output High hex digit
			o_data = hi_b;
			if (o_ready) begin
				stateNext = Lo;
			end
		end
		Lo: begin // output Low hex digit
			o_data = lo_b;
			if (o_ready) begin
				stateNext = Sp;
			end
		end
		Sp: begin // output Space character
			o_data = 8'h20;
			if (o_ready) begin
				stateNext = Idle;
			end
		end
		endcase
	end

	// advance FSM state:
	always_ff @(posedge clk) begin
		if (rst) begin
			hi_b  <= 0;
			lo_b  <= 0;
			state <= Idle;
		end else begin
			hi_b  <= hi_bNext;
			lo_b  <= lo_bNext;
			state <= stateNext;
		end
	end

endmodule: byte_to_ascii_hex

`ifdef TB_DEB
// // verilator --binary --trace -DTB_DEB --top tb_debounce ps2rx.sv
module tb_debounce ();

	localparam N=1024;

	logic clk, rst, a, y;

	debounce #(
		.CW(2)
	) debounce_inst (
		.a(a),
		.y(y),
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
		repeat (N) begin
			@(posedge clk);
		end
		$finish;
	end

	// output waveforms to vcd file:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(2); // go two levels of submodules deep
	end

	initial begin
		repeat (30) begin
			@(posedge clk);
		end
		repeat (5) begin
			a = 0;
			@(posedge clk);
		end
		repeat (4) begin
			a = 1;
			@(posedge clk);
		end
		repeat (2) begin
			a = 0;
			@(posedge clk);
		end
		repeat (1) begin
			a = 1;
			@(posedge clk);
		end
		repeat (5) begin
			a = 0;
			@(posedge clk);
		end
		repeat (10) begin
			a = 1;
			@(posedge clk);
		end
		repeat (10) begin
			a = 0;
			@(posedge clk);
		end
	end

endmodule: tb_debounce
`endif // TB_DEB

`ifdef TB_B2ASC
// // verilator --binary --trace -DTB_B2ASC --top tb_b2asc ps2rx.sv
module tb_b2asc ();

	localparam N = 2048;

	logic clk, rst, i_valid, i_ready, o_valid, o_ready;
	logic [7:0] i_data, o_data;

	byte_to_ascii_hex inst_b2asc (
		.i_data(i_data),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_data(o_data),
		.o_valid(o_valid),
		.o_ready(o_ready),
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
		repeat (100) begin
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
			repeat (200) begin
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

endmodule: tb_b2asc
`endif // TB_B2ASC
