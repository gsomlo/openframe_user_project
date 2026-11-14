// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`default_nettype none

module valid_ready_sync_fifo #(
	parameter DW = 16,
	parameter PW = 3,              // pointer width (buf. size = 2^PW)
	parameter ENABLE_I_READY_2 = 0 // `i_ready` means >= 2 available slots
) (
	// input (write) interface:
        input  logic [DW-1:0] i_data,
	input  logic          i_valid, // a.k.a. `wr_en`
	output logic          i_ready, // a.k.a. `!full`
				       // (or >= 2 slots if ENABLE_I_READY_2)

	// output (read) interface:
        output logic [DW-1:0] o_data,
        output logic          o_valid, // a.k.a. `!empty`
	input  logic          o_ready, // a.k.a. `rd_en`

	input logic clk,
	input logic rst
);

	// size of circular buffer (number of data words):
	localparam NUMW = 2 ** PW;

	// "memory" buffer for storing data:
	logic [DW-1:0] fifo[0:NUMW-1];

	// write and read pointers:
	logic [PW-1:0] wptr, wptr_p1, rptr, rptr_p1;
	assign wptr_p1 = (wptr + 1);
	assign rptr_p1 = (rptr + 1);

	// output (read) data (invalid when empty):
	assign o_data = fifo[rptr];

	// utilization counter:
	logic [PW:0] util, util_p1, util_m1;
	assign util_p1 = (util + 1);
	assign util_m1 = (util - 1);

	// we need a proper, internal "input-ready" signal:
	logic inp_rdy;
	assign inp_rdy = ~util[PW]; // (util < NUMW); (only checking MSB)
	assign o_valid = |util;     // (util > 0);

	// externally-facing `i_ready` depends on `ENABLE_I_READY_2`
	generate
	if (ENABLE_I_READY_2) begin
	    // `i_ready` guarantees >= 2 available slots in the fifo:
	    assign i_ready = ~(util[PW] | &util[PW-1:0]); // (util < NUMW-1);
	end else begin
	    // `i_ready` guarantees >= 1 available slots in the fifo:
	    assign i_ready = inp_rdy;
	end
	endgenerate

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_valid & inp_rdy;
	assign o_handshake = o_valid & o_ready;

	always_ff @(posedge clk) begin
		if (rst) begin
			wptr <= 0;
			rptr <= 0;
			util <= 0;
		end else begin
			// input/write op:
			if (i_handshake) begin
				fifo[wptr] <= i_data;
				wptr <= wptr_p1; // wptr <= wptr + 1;
			end
			// output/read op:
			if (o_handshake) begin
				rptr <= rptr_p1; // rptr <= rptr + 1;
			end
			// update utilization:
			case ({i_handshake, o_handshake})
			2'b01:   util <= util_m1; // util <= util - 1;
			2'b10:   util <= util_p1; // util <= util + 1;
			default: util <= util;
			endcase
		end
	end

endmodule: valid_ready_sync_fifo

