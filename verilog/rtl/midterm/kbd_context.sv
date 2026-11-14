// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`include "kbd.svh"

// convert sequences of raw keyboard scan codes into "actionable" events:
module kbd_context (
	// consume raw scan codes produced by the (ps/2) keyboard:
	input  logic [7:0] i_raw_sc,
	input  logic       i_raw_valid,
	output logic       i_raw_ready,

	// produce processed keypress/chord "events", with context:
	output logic [7:0] o_key_sc,
	output kbd_pkg::key_ctx_t   o_key_ctx,
	output logic       o_key_valid,
	input  logic       o_key_ready,

	input logic clk,
	input logic rst
);

	// accept input if consumer is waiting (`o_key_ready`), or if we
	// don't already have an unconsumed token on offer (`~o_key_valid`):
	assign i_raw_ready = o_key_ready | ~o_key_valid;

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_raw_valid & i_raw_ready;
	assign o_handshake = o_key_valid & o_key_ready;

	// next values for sequential output registers:
	logic     [7:0] o_key_scNext;
	kbd_pkg::key_ctx_t       o_key_ctxNext;
	logic           o_key_validNext;

	// forward condition:
	logic i_o_forward;

	// FSM states:
	enum logic [2:0] {Key, Brk, Ext0, Brk0, Ext1, Brk1} state, stateNext;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_key_scNext    = o_key_sc;
		o_key_ctxNext   = o_key_ctx;
		o_key_validNext = o_key_valid;
		stateNext       = state;

		// forwarding condition is false by default, to be
		// overridden by next-state computation logic:
		i_o_forward = 0;

		// advance FSM only on input handshake:
		if (i_handshake) begin
			// next state is most often to `Key`, with
			// some specific exceptions:
			stateNext = Key;

			unique case (state)
			/* verilator lint_off CASEINCOMPLETE */
			Key: begin
				// NOTE: to improve ergonomics, consider
				// swapping CAPS and CTL in this block:
				case (i_raw_sc)
				// toggle, if applicable:
				kbd_pkg::SC_CAPS: o_key_ctxNext.caps = ~o_key_ctx.caps;
				kbd_pkg::SC_SCRL: o_key_ctxNext.scrl = ~o_key_ctx.scrl;
				kbd_pkg::SC_NUML: if (o_key_ctx.ctl3) begin
					  // part of Pause sequence,
					  // treat as pass-through scan code:
					  i_o_forward = 1;
					  // clear ext* context bits:
//					  o_key_ctxNext.ext1 = 0;
					  o_key_ctxNext.ext0 = 0;
					end else begin
					  // not part of Pause sequence,
					  // so toggle context bit:
					  o_key_ctxNext.numl = ~o_key_ctx.numl;
					end
				// set, if applicable:
				kbd_pkg::SC_ALT:  o_key_ctxNext.altl = 1;
				kbd_pkg::SC_CTL:  o_key_ctxNext.ctll = 1;
				kbd_pkg::SC_SHFL: o_key_ctxNext.shfl = 1;
				kbd_pkg::SC_SHFR: o_key_ctxNext.shfr = 1;
				// switch to ext mode, if applicable:
				kbd_pkg::SC_EXT0: stateNext = Ext0;
				kbd_pkg::SC_EXT1: stateNext = Ext1;
				// key release (break):
				kbd_pkg::SC_BRK:  stateNext = Brk;
				// regular key press:
				default: begin
					i_o_forward = 1;
					// clear ext* context bits:
//					o_key_ctxNext.ext1 = 0;
					o_key_ctxNext.ext0 = 0;
				end
				endcase
			end
			Brk: begin
				case (i_raw_sc)
				// clear, if applicable:
				// NOTE: s/CTL/CAPS/ to match any swap in `Key`
				kbd_pkg::SC_ALT:  o_key_ctxNext.altl = 0;
				kbd_pkg::SC_CTL:  o_key_ctxNext.ctll = 0;
				kbd_pkg::SC_SHFL: o_key_ctxNext.shfl = 0;
				kbd_pkg::SC_SHFR: o_key_ctxNext.shfr = 0;
				endcase
			end
			Ext0: begin
				case (i_raw_sc)
				// set, if applicable
				kbd_pkg::SC_ALT:  o_key_ctxNext.altr = 1;
				kbd_pkg::SC_CTL:  o_key_ctxNext.ctlr = 1;
				kbd_pkg::SC_METL: o_key_ctxNext.metl = 1;
				kbd_pkg::SC_METR: o_key_ctxNext.metr = 1;
				kbd_pkg::SC_SHFL: o_key_ctxNext.shf3 = 1;
				// key release (break):
				kbd_pkg::SC_BRK:  stateNext = Brk0;
				// ext0 key press:
				default: begin
					i_o_forward = 1;
					// set ext0 context bit:
					o_key_ctxNext.ext0 = 1;
				end
				endcase
			end
			Brk0: begin
				case (i_raw_sc)
				// clear, if applicable:
				kbd_pkg::SC_ALT:  o_key_ctxNext.altr = 0;
				kbd_pkg::SC_CTL:  o_key_ctxNext.ctlr = 0;
				kbd_pkg::SC_METL: o_key_ctxNext.metl = 0;
				kbd_pkg::SC_METR: o_key_ctxNext.metr = 0;
				kbd_pkg::SC_SHFL: o_key_ctxNext.shf3 = 0;
				endcase
			end
			Ext1: begin
				case (i_raw_sc)
				// set, if applicable
				kbd_pkg::SC_CTL:  o_key_ctxNext.ctl3 = 1;
				// key release (break):
				kbd_pkg::SC_BRK:  stateNext = Brk1;
				// ext1 key press:
				// NOTE: this never happens!
//				// (commented out deliberately)
//				default: begin
//					i_o_forward = 1;
//					// set ext1 context bit:
//					o_key_ctxNext.ext1 = 1;
//				end
				endcase
			end
			Brk1: begin
				case (i_raw_sc)
				// clear, if applicable:
				kbd_pkg::SC_CTL:  o_key_ctxNext.ctl3 = 0;
				endcase
			end
			endcase
		end

		// selectively forward (context-augmented) input scancode:
		if (i_handshake & i_o_forward) begin
			// NOTE: o_key_ctxNext as calculated by the FSM logic
			o_key_scNext    = i_raw_sc;
			o_key_validNext = 1;
		end else if (o_handshake) begin
			// output handshake, but no forwarding-eligible input:
			o_key_validNext = 0;
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			o_key_sc    <= 0;
			o_key_ctx   <= 0; // o_key_ctx.numl <= 1; // default on!
			o_key_valid <= 0;
			state       <= Key;
		end else begin
			o_key_sc    <= o_key_scNext;
			o_key_ctx   <= o_key_ctxNext;
			o_key_valid <= o_key_validNext;
			state       <= stateNext;
		end
	end

endmodule: kbd_context

