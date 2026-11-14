// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`include "video.svh"

// This is implemented as a suspend-capable valid-ready filter/generator
// (see `./valid_ready.sv` for the core design).
//
// A sequence of bytes produced by the UART RX module is consumed.
// Command sequences are filtered; Printable characters are produced
// (i.e., forwarded); Erase commands are implemented as generating the
// appropriate string of blank characters sent to be "displayed".
// Finally, the cursor address is exposed as a "side effect", so that
// the renderer will know which screen location to fast-blink.
//
// See also:
//   https://vt100.net/docs/vt52-mm/
//   https://en.wikipedia.org/wiki/VT52
module vt52_parser (
	// stream input: consume from uart-rx:
	input  logic [7:0] i_data,
	input  logic       i_valid,
	output logic       i_ready,

	// stream output: SRAM address and glyphbox payload for display:
	output logic [video_pkg::SCR_BUF_AW-1:0] o_glyphadr,
	output video_pkg::glyph_box_t            o_glyphbox,
	output logic                  o_valid,
	input  logic                  o_ready,

	// steady output: publish current bell trigger, viewport base-address,
	// and cursor pointer (NOTE: this module is mutually exclusive w.r.t.
	// frame rendering, which can therefore treat these values as stable
	// for the entire duration of painting a frame):
	output logic                  bell,
	output logic [video_pkg::SCR_BUF_AW-1:0] vp_base,
	output logic [video_pkg::SCR_BUF_AW-1:0] crs_adr,

	// control:
	input logic clk,
	input logic rst
);

	localparam
		LAST_ROW = video_pkg::SCR_ROWS - 1,        // last row index
		L_ROW_OF = LAST_ROW * video_pkg::SCR_COLS, // last row offset
		SCR_SIZE = video_pkg::SCR_ROWS * video_pkg::SCR_COLS, // screen size (total boxes)
		LAST_BOX = SCR_SIZE - 1,        // last box offset
		LAST_COL = video_pkg::SCR_COLS - 1,        // last col index
		LAST_TAB = video_pkg::SCR_COLS - 9;	// last tab stop

	// FSM states:
	// NOTE: `Clr` is the erase loop: accepts no input, generates output
	enum logic [2:0] {Asc, Utf, Esc, Row, Col, Fgc, Bgc, Clr}
			 state, stateNext;

	// utf8 decode counter:
	logic [1:0] utf8ct, utf8ctNext;

	// during erase (`Clr`), erase from `o_glyphadr` to here:
	logic [video_pkg::SCR_BUF_AW-1:0] erase_to, erase_toNext;
	// increment o_glyphadr by 1 (modulo SCR_SIZE):
	logic [video_pkg::SCR_BUF_AW-1:0] o_glyphadr_inc;
	assign o_glyphadr_inc = (o_glyphadr < LAST_BOX) ? o_glyphadr + 1 : 0;
	// check if `o_glyphadr_inc` has reached `erase_to`:
	logic clr_done;
	assign clr_done = (o_glyphadr_inc == erase_to);

	// keep track of cursor coordinates:
	// NOTE: relative to `vp_base` !!!
	video_pkg::scr_pos_t crs_pos, crs_posNext;
	// maintain cursor (row) address:
	logic [video_pkg::SCR_BUF_AW-1:0] row_adr;
	comb_pos_to_addr inst_comb_pos_to_addr (
		.vp_base(vp_base),
		.scr_pos(crs_pos),
		.row_adr(row_adr),
		.box_adr(crs_adr)
	);

	// combinational modulo-decremented and incremented values of vp_base:
	logic [video_pkg::SCR_BUF_AW-1:0] vp_base_dec, vp_base_inc;
	assign vp_base_dec = (vp_base == 0) ? L_ROW_OF : vp_base - video_pkg::SCR_COLS;
	assign vp_base_inc = (vp_base == L_ROW_OF) ? 0 : vp_base + video_pkg::SCR_COLS;

	// filtering unless in `Clr` (erase) loop, when generating:
	logic filtering;
	assign filtering = (state != Clr);

	// accept input:
	assign i_ready = filtering & (o_ready | ~o_valid);

	// input (uart-rx) and output (SRAM write) handshake conditions:
	logic i_handshake, o_handshake;
	assign i_handshake = i_ready & i_valid;
	assign o_handshake = o_ready & o_valid;

	// `o_*` outputs are registers (flops, a.k.a. "Q"),
	// so we need next ("D") values for them:
	video_pkg::glyph_box_t            o_glyphboxNext;
	logic [video_pkg::SCR_BUF_AW-1:0] o_glyphadrNext, vp_baseNext;
	logic                  o_validNext;
	// `bell` is also a register, so we can do a one-cycle pulse:
	logic                  bellNext;

	// boolean: input causes eligible output
	// (e.g., parsed a character, or about to start generating)
	logic o_eligible_i;

	// combinational logic:
	always_comb begin
	    // by default, keep registered values steady:
	    o_glyphboxNext = o_glyphbox;
	    o_glyphadrNext = o_glyphadr;
	    o_validNext    = o_valid;
	    utf8ctNext     = utf8ct;
	    vp_baseNext    = vp_base;
	    crs_posNext    = crs_pos;
	    erase_toNext   = erase_to;
	    stateNext      = state;
	    // bell is a one-cycle pulse, so default to always turning off:
	    bellNext       = 0;

	    // assume no eligible output will be produced (unless specific
	    // conditions encountered by next-state FSM logic):
	    o_eligible_i = 0;

	    /* verilator lint_off CASEINCOMPLETE */
	    case (state)
	    Asc: if (i_handshake) begin
		case (i_data)
		8'h07: begin // bel
		    bellNext = 1;
		end // bel
		8'h08: begin // bsp
		    if (crs_pos.x != 0) begin
			crs_posNext.x = crs_pos.x - 1;
		    end
		end // bsp
		8'h09: begin // tab
		    // 8 spaces to last tab stop, then 1 by 1
		    if (crs_pos.x < LAST_TAB) begin
			crs_posNext.x[video_pkg::SCR_CCW-1:3] = crs_pos.x[video_pkg::SCR_CCW-1:3] + 1;
			crs_posNext.x[2:0] = 0;
		    end else if (crs_pos.x < LAST_COL) begin
			crs_posNext.x = crs_pos.x + 1;
		    end
		end // tab
		8'h0a: begin // lf
		    if (crs_pos.y < LAST_ROW) begin
			// no scroll:
			crs_posNext.y = crs_pos.y + 1;
		    end else begin
			// scroll:
			vp_baseNext        = vp_base_inc;
			// clear new row, rotated into view at bottom:
			// NOTE: new row starts at *current* vp_base !!!
			erase_toNext       = vp_base + LAST_COL;
			o_glyphboxNext.utf = 0;
			o_glyphadrNext     = vp_base;
			o_eligible_i       = 1;
			stateNext          = Clr;
		    end
		end // lf
		8'h0d: begin // cr
		    crs_posNext.x = 0;
		end // cr
		8'h1b: begin // esc
		    stateNext = Esc;
		end // esc
		default: begin // possibly utf8 or ascii
		    // NOTE: the following tests are non-overlapping!
		    if ((i_data[7:3] == 5'h1E) & |i_data[2:0]) begin
			utf8ctNext         = 2;
			o_glyphboxNext.utf = {18'b0, i_data[2:0]};
			stateNext          = Utf;
		    end
		    if ((i_data[7:4] == 4'hE) & |i_data[3:0]) begin
			utf8ctNext         = 1;
			o_glyphboxNext.utf = {17'b0, i_data[3:0]};
			stateNext          = Utf;
		    end
		    if ((i_data[7:5] == 3'h6) & |i_data[4:0]) begin
			utf8ctNext         = 0;
			o_glyphboxNext.utf = {16'b0, i_data[4:0]};
			stateNext          = Utf;
		    end
		    if (~i_data[7] & (i_data[6:0] >= 7'h20)) begin
			o_glyphboxNext.utf = {13'b0, i_data};
			// NOTE: no auto linefeed!!!
			if (crs_pos.x < LAST_COL) begin
			    crs_posNext.x = crs_pos.x + 1;
			end
			o_glyphadrNext = crs_adr;
			o_eligible_i   = 1;
		    end
		end // default (utf8 or ascii)
		endcase // (i_data)
	    end // case: Asc
	    Utf: if (i_handshake) begin
		if (i_data[7:6] == 2'b10) begin // valid utf8 continuation
		    utf8ctNext         = utf8ct - 1;
		    o_glyphboxNext.utf = {o_glyphbox.utf[14:0], i_data[5:0]};
		    if (utf8ct == 0) begin
			// NOTE: no auto linefeed!!!
			if (crs_pos.x < LAST_COL) begin
			    crs_posNext.x = crs_pos.x + 1;
			end
			o_glyphadrNext = crs_adr;
			o_eligible_i   = 1;
			stateNext      = Asc;
		    end
		end else begin // invalid utf8 continuation
		    stateNext = Asc;
		end
	    end // case: Utf
	    Esc: if (i_handshake) begin
		case (i_data)
		8'h1b: begin // "\e\e"
		    // on VT52 two escapes don't cancel each other -- do nothing
		end // "\e\e"
		"A": begin // "\eA": cursor-up
		    if (crs_pos.y != 0) begin
			crs_posNext.y = crs_pos.y - 1;
		    end
		    stateNext = Asc;
		end // "\eA"
		"B": begin // "\eB": cursor-down
		    if (crs_pos.y < LAST_ROW) begin
			crs_posNext.y = crs_pos.y + 1;
		    end
		    stateNext = Asc;
		end // "\eB"
		"C": begin // "\eC": cursor-right
		    if (crs_pos.x < LAST_COL) begin
			crs_posNext.x = crs_pos.x + 1;
		    end
		    stateNext = Asc;
		end // "\eC"
		"D": begin // "\eD": cursor-left
		    if (crs_pos.x != 0) begin
			crs_posNext.x = crs_pos.x - 1;
		    end
		    stateNext = Asc;
		end // "\eD"
		"H": begin // "\eH": cursor-top-left
		    crs_posNext.x = 0;
		    crs_posNext.y = 0;
		    stateNext = Asc;
		end // "\eH"
		"I": begin // "\eI": cursor-up (with scroll)
		    if (crs_pos.y != 0) begin
			// no scroll:
			crs_posNext.y = crs_pos.y - 1;
			stateNext     = Asc;
		    end else begin
			// scroll:
			vp_baseNext        = vp_base_dec;
			// clear new row, rotaded into view at top:
			erase_toNext       = vp_base_dec + LAST_COL;
			o_glyphboxNext.utf = 0;
			o_glyphadrNext     = vp_base_dec;
			o_eligible_i       = 1;
			stateNext          = Clr;
		    end
		end // "\eI"
		"J": begin // "\eJ": erase-to-end-of-screen
		    // NOTE: erase loop skips over "unreachable" addresses!
		    erase_toNext       = vp_base_dec + LAST_COL;
		    o_glyphboxNext.utf = 0;
		    o_glyphadrNext     = crs_adr;
		    o_eligible_i       = 1;
		    stateNext          = Clr;
		end // "\eJ"
		"K": begin // "\eK": erase-to-eol
		    erase_toNext       = row_adr + LAST_COL;
		    o_glyphboxNext.utf = 0;
		    o_glyphadrNext     = crs_adr;
		    o_eligible_i       = 1;
		    stateNext          = Clr;
		end // "\eK"
		"Y": begin // "\eY": cursor-to-row-col (direct address)
		    // NOTE: relative to *current* viewport (no scrolling)!!!
		    stateNext = Row;
		end // "\eY"
		"Z": begin // "\eZ": ident
		    // FIXME: send "\e/K" back over uart-tx !!!
		    stateNext = Asc; // ignore for now
		end // "\eZ"
		"b": begin // "\eb": set foreground color
		    stateNext = Fgc;
		end // "\eb"
		"c": begin // "\ec": set background color
		    stateNext = Bgc;
		end // "\ec"
		default: begin // "\e*": unhandled escape sequence
		    // ignore & return to Asc
		    stateNext = Asc;
		end // esc-* (default)
		endcase // (i_data)
	    end // case: Esc
	    Row: if (i_handshake) begin // new row position received:
		// if row out of bounds, maintain current row:
		if ((i_data >= 8'h20) & (i_data < 8'h20 + video_pkg::SCR_ROWS)) begin
		    /* verilator lint_off WIDTHTRUNC */
		    crs_posNext.y = i_data - 8'h20;
		end
		// now ready to receive new col:
		stateNext = Col;
	    end // case: Row
	    Col: if (i_handshake) begin // new col position received:
		// if col out of bounds, go to last column:
		if ((i_data >= 8'h20) & (i_data < 8'h20 + video_pkg::SCR_COLS)) begin
		    /* verilator lint_off WIDTHTRUNC */
		    crs_posNext.x = i_data - 8'h20;
		end else begin
		    crs_posNext.x = LAST_COL;
		end
		stateNext = Asc;
	    end // case: Col
	    Fgc: if (i_handshake) begin // new foreground color received:
		if (i_data >= 8'h20) begin
		    o_glyphboxNext.fgc = i_data - 8'h20;
		end
		stateNext = Asc;
	    end // case: Fgc
	    Bgc: if (i_handshake) begin // new background color received:
		if (i_data >= 8'h20) begin
		    o_glyphboxNext.bgc = i_data - 8'h20;
		end
		stateNext = Asc;
	    end // case: Bgc
	    Clr: if (o_handshake) begin
		o_glyphadrNext = o_glyphadr_inc;
		if (clr_done) begin
		    stateNext = Asc;
		end
	    end // case: Clr
	    endcase // (state)

	    // valid-ready protocol logic:
	    if (filtering) begin
		if (i_handshake & o_eligible_i) begin
		    // actual next-cycle output values set by FSM logic above
		    o_validNext = 1;
		end else if (o_handshake) begin
		    // no eligible output for next cycle:
		    o_validNext = 0;
		end
	    end
	    // NOTE: (~filtering & o_handshake) generator progress handled
	    //       by FSM logic (`Clr` state) above
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			o_glyphbox <= 0;
			// default to (approx. of) "wheat" on "dark slate gray"
			o_glyphbox.fgc <= 8'hE0;
			o_glyphbox.bgc <= 8'h16;
			o_glyphadr <= 0;
			o_valid    <= 0;
			utf8ct     <= 0;
			vp_base    <= 0;
			crs_pos    <= 0;
			erase_to   <= 0;
			bell       <= 0;
			state      <= Asc;
		end else begin
			o_glyphbox <= o_glyphboxNext;
			o_glyphadr <= o_glyphadrNext;
			o_valid    <= o_validNext;
			utf8ct     <= utf8ctNext;
			vp_base    <= vp_baseNext;
			crs_pos    <= crs_posNext;
			erase_to   <= erase_toNext;
			bell       <= bellNext;
			state      <= stateNext;
		end
	end

endmodule: vt52_parser

// UTF-8 Decoder (see https://en.wikipedia.org/wiki/UTF-8)
//
// FirstCP   LastCP     Byte_1    Byte_2    Byte_3    Byte_4
// ----------------------------------------------------------
// U+0000    U+007F    0yyyzzzz                // NOTE: ASCII
// U+0080    U+07FF    110xxxyy  10yyzzzz
// U+0800    U+FFFF    1110wwww  10xxxxyy  10yyzzzz
// U+010000  U+10FFFF  11110uvv  10vvwwww  10xxxxyy  10yyzzzz
// ----------------------------------------------------------
//
// NOTE1: to avoid "overlong" encoding, ensure Byte1 payload bits are nonzero!
// NOTE2: this is styled as a valid/ready filter
module utf8decode (
	// input: consume byte stream:
	input  logic [7:0] i_data,
	input  logic       i_valid,
	output logic       i_ready,
	// output: produce decoded UTF-21:
	output logic [20:0] o_utf,
	output logic        o_valid,
	input  logic        o_ready,
	//
	input logic clk,
	input logic rst
);

	// accept input if consumer waiting
	// or if we don't already have unconsumed output:
	assign i_ready = o_ready | ~o_valid;

	// handshake conditions:
	logic i_handshake, o_handshake;
	assign i_handshake = i_valid & i_ready;
	assign o_handshake = o_valid & o_ready;

	// next values for output registers:
	logic [20:0] o_utfNext;
	logic        o_validNext;

	// forwarding condition:
	logic i_o_forward;

	// FSM states:
	enum logic {Asc, Utf} state, stateNext;
	// UTF sequence counter:
	logic [1:0] utfct, utfctNext;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_utfNext   = o_utf;
		o_validNext = o_valid;
		utfctNext   = utfct;
		stateNext   = state;

		// forwarding is off by default, unless enabled by FSM below:
		i_o_forward = 0;

		// advance FSM on input handshake:
		if (i_handshake) begin
			case (state)
			Asc: begin
				if ((i_data[7:3] == 5'h1E) & |i_data[2:0]) begin
					o_utfNext = {18'b0, i_data[2:0]};
					utfctNext = 2;
					stateNext = Utf;
				end
				if ((i_data[7:4] == 4'hE) & |i_data[3:0]) begin
					o_utfNext = {17'b0, i_data[3:0]};
					utfctNext = 1;
					stateNext = Utf;
				end
				if ((i_data[7:5] == 3'h6) & |i_data[4:0]) begin
					o_utfNext = {16'b0, i_data[4:0]};
					utfctNext = 0;
					stateNext = Utf;
				end
				if (~i_data[7] & (i_data[6:0] >= 7'h20)) begin
					o_utfNext = {13'b0, i_data};
					i_o_forward = 1;
				end
			end // Asc
			Utf: begin
				if (i_data[7:6] == 2'b10) begin // valid cont.
					utfctNext = utfct - 1;
					o_utfNext = {o_utf[14:0], i_data[5:0]};
					if (utfct == 0) begin
						i_o_forward = 1;
						stateNext = Asc;
					end
				end else begin // error
					stateNext = Asc;
				end
			end // Utf
			endcase
		end // if (i_handshake)

		// valid/ready filter logic:
		if (i_handshake & i_o_forward) begin
			// NOTE: o_utf calculated by FSM logic (above)
			o_validNext = 1;
		end else if (o_handshake) begin
			// no forwarding-eligible data for next cycle:
			o_validNext = 0;
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			o_utf   <= 0;
			o_valid <= 0;
			utfct   <= 0;
			state   <= Asc;
		end else begin
			o_utf   <= o_utfNext;
			o_valid <= o_validNext;
			utfct   <= utfctNext;
			state   <= stateNext;
		end
	end

endmodule: utf8decode

`ifdef TB_VT52

// produce bytes from a file, using the valid/ready protocol:
module vr_prod #(
	parameter FN = "",
	parameter DW = 8,
	parameter AW = 8
) (
	output logic [DW-1:0] o_data,
	output logic          o_valid,
	input  logic          o_ready,
	input  logic clk,
	input  logic rst
);

	// mem. array size (number of words):
	localparam NUMW = 2 ** AW;

	// mem. array:
	logic [DW-1:0] mem[0:NUMW-1];

	// init (from file, if possible):
	initial begin
		if ($bits(FN) > 8)
			$readmemh(FN, mem);
		else
			for (int i = 0; i < NUMW; i++)
				mem[i] = 0;
	end

	// output index
	logic [AW-1:0] o_adr;
	assign o_data = mem[o_adr];
	// output is *always* valid (handshake whenever `o_ready == 1`):
	assign o_valid = 1;

	always_ff @(posedge clk) begin
		if (rst)
			o_adr <= 0;
		else if (o_ready)
			o_adr <= o_adr + 1;
	end

endmodule: vr_prod

// // verilator --binary --trace -DTB_VT52 --top tb_vt52 vt52.sv scr_draw.sv
// // iverilog -g2005-sv -DTB_VT52 -s tb_vt52 -o tb_vt52 vt52.sv scr_draw.sv
// // tb_vt52 > o.log; paste <(grep i_data o.log) <(grep o_adr o.log)
module tb_vt52 ();

	// parameters:
	localparam NC = 550; // clock cycles to simulate
	localparam DW =   8; // data width
	localparam AW =   8; // address width
	localparam FN = "testvt52.hex";

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
	logic [7:0] i_data;
	logic [video_pkg::SCR_BUF_AW-1:0] o_glyphadr, vp_base, crs_adr;
	video_pkg::glyph_box_t o_glyphbox;
	logic       i_valid, i_ready, o_valid, o_ready, bell;

	vr_prod #(
		.FN(FN),
		.DW(DW),
		.AW(AW)
	) inst_vr_prod (
		.o_data(i_data),
		.o_valid(i_valid),
		.o_ready(i_ready),
		.clk(clk),
		.rst(rst)
	);

	vt52_parser DUT (
		.i_data(i_data),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_glyphadr(o_glyphadr),
		.o_glyphbox(o_glyphbox),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.bell(bell),
		.vp_base(vp_base),
		.crs_adr(crs_adr),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			o_ready <= 0;
		end else begin
`ifdef VERILATOR
			o_ready <= $random[0];
`else
			o_ready <= $random;
`endif
			// show data received from upstream/master/producer:
			if (i_valid & i_ready)
				$display("[%04t] i_data=0x%h", $time, i_data);
			// show data transfered to downstream/slave/consumer:
			if (o_valid & o_ready)
	$display("[%04t] o_adr=0x%04h o_chr=%02h vp=%04h cr=%04h",
		$time, o_glyphadr, o_glyphbox.utf[7:0], vp_base, crs_adr);
			// bursty, always-ready consumer:
//			o_ready <= 1;
		end
	end

endmodule: tb_vt52

// // verilator --binary --trace -DTB_VT52 --top tb_utf vt52.sv
// // iverilog -g2005-sv -DTB_VT52 -s tb_utf -o tb_utf vt52.sv
// // tb_utf > o.log; paste <(grep i_d o.log) <(grep o_u o.log)
module tb_utf ();

	// parameters:
	localparam NC =  64; // clock cycles to simulate
	localparam DW =   8; // data width
	localparam AW =   8; // address width
	localparam FN = "testvt52.hex";

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

/*
	// record signal waveforms:
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(3); // go 3 submodule layers deep
	end
*/

	// DUT (and associated wires):
	logic [ 7:0] i_data;
	logic [20:0] o_utf;
	logic        i_valid, i_ready, o_valid, o_ready;

	vr_prod #(
		.FN(FN),
		.DW(DW),
		.AW(AW)
	) inst_vr_prod (
		.o_data(i_data),
		.o_valid(i_valid),
		.o_ready(i_ready),
		.clk(clk),
		.rst(rst)
	);

	utf8decode DUT (
		.i_data(i_data),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_utf(o_utf),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			o_ready <= 0;
		end else begin
`ifdef VERILATOR
			o_ready <= $random[0];
`else
			o_ready <= $random;
`endif
			// show data received from upstream/master/producer:
			if (i_valid & i_ready)
				$display("[%04t] i_d=0x%02h %08b",
						$time, i_data, i_data);
			// show data transfered to downstream/slave/consumer:
			if (o_valid & o_ready)
				$display("[%04t] o_u=0x%06h %021b",
						$time, o_utf, o_utf);
			// bursty, always-ready consumer:
//			o_ready <= 1;
		end
	end

endmodule: tb_utf
`endif // TB_VT52