// "simple" means we're saving on logic at the expense of never being able
// to totally fill the circular buffer (max. utilization is 2**PW - 1)
// NOTE: according to yosys, this saves about 14 gates
module valid_ready_sync_fifo_simple #(
	parameter DW = 16,
	parameter PW = 3,              // pointer width (buf. size = 2^PW)
	parameter ENABLE_I_READY_2 = 0 // `i_ready` means >= 2 available slots
) (
	// input (write) interface:
        input  logic [DW-1:0] i_data,
	input  logic          i_valid, // a.k.a. `wr_en`
	output logic          i_ready, // a.k.a. `!full`
				       // (or >= 2 slots if ENABLE_I_READY_2)

	// output (read) interface:
        output logic [DW-1:0] o_data,
        output logic          o_valid, // a.k.a. `!empty`
	input  logic          o_ready, // a.k.a. `rd_en`

	input logic clk,
	input logic rst
);

	// size of circular buffer (number of data words):
	localparam NUMW = 2 ** PW;

	// "memory" buffer for storing data:
	logic [DW-1:0] fifo[0:NUMW-1];

	// write and read pointers:
	logic [PW-1:0] wptr, wptr_p1, rptr, rptr_p1;
	assign wptr_p1 = (wptr + 1);
	assign rptr_p1 = (rptr + 1);

	// output (read) data (invalid when empty):
	assign o_data = fifo[rptr];

	// we need a proper, internal "input-ready" signal:
	logic inp_rdy;
	assign inp_rdy = ~(wptr_p1 == rptr); // ~full a.k.a ~(wptr + 1 == rptr)
	assign o_valid = ~(wptr == rptr);    // ~empty
	// NOTE: in this implementation, the maximum buffer utilization is
	//       (NUMW - 1), as full NUMW utilization is indistinguishable
	//       from an empty buffer w/o an additional utilization counter!!!

	// externally-facing `i_ready` depends on `ENABLE_I_READY_2`
	generate
	if (ENABLE_I_READY_2) begin
	    logic [PW-1:0] wptr_p2;
	    assign wptr_p2 = (wptr + 2);
	    // `i_ready` guarantees >= 2 available slots in the fifo:
	    assign i_ready = inp_rdy & ~(wptr_p2 == rptr);
	end else begin
	    // `i_ready` guarantees >= 1 available slots in the fifo:
	    assign i_ready = inp_rdy;
	end
	endgenerate

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_valid & inp_rdy;
	assign o_handshake = o_valid & o_ready;

	always_ff @(posedge clk) begin
		if (rst) begin
			wptr <= 0;
			rptr <= 0;
		end else begin
			// input/write op:
			if (i_handshake) begin
				fifo[wptr] <= i_data;
				wptr <= wptr_p1; // wptr <= wptr + 1;
			end
			// output/read op:
			if (o_handshake) begin
				rptr <= rptr_p1; // rptr <= rptr + 1;
			end
		end
	end

endmodule: valid_ready_sync_fifo_simple

module valid_ready_bridge #(
	parameter DW = 8
) (
	// in valid/ready interface:
	input  logic [DW-1:0] i_data,
	input  logic          i_valid,
	output logic          i_ready,

	// out valid/ready interface:
	output logic [DW-1:0] o_data,
	output logic          o_valid,
	input  logic          o_ready,

	input logic clk,
	input logic rst
);

	// accept input if either consumer is waiting (`o_ready`), or if we
	// don't already have an unconsumed data token on offer (`~o_valid`):
	assign i_ready = o_ready | ~o_valid;

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_valid & i_ready;
	assign o_handshake = o_valid & o_ready;

	// `o_data` and `o_valid` are registers (flops, a.k.a. "Q"),
	// so we need to calculate next ("D") values for them:
	logic [DW-1:0] o_dataNext;
	logic          o_validNext;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_dataNext  = o_data;
		o_validNext = o_valid;

		if (i_handshake) begin
			o_validNext = 1;
			o_dataNext  = i_data;
		end else if (o_handshake) begin
			// i.e., (o_handshake & ~i_handshake);
			// output handshake takes away our current output,
			// but no input handshake means we won't have valid
			// data on offer for the next clock edge:
			o_validNext = 0;
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			o_data  <= 0;
			o_valid <= 0;
		end else begin
			o_data  <= o_dataNext;
			o_valid <= o_validNext;
		end
	end

endmodule: valid_ready_bridge

module valid_ready_filter #(
	parameter DW = 8
) (
	// in valid/ready interface:
	input  logic [DW-1:0] i_data,
	input  logic          i_valid,
	output logic          i_ready,

	// out valid/ready interface:
	output logic [DW-1:0] o_data,
	output logic          o_valid,
	input  logic          o_ready,

	input logic clk,
	input logic rst
);

	// accept input if either consumer is waiting (`o_ready`), or if we
	// don't already have an unconsumed data token on offer (`~o_valid`):
	assign i_ready = o_ready | ~o_valid;

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_valid & i_ready;
	assign o_handshake = o_valid & o_ready;

	// `o_data` and `o_valid` are registers (flops, a.k.a. "Q"),
	// so we need to calculate next ("D") values for them:
	logic [DW-1:0] o_dataNext;
	logic          o_validNext;

	// forward input to output if true;
	// consume input w/o forwarding if false:
	logic i_o_forward;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_dataNext  = o_data;
		o_validNext = o_valid;

		// set forwarding condition:
		// NOTE: may be arbitrarily complex, e.g. set from a FSM
		i_o_forward = ~i_data[0]; // even numbers only
		// i_o_forward = i_data[0]; // odd numbers only

		if (i_handshake & i_o_forward) begin
			o_validNext = 1;
			o_dataNext  = i_data;
		end else if (o_handshake) begin
			// i.e., (o_handshake & (~i_handshake | ~i_o_forward);
			// output handshake takes away our current output,
			// but no eligible input means we won't have valid
			// data on offer for the next clock edge:
			o_validNext = 0;
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			o_data  <= 0;
			o_valid <= 0;
		end else begin
			o_data  <= o_dataNext;
			o_valid <= o_validNext;
		end
	end

