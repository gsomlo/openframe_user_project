// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`include "kbd.svh"

// turn a scancode with context modifier flags into a byte sequence
// representing an ASCII / UTF-8 character, or ANSI escape sequence;
// NOTE: this module could be implemented as a ROM, or as a RAM that is
//       only written during startup (i.e., populated from flash), then
//       accessed only in read mode. However, it would end up a *very*
//       sparse ROM (or RAM), and therefore the purported inefficiency
//       of implementing it combinationally could well be mitigated by
//       the relative simplicity and legibility.
module kbd_comb_layout (
	// address: consume processed, context-enabled keypress events:
	input  logic [7:0] i_key_sc,
	input  kbd_pkg::key_ctx_t   i_key_ctx,

	// data: keycode byte vector to send out (e.g., via uart_tx):
	output kbd_pkg::keycode_t o_key_vec,
	// also, signal if the designated "compose" key was pressed:
	output logic     o_key_compose
);

	// collapse/simplify part of the modifier context:
	logic cntrl, shift, meta;
	// Shift, Ctrl and Meta are "achiral":
	assign cntrl = (i_key_ctx.ctll | i_key_ctx.ctlr);
	assign meta  = (i_key_ctx.metl | i_key_ctx.metr);
	// if CapsLock, shift *down* (vs. up)!
	assign shift = (i_key_ctx.shfl | i_key_ctx.shfr) ^ i_key_ctx.caps;

	// ┌───────────── i_key_ctx.ext0 (ext0-mode key press)
	// │┌──────────── i_key_ctx.numl (NumLock)
	// ││ ┌────────── i_key_ctx.ctl3 (ext1-mode "ctl", during Pause)
	// ││ │┌───────── i_key_ctx.shf3 (ext0-mode "shfl, during PrSc)
	// ││ ││┌──────── i_key_ctx.scrl (ScrollLock)
	// ││ │││ ┌────── meta (a.k.a. "Windows", left or right)
	// ││ │││ │┌───── altr (AltGr, right)
	// ││ │││ ││ ┌─── altl (Alt, left)
	// ││ │││ ││ │┌── cntrl (left or right)
	// ││ │││ ││ ││┌─ shift (left or right, accounting for CapsLock)
	// en_xyr_mg_acs
	logic [9:0] en_xyr_mg_acs;
	assign en_xyr_mg_acs = {i_key_ctx.ext0, i_key_ctx.numl,
				i_key_ctx.ctl3, i_key_ctx.shf3, i_key_ctx.scrl,
				meta, i_key_ctx.altr,
				i_key_ctx.altl, cntrl, shift};

	always_comb begin

	    // default output is "nothing":
	    // NOTE: some compilers (e.g., Quartus) will truncate a literal
	    //       down to 32 bits, even if it is being assigned to a wide
	    //       enough vector. Therefore, we forego the possibly more
	    //       elegant {SW'('h0), KW'('hXX_XX_XX_XX_XX)} (or even
	    //       'h0_XX_XX_XX_XX_XX) options of formulating the literal
	    //       assigned to `o_key_vec` below in favor of a
	    //       comma-separated list of individual bytes.
	    o_key_vec = {kbd_pkg::SW'('h0), {8'hXX,8'hXX,8'hXX,8'hXX,8'hXX}};
	    // also, assume compose key was not pressed:
	    o_key_compose = 0;

	    /* verilator lint_off CASEINCOMPLETE */
	    case (i_key_sc)
	    // Escape and Function keys:
	    kbd_pkg::SC_ESC:	// '<esc>' (regardless of any modifiers)
		o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1B}};
	    kbd_pkg::SC_F1:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>OP'
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'h1B,8'h4F,8'h50}};
		10'b??_???_??_??1: // '<esc>[25~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h32,8'h35,8'h7E}};
		endcase
	    kbd_pkg::SC_F2:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>OQ'
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'h1B,8'h4F,8'h51}};
		10'b??_???_??_??1: // '<esc>[26~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h32,8'h36,8'h7E}};
		endcase
	    kbd_pkg::SC_F3:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>OR'
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'h1B,8'h4F,8'h52}};
		10'b??_???_??_??1: // '<esc>[28~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h32,8'h38,8'h7E}};
		endcase
	    kbd_pkg::SC_F4:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>OS'
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'h1B,8'h4F,8'h53}};
		10'b??_???_??_??1: // '<esc>[29~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h32,8'h39,8'h7E}};
		endcase
	    kbd_pkg::SC_F5:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>[15~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h31,8'h35,8'h7E}};
		10'b??_???_??_??1: // '<esc>[31~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h33,8'h31,8'h7E}};
		endcase
	    kbd_pkg::SC_F6:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>[17~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h31,8'h37,8'h7E}};
		10'b??_???_??_??1: // '<esc>[32~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h33,8'h32,8'h7E}};
		endcase
	    kbd_pkg::SC_F7:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>[18~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h31,8'h38,8'h7E}};
		10'b??_???_??_??1: // '<esc>[33~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h33,8'h33,8'h7E}};
		endcase
	    kbd_pkg::SC_F8:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>[19~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h31,8'h39,8'h7E}};
		10'b??_???_??_??1: // '<esc>[34~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h33,8'h34,8'h7E}};
		endcase
	    kbd_pkg::SC_F9:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>[20~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h32,8'h30,8'h7E}};
		10'b??_???_??_??1: // '<esc>[11~' (alternate F1)
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h31,8'h31,8'h7E}};
		endcase
	    kbd_pkg::SC_F10:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>[21~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h32,8'h31,8'h7E}};
		10'b??_???_??_??1: // '<esc>[12~' (alternate F2)
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h31,8'h32,8'h7E}};
		endcase
	    kbd_pkg::SC_F11:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>[23~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h32,8'h33,8'h7E}};
		10'b??_???_??_??1: // '<esc>[13~' (alternate F3)
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h31,8'h33,8'h7E}};
		endcase
	    kbd_pkg::SC_F12:
		casez (en_xyr_mg_acs)
		10'b??_???_??_??0: // '<esc>[24~'
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h32,8'h34,8'h7E}};
		10'b??_???_??_??1: // '<esc>[14~' (alternate F4)
		    o_key_vec = {kbd_pkg::SW'('h5), {8'h1B,8'h5B,8'h31,8'h34,8'h7E}};
		endcase

	    // Row 1:
	    kbd_pkg::SC_BKT:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // `
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h60}};
		10'b??_???_??_001: // ~
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h7E}};
		10'b??_???_??_010: // <nul>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h00}};
		10'b??_???_??_011: // <rs>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1E}};
		10'b??_???_??_100: // '<esc>`'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h60}};
		10'b??_???_??_101: // '<esc>~'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h7E}};
		10'b??_???_??_110: // '<esc><nul>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h00}};
		10'b??_???_??_111: // '<esc><rs>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1E}};
		endcase
	    kbd_pkg::SC_1:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0?0: // 1
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h31}};
		10'b??_???_??_0?1: // !
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h21}};
		10'b??_???_??_1?0: // '<esc>1'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h31}};
		10'b??_???_??_1?1: // '<esc>!'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h21}};
		endcase
	    kbd_pkg::SC_2:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // 2
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h32}};
		10'b??_???_??_001: // @
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h40}};
		10'b??_???_??_01?: // <nul>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h00}};
		10'b??_???_??_100: // '<esc>2'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h32}};
		10'b??_???_??_101: // '<esc>@'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h40}};
		10'b??_???_??_11?: // '<esc><nul>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h00}};
		endcase
	    kbd_pkg::SC_3:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // 3
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h33}};
		10'b??_???_??_001: // #
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h23}};
		10'b??_???_??_100: // '<esc>3'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h33}};
		10'b??_???_??_101: // '<esc>#'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h23}};
		10'b??_???_??_?1?: // <esc> (no '<esc><esc>'!)
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1B}};
		endcase
	    kbd_pkg::SC_4:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // 4
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h34}};
		10'b??_???_??_001: // $
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h24}};
		10'b??_???_??_01?: // <fs>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1C}};
		10'b??_???_??_100: // '<esc>4'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h34}};
		10'b??_???_??_101: // '<esc>$'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h24}};
		10'b??_???_??_11?: // '<esc><fs>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1C}};
		endcase
	    kbd_pkg::SC_5:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // 5
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h35}};
		10'b??_???_??_001: // %
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h25}};
		10'b??_???_??_01?: // <gs>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1D}};
		10'b??_???_??_100: // '<esc>5'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h35}};
		10'b??_???_??_101: // '<esc>%'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h25}};
		10'b??_???_??_11?: // '<esc><gs>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1D}};
		endcase
	    kbd_pkg::SC_6:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // 6
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h36}};
		10'b??_???_??_001: // ^
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h5E}};
		10'b??_???_??_01?: // <rs>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1E}};
		10'b??_???_??_100: // '<esc>6'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h36}};
		10'b??_???_??_101: // '<esc>^'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h5E}};
		10'b??_???_??_11?: // '<esc><rs>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1E}};
		endcase
	    kbd_pkg::SC_7:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // 7
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h37}};
		10'b??_???_??_001: // &
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h26}};
		10'b??_???_??_01?: // <us>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1F}};
		10'b??_???_??_100: // '<esc>7'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h37}};
		10'b??_???_??_101: // '<esc>&'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h26}};
		10'b??_???_??_11?: // '<esc><us>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1F}};
		endcase
	    kbd_pkg::SC_8:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // 8
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h38}};
		10'b??_???_??_001: // *
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2A}};
		10'b??_???_??_01?: // <del>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h7F}};
		10'b??_???_??_100: // '<esc>8'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h38}};
		10'b??_???_??_101: // '<esc>*'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h2A}};
		10'b??_???_??_11?: // '<esc><del>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h7F}};
		endcase
	    kbd_pkg::SC_9:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0?0: // 9
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h39}};
		10'b??_???_??_0?1: // (
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h28}};
		10'b??_???_??_1?0: // '<esc>9'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h39}};
		10'b??_???_??_1?1: // '<esc>('
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h28}};
		endcase
	    kbd_pkg::SC_0:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0?0: // 0
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h30}};
		10'b??_???_??_0?1: // )
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h29}};
		10'b??_???_??_1?0: // '<esc>0'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h30}};
		10'b??_???_??_1?1: // '<esc>)'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h29}};
		endcase
	    kbd_pkg::SC_SUB:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // -
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2D}};
		10'b??_???_??_001: // _
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h5F}};
		10'b??_???_??_01?: // <us>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1F}};
		10'b??_???_??_100: // '<esc>-'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h2D}};
		10'b??_???_??_101: // '<esc>_'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h5F}};
		10'b??_???_??_11?: // '<esc><us>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1F}};
		endcase
	    kbd_pkg::SC_EQL:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0?0: // =
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h3D}};
		10'b??_???_??_0?1: // +
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2B}};
		10'b??_???_??_1?0: // '<esc>='
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h3D}};
		10'b??_???_??_1?1: // '<esc>+'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h2B}};
		endcase
	    kbd_pkg::SC_BSP:
		casez (en_xyr_mg_acs)
		10'b??_???_??_00?: // <del>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h7F}};
		10'b??_???_??_01?: // <bs>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h08}};
		10'b??_???_??_10?: // '<esc><del>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h7F}};
		10'b??_???_??_11?: // '<esc><bs>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h08}};
		endcase

	    // Row 2:
	    kbd_pkg::SC_TAB:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0??: // <ht>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h09}};
// or:		10'b??_???_??_001: // '<esc>[Z'
//		    o_key_vec = {SW'('h3), {8'hXX,8'hXX,8'h1B,8'h5B,8'h5A}};
		10'b??_???_??_1??: // '<esc><ht>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h09}};
		endcase
	    kbd_pkg::SC_Q:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // q
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h71}};
		10'b??_???_??_001: // Q
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h51}};
		10'b??_???_??_01?: // <dc1>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h11}};
		10'b??_???_??_100: // '<esc>q'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h71}};
		10'b??_???_??_101: // '<esc>Q'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h51}};
		10'b??_???_??_11?: // '<esc><dc1>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h11}};
		endcase
	    kbd_pkg::SC_W:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // w
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h77}};
		10'b??_???_??_001: // W
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h57}};
		10'b??_???_??_01?: // <etb>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h17}};
		10'b??_???_??_100: // '<esc>w'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h77}};
		10'b??_???_??_101: // '<esc>W'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h57}};
		10'b??_???_??_11?: // '<esc><etb>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h17}};
		endcase
	    kbd_pkg::SC_E:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // e
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h65}};
		10'b??_???_??_001: // E
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h45}};
		10'b??_???_??_01?: // <enq>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h05}};
		10'b??_???_??_100: // '<esc>e'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h65}};
		10'b??_???_??_101: // '<esc>E'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h45}};
		10'b??_???_??_11?: // '<esc><enq>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h05}};
		endcase
	    kbd_pkg::SC_R:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // r
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h72}};
		10'b??_???_??_001: // R
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h52}};
		10'b??_???_??_01?: // <dc2>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h12}};
		10'b??_???_??_100: // '<esc>r'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h72}};
		10'b??_???_??_101: // '<esc>R'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h52}};
		10'b??_???_??_11?: // '<esc><dc2>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h12}};
		endcase
	    kbd_pkg::SC_T:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // t
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h74}};
		10'b??_???_??_001: // T
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h54}};
		10'b??_???_??_01?: // <dc4>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h14}};
		10'b??_???_??_100: // '<esc>t'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h74}};
		10'b??_???_??_101: // '<esc>T'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h54}};
		10'b??_???_??_11?: // '<esc><dc4>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h14}};
		endcase
	    kbd_pkg::SC_Y:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // y
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h79}};
		10'b??_???_??_001: // Y
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h59}};
		10'b??_???_??_01?: // <em>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h19}};
		10'b??_???_??_100: // '<esc>y'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h79}};
		10'b??_???_??_101: // '<esc>Y'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h59}};
		10'b??_???_??_11?: // '<esc><em>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h19}};
		endcase
	    kbd_pkg::SC_U:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // u
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h75}};
		10'b??_???_??_001: // U
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h55}};
		10'b??_???_??_010: // <nak>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h15}};
		10'b??_???_??_011: // Arb. ≤5 byte seq. compose (e.g., utf-8):
		    o_key_compose = 1;
		10'b??_???_??_100: // '<esc>u'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h75}};
		10'b??_???_??_101: // '<esc>U'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h55}};
		10'b??_???_??_11?: // '<esc><nak>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h15}};
		endcase
	    kbd_pkg::SC_I:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // i
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h69}};
		10'b??_???_??_001: // I
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h49}};
		10'b??_???_??_01?: // <ht>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h09}};
		10'b??_???_??_100: // '<esc>i'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h69}};
		10'b??_???_??_101: // '<esc>I'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h49}};
		10'b??_???_??_11?: // '<esc><ht>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h09}};
		endcase
	    kbd_pkg::SC_O:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // o
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h6F}};
		10'b??_???_??_001: // O
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h4F}};
		10'b??_???_??_01?: // <si>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h0F}};
		10'b??_???_??_100: // '<esc>o'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h6F}};
		10'b??_???_??_101: // '<esc>O'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h4F}};
		10'b??_???_??_11?: // '<esc><si>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h0F}};
		endcase
	    kbd_pkg::SC_P:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // p
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h70}};
		10'b??_???_??_001: // P
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h50}};
		10'b??_???_??_01?: // <cc>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h10}};
		10'b??_???_??_100: // '<esc>p'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h70}};
		10'b??_???_??_101: // '<esc>P'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h50}};
		10'b??_???_??_11?: // '<esc><cc>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h10}};
		endcase
	    kbd_pkg::SC_SQL:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // [
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h5B}};
		10'b??_???_??_001: // {
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h7B}};
		10'b??_???_??_100: // '<esc>['
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h5B}};
		10'b??_???_??_101: // '<esc>{'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h7B}};
		10'b??_???_??_?1?: // <esc> (no '<esc><esc>'!)
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1B}};
		endcase
	    kbd_pkg::SC_SQR:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // ]
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h5D}};
		10'b??_???_??_001: // }
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h7D}};
		10'b??_???_??_01?: // <gs>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1D}};
		10'b??_???_??_100: // '<esc>l'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h5D}};
		10'b??_???_??_101: // '<esc>L'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h7D}};
		10'b??_???_??_11?: // '<esc><gs>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1D}};
		endcase
	    kbd_pkg::SC_BSL:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // \
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h5C}};
		10'b??_???_??_001: // |
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h7C}};
		10'b??_???_??_01?: // <fs>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1C}};
		10'b??_???_??_100: // '<esc>\'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h5C}};
		10'b??_???_??_101: // '<esc>|'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h7C}};
		10'b??_???_??_11?: // '<esc><fs>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1C}};
		endcase

	    // Row 3:
	    kbd_pkg::SC_A:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // a
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h61}};
		10'b??_???_??_001: // A
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h41}};
		10'b??_???_??_01?: // <soh>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h01}};
		10'b??_???_??_100: // '<esc>a'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h61}};
		10'b??_???_??_101: // '<esc>A'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h41}};
		10'b??_???_??_11?: // '<esc><soh>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h01}};
		endcase
	    kbd_pkg::SC_S:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // s
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h73}};
		10'b??_???_??_001: // S
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h53}};
		10'b??_???_??_01?: // <dc3>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h13}};
		10'b??_???_??_100: // '<esc>s'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h73}};
		10'b??_???_??_101: // '<esc>S'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h53}};
		10'b??_???_??_11?: // '<esc><dc3>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h13}};
		endcase
	    kbd_pkg::SC_D:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // d
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h64}};
		10'b??_???_??_001: // D
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h44}};
		10'b??_???_??_01?: // <eot>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h04}};
		10'b??_???_??_100: // '<esc>d'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h64}};
		10'b??_???_??_101: // '<esc>D'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h44}};
		10'b??_???_??_11?: // '<esc><eot>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h04}};
		endcase
	    kbd_pkg::SC_F:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // f
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h66}};
		10'b??_???_??_001: // F
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h46}};
		10'b??_???_??_01?: // <ack>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h06}};
		10'b??_???_??_100: // '<esc>f'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h66}};
		10'b??_???_??_101: // '<esc>F'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h46}};
		10'b??_???_??_11?: // '<esc><ack>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h06}};
		endcase
	    kbd_pkg::SC_G:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // g
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h67}};
		10'b??_???_??_001: // G
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h47}};
		10'b??_???_??_01?: // <bel>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h07}};
		10'b??_???_??_100: // '<esc>g'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h67}};
		10'b??_???_??_101: // '<esc>G'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h47}};
		10'b??_???_??_11?: // '<esc><bel>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h07}};
		endcase
	    kbd_pkg::SC_H:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // h
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h68}};
		10'b??_???_??_001: // H
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h48}};
		10'b??_???_??_01?: // <bs>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h08}};
		10'b??_???_??_100: // '<esc>h'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h68}};
		10'b??_???_??_101: // '<esc>H'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h48}};
		10'b??_???_??_11?: // '<esc><bs>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h08}};
		endcase
	    kbd_pkg::SC_J:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // j
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h6A}};
		10'b??_???_??_001: // J
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h4A}};
		10'b??_???_??_01?: // <lf>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h0A}};
		10'b??_???_??_100: // '<esc>j'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h6A}};
		10'b??_???_??_101: // '<esc>J'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h4A}};
		10'b??_???_??_11?: // '<esc><lf>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h0A}};
		endcase
	    kbd_pkg::SC_K:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // k
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h6B}};
		10'b??_???_??_001: // K
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h4B}};
		10'b??_???_??_01?: // <vt>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h0B}};
		10'b??_???_??_100: // '<esc>k'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h6B}};
		10'b??_???_??_101: // '<esc>K'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h4B}};
		10'b??_???_??_11?: // '<esc><vt>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h0B}};
		endcase
	    kbd_pkg::SC_L:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // l
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h6C}};
		10'b??_???_??_001: // L
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h4C}};
		10'b??_???_??_01?: // <ff>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h0C}};
		10'b??_???_??_100: // '<esc>l'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h6C}};
		10'b??_???_??_101: // '<esc>L'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h4C}};
		10'b??_???_??_11?: // '<esc><ff>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h0C}};
		endcase
	    kbd_pkg::SC_SEM:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0?0: // ;
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h3B}};
		10'b??_???_??_0?1: // :
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h3A}};
		10'b??_???_??_1?0: // '<esc>;'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h3B}};
		10'b??_???_??_1?1: // '<esc>:'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h3A}};
		endcase
	    kbd_pkg::SC_TCK:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0?0: // '
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h27}};
		10'b??_???_??_0?1: // "
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h22}};
		10'b??_???_??_1?0: // '<esc>''
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h27}};
		10'b??_???_??_1?1: // '<esc>"'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h22}};
		endcase
	    kbd_pkg::SC_ENT:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0??: // <cr>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h0D}};
		10'b??_???_??_1??: // '<esc><cr>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h0D}};
		endcase

	    // Row 4:
	    kbd_pkg::SC_Z:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // z
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h7A}};
		10'b??_???_??_001: // Z
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h5A}};
		10'b??_???_??_01?: // <sub>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h1A}};
		10'b??_???_??_100: // '<esc>z'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h7A}};
		10'b??_???_??_101: // '<esc>Z'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h5A}};
		10'b??_???_??_11?: // '<esc><sub>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h1A}};
		endcase
	    kbd_pkg::SC_X:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // x
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h78}};
		10'b??_???_??_001: // X
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h58}};
		10'b??_???_??_01?: // <can>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h18}};
		10'b??_???_??_100: // '<esc>x'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h78}};
		10'b??_???_??_101: // '<esc>X'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h58}};
		10'b??_???_??_11?: // '<esc><can>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h18}};
		endcase
	    kbd_pkg::SC_C:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // c
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h63}};
		10'b??_???_??_001: // C
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h43}};
		10'b??_???_??_01?: // <etx>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h03}};
		10'b??_???_??_100: // '<esc>c'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h63}};
		10'b??_???_??_101: // '<esc>C'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h43}};
		10'b??_???_??_11?: // '<esc><etx>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h03}};
		endcase
	    kbd_pkg::SC_V:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // v
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h76}};
		10'b??_???_??_001: // V
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h56}};
		10'b??_???_??_01?: // <syn>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h16}};
		10'b??_???_??_100: // '<esc>v'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h76}};
		10'b??_???_??_101: // '<esc>V'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h56}};
		10'b??_???_??_11?: // '<esc><syn>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h16}};
		endcase
	    kbd_pkg::SC_B:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // b
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h62}};
		10'b??_???_??_001: // B
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h42}};
		10'b??_???_??_01?: // <stx>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h02}};
		10'b??_???_??_100: // '<esc>b'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h62}};
		10'b??_???_??_101: // '<esc>B'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h42}};
		10'b??_???_??_11?: // '<esc><stx>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h02}};
		endcase
	    kbd_pkg::SC_N:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // n
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h6E}};
		10'b??_???_??_001: // N
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h4E}};
		10'b??_???_??_01?: // <so>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h0E}};
		10'b??_???_??_100: // '<esc>n'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h6E}};
		10'b??_???_??_101: // '<esc>N'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h4E}};
		10'b??_???_??_11?: // '<esc><so>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h0E}};
		endcase
	    kbd_pkg::SC_M:
		casez (en_xyr_mg_acs)
		10'b??_???_??_000: // m
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h6D}};
		10'b??_???_??_001: // M
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h4D}};
		10'b??_???_??_01?: // <cr>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h0D}};
		10'b??_???_??_100: // '<esc>m'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h6D}};
		10'b??_???_??_101: // '<esc>M'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h4D}};
		10'b??_???_??_11?: // '<esc><cr>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h0D}};
		endcase
	    kbd_pkg::SC_COM:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0?0: // ,
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2C}};
		10'b??_???_??_0?1: // <
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h3C}};
		10'b??_???_??_1?0: // '<esc>,'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h2C}};
		10'b??_???_??_1?1: // '<esc><'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h3C}};
		endcase
	    kbd_pkg::SC_PER:
		casez (en_xyr_mg_acs)
		10'b??_???_??_0?0: // .
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2E}};
		10'b??_???_??_0?1: // >
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h3E}};
		10'b??_???_??_1?0: // '<esc>.'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h2E}};
		10'b??_???_??_1?1: // '<esc>>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h3E}};
		endcase
	    kbd_pkg::SC_FSL:
		casez (en_xyr_mg_acs)
		10'b0?_???_??_000: // /
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2F}};
		10'b0?_???_??_001: // ?
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h3F}};
		10'b0?_???_??_01?: // <del>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h7F}};
		10'b0?_???_??_100: // '<esc>/'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h2F}};
		10'b0?_???_??_101: // '<esc>?'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h3F}};
		10'b0?_???_??_11?: // '<esc><del>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h7F}};
		10'b1?_???_??_???: // / (NumPad alternative)
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2F}};
		endcase

	    // Row 5:
	    kbd_pkg::SC_SPC:
		casez (en_xyr_mg_acs)
		10'b??_???_??_00?: // <space>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h20}};
		10'b??_???_??_01?: // <nul>
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h00}};
		10'b??_???_??_10?: // '<esc><space>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h20}};
		10'b??_???_??_11?: // '<esc><nul>'
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'h1B,8'h00}};
/* FIXME: zero out the `g` column above if we end up using these:
		10'b??_???_?1_??0: // <nbsp> (utf-8)
		    o_key_vec = {kbd_pkg::SW'('h2), {8'hXX,8'hXX,8'hXX,8'hC2,8'hA0}};
		10'b??_???_?1_??1: // <nnbsp> (utf-8)
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'hE2,8'h80,8'hAF}};
*/
		endcase
//	    SC_MEN: // menu key (ext0 only, not present on all keyboards)
//		o_key_vec = {SW'('h0), {8'hXX,8'hXX,8'hXX,8'hXX,8'hXX}};

	    // NumPad:
	    kbd_pkg::SC_KP_MUL:
		casez (en_xyr_mg_acs)
		10'b0?_???_??_???: // *
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2A}};
//		10'b1?_???_??_???: // PrtScr/SysRq (unmod, w. y=shf3 on)
//		    o_key_vec = {SW'('h0), {8'hXX,8'hXX,8'hXX,8'hXX,8'hXX}};
		endcase
	    kbd_pkg::SC_KP_ADD:	// +
		o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2B}};
	    kbd_pkg::SC_KP_SUB:	// -
		o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2D}};
	    kbd_pkg::SC_KP_PER:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // .
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h2E}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // Del  '<esc>[3~'
		    o_key_vec = {kbd_pkg::SW'('h4), {8'hXX,8'h1B,8'h5B,8'h33,8'h7E}};
		endcase
	    kbd_pkg::SC_KP_0:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 0
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h30}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // Ins  '<esc>[2~'
		    o_key_vec = {kbd_pkg::SW'('h4), {8'hXX,8'h1B,8'h5B,8'h32,8'h7E}};
		endcase
	    kbd_pkg::SC_KP_1:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 1
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h31}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // End  '<esc>[4~'
		    o_key_vec = {kbd_pkg::SW'('h4), {8'hXX,8'h1B,8'h5B,8'h34,8'h7E}};
// or:		10'b1?_???_??_???,
//		10'b00_???_??_???: // End  '<esc>[8~'
//		    o_key_vec = {SW'('h4), {8'hXX,8'h1B,8'h5B,8'h38,8'h7E}};
		endcase
	    kbd_pkg::SC_KP_2:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 2
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h32}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // ↓    '<esc>[B'
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'h1B,8'h5B,8'h42}};
		endcase
	    kbd_pkg::SC_KP_3:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 3
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h33}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // PgDn '<esc>[6~'
		    o_key_vec = {kbd_pkg::SW'('h4), {8'hXX,8'h1B,8'h5B,8'h36,8'h7E}};
		endcase
	    kbd_pkg::SC_KP_4:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 4
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h34}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // ←    '<esc>[D'
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'h1B,8'h5B,8'h44}};
		endcase
	    kbd_pkg::SC_KP_5: // 5
		o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h35}};
	    kbd_pkg::SC_KP_6:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 6
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h36}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // →    '<esc>[C'
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'h1B,8'h5B,8'h43}};
		endcase
	    kbd_pkg::SC_KP_7:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 7
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h37}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // Home '<esc>[1~'
		    o_key_vec = {kbd_pkg::SW'('h4), {8'hXX,8'h1B,8'h5B,8'h31,8'h7E}};
// or:		10'b1?_???_??_???,
//		10'b00_???_??_???: // Home '<esc>[7~'
//		    o_key_vec = {SW'('h4), {8'hXX,8'h1B,8'h5B,8'h37,8'h7E}};
		endcase
	    kbd_pkg::SC_KP_8:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 8
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h38}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // ↑    '<esc>[A'
		    o_key_vec = {kbd_pkg::SW'('h3), {8'hXX,8'hXX,8'h1B,8'h5B,8'h41}};
		endcase
	    kbd_pkg::SC_KP_9:
		casez (en_xyr_mg_acs)
		10'b01_???_??_???: // 9
		    o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h39}};
		10'b1?_???_??_???,
		10'b00_???_??_???: // PgUp '<esc>[5~'
		    o_key_vec = {kbd_pkg::SW'('h4), {8'hXX,8'h1B,8'h5B,8'h35,8'h7E}};
		endcase

	    // Special:
	    kbd_pkg::SC_SCRL:	// Ctrl+Pause/Break (ext0 only, no need to test)
		o_key_vec = {kbd_pkg::SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h03}};
//	    SC_NUML:	// Pause/Break (unmodified, with x=ctl3 active)
//		o_key_vec = {SW'('h0), {8'hXX,8'hXX,8'hXX,8'hXX,8'hXX}};
//	    SC_PRT:	// PrtScr/SysRq (with at least one Alt key enabled)
//		o_key_vec = {SW'('h0), {8'hXX,8'hXX,8'hXX,8'hXX,8'hXX}};

	    endcase // (i_key_sc)
	end // always_comb

endmodule: kbd_comb_layout

// sequential wrapper for keyboard layout
// NOTE: only forward valid (non-zero-length) output keycode vectors,
//       except when "compose" is signaled by the combinational module,
//       in which case we provide a zero length output keycode vector
//       along with activating o_key_valid.
module kbd_layout (
	// consume processed, context-enabled keypress events:
	input  logic [7:0] i_key_sc,
	input  kbd_pkg::key_ctx_t   i_key_ctx,
	input  logic       i_key_valid,
	output logic       i_key_ready,

	// produce {len, {byte, ..., byte}} keycode vectors:
	// NOTE: (len == 0 & o_key_valid) signals
	//       that a "compose" operation is being requested!
	output kbd_pkg::keycode_t o_key_vec,
	output logic     o_key_valid,
	input  logic     o_key_ready,

	input logic clk,
	input logic rst
);

	// accept input if either consumer is waiting (`o_*_ready`), or if we
	// don't already have an unconsumed data token on offer (`~o_*_valid`):
	assign i_key_ready = o_key_ready | ~o_key_valid;

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_key_valid & i_key_ready;
	assign o_handshake = o_key_valid & o_key_ready;

	// next values for (registered) output:
	kbd_pkg::keycode_t o_key_vecNext;
	logic     o_key_validNext;

	// intermediate `key_vec` and `compose` values,
	// (combinationally calculated):
	kbd_pkg::keycode_t key_vec;
	logic     compose;

	// combinationally retrieve `key_vec` and `compose` based on
	// input data:
	kbd_comb_layout inst_kbd_comb_layout(
		.i_key_sc(i_key_sc),
		.i_key_ctx(i_key_ctx),
		.o_key_vec(key_vec),
		.o_key_compose(compose)
	);

	// forwarding condition:
	logic i_o_forward;

	// combinational logic:
	always_comb begin
		// by default, keep registered values steady:
		o_key_vecNext   = o_key_vec;
		o_key_validNext = o_key_valid;

		// set forwarding condition: (compose | (key_vec.len > 0))
		i_o_forward = |{compose, key_vec.len};

		// selective forwarding:
		if (i_handshake & i_o_forward) begin
			o_key_vecNext   = key_vec;
			o_key_validNext = 1;
		end else if (o_handshake) begin
			o_key_validNext = 0;
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			o_key_vec   <= 0;
			o_key_valid <= 0;
		end else begin
			o_key_vec   <= o_key_vecNext;
			o_key_valid <= o_key_validNext;
		end
	end

endmodule: kbd_layout

// Pass through combinationally generated keycodes;
// NOTE: when `i_key_valid` is asserted but `i_key_vec` contains a 0-length
//       payload, we interpret that as a signal to start a keycode
//       "compose" sequence, whereby we collect the appropriate number
//       of ASCII hex digits from subsequent keypresses, and deliver
//       the resulting keycode if successful;
module kbd_compose (
	// consume context-enabled scancodes filtered through comb_layout:
	input  kbd_pkg::keycode_t i_key_vec,
	input  logic     i_key_valid,
	output logic     i_key_ready,

	// produce keycodes either (1) pass-through comb_layout,
	// or (2) collected by "compose" FSM:
	output kbd_pkg::keycode_t o_key_vec,
	output logic     o_key_valid,
	input  logic     o_key_ready,

	input logic clk,
	input logic rst
);

	// accept input if either consumer is waiting (`o_*_ready`), or if we
	// don't already have an unconsumed data token on offer (`~o_*_valid`):
	assign i_key_ready = o_key_ready | ~o_key_valid;

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = i_key_valid & i_key_ready;
	assign o_handshake = o_key_valid & o_key_ready;

	// input vector LSB:
	logic [7:0] i_lb;
	assign i_lb = i_key_vec.key[7:0];

	// ASCII hex char -> 4-bit nibble:
	// [0..9]
	// 0: 0011_0000 (0x30)
	// 9: 0011_1001 (0x39)
	// nibble = i_lb[3:0];
	//
	// [Aa..Ff]
	// A: 0100_0001 (0x41)
	// a: 0110_0001 (0x61)
	// F: 0100_0110 (0x46)
	// f: 0110_0110 (0x66)
	// nibble = i_lb[3:0] + '4b1001;

	// test if input vector LSB is hex digit:
	logic is_09, is_AF, is_Hex;
	assign is_09 = ((i_lb[7:4] == 4'h3) &
			(i_lb[3:0] < 4'hA));
/* this is more elegant, but lacks widespread compiler support:
	assign is_AF = ((i_lb[7:4] ==? 4'b01?0) &
			(i_lb[3:0] inside {[4'h1:4'h6]}));
*/
	assign is_AF = ((i_lb[7:6] == 2'b01) & (~i_lb[4]) &
			(|i_lb[3:0]) & (i_lb[3:0] < 4'h7));
	// LSB is a valid hex digit only if input is ASCII (single byte):
	assign is_Hex = ((is_09 | is_AF) & (i_key_vec.len == 1));

	// input hex nibble (only valid when `is_Hex`):
	logic [3:0] nib;
	assign nib = (i_lb[6]) ? (i_lb[3:0] + 4'h9) : i_lb[3:0];

	// input, output vector non-zero length conditions:
	logic i_len_nz, o_len_nz;
	assign i_len_nz = |(i_key_vec.len);
	assign o_len_nz = |(o_key_vec.len);

	// next values for sequential output registers:
	kbd_pkg::keycode_t o_key_vecNext;
	logic     o_key_validNext;

	// forwarding condition:
	logic i_o_forward;

	// FSM states:
	enum logic [1:0] {KeyFw, HiNib, LoNib} state, stateNext;

	// combinational logic:
	always_comb begin
	    // by default, keep registered values steady:
	    o_key_vecNext   = o_key_vec;
	    o_key_validNext = o_key_valid;
	    stateNext       = state;

	    // forwarding is off by default, unless explicitly
	    // enabled during FSM computation below:
	    i_o_forward = 0;

	    // advance FSM on input handshake:
	    if (i_handshake) begin
		// most often return to `KeyFw`, unless otherwise specified:
		stateNext = KeyFw;

		unique case (state)
		KeyFw: begin
		    if (i_len_nz) begin // i_key_vec.len > 0
			// forward keycode from input (typical case):
			i_o_forward   = 1;
			o_key_vecNext = i_key_vec;
		    end else begin
			// valid input w. 0 bytes means compose request:
			// NOTE: `o_key_vec` used as compose buffer!
			o_key_vecNext.len = 0;
			stateNext         = HiNib;
		    end
		end
		HiNib: begin
		    if (is_Hex) begin
			// capture hex digit (nibble) from input keycode:
			o_key_vecNext.key = {o_key_vec.key[kbd_pkg::KW-5:0], nib};
			stateNext         = LoNib;
		    end else if (o_len_nz) begin // o_key_vec.len > 0
			// we have an accumulated set of whole bytes, send it:
			i_o_forward = 1;
		    end else if (i_len_nz) begin // i_key_vec.len > 0
			// we have an otherwise valid input keycode, send it:
			i_o_forward   = 1;
			o_key_vecNext = i_key_vec;
		    end
		end
		LoNib: begin
		    if (is_Hex) begin
			// capture hex digit (nibble) from input keycode:
			o_key_vecNext.key = {o_key_vec.key[kbd_pkg::KW-5:0], nib};
			// increment accumulated compose byte count:
			o_key_vecNext.len = o_key_vec.len + 1;
			if (o_key_vec.len == kbd_pkg::SW'(kbd_pkg::BW - 1)) begin
			    // we've maxed out the compose buffer, send it:
			    i_o_forward = 1;
			end else begin
			    // compose buffer not yet full, get more nibbles:
			    stateNext = HiNib;
			end
		    end else if (i_len_nz) begin // i_key_vec.len > 0
			// abandoning incomplete compose buffer;
			// if the input is otherwise valid, send it:
			i_o_forward   = 1;
			o_key_vecNext = i_key_vec;
		    end
		end
		endcase // (state)
	    end // if (i_handshake)

	    // selectively forward input source selected by FSM:
	    if (i_handshake & i_o_forward) begin
		// NOTE: o_key_vecNext calculated by the FSM logic
		o_key_validNext = 1;
	    end else if (o_handshake) begin
		// output handshake, but no forwarding-eligible data:
		o_key_validNext = 0;
	    end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
	    if (rst) begin
		o_key_vec   <= 0;
		o_key_valid <= 0;
		state       <= KeyFw;
	    end else begin
		o_key_vec   <= o_key_vecNext;
		o_key_valid <= o_key_validNext;
		state       <= stateNext;
	    end
	end

endmodule: kbd_compose

module kbd_layout_to_ascii (
	// consume ascii byte sequences produced by the layout module:
	input  kbd_pkg::keycode_t key_vec,
	input  logic     key_valid,
	output logic     key_ready,

	// produce ascii bytes to print out (e.g., via uart_tx):
	output logic [7:0] out_char,
	output logic       out_valid,
	input  logic       out_ready,

	input logic clk,
	input logic rst
);

	logic [7:0] ob0, ob1, ob2, ob3, ob4;
	assign ob4 = key_vec.key[39:32];
	assign ob3 = key_vec.key[31:24];
	assign ob2 = key_vec.key[23:16];
	assign ob1 = key_vec.key[15: 8];
	assign ob0 = key_vec.key[ 7: 0];

	// "x  xx xx xx xx xx\n\r" - 19 total characters
	localparam BUFSIZE = 19;
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
				// start with count:
				ascii['d18] = 8'h20;
				ascii['d17] = {5'h0, key_vec.len} + 8'h30;
				ascii['d16] = 8'h20;
				// add upper and lower nibbles for 4:0 bytes:
				ascii['d15] = {4'h0, ob4[7:4]} + 8'h30 +
					((ob4[7:4] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d14] = {4'h0, ob4[3:0]} + 8'h30 +
					((ob4[3:0] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d13] = 8'h20;
				ascii['d12] = {4'h0, ob3[7:4]} + 8'h30 +
					((ob3[7:4] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d11] = {4'h0, ob3[3:0]} + 8'h30 +
					((ob3[3:0] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d10] = 8'h20;
				ascii['d09] = {4'h0, ob2[7:4]} + 8'h30 +
					((ob2[7:4] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d08] = {4'h0, ob2[3:0]} + 8'h30 +
					((ob2[3:0] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d07] = 8'h20;
				ascii['d06] = {4'h0, ob1[7:4]} + 8'h30 +
					((ob1[7:4] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d05] = {4'h0, ob1[3:0]} + 8'h30 +
					((ob1[3:0] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d04] = 8'h20;
				ascii['d03] = {4'h0, ob0[7:4]} + 8'h30 +
					((ob0[7:4] > 4'h9) ? 8'h07 : 8'h0);
				ascii['d02] = {4'h0, ob0[3:0]} + 8'h30 +
					((ob0[3:0] > 4'h9) ? 8'h07 : 8'h0);
				// add <cr> and <lf>:
				ascii['d01] = 8'h0D;
				ascii['d00] = 8'h0A;
				// set counter and move to `Send`:
				idxNext   = 'd20;
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

endmodule: kbd_layout_to_ascii

// convert raw keyboard scancodes to ascii repr. of context-enabled key codes
// NOTE: "hide" key_ctx_t type from outside test harness
module kbd_layout_wrapper (
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
	kbd_pkg::key_ctx_t   key_cx;
	logic key_valid, key_ready;

	// convert raw keyboard scan codes into chords + context
	kbd_context inst_kbd_context (
		.i_raw_sc(i_raw_sc),
		.i_raw_valid(i_raw_valid),
		.i_raw_ready(i_raw_ready),
		.o_key_sc(key_sc),
		.o_key_ctx(key_cx),
		.o_key_valid(key_valid),
		.o_key_ready(key_ready),
		.clk(clk),
		.rst(rst)
	);

	kbd_pkg::keycode_t kcode_vec;
	logic kcode_valid, kcode_ready;

	// layout module (zero-length kcode_vec output means "compose"):
	kbd_layout inst_kbd_layout (
		.i_key_sc(key_sc),
		.i_key_ctx(key_cx),
		.i_key_valid(key_valid),
		.i_key_ready(key_ready),
		.o_key_vec(kcode_vec),
		.o_key_valid(kcode_valid),
		.o_key_ready(kcode_ready),
		.clk(clk),
		.rst(rst)
	);

	kbd_pkg::keycode_t kout_vec;
	logic kout_valid, kout_ready;

	// compose module (intercept, act on compose "signal"):
	kbd_compose inst_kbd_compose (
		.i_key_vec(kcode_vec),
		.i_key_valid(kcode_valid),
		.i_key_ready(kcode_ready),
		.o_key_vec(kout_vec),
		.o_key_valid(kout_valid),
		.o_key_ready(kout_ready),
		.clk(clk),
		.rst(rst)
	);

	// convert chords+context into ascii bytes to display:
	kbd_layout_to_ascii inst_kbd_layout_to_ascii(
		.key_vec(kout_vec),
		.key_valid(kout_valid),
		.key_ready(kout_ready),
		.out_char(out_char),
		.out_valid(out_valid),
		.out_ready(out_ready),
		.clk(clk),
		.rst(rst)
	);

endmodule: kbd_layout_wrapper

`ifdef TB_KBLAY
// // iverilog -g2005-sv -DTB_KBLAY -stb_layout -o tb_layout kbd_layout.sv
// // verilator --binary -DTB_KBLAY --top tb_layout kbd_layout.sv
module tb_layout ();

	logic clk;
	logic [7:0] sc;
	kbd_pkg::key_ctx_t ct;
	kbd_pkg::keycode_t vc;
	logic cp;

	kbd_comb_layout inst_kbd_comb_layout (
		.i_key_sc(sc),
		.i_key_ctx(ct),
		.o_key_vec(vc),
		.o_key_compose(cp)
	);

	always #5 clk <= ~clk;

	initial begin
		clk = 0;
		$display("kbd_pkg::BW=%d kbd_pkg::KW=%d kbd_pkg::SW=%d", kbd_pkg::BW, kbd_pkg::KW, kbd_pkg::SW);
		repeat (128) begin
			@(posedge clk);
			$display("sc=%h ct=%h  vc=%h cp=%b", sc, ct, vc, cp);