/* prints out the following format:
┌────────────────── ext1 (always 0, not actually used)
│ ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ ext0
│ ╎ ┌──────────────── caps
│ ╎ │ ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ numl
│ ╎ │ ╎ ┌────────────── scrl
│ ╎ │ ╎ │ ┌╌╌╌╌╌╌╌╌╌╌╌╌╌ metL
│ ╎ │ ╎ │ ╎ ┌──────────── metR
│ ╎ │ ╎ │ ╎ │ ┌╌╌╌╌╌╌╌╌╌╌╌ altL
│ ╎ │ ╎ │ ╎ │ ╎ ┌────────── altR
│ ╎ │ ╎ │ ╎ │ ╎ │ ┌╌╌╌╌╌╌╌╌╌ ctlL
│ ╎ │ ╎ │ ╎ │ ╎ │ ╎ ┌──────── ctlR
│ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ┌╌╌╌╌╌╌╌ ctl3 (ext1-mode ctl during Pause chord)
│ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ╎ ┌────── shfL
│ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ┌╌╌╌╌╌ shfR
│ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ╎ ┌──── shf3 (ext0-mode shfL during PrSc chord)
│ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │   ┌┬─ scancode (hex)
│ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │ ╎ │   ││
e.g.,
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0   1C   // unmodified A
0 0 0 0 0 0 0 0 0 1 0 0 0 0 0   21   // left-ctl C
0 0 0 0 0 0 0 0 0 0 1 0 0 0 0   21   // right-ctl C
0 0 0 0 0 0 0 1 0 0 0 0 0 0 0   22   // left-alt X
... etc.
*/
module kbd_context_to_ascii (
	// consume processed keypress/chord "events", with context:
	input  logic [7:0] key_sc,
	input  kbd_pkg::key_ctx_t   key_ctx,
	input  logic       key_valid,
	output logic       key_ready,

	// produce ascii bytes to print out (e.g., via uart_tx):
	output logic [7:0] out_char,
	output logic       out_valid,
	input  logic       out_ready,

	input logic clk,
	input logic rst
);

	// 15*2 (bit+spc), 2 spc, 2 hex digits, 1 <cr>, 1 <lf> = 36 characters:
	localparam BUFSIZE = 36;
	// round bufsize to next power-of-two, so we can validly index into it
	// at all times:
	logic [7:0] ascii[1 << $clog2(BUFSIZE)];

	// index into buffer:
	logic [$clog2(BUFSIZE)-1:0] idx, idxNext;

	enum logic {Idle, Send} state, stateNext;

	always_comb begin
		key_ready = (state == Idle);
		out_valid = (state == Send);
		out_char  = ascii[idx];

		idxNext   = idx;
		stateNext = state;

		unique case (state)
		Idle: begin
			if (key_valid) begin
				// load buffer with appropriate ascii chars:
				// start with context flags:
				ascii['d35] = 8'h20;
//				ascii['d35] = {7'h0, key_ctx.ext1} | 8'h30;
				ascii['d34] = 8'h20;
				ascii['d33] = {7'h0, key_ctx.ext0} | 8'h30;
				ascii['d32] = 8'h20;
				ascii['d31] = {7'h0, key_ctx.caps} | 8'h30;
				ascii['d30] = 8'h20;
				ascii['d29] = {7'h0, key_ctx.numl} | 8'h30;
				ascii['d28] = 8'h20;
				ascii['d27] = {7'h0, key_ctx.scrl} | 8'h30;
				ascii['d26] = 8'h20;
				ascii['d25] = {7'h0, key_ctx.metl} | 8'h30;
				ascii['d24] = 8'h20;
				ascii['d23] = {7'h0, key_ctx.metr} | 8'h30;
				ascii['d22] = 8'h20;
				ascii['d21] = {7'h0, key_ctx.altl} | 8'h30;
				ascii['d20] = 8'h20;
				ascii['d19] = {7'h0, key_ctx.altr} | 8'h30;
				ascii['d18] = 8'h20;
				ascii['d17] = {7'h0, key_ctx.ctll} | 8'h30;
				ascii['d16] = 8'h20;
				ascii['d15] = {7'h0, key_ctx.ctlr} | 8'h30;
				ascii['d14] = 8'h20;
				ascii['d13] = {7'h0, key_ctx.ctl3} | 8'h30;
				ascii['d12] = 8'h20;
				ascii['d11] = {7'h0, key_ctx.shfl} | 8'h30;
				ascii['d10] = 8'h20;
				ascii['d09] = {7'h0, key_ctx.shfr} | 8'h30;
				ascii['d08] = 8'h20;
				ascii['d07] = {7'h0, key_ctx.shf3} | 8'h30;
				ascii['d06] = 8'h20;
				// add two spaces:
				ascii['d05] = 8'h20;
				ascii['d04] = 8'h20;
				// add upper and lower scan code nibbles:
				ascii['d03] = {4'h0, key_sc[7:4]} + 8'h30 +
					((key_sc[7:4] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d02] = {4'h0, key_sc[3:0]} + 8'h30 +
					((key_sc[3:0] > 4'h9) ? 8'h07 : 8'h0);
				// add <cr> and <lf>:
				ascii['d01] = 8'h0D;
				ascii['d00] = 8'h0A;
				// set counter and move to `Send`:
				idxNext   = 'd35;
				stateNext = Send;
			end
		end
		Send: begin
			if (out_ready) begin
				idxNext = idx - 1;
				if (idx == 0)
					stateNext = Idle;
			end
		end
		endcase
	end

	always_ff @(posedge clk) begin
		if (rst) begin
			idx   <= 0;
			state <= Idle;
		end else begin
			idx   <= idxNext;
			state <= stateNext;
		end
	end

endmodule: kbd_context_to_ascii

// convert raw keyboard scancodes to ascii repr. of context-enabled key codes
// NOTE: "hide" key_ctx_t type from outside test harness
module kbd_context_wrapper (
	// consume raw scan codes produced by the (ps/2) keyboard:
	input  logic [7:0] i_raw_sc,
	input  logic       i_raw_valid,
	output logic       i_raw_ready,

	// produce ascii bytes to print out (e.g., via uart_tx):
	output logic [7:0] out_char,
	output logic       out_valid,
	input  logic       out_ready,

	input logic clk,
	input logic rst
);

	logic [7:0] key_sc;
	kbd_pkg::key_ctx_t   key_ctx;
	logic key_valid, key_ready;

	// convert raw keyboard scan codes into chords + context
	kbd_context inst_kbd_context (
		.i_raw_sc(i_raw_sc),
		.i_raw_valid(i_raw_valid),
		.i_raw_ready(i_raw_ready),
		.o_key_sc(key_sc),
		.o_key_ctx(key_ctx),
		.o_key_valid(key_valid),
		.o_key_ready(key_ready),
		.clk(clk),
		.rst(rst)
	);

	// convert chords+context into ascii bytes to display:
	kbd_context_to_ascii inst_kbd_context_to_ascii(
		.key_sc(key_sc),
		.key_ctx(key_ctx),
		.key_valid(key_valid),
		.key_ready(key_ready),
		.out_char(out_char),
		.out_valid(out_valid),
		.out_ready(out_ready),
		.clk(clk),
		.rst(rst)
	);

endmodule: kbd_context_wrapper

`ifdef TB_KBCTX
// // verilator --binary --trace -DTB_KBCTX --top tb_kbd_context kbd_context.sv
module tb_kbd_context ();

	// stop condition
	logic stop;

	// clk, rst:
	logic clk, rst;
	initial begin
		clk     = 0;
		rst     = 1;
		#22 rst = 0;
	end
	always #5 clk <= ~clk;

	// simulate for N `clk` cycles:
	initial begin
		stop = 0;
		while (!stop)
			@(posedge clk);
		$finish;
	end

	// write waveforms to vcd file:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(3); // 3 submodule layers deep
	end

	// Data used by DUT:
	logic [7:0] raw_scan[] = {
// a bc
8'h1C, 8'hF0, 8'h1C, 8'h29, 8'hF0, 8'h29, 8'h32, 8'hF0, 8'h32, 8'h21, 8'hF0, 8'h21,
// ctl-c
8'h1C, 8'hF0, 8'h1C, 8'h29, 8'hF0, 8'h29, 8'h32, 8'hF0, 8'h32, 8'h21, 8'hF0, 8'h21, 8'h14, 8'h21, 8'hF0, 8'h21, 8'hF0, 8'h14,
// ctl-c c c ... (release ctrl, keep c down)
8'h14, 8'h21, 8'h21, 8'hF0, 8'h14, 8'h21, 8'h21, 8'h21, 8'h21, 8'hF0, 8'h21,
// c c ctrl-c (add ctrl while holding down c)
8'h21, 8'h21, 8'h21, 8'h21, 8'h21, 8'h21, 8'h21, 8'h21, 8'h14, 8'hF0, 8'h14, 8'h14, 8'h14, 8'hF0, 8'h21, 8'h14, 8'h14, 8'h14, 8'h14, 8'h21, 8'hF0, 8'h21, 8'hF0, 8'h14,
// ctl-alt-del (left)
8'h14, 8'h14, 8'h11, 8'h11, 8'h11, 8'hE0, 8'h71, 8'hE0, 8'hF0, 8'h71, 8'hF0, 8'h11, 8'hF0, 8'h14,
// ctl-alt-del (right)
8'hE0, 8'h11, 8'hE0, 8'h14, 8'hE0, 8'h14, 8'hE0, 8'h14, 8'hE0, 8'h14, 8'hE0, 8'h14, 8'hE0, 8'h71, 8'hE0, 8'hF0, 8'h71, 8'hE0, 8'hF0, 8'h14, 8'hE0, 8'hF0, 8'h11,
// altR-shiftR-P
8'hE0, 8'h11, 8'h59, 8'h59, 8'h59, 8'h4D, 8'hF0, 8'h4D, 8'hF0, 8'h59, 8'hE0, 8'hF0, 8'h11,
// ctlR-x-c (emacs)
8'hE0, 8'h14, 8'hE0, 8'h14, 8'h22, 8'hF0, 8'h22, 8'h21, 8'hF0, 8'h21, 8'hE0, 8'hF0, 8'h14,
// altL-PrSc
8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h11, 8'h84, 8'hF0, 8'h84, 8'hF0, 8'h11,
// ctlR-Pause
8'hE0, 8'h14, 8'hE0, 8'h14, 8'hE0, 8'h14, 8'hE0, 8'h14, 8'hE0, 8'h7E, 8'hE0, 8'hF0, 8'h7E, 8'hE0, 8'hF0, 8'h14,
// ctlL-Pause
8'h14, 8'hE0, 8'h7E, 8'hE0, 8'hF0, 8'h7E, 8'hF0, 8'h14,
// Pause (no modifiers)
8'hE1, 8'h14, 8'h77, 8'hE1, 8'hF0, 8'h14, 8'hF0, 8'h77,
// altL-Pause
8'h11, 8'hE1, 8'h14, 8'h77, 8'hE1, 8'hF0, 8'h14, 8'hF0, 8'h77, 8'hF0, 8'h11,
// ctlL-PrSc
8'h14, 8'hE0, 8'h7C, 8'hE0, 8'hF0, 8'h7C, 8'hF0, 8'h14,
// altR-PrSc
8'hE0, 8'h11, 8'h84, 8'hF0, 8'h84, 8'hE0, 8'hF0, 8'h11,
// shR-PrSc
8'h59, 8'h59, 8'h59, 8'h59, 8'hE0, 8'h7C, 8'hE0, 8'hF0, 8'h7C, 8'hF0, 8'h59,
// shR-Pause
8'h59, 8'h59, 8'h59, 8'h59, 8'hE1, 8'h14, 8'h77, 8'hE1, 8'hF0, 8'h14, 8'hF0, 8'h77, 8'hF0, 8'h59,
// shR-PrSc (again)
8'h59, 8'h59, 8'h59, 8'h59, 8'hE0, 8'h7C, 8'hE0, 8'hF0, 8'h7C, 8'hF0, 8'h59
	};

	int idx;

	logic  [7:0] raw_sc, key_sc;
	logic [13:0] key_ctx;
	logic        raw_valid, raw_ready, key_valid, key_ready;

	// DUT:
	kbd_context dut (
		.i_raw_sc(raw_sc),
		.i_raw_valid(raw_valid),
		.i_raw_ready(raw_ready),
		.o_key_sc(key_sc),
		.o_key_ctx(key_ctx),
		.o_key_valid(key_valid),
		.o_key_ready(key_ready),
		.clk(clk),
		.rst(rst)
	);

	// writer:
	always @(posedge clk) begin
		if (rst) begin
			raw_valid <= 0;
			raw_sc    <= 0;
			idx       <= 0;
		end else begin
			if (idx < raw_scan.size) begin
				raw_valid <= 1;
				raw_sc    <= raw_scan[idx];
				if (raw_valid & raw_ready)
					idx <= idx + 1;
			end else begin
				raw_valid <= 0;
				raw_sc    <= 0;
				idx       <= idx + 1;
			end
			// go 20 clock cycles beyond the input data:
			if (idx == raw_scan.size + 20)
				stop <= 1;
		end
	end

	// reader:
	always @(posedge clk) begin
		if (rst) begin
			key_ready <= 0;
		end else begin
			key_ready <= 1;
			if (key_valid & key_ready)
				$display("[%0t] key_sc=0x%0h key_ctx=0x%0h",
					 $time, key_sc, key_ctx);
		end
	end

endmodule: tb_kbd_context
`endif // TB_KBCTX