endmodule: valid_ready_filter

module val_rdy_filt_gen #(
	parameter DW = 8,
	parameter GW = 4,
	parameter GC = 4
) (
	// in valid/ready interface:
	input  logic [DW-1:0] i_data,
	input  logic          i_valid,
	output logic          i_ready,

	// out valid/ready interface:
	output logic [DW-1:0] o_data,
	output logic          o_valid,
	input  logic          o_ready,

	input logic clk,
	input logic rst
);

	// output generator counter (0 means we're filtering):
	logic [GW-1:0] gen_ctr, gen_ctrNext;

	// state flag (generating == ~filtering):
	logic filtering;
	assign filtering = ~|gen_ctr; // (gen_ctr == 0)

	// accept input if either consumer is waiting (`o_ready`), or if we
	// don't already have an unconsumed data token on offer (`~o_valid`),
	// but *only* while filtering:
	assign i_ready = filtering & (o_ready | ~o_valid);

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_valid & i_ready;
	assign o_handshake = o_valid & o_ready;

	// `o_data` and `o_valid` are registers (flops, a.k.a. "Q"),
	// so we need to calculate next ("D") values for them:
	logic [DW-1:0] o_dataNext;
	logic          o_validNext;

	// trigger generating mode if true;
	logic trigger_gen;

	// forward input to output if true;
	// consume input w/o forwarding if false:
	logic i_o_forward;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_dataNext  = o_data;
		o_validNext = o_valid;
		gen_ctrNext = gen_ctr;

		// set forwarding and trigger conditions:
		// NOTE: may be arbitrarily complex, e.g. set from a FSM
		i_o_forward = ~i_data[0]; // even numbers only
		trigger_gen = (i_data == DW'('h42));

		if (filtering) begin
			if (i_handshake & (trigger_gen | i_o_forward)) begin
				// NOTE: trigger_gen has precedence!
				if (trigger_gen) begin
					// switch to generating mode:
					gen_ctrNext = GW'(GC - 1); // set ctr.
					o_dataNext  = DW'('h41); // gen. 0x41
				end else begin
					// input eligible to be forwarded:
					o_dataNext  = i_data;
				end
				o_validNext = 1;
			end else if (o_handshake) begin
				// no eligible output for next cycle:
				o_validNext = 0;
			end
		end else if (o_handshake) begin
			// decrement generate-item counter:
			gen_ctrNext = gen_ctr - 1;
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			o_data  <= 0;
			o_valid <= 0;
			gen_ctr <= 0;
		end else begin
			o_data  <= o_dataNext;
			o_valid <= o_validNext;
			gen_ctr <= gen_ctrNext;
		end
	end

endmodule: val_rdy_filt_gen