`ifdef VERILATOR
			sc = $random[7:0];
			ct = $random[13:0];
`else
			sc = $random;
			ct = $random;
`endif
		end
		$finish;
	end

endmodule: tb_layout
`endif //  TB_KBLAY

`ifdef TB_ASC2NIB
module asc2nib (
	input  logic [7:0] a,
	output logic [3:0] n,
	output logic       h
);

	logic is_09, is_AF;
	assign is_09 = ((a[7:4] == 4'h3) &
			(a[3:0] < 4'hA));
	assign is_AF = ((a[7:4] ==? 4'b01?0) &
			(|a[3:0]) & // >= 1
			(a[3:0] < 4'h7));

	assign n = (a[6]) ? (a[3:0] + 4'h9) : a[3:0];
	assign h = (is_09 | is_AF);
endmodule: asc2nib

// // iverilog -g2005-sv -DTB_ASC2NIB -stb_nibble -o tb_nibble kbd_layout.sv
module tb_nibble ();

	logic clk;
	logic [7:0] a;
	logic [3:0] n;
	logic       h;

	asc2nib inst_asc2nib (
		.a(a),
		.n(n),
		.h(h)
	);

	always #5 clk <= ~clk;

	initial begin
		clk = 0;
		repeat (128) begin
			@(posedge clk);
			$display("a='%c'(%h)  --  n=%h h=%b",
				(((a > 8'h20) && (a < 8'h7F)) ? a : 8'h2E),
				a, n, h);
			a = $random;
		end
		$finish;
	end

endmodule: tb_nibble
`endif // TB_ASC2NIB
