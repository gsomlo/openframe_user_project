// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`ifndef VIDEO_SVH
`define VIDEO_SVH

`default_nettype none

// NOTE: place everything inside a package: Yosys 0.46 (LibreLane 2.4.x)
// mis-handles typedef'd structs and computed localparams declared at
// file ($unit) scope. Reference these as kbd_pkg::NAME as wildcard `import`
// is not supported either.
package video_pkg;

localparam
	// depth of the render pipeline (measured after impl. complete)
	// NOTE: see `terminal.sv:uart_to_vga` for full pipeline
	// NOTE: see `scr_draw.sv` for pipeline building blocks
	RNDR_PIPE_DEPTH = 8,

	// 640x480p60 (DMT0659) VGA timing parameters:
	// Modeline "640x480_60" 25.175 640 656 752 800 480 490 492 525 -HSync -VSync
	// NOTE1: VESA specifies a 25.175MHz pixel clock with 0.5% tolerance;
	//        *Technically*, a 25.000MHz pixel clock is out of spec,
	//        though widely reported to work just fine in practice!
	// NOTE2: horizontal & vertical (below) are used in the context of
	//        *landscape* display mode
	// horizontal (width), expressed in 1-pixel units:
	VGA_HTOTAL = 800, // total horz. line width
	VGA_HBPW   =  48, // horz. back porch
	VGA_HVPW   = 640, // horz. visible pixels
	VGA_HFPW   =  16, // horz. front porch
	VGA_HSW    =  96, // horz. sync (neg. polarity)
	// vertical (height), expressed in 1-hline units:
	VGA_VTOTAL = 525, // total vert. "line" count
	VGA_VBPW   =  33, // vert. back porch
	VGA_VVLW   = 480, // vert. visible lines
	VGA_VFPW   =  10, // vert. front porch
	VGA_VSW    =   2, // vert. sync (neg. polarity)
	// horizontal & vertical counter width values:
	VGA_HCW    = $clog2(VGA_HTOTAL),
	VGA_VCW    = $clog2(VGA_VTOTAL),

	// screen size (portrait mode, in characters):
	SCR_COLS   =  80, // columns
	SCR_ROWS   =  53, // rows
	// counter width values:
	SCR_CCW    = $clog2(SCR_COLS),
	SCR_RCW    = $clog2(SCR_ROWS),

	// character matrix (fixed-font) size (in pixels):
	CHR_WIDE   =   6, // width
	CHR_HIGH   =  12, // height
	// counter width values:
	CHR_WCW    = $clog2(CHR_WIDE),
	CHR_HCW    = $clog2(CHR_HIGH),

	// glyph ROM address and data width:
	GLP_AW     = $clog2(4043), // number of symbols in ./chargen/6x12.bdf
	GLP_DW     = CHR_WIDE * CHR_HIGH; // number of bits per glyph/symbol

typedef struct packed {
	logic [7:0] r, g, b;
} vga_rgb_t;

typedef struct packed {
	logic [SCR_CCW-1:0] x; // col
	logic [SCR_RCW-1:0] y; // row
} scr_pos_t;

// flags field type for screen-buffer glyph box:
typedef struct packed {
	logic blink;
	logic under;
	logic reserved;
} glyph_flag_t;

// screen-buffer glyph box type:
typedef struct packed {
	glyph_flag_t flg; // flags: blink, underline, etc.
	logic [20:0] utf; // utf character code
	logic  [7:0] fgc; // foreground color
	logic  [7:0] bgc; // background color
} glyph_box_t;

localparam
	// address width of the screen buffer SRAM:
	// NOTE: - circular screen buffer, no storage outside visible viewport:
	//       - increase beyond this limit if adding scroll/history support!
	SCR_BUF_AW = $clog2(SCR_ROWS * SCR_COLS),
	// data width of the screen buffer SRAM:
	// NOTE: this is an "alias" for the `$bits(glyph_box_t)`, but allows
	//       for a more concise specification of RAM interface wires!
	// SCR_BUF_DW = $bits(glyph_box_t);
	// NOTE: yosys 0.46 can't handle `$bits(<type>)`
	SCR_BUF_DW = 40;

// pass-through attributes:
typedef struct packed {
	logic        border; // border override bit
	logic        cursor; // glyphbox has cursor
	glyph_flag_t flg; // flags: blink, underline, etc.
	logic  [7:0] fgc; // foreground color
	logic  [7:0] bgc; // background color
} pass_attr_t;

// blink (and visual bell) signal bundle:
typedef struct packed {
	logic cursor; // cursor blink bit
	logic attrib; // attrib blink bit
	logic v_bell; // visual bell bit
} blink_sig_t;

endpackage: video_pkg

`endif // VIDEO_SVH