module val_rdy_filt_gen_susp #(
	parameter DW = 8,
	parameter GW = 4,
	parameter GC = 4
) (
	// in valid/ready interface:
	input  logic [DW-1:0] i_data,
	input  logic          i_valid,
	output logic          i_ready,

	// out valid/ready interface:
	output logic [DW-1:0] o_data,
	output logic          o_valid,
	input  logic          o_ready,

	// pause signal:
	// NOTE: while this might be an interesting intellectual exercise,
	// "pausing" is only useful if done by a third-party! If either the
	// producer or consumer want a pause, they can just de-assert their
	// i_valid (producer) or o_ready (consumer) signals!!!
	input logic pause,

	input logic clk,
	input logic rst
);

	// pause state flag:
	logic paused, pausedNext;
	// parallel o_valid "save state" to be used during resume:
	logic op_val, op_valNext;

	// output generator counter (0 means we're filtering):
	logic [GW-1:0] gen_ctr, gen_ctrNext;

	// state flag (generating == ~filtering):
	logic filtering;
	assign filtering = ~|gen_ctr; // (gen_ctr == 0)

	// accept input if either consumer is waiting (`o_ready`), or if we
	// don't already have an unconsumed data token on offer (`~o_valid`),
	// but *only* while filtering and not while paused:
	// NOTE: if [about to be] paused, disallow input handshake!
	assign i_ready = ~(pause | paused) & filtering & (o_ready | ~o_valid);

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_valid & i_ready;
	assign o_handshake = o_valid & o_ready;

	// `o_data` and `o_valid` are registers (flops, a.k.a. "Q"),
	// so we need to calculate next ("D") values for them:
	logic [DW-1:0] o_dataNext;
	logic          o_validNext;

	// trigger generating mode if true;
	logic trigger_gen;
	assign trigger_gen = (i_data == DW'('h42));

	// forward input to output if true;
	// consume input w/o forwarding if false:
	logic i_o_forward;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_dataNext  = o_data;
		o_validNext = o_valid;
		gen_ctrNext = gen_ctr;
		pausedNext  = paused;
		op_valNext  = op_val;

		// set forwarding condition:
		// NOTE: may be arbitrarily complex, e.g. set from a FSM
		i_o_forward = ~i_data[0]; // even numbers only

		if (filtering) begin
			if (i_handshake & (trigger_gen | i_o_forward)) begin
				// NOTE: trigger_gen has precedence!
				if (trigger_gen) begin
					// switch to generating mode:
					gen_ctrNext = GW'(GC - 1); // set ctr.
					o_dataNext  = DW'('h41); // gen. 0x41
				end else begin
					// input eligible to be forwarded:
					o_dataNext  = i_data;
				end
				o_validNext = 1;
				op_valNext  = 1;
			end else if (o_handshake) begin
				// no eligible output for next cycle
				// (or cycle immediately following unpause):
				o_validNext = 0;
				op_valNext  = 0;
			end
		end else if (o_handshake) begin
			// decrement generate-item counter:
			gen_ctrNext = gen_ctr - 1;
		end

		if (pause) begin
			pausedNext  = 1;
			o_validNext = 0;
		end else if (paused) begin
			pausedNext  = 0;
			o_validNext = op_val;
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			o_data  <= 0;
			o_valid <= 0;
			gen_ctr <= 0;
			paused  <= 0;
			op_val  <= 0;
		end else begin
			o_data  <= o_dataNext;
			o_valid <= o_validNext;
			gen_ctr <= gen_ctrNext;
			paused  <= pausedNext;
			op_val  <= op_valNext;
		end
	end

endmodule: val_rdy_filt_gen_susp

module valid_ready_serializer #(
	parameter DW = 8,
	parameter IW = 5 // input width in DW-sized words
) (
	// in valid/ready interface (wide):
	input  logic [IW*DW-1:0] i_data,
	input  logic             i_valid,
	output logic             i_ready,

	// out valid/ready interface (narrow):
	output logic [DW-1:0] o_data,
	output logic          o_valid,
	input  logic          o_ready,

	input logic clk,
	input logic rst
);

	// input data register:
	logic [IW*DW-1:0] regbuf, regbufNext;
	// output is data register LSW
	assign o_data = regbuf[DW-1:0];

	// data word counter:
	localparam CW = $clog2(IW); // counter width
	logic [CW:0] cnt, cntNext;  // NOTE: cnt is deliberately (CW+1) wide
				    // (cnt == -1) resv'd for handshake cond.

	// accept input if either consumer is waiting (`o_ready`), or if we
	// don't already have an unconsumed data token on offer (`~o/_valid`),
	// but only once we're down to the *last* (narrow) data word,
	// (i.e., once cnt <= 0):
	assign i_ready = (o_ready | ~o_valid) &
			 (cnt == 0 | &cnt); // 0 or -1

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = (i_valid & i_ready);
	assign o_handshake = (o_valid & o_ready);

	// next value for o_valid
	logic o_validNext;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		regbufNext  = regbuf;
		cntNext     = cnt;
		o_validNext = o_valid;

		if (i_handshake) begin
			regbufNext  = i_data;
			cntNext     = (CW + 1)'(IW - 1);
			o_validNext = 1;
		end else if (o_handshake) begin
			regbufNext = {DW'('h0), regbuf[IW*DW-1:DW]};
			cntNext    = cnt - 1;
			if (cnt == 0) begin
				o_validNext = 0;
			end
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			regbuf  <= 0;
			cnt     <= 0;
			o_valid <= 0;
		end else begin
			regbuf  <= regbufNext;
			cnt     <= cntNext;
			o_valid <= o_validNext;
		end
	end

