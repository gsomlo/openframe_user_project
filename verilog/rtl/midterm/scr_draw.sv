// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`include "video.svh"

module scr_sweep_raster (
	// signal to start drawing a new frame:
	input  logic               frm_rndr_start,

	// bell trigger countdown:
	input  logic               bell,

	// blink and visual bell outputs:
	output video_pkg::blink_sig_t         blink,

	// sweep screen raster coordinates *and* glyph column:
	output video_pkg::scr_pos_t           pos,
	output logic [video_pkg::CHR_WCW-1:0] col,
	output logic               border,
	output logic               done,
	output logic               valid,
	input  logic               ready,

	input logic clk,
	input logic rst
);

	// frame counter (for frame-synchronous blink signals):
	logic [6:0] frmct, frmctNext;
	assign blink.cursor = frmct[4];
	assign blink.attrib = frmct[6];
	// bell counter (for flashing a visual bell):
	logic [2:0] belct, belctNext;
	assign blink.v_bell = |belct;

	// FSM states:
	enum logic [1:0] {Wait, Top, Col, Bot} state, stateNext;

	// coordinate register next ("d") values:
	video_pkg::scr_pos_t           posNext;
	logic [video_pkg::CHR_WCW-1:0] colNext;

	// assert `border` in `Top`, `Bot`:
	// NOTE: `Wait` irrelevant since output not `valid`!
	assign border = (state != Col);

	// assert `valid` during all states except for `Wait`:
	assign valid = (state != Wait);

	// combinational logic:
	always_comb begin
		// by default, maintain current position:
		frmctNext = frmct;
		posNext   = pos;
		colNext   = col;
		stateNext = state;

		done = 0;

		// restart bell-flash countdown if trigger active:
		belctNext = (bell) ? '1 : belct;

		unique case (state)
		Wait: if (frm_rndr_start) begin
			// increment frame counter (before starting to draw
			// a new frame, so flags are stable in later stages):
			frmctNext = frmct + 1;
			// decrement bell counter if currently active:
			if (blink.v_bell) begin
				belctNext = belct - 1;
			end
			// start at col=79, row=0, char_col=5:
			posNext.x = video_pkg::SCR_CCW'(video_pkg::SCR_COLS - 1);
			posNext.y = 0;
			colNext   = video_pkg::CHR_WCW'(video_pkg::CHR_WIDE - 1);
			stateNext = Top;
		end
		Top: if (ready) begin
			stateNext = Col;
		end
		Col: if (ready) begin
			posNext.y = pos.y + 1;
			if (pos.y == video_pkg::SCR_RCW'(video_pkg::SCR_ROWS - 1)) begin
				posNext.y = 0;
				stateNext = Bot;
			end
		end
		Bot: if (ready) begin
			colNext   = col - 1;
			stateNext = Top;
			if (col == 0) begin
				posNext.x = pos.x - 1;
				colNext   = video_pkg::CHR_WCW'(video_pkg::CHR_WIDE - 1);
				if (pos.x == 0) begin
					// finished drawing current frame:
					done = 1;
					stateNext = Wait;
				end
			end
		end
		endcase
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			frmct <= 0;
			belct <= 0;
			pos   <= 0;
			col   <= 0;
			state <= Wait;
		end else begin
			frmct <= frmctNext;
			belct <= belctNext;
			pos   <= posNext;
			col   <= colNext;
			state <= stateNext;
		end
	end

endmodule: scr_sweep_raster

// combinational SRAM (glyph box) address given `vp_base` and `pos`
// NOTE: assumes we don't maintain a history/scroll buffer!!!
module comb_pos_to_addr (
	input  logic [video_pkg::SCR_BUF_AW-1:0] vp_base,
	input  video_pkg::scr_pos_t              scr_pos,
	output logic [video_pkg::SCR_BUF_AW-1:0] row_adr,
	output logic [video_pkg::SCR_BUF_AW-1:0] box_adr
);

	localparam
		LAST_ROW = video_pkg::SCR_ROWS - 1,        // last row index
		LAST_OFF = LAST_ROW * video_pkg::SCR_COLS, // last row offset
		SCR_SIZE = video_pkg::SCR_ROWS * video_pkg::SCR_COLS; // screen size (total boxes)

	logic [video_pkg::SCR_BUF_AW:0] long_row_adr;
	assign long_row_adr = vp_base + scr_pos.y * video_pkg::SCR_COLS;

	/* verilator lint_off WIDTHTRUNC */
	assign row_adr = (long_row_adr > LAST_OFF) ? long_row_adr - SCR_SIZE :
						     long_row_adr;
	/* verilator lint_off WIDTHEXPAND */
	assign box_adr = row_adr + scr_pos.x;

endmodule: comb_pos_to_addr

// convert (base, row, col) to SRAM address
module scr_pos_to_addr (
	// use current viewport scroll offset when computing address:
	input  logic [video_pkg::SCR_BUF_AW-1:0] vp_base,

	// consume screen coordinates:
	input  video_pkg::scr_pos_t           i_pos,
	input  logic [video_pkg::CHR_WCW-1:0] i_col,
	input  logic               i_border,
	input  logic               i_done,
	input  logic               i_valid,
	output logic               i_ready,

	// produce address, pass-thru `col`, `border`, `done`:
	output logic [video_pkg::SCR_BUF_AW-1:0] o_addr,
	output logic    [video_pkg::CHR_WCW-1:0] o_col,
	output logic                  o_border,
	output logic                  o_done,
	output logic                  o_valid,
	input  logic                  o_ready,

	input logic clk,
	input logic rst
);

	// combinationally calculate address:
	logic [video_pkg::SCR_BUF_AW-1:0] adr;
	comb_pos_to_addr inst_comb_pos_to_addr (
		.vp_base(vp_base),
		.scr_pos(i_pos),
		.row_adr(), // ignored in this use case
		.box_adr(adr)
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
	logic [video_pkg::SCR_BUF_AW-1:0] o_addrNext;
	logic    [video_pkg::CHR_WCW-1:0] o_colNext;
	logic                  o_borderNext;
	logic                  o_doneNext;
	logic                  o_validNext;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_addrNext   = o_addr;
		o_colNext    = o_col;
		o_borderNext = o_border;
		o_doneNext   = o_done;
		o_validNext  = o_valid;

		if (i_handshake) begin
			o_validNext  = 1;
			o_addrNext   = adr;
			o_colNext    = i_col;    // pass-thru
			o_borderNext = i_border; // pass-thru
			o_doneNext   = i_done;   // pass-thru
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
			o_addr   <= 0;
			o_col    <= 0;
			o_border <= 0;
			o_done   <= 0;
			o_valid  <= 0;
		end else begin
			o_addr   <= o_addrNext;
			o_col    <= o_colNext;
			o_border <= o_borderNext;
			o_done   <= o_doneNext;
			o_valid  <= o_validNext;
		end
	end

endmodule: scr_pos_to_addr

// retrieve glyph box from display buffer SRAM (during frame rendering)
// accept updates from command parser (during vblank interval)
module scr_display_buf (
	// use current cursor address to set cursor flag:
	input  logic [video_pkg::SCR_BUF_AW-1:0] crs_adr,
	// signal to switch to render-pipeline (read) mode,
	// (away from command parser write mode):
	// NOTE: complementary w.r.t. `i_done`
	input  logic                  start,

	// consume command parser SRAM write address & data:
	input  logic [video_pkg::SCR_BUF_AW-1:0] w_addr,
	input  video_pkg::glyph_box_t            w_glyphbox,
	input  logic                  w_valid,
	output logic                  w_ready,

	// consume screen SRAM address, passed-through `col`, `border`:
	input  logic [video_pkg::SCR_BUF_AW-1:0] i_addr,
	input  logic    [video_pkg::CHR_WCW-1:0] i_col,
	input  logic                  i_border,
	input  logic                  i_done,
	input  logic                  i_valid,
	output logic                  i_ready,

	// produce glyph_box, pass-thru `col`, `border`:
	output video_pkg::glyph_box_t         o_glyphbox,
	output logic [video_pkg::CHR_WCW-1:0] o_col,
	output logic               o_border,
	output logic               o_cursor,
	output logic               o_valid,
	input  logic               o_ready,

	// RAM interface
	output logic [video_pkg::SCR_BUF_AW-1:0] ram_addr,
	output logic                  ram_wren,
	output logic [video_pkg::SCR_BUF_DW-1:0] ram_wdata,
	input  logic [video_pkg::SCR_BUF_DW-1:0] ram_rdata,

	input logic clk,
	input logic rst
);

	logic i_cursor;
	assign i_cursor = (i_addr == crs_adr);

	// we're only really "done" once the last render-pipeline data
	// item has finished passing through the `ready_valid_sram_ext`:
	logic o_done, done;
	assign done = &{o_done, o_valid, o_ready};

	// mode register (`~render` -> accept updates from command parser):
	logic update, render, renderNext;
	assign renderNext = (start) ? 1 : (done) ? 0 : render;
	assign update = ~render;

	// route `i_ready` of `ready_valid_sram_ext` to appropriate producer:
	logic s_ready;
	assign i_ready = render & s_ready;
	assign w_ready = update & s_ready;

	ready_valid_sram_ext #(
		.AW(video_pkg::SCR_BUF_AW),
		.DW(video_pkg::SCR_BUF_DW), // alias for `$bits(glyph_box_t)`
		.TW($bits({i_col, i_border, i_cursor, i_done}))
	) inst_ready_valid_sram_ext (
		.i_addr((render) ? i_addr : w_addr),
		.i_wren(update),
		.i_wdata(w_glyphbox),
		.i_valid((render) ? i_valid : w_valid),
		.i_ready(s_ready),
		.i_ptdat({i_col, i_border, i_cursor, i_done}),
		.o_rdata(o_glyphbox),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.o_ptdat({o_col, o_border, o_cursor, o_done}),
		.ram_addr(ram_addr),
		.ram_wren(ram_wren),
		.ram_wdata(ram_wdata),
		.ram_rdata(ram_rdata),
		.clk(clk),
		.rst(rst)
	);

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			render <= 0;
		end else begin
			render <= renderNext;
		end
	end

endmodule: scr_display_buf

// combinational 21-bit utf-encoding to 12-bit font ROM address calculator:
// - custom-generated (GLP_AW=12, see 6x12.bdf and bdfparse.c in ./chargen/)
module utf_to_adr (
    input  logic [20:0] utf,
    output logic [11:0] adr
);

    logic [15:0] utflo, addr, sub;
    logic dflt_sub;

    assign dflt_sub = (sub == 0);
    assign utflo = utf[15:0];
    // if (UTF > 16'hFFFF | sub == 0), return adr('�`) (unsup. glyph)
    assign addr = (|{utf[20:16], dflt_sub}) ? 16'h0FCA : utflo - sub;
    assign adr = addr[11:0];

    always_comb begin
	case (utflo)
	16'h0000: sub = 16'hFFFF; // special case: add 1 (subtract -1)
	16'h038C: sub = 16'h00B8;
	16'h1F59: sub = 16'h1973;
	16'h1F5B: sub = 16'h1974;
	16'h1F5D: sub = 16'h1975;
	16'h20BF: sub = 16'h19BA;
	16'h274D: sub = 16'h1A97;
	16'h2756: sub = 16'h1A9B;
	16'h27CC: sub = 16'h1AA4;
	default: begin
	    if      (utflo >= 16'h0020 && utflo <= 16'h007E) sub = 16'h001F;
	    else if (utflo >= 16'h00A0 && utflo <= 16'h02FF) sub = 16'h0040;
	    else if (utflo >= 16'h0370 && utflo <= 16'h0377) sub = 16'h00B0;
	    else if (utflo >= 16'h037A && utflo <= 16'h037E) sub = 16'h00B2;
	    else if (utflo >= 16'h0384 && utflo <= 16'h038A) sub = 16'h00B7;
	    else if (utflo >= 16'h038E && utflo <= 16'h03A1) sub = 16'h00B9;
	    else if (utflo >= 16'h03A3 && utflo <= 16'h0482) sub = 16'h00BA;
	    else if (utflo >= 16'h048A && utflo <= 16'h0523) sub = 16'h00C1;
	    else if (utflo >= 16'h0531 && utflo <= 16'h0556) sub = 16'h00CE;
	    else if (utflo >= 16'h0559 && utflo <= 16'h055E) sub = 16'h00D0;
	    else if (utflo >= 16'h0561 && utflo <= 16'h0587) sub = 16'h00D2;
	    else if (utflo >= 16'h0589 && utflo <= 16'h058A) sub = 16'h00D3;
	    else if (utflo >= 16'h05D0 && utflo <= 16'h05EA) sub = 16'h0118;
	    else if (utflo >= 16'h05F0 && utflo <= 16'h05F4) sub = 16'h011D;
	    else if (utflo >= 16'h1680 && utflo <= 16'h169C) sub = 16'h11A8;
	    else if (utflo >= 16'h16A0 && utflo <= 16'h16F0) sub = 16'h11AB;
	    else if (utflo >= 16'h1D62 && utflo <= 16'h1D65) sub = 16'h181C;
	    else if (utflo >= 16'h1E02 && utflo <= 16'h1E07) sub = 16'h18B8;
	    else if (utflo >= 16'h1E0A && utflo <= 16'h1E13) sub = 16'h18BA;
	    else if (utflo >= 16'h1E1E && utflo <= 16'h1E1F) sub = 16'h18C4;
	    else if (utflo >= 16'h1E30 && utflo <= 16'h1E35) sub = 16'h18D4;
	    else if (utflo >= 16'h1E3E && utflo <= 16'h1E43) sub = 16'h18DC;
	    else if (utflo >= 16'h1E54 && utflo <= 16'h1E57) sub = 16'h18EC;
	    else if (utflo >= 16'h1E60 && utflo <= 16'h1E71) sub = 16'h18F4;
	    else if (utflo >= 16'h1E80 && utflo <= 16'h1E8F) sub = 16'h1902;
	    else if (utflo >= 16'h1EF2 && utflo <= 16'h1EF9) sub = 16'h1964;
	    else if (utflo >= 16'h1F00 && utflo <= 16'h1F15) sub = 16'h196A;
	    else if (utflo >= 16'h1F18 && utflo <= 16'h1F1D) sub = 16'h196C;
	    else if (utflo >= 16'h1F20 && utflo <= 16'h1F45) sub = 16'h196E;
	    else if (utflo >= 16'h1F48 && utflo <= 16'h1F4D) sub = 16'h1970;
	    else if (utflo >= 16'h1F50 && utflo <= 16'h1F57) sub = 16'h1972;
	    else if (utflo >= 16'h1F5F && utflo <= 16'h1F7D) sub = 16'h1976;
	    else if (utflo >= 16'h1F80 && utflo <= 16'h1FB4) sub = 16'h1978;
	    else if (utflo >= 16'h1FB6 && utflo <= 16'h1FC4) sub = 16'h1979;
	    else if (utflo >= 16'h1FC6 && utflo <= 16'h1FD3) sub = 16'h197A;
	    else if (utflo >= 16'h1FD6 && utflo <= 16'h1FDB) sub = 16'h197C;
	    else if (utflo >= 16'h1FDD && utflo <= 16'h1FEF) sub = 16'h197D;
	    else if (utflo >= 16'h1FF2 && utflo <= 16'h1FF4) sub = 16'h197F;
	    else if (utflo >= 16'h1FF6 && utflo <= 16'h1FFE) sub = 16'h1980;
	    else if (utflo >= 16'h2010 && utflo <= 16'h2027) sub = 16'h1991;
	    else if (utflo >= 16'h2030 && utflo <= 16'h205E) sub = 16'h1999;
	    else if (utflo >= 16'h2070 && utflo <= 16'h2071) sub = 16'h19AA;
	    else if (utflo >= 16'h2074 && utflo <= 16'h208E) sub = 16'h19AC;
	    else if (utflo >= 16'h2090 && utflo <= 16'h2099) sub = 16'h19AD;
	    else if (utflo >= 16'h209B && utflo <= 16'h209C) sub = 16'h19AE;
	    else if (utflo >= 16'h20A0 && utflo <= 16'h20B5) sub = 16'h19B1;
	    else if (utflo >= 16'h2100 && utflo <= 16'h214F) sub = 16'h19FA;
	    else if (utflo >= 16'h2153 && utflo <= 16'h2188) sub = 16'h19FD;
	    else if (utflo >= 16'h2190 && utflo <= 16'h2328) sub = 16'h1A04;
	    else if (utflo >= 16'h232B && utflo <= 16'h23E7) sub = 16'h1A06;
	    else if (utflo >= 16'h2400 && utflo <= 16'h2426) sub = 16'h1A1E;
	    else if (utflo >= 16'h2440 && utflo <= 16'h244A) sub = 16'h1A37;
	    else if (utflo >= 16'h2460 && utflo <= 16'h2613) sub = 16'h1A4C;
	    else if (utflo >= 16'h2616 && utflo <= 16'h2617) sub = 16'h1A4E;
	    else if (utflo >= 16'h2619 && utflo <= 16'h269C) sub = 16'h1A4F;
	    else if (utflo >= 16'h26A0 && utflo <= 16'h26BC) sub = 16'h1A52;
	    else if (utflo >= 16'h26C0 && utflo <= 16'h26C3) sub = 16'h1A55;
	    else if (utflo >= 16'h2701 && utflo <= 16'h2704) sub = 16'h1A92;
	    else if (utflo >= 16'h2706 && utflo <= 16'h2709) sub = 16'h1A93;
	    else if (utflo >= 16'h270C && utflo <= 16'h2727) sub = 16'h1A95;
	    else if (utflo >= 16'h2729 && utflo <= 16'h274B) sub = 16'h1A96;
	    else if (utflo >= 16'h274F && utflo <= 16'h2752) sub = 16'h1A98;
	    else if (utflo >= 16'h2758 && utflo <= 16'h275E) sub = 16'h1A9C;
	    else if (utflo >= 16'h2761 && utflo <= 16'h2794) sub = 16'h1A9E;
	    else if (utflo >= 16'h2798 && utflo <= 16'h27AF) sub = 16'h1AA1;
	    else if (utflo >= 16'h27B1 && utflo <= 16'h27BE) sub = 16'h1AA2;
	    else if (utflo >= 16'h27C0 && utflo <= 16'h27CA) sub = 16'h1AA3;
	    else if (utflo >= 16'h27D0 && utflo <= 16'h27FF) sub = 16'h1AA7;
	    else if (utflo >= 16'h2900 && utflo <= 16'h2B4C) sub = 16'h1BA7;
	    else if (utflo >= 16'h2C60 && utflo <= 16'h2C6F) sub = 16'h1CBA;
	    else if (utflo >= 16'h2C71 && utflo <= 16'h2C7D) sub = 16'h1CBB;
	    else if (utflo >= 16'hFB00 && utflo <= 16'hFB06) sub = 16'hEB3D;
	    else                                             sub = 16'h0000;
	end // default
	endcase
    end

endmodule: utf_to_adr

// convert `glyphbox.utf` to font/glyph ROM address, pass-thru attributes
// NOTE: this is a customized version of `valid_ready_bridge`
module utf_enc_to_addr (
	// consume glyphbox, col, border:
	input  video_pkg::glyph_box_t         i_glyphbox,
	input  logic [video_pkg::CHR_WCW-1:0] i_col,
	input  logic               i_border,
	input  logic               i_cursor,
	input  logic               i_valid,
	output logic               i_ready,

	// produce glyph ROM address, col, attributes:
	output logic  [video_pkg::GLP_AW-1:0] o_addr,
	output logic [video_pkg::CHR_WCW-1:0] o_col,
	output video_pkg::pass_attr_t         o_attr,
	output logic               o_valid,
	input  logic               o_ready,

	input logic clk,
	input logic rst
);

	// combinationally calculate rom address (`addr`):
	logic [video_pkg::GLP_AW-1:0] addr;
	utf_to_adr inst_utf_to_adr (
		.utf(i_glyphbox.utf),
		.adr(addr)
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
	logic  [video_pkg::GLP_AW-1:0] o_addrNext;
	logic [video_pkg::CHR_WCW-1:0] o_colNext;
	video_pkg::pass_attr_t         o_attrNext;
	logic               o_validNext;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_addrNext  = o_addr;
		o_colNext   = o_col;
		o_attrNext  = o_attr;
		o_validNext = o_valid;

		if (i_handshake) begin
			o_validNext = 1;
			o_addrNext  = addr;
			o_colNext   = i_col;
			o_attrNext.border = i_border;
			o_attrNext.cursor = i_cursor;
			o_attrNext.flg    = i_glyphbox.flg;
			o_attrNext.fgc    = i_glyphbox.fgc;
			o_attrNext.bgc    = i_glyphbox.bgc;
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
			o_addr  <= 0;
			o_col   <= 0;
			o_attr  <= 0;
			o_valid <= 0;
		end else begin
			o_addr  <= o_addrNext;
			o_col   <= o_colNext;
			o_attr  <= o_attrNext;
			o_valid <= o_validNext;
		end
	end

endmodule: utf_enc_to_addr

// lookup glyph/symbol at `i_addr` in font ROM, and select column `i_col`;
// pass-thru `i_attr` (containing colors, border status, etc.);
// NOTE: this is a customized version of `ready_valid_srom`
module glyph_font_lookup (
	// consume `i_addr`, `i_col`, and pass-thru data `i_attr`:
	input  logic  [video_pkg::GLP_AW-1:0] i_addr,
	input  logic [video_pkg::CHR_WCW-1:0] i_col,
	input  video_pkg::pass_attr_t         i_attr,
	input  logic               i_valid,
	output logic               i_ready,

	// produce font bits, pass-thru data `o_attr`:
	output logic [video_pkg::CHR_HIGH-1:0] o_col_bits,
	output video_pkg::pass_attr_t          o_attr,
	output logic                o_valid,
	input  logic                o_ready,

	// ROM interface:
	output logic  [video_pkg::GLP_AW-1:0] rom_addr,
	input  logic  [video_pkg::GLP_DW-1:0] rom_data,

	input logic clk,
	input logic rst
);

	assign rom_addr = i_addr;

	// post-ROM wires:
	logic  [video_pkg::CHR_WCW-1:0] rom_col;   // delayed column selector
	logic [video_pkg::CHR_HIGH-1:0] rom_bits;  // selected column bits
	logic                rom_valid; // delayed valid signal
	// pass-thru delay registers:
	video_pkg::pass_attr_t rom_attr;

	// sequentially keep track of input conditions:
	always_ff @(posedge clk) begin
		if (rst) begin
			rom_valid <= 0;
			rom_col   <= 0;
			rom_attr  <= 0;
		end else begin
			// `rom_valid` is 1 cycle behind input handshake:
			rom_valid <= i_valid & i_ready;
			// maintain pass-thru data during memory lookup cycle:
			rom_col  <= i_col;
			rom_attr <= i_attr;
		end
	end

	// select `rom_bits` from `rom_data` using `rom_col`:
	vec_slice_sel #(
		.SL(video_pkg::CHR_HIGH),
		.NS(video_pkg::CHR_WIDE),
		.MSF(1)
	) inst_vec_slice_sel (
		.vector(rom_data),
		.index(rom_col),
		.slice(rom_bits)
	);

	// valid/ready "lookahead" sync fifo:
	valid_ready_sync_fifo #(
		.DW($bits(o_col_bits)+$bits(o_attr)),
		.PW(2), // min. required size for optimal throughput
		.ENABLE_I_READY_2(1) // `i_ready` = min. *two* free fifo slots!
	) inst_lookahead_sync_fifo (
		.i_data({rom_bits, rom_attr}),
		.i_valid(rom_valid),
		.i_ready(i_ready), // at least *two* free fifo slots!
		.o_data({o_col_bits, o_attr}),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

endmodule: glyph_font_lookup

module pxl_col_serialize (
	// use blink & bell signals from frame generator:
	input  video_pkg::blink_sig_t blink,

	// consume a vector of 2 (if `border`) or 12 (otherwise) bits,
	// with the associated fg and bg color information
	input  logic [video_pkg::CHR_HIGH-1:0] chr_col_bits,
	input  video_pkg::pass_attr_t          chr_attr,
	input  logic                chr_col_valid,
	output logic                chr_col_ready,

	// produce pixels for the VGA phy:
	output video_pkg::vga_rgb_t pxl_data,
	output logic     pxl_valid,
	input  logic     pxl_ready,

	input logic clk,
	input logic rst
);

	// input data register(s):
	logic [video_pkg::CHR_HIGH-1:0] regbuf, regbufNext;
	// also register fg and bg colors:
	logic [7:0] clr_idx, regfg, regbg, regfgNext, regbgNext;
	// output color is fg (if MSB == 1), or bg (if MSB == 0):
	assign clr_idx = regbuf[video_pkg::CHR_HIGH-1] ? regfg : regbg;

	// convert current pixel color from ansi palette index to RGB:
	palette_comb inst_palette_comb (
		.index(clr_idx),
		.color(pxl_data)
	);

	// pixel counter:
	logic [video_pkg::CHR_HCW:0] cnt, cntNext; // (CW+1) wide, as (cnt == -1) reserved!

	// accept input if either consumer is waiting (`pxl_ready`),
	// or if we don't already have an unconsumed data token
	// on offer (`~/pxl_valid`), but only once we're down to
	// the *last* pixel (i.e., once cnt <= 0):
	assign chr_col_ready = (pxl_ready | ~pxl_valid) &
				(cnt == 0 | &cnt); // 0 or -1

	// handshake cond. for input (consumer) & output (producer) interf.:
	logic i_handshake, o_handshake;
	assign i_handshake = (chr_col_valid & chr_col_ready);
	assign o_handshake = (pxl_valid & pxl_ready);

	// next value for pxl_valid:
	logic pxl_validNext;

	// reverse video for given glyph box:
	logic rev;
	assign rev = (chr_attr.cursor & blink.cursor) ^
		     (chr_attr.flg.blink & blink.attrib);

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		regbufNext    = regbuf;
		regfgNext     = regfg;
		regbgNext     = regbg;
		cntNext       = cnt;
		pxl_validNext = pxl_valid;

		if (i_handshake) begin
			if (chr_attr.border) begin
				// only two bits are useful for the border;
				cntNext    = 1;
				// set them both to the current `v_bell`:
				regbufNext = {{2{blink.v_bell}},
						(video_pkg::CHR_HIGH-2)'('bX)};
				regfgNext  = 8'hF; // hardcode white for flash
				regbgNext  = 8'h0; // hardcode black for off
			end else begin
				cntNext    = video_pkg::CHR_HIGH - 1;
				regbufNext = chr_col_bits | chr_attr.flg.under;
				regfgNext  = rev ? chr_attr.bgc : chr_attr.fgc;
				regbgNext  = rev ? chr_attr.fgc : chr_attr.bgc;
			end
			pxl_validNext = 1;
		end else if (o_handshake) begin
			regbufNext = {regbuf[video_pkg::CHR_HIGH-2:0], 1'b0};
			cntNext    = cnt - 1;
			if (cnt == 0) begin
				pxl_validNext = 0;
			end
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			regbuf    <= 0;
			regfg     <= 0;
			regbg     <= 0;
			cnt       <= 0;
			pxl_valid <= 0;
		end else begin
			regbuf    <= regbufNext;
			regfg     <= regfgNext;
			regbg     <= regbgNext;
			cnt       <= cntNext;
			pxl_valid <= pxl_validNext;
		end
	end

endmodule: pxl_col_serialize

`ifdef TB_RASTER
// // verilator --binary -DTB_RASTER --top tb_raster scr_draw.sv
// // iverilog -g2005-sv -DTB_RASTER -s tb_raster -o tb_raster scr_draw.sv
module tb_raster ();

	// parameters:
	localparam NC = 65536; // clock cycles to simulate

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
	video_pkg::blink_sig_t blink;
	video_pkg::scr_pos_t pos;
	logic [video_pkg::CHR_WCW-1:0] col;
	logic frm_rndr_start, border, done, valid, ready;

	scr_sweep_raster dut (
		.frm_rndr_start(frm_rndr_start),
		.bell(0),
		.blink(blink),
		.pos(pos),
		.col(col),
		.border(border),
		.done(done),
		.valid(valid),
		.ready(ready),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			frm_rndr_start <= 1; // start 1st frame right away
			ready     <= 0;
		end else begin
			frm_rndr_start <= 0; // ensure we don't start 2nd frame
`ifdef VERILATOR
			ready <= $random[0];
`else
			ready <= $random;
`endif
			// on handshake, print coordinates & border flag:
			if (ready & valid)
				$display("r=%02d c=%02d cc=%0d b=%b done=%b",
					pos.y, pos.x, col, border, done);
		end
	end

endmodule: tb_raster
`endif // TB_RASTER

`ifdef TB_ADDR
// // verilator --binary -DTB_ADDR --top tb_addr scr_draw.sv
// // iverilog -g2005-sv -DTB_ADDR -s tb_addr -o tb_addr scr_draw.sv
// // tb_addr > o.log; paste <(grep ^i o.log) <(grep ^o o_log)
module tb_addr ();

	// parameters:
	localparam NC = 65536; // clock cycles to simulate

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
	video_pkg::blink_sig_t blink;
	video_pkg::scr_pos_t i_pos;
	logic [video_pkg::CHR_WCW-1:0] i_col;
	logic frm_rndr_start, i_border, i_done, i_valid, i_ready;

	scr_sweep_raster inst_scr_sweep_raster (
		.frm_rndr_start(frm_rndr_start),
		.bell(0),
		.blink(blink),
		.pos(i_pos),
		.col(i_col),
		.border(i_border),
		.done(i_done),
		.valid(i_valid),
		.ready(i_ready),
		.clk(clk),
		.rst(rst)
	);

	logic [video_pkg::SCR_BUF_AW-1:0] vp_base, o_addr;
	logic    [video_pkg::CHR_WCW-1:0] o_col;
	logic o_border, o_done, o_valid, o_ready;

	scr_pos_to_addr dut (
		.vp_base(vp_base),
		.i_pos(i_pos),
		.i_col(i_col),
		.i_border(i_border),
		.i_done(i_done),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_addr(o_addr),
		.o_col(o_col),
		.o_border(o_border),
		.o_done(o_done),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			vp_base   <= video_pkg::SCR_BUF_AW'('h0);
			frm_rndr_start <= 1; // start 1st frame right away
			o_ready   <= 0;
		end else begin
			frm_rndr_start <= 0; // ensure we don't start 2nd frame
`ifdef VERILATOR
			o_ready <= $random[0];
`else
			o_ready <= $random;
`endif
			// on i_handshake, print coordinates & border flag,
			// and also the expected resulting address:
			/* verilator lint_off WIDTHEXPAND */
			if (i_ready & i_valid)
			   $display("i: r=%02d c=%02d cc=%0d b=%b dn=%b a=%04h",
				i_pos.y, i_pos.x, i_col, i_border, i_done,
			video_pkg::SCR_BUF_AW'(vp_base + i_pos.y * video_pkg::SCR_COLS + i_pos.x)
			   );
			// on o_handshake, print address and pass-thru data:
			if (o_ready & o_valid)
				$display("o: a=%04h cc=%0d b=%b dn=%b",
					o_addr, o_col, o_border, o_done);
		end
	end

endmodule: tb_addr
`endif // TB_ADDR

`ifdef TB_SBUF
// // verilator --binary -DTB_SBUF --top tb_sbuf scr_draw.sv syncmem.sv valid_ready.sv
// // iverilog -g2005-sv -DTB_SBUF -s tb_sbuf -o tb_sbuf scr_draw.sv syncmem.sv valid_ready.sv
// // tb_sbuf > o.log; paste <(grep ^i o.log) <(grep ^o o_log)
module tb_sbuf ();

	// parameters:
	localparam NC = 128; // clock cycles to simulate

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
	logic [video_pkg::SCR_BUF_AW-1:0] i_addr;
	video_pkg::glyph_box_t o_glyphbox;
	logic [video_pkg::CHR_WCW-1:0] i_col, o_col;
	logic i_border, i_done, i_valid, i_ready,
		o_border, o_cursor, o_valid, o_ready;

	scr_display_buf dut (
		.crs_adr(0),
		.start(0),
		.i_addr(i_addr),
		.i_col(i_col),
		.i_border(i_border),
		.i_done(i_done),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_glyphbox(o_glyphbox),
		.o_col(o_col),
		.o_border(o_border),
		.o_cursor(o_cursor),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_valid  <= 0;
			i_addr   <= 0;
			i_col    <= 0;
			i_border <= 0;
			o_ready  <= 0;
		end else begin
`ifdef VERILATOR
			// producer:
			i_valid  <= $random[0];
			i_addr   <= $random[video_pkg::SCR_BUF_AW-1:0];
			i_col    <= $random[video_pkg::CHR_WCW-1:0];
			i_border <= $random[0];
			// consumer:
			o_ready  <= $random[0];
`else
			// producer:
			i_valid  <= $random;
			i_addr   <= $random;
			i_col    <= $random;
			i_border <= $random;
			// consumer:
			o_ready  <= $random;
`endif
//			// test bursting:
//			i_valid  <= 1;
//			o_ready  <= 1;
			// print i_handshake:
			if (i_ready & i_valid)
				$display("i[%04t]: a=%04h cc=%0d b=%b",
					$time, i_addr, i_col, i_border);
			// print i_handshake:
			if (o_ready & o_valid)
				$display("o[%04t]: gb=%010h cc=%0d b=%b",
					$time, o_glyphbox, o_col, o_border);
		end
	end

endmodule: tb_sbuf
`endif // TB_SBUF

`ifdef TB_UTFADR
// // verilator --binary -DTB_UTFADR --top tb_utfadr scr_draw.sv
// // iverilog -g2005-sv -DTB_UTFADR -s tb_utfadr -o tb_utfadr scr_draw.sv
// // tb_utfadr > o.log; paste <(grep ^i o.log) <(grep ^o o_log)
module tb_utfadr ();

	// parameters:
	localparam NC = 128; // clock cycles to simulate

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

	// DUT (and associated wires):
	video_pkg::glyph_box_t         i_glyphbox;
	logic [video_pkg::CHR_WCW-1:0] i_col, o_col;
	logic  [video_pkg::GLP_AW-1:0] o_addr;
	video_pkg::pass_attr_t         o_attr;
	logic i_border, i_cursor, i_valid, i_ready, o_valid, o_ready;

	utf_enc_to_addr dut (
		.i_glyphbox(i_glyphbox),
		.i_col(i_col),
		.i_border(i_border),
		.i_cursor(i_cursor),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_addr(o_addr),
		.o_col(o_col),
		.o_attr(o_attr),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_valid    <= 0;
			i_glyphbox <= 0;
			i_col      <= 0;
			i_border   <= 0;
			i_cursor   <= 0;
			o_ready    <= 0;
		end else begin
`ifdef VERILATOR
			// orig. upstream producer:
			i_valid        <= $random[0];
//			i_glyphbox.utf <= $random[20:0];
			i_glyphbox.utf <= {13'b0, $random[7:0]};
			i_col          <= $random[video_pkg::CHR_WCW-1:0];
			i_border       <= $random[0];
			i_cursor       <= $random[0];
			// dut consumer:
			o_ready  <= $random[0];
`else
			// orig. producer:
			i_valid        <= $random;
			i_glyphbox.utf <= $random;
			i_col          <= $random;
			i_border       <= $random;
			i_cursor       <= $random;
			// consumer:
			o_ready  <= $random;
`endif
//			// test bursting:
//			valid   <= 1;
//			o_ready <= 1;
			// print i_handshake:
			if (i_ready & i_valid)
				$display("i[%04t]: utf=%06h cc=%0d b=%b",
				     $time, i_glyphbox.utf, i_col, i_border);
			// print o_handshake:
			if (o_ready & o_valid)
				$display("o[%04t]: adr=%03h cc=%0d b=%b",
					$time, o_addr, o_col, o_attr.border);
		end
	end

endmodule: tb_utfadr
`endif // TB_UTFADR

`ifdef TB_GLPH
// // verilator --binary -DTB_GLPH --top tb_glph scr_draw.sv syncmem.sv valid_ready.sv vec_slice_sel.sv
// // iverilog -g2005-sv -DTB_GLPH -s tb_glph -o tb_glph scr_draw.sv syncmem.sv valid_ready.sv vec_slice_sel.sv
// // tb_glph > o.log; paste <(grep ^i o.log) <(grep ^o o_log)
module tb_glph ();

	// parameters:
	localparam NC = 128; // clock cycles to simulate

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

	// DUT (and associated wires):
	logic   [video_pkg::GLP_AW-1:0] i_addr;
	logic  [video_pkg::CHR_WCW-1:0] i_col;
	video_pkg::pass_attr_t          i_attr, o_attr;
	logic [video_pkg::CHR_HIGH-1:0] o_col_bits;
	logic i_valid, i_ready, o_valid, o_ready;
	logic   [video_pkg::GLP_AW-1:0] rom_addr;
	logic   [video_pkg::GLP_DW-1:0] rom_data;

	// glyph ROM:
	sync_rom #(
		.FN("chargen/utfglphrom.hex"),
		.AW(video_pkg::GLP_AW),
		.DW(video_pkg::GLP_DW)
	) inst_sync_rom (
		.addr(rom_addr),
		.rdata(rom_data),
		.clk(clk)
	);

	glyph_font_lookup dut (
		.i_addr(i_addr),
		.i_col(i_col),
		.i_attr(i_attr),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_col_bits(o_col_bits),
		.o_attr(o_attr),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.rom_addr(rom_addr),
		.rom_data(rom_data),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_valid <= 0;
			i_addr  <= 0;
			i_col   <= 0;
			i_attr  <= 0;
			o_ready <= 0;
		end else begin
`ifdef VERILATOR
			// orig. upstream producer:
			i_valid <= $random[0];
			i_addr  <= $random[video_pkg::GLP_AW-1:0];
			i_col   <= $random[video_pkg::CHR_WCW-1:0];
			i_attr  <= {$random,$random}[$bits(i_attr)-1:0];
			// dut consumer:
			o_ready <= $random[0];
`else
			// orig. producer:
			i_valid <= $random;
			i_addr  <= $random;
			i_col   <= $random;
			i_attr  <= $random;
			// consumer:
			o_ready <= $random;
`endif
//			// do `col` sequentially instead:
//			i_addr  <= 'h42;
//			i_col   <= i_col - 1;
//			// test bursting:
//			i_valid <= 1;
//			o_ready <= 1;
			// print i_handshake:
			if (i_ready & i_valid)
				$display("i[%04t]: addr=%03h cc=%0d att=%09h",
					$time, i_addr, i_col, i_attr);
			// print o_handshake:
			if (o_ready & o_valid)
				$display("o[%04t]: cb=%b att=%09h",
					$time, o_col_bits, o_attr);
		end
	end

endmodule: tb_glph
`endif // TB_GLPH