endmodule: valid_ready_serializer

`ifdef TBVRPIPE
// // verilator --binary --trace -DTBVRPIPE --top tb_vrpipe valid_ready.sv
// // iverilog -g2005-sv -DTBVRPIPE -s tb_vrpipe -o tb_vrpipe valid_ready.sv
// // tb_vrpipe > o.log; paste <(grep i_data o.log) <(grep o_data o.log)
module tb_vrpipe ();

	// parameters:
	localparam NC = 999; // clock cycles to simulate
	localparam DW =   8; // data width
	localparam PW =   3; // fifo pointer width (depth = 2^PW)
	localparam GW =   4; // width of generate counter (val_rdy_filt_gen)
	localparam GC =   4; // count of generated sequence (val_rdy_filt_gen)

	// provide clk, rst:
	logic clk, rst;
	initial begin
		clk     = 1;
		rst     = 1;
		#22 rst = 0;
	end
	always #5 clk <= ~clk;

	// run simulation for NC `clk` cycles:
	initial begin
		repeat (NC)
			@(posedge clk);
		$finish;
	end

	// record signal waveforms:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(3); // go 3 submodule layers deep
	end

	// DUT (and associated wires):
	logic [7:0] i_data, o_data;
	logic       i_valid, i_ready, o_valid, o_ready;

/*
	valid_ready_sync_fifo #(
		.DW(DW),
		.PW(PW),
		.ENABLE_I_READY_2(0)
	valid_ready_sync_fifo_simple #(
		.DW(DW),
		.PW(PW),
		.ENABLE_I_READY_2(0)
	valid_ready_bridge #(
		.DW(DW)
	valid_ready_filter #(
		.DW(DW)
*/
	val_rdy_filt_gen #(
		.DW(DW),
		.GW(GW),
		.GC(GC)
	) dut (
		.i_data(i_data),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_data(o_data),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_valid <= 0;
			i_data  <= 0;
			o_ready <= 0;
		end else begin
`ifdef VERILATOR
			// upstream/master/producer:
			i_valid <= $random[0];
			i_data  <= $random[7:0];
			// downstream/slave/consumer:
			o_ready <= $random[0];
`else
			// upstream/master/producer:
			i_valid <= $random;
			i_data  <= $random;
			// downstream/slave/consumer:
			o_ready <= $random;
`endif
			// show data received from upstream/master/producer:
//			if (i_valid & i_ready && ~i_data[0]) // val_rdy_filt_gen
			if (i_valid & i_ready)
				$display("[%04t] i_data=0x%h", $time, i_data);
			// show data transfered to downstream/slave/consumer:
			if (o_valid & o_ready)
				$display("[%04t] o_data=0x%h", $time, o_data);
			// NOTE: input stream MUST match output stream,
			//       *unless* filtering occurs!!!

			// NOTE: uncomment below to test for throughput!
			//
			// bursty, always-valid provider:
//			i_valid <= 1;
			//
			// bursty, always-ready consumer:
//			o_ready <= 1;
		end
	end

endmodule: tb_vrpipe
`endif // TBVRPIPE

`ifdef TBPAUSE
// // verilator --binary --trace -DTBPAUSE --top tb_pause valid_ready.sv
// // iverilog -g2005-sv -DTBPAUSE -s tb_pause -o tb_pause valid_ready.sv
// // tb_pause > o.log; paste <(grep i_data o.log) <(grep o_data o.log)
module tb_pause ();

	// parameters:
	localparam NC = 999; // clock cycles to simulate

	// provide clk, rst:
	logic clk, rst;
	initial begin
		clk     = 1;
		rst     = 1;
		#22 rst = 0;
	end
	always #5 clk <= ~clk;

	// run simulation for NC `clk` cycles:
	initial begin
		repeat (NC)
			@(posedge clk);
		$finish;
	end

	// record signal waveforms:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(3); // go 3 submodule layers deep
	end

	// DUT (and associated wires):
	logic [7:0] i_data, o_data;
	logic       i_valid, i_ready, o_valid, o_ready, pause;

	val_rdy_filt_gen_susp #(
		.DW(8),
		.GW(4),
		.GC(4)
	) dut (
		.i_data(i_data),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_data(o_data),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.pause(pause),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_valid <= 0;
			i_data  <= 0;
			o_ready <= 0;
			pause   <= 0;
		end else begin
`ifdef VERILATOR
			// upstream/master/producer:
			i_valid <= $random[0];
			i_data  <= $random[7:0];
			// downstream/slave/consumer:
			o_ready <= $random[0];
			// random pause signal:
			pause   <= $random[0];
`else
			// upstream/master/producer:
			i_valid <= $random;
			i_data  <= $random;
			// downstream/slave/consumer:
			o_ready <= $random;
			// random pause signal:
			pause   <= $random;
`endif
//			// toggle pause every 100 cycles:
//			if (($time/10) % 100 == 10)
//				pause <= ~pause;
			// show data received from upstream/master/producer:
			if (i_valid & i_ready && ~i_data[0]) // match filter
				$display("[%04t] i_data=0x%h", $time, i_data);
			// show data transfered to downstream/slave/consumer:
			if (o_valid & o_ready)
				$display("[%04t] o_data=0x%h", $time, o_data);

			// NOTE: uncomment below to test for throughput!
			//
			// bursty, always-valid provider:
//			i_valid <= 1;
			//
			// bursty, always-ready consumer:
//			o_ready <= 1;
		end
	end

endmodule: tb_pause
`endif // TBPAUSE

`ifdef TBVRSER
// // verilator --binary --trace -DTBVRSER --top tb_vrser valid_ready.sv
// // iverilog -g2005-sv -DTBVRSER -s tb_vrser -o tb_vrser valid_ready.sv
// // tb_vrser > o.log; paste <(grep i_data o.log) <(grep o_data o.log)
module tb_vrser ();

	// parameters:
	localparam NC = 64; // clock cycles to simulate
	localparam DW =  8; // serializer data width:
	localparam IW =  5; // serializer input vector width (in data words):

	// provide clk, rst:
	logic clk, rst;
	initial begin
		clk     = 1;
		rst     = 1;
		#22 rst = 0;
	end
	always #5 clk <= ~clk;

	// run simulation for NC `clk` cycles:
	initial begin
		repeat (NC)
			@(posedge clk);
		$finish;
	end

	// record signal waveforms:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(3); // 3 submodule layers deep
	end

	// DUT (and associated wires):
	logic [IW*DW-1:0] i_data;
	logic    [DW-1:0] o_data;
	logic i_valid, i_ready, o_valid, o_ready;

	valid_ready_serializer #(
		.DW(DW),
		.IW(IW)
	) dut (
		.i_data(i_data),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_data(o_data),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_valid <= 0;
			i_data  <= 0;
			o_ready <= 0;
		end else begin
`ifdef VERILATOR
			// upstream/master/producer:
			i_valid <= $random[0];
			i_data  <= {$random,$random,$random,$random}[IW*DW-1:0];
			// downstream/slave/consumer:
			o_ready <= $random[0];
`else
			// upstream/master/producer:
			i_valid <= $random;
			i_data  <= $random;
			// downstream/slave/consumer:
			o_ready <= $random;
`endif
			// show data received from upstream/master/producer:
			if (i_valid & i_ready)
				$display("[%04t] i_data=0x%h", $time, i_data);
			// show data transfered to downstream/slave/consumer:
			if (o_valid & o_ready)
				$display("[%04t] o_data=0x%h", $time, o_data);

			// NOTE: uncomment below to test for throughput!
			//
			// bursty, always-valid provider:
//			i_valid <= 1;
			//
			// bursty, always-ready consumer:
//			o_ready <= 1;
		end
	end

	// reader:
	always @(posedge clk) begin
		if (rst) begin
		end else begin
		end
	end

endmodule: tb_vrser
`endif // TBVRSER
