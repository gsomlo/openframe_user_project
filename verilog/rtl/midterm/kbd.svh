// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`ifndef KBD_SVH
`define KBD_SVH

`default_nettype none

// NOTE: place everything inside a package: Yosys 0.46 (LibreLane 2.4.x)
// mis-handles typedef'd structs and computed localparams declared at
// file ($unit) scope. Reference these as kbd_pkg::NAME as wildcard `import`
// is not supported either.
package kbd_pkg;

// scan codes for standard 104-key US keyboard:
localparam
	// Escape and Function keys:
	SC_ESC    = 8'h76, // Escape
	SC_F1     = 8'h05,
	SC_F2     = 8'h06,
	SC_F3     = 8'h04,
	SC_F4     = 8'h0C,
	SC_F5     = 8'h03,
	SC_F6     = 8'h0B,
	SC_F7     = 8'h83,
	SC_F8     = 8'h0A,
	SC_F9     = 8'h01,
	SC_F10    = 8'h09,
	SC_F11    = 8'h78,
	SC_F12    = 8'h07,

	// Row 1:
	SC_BKT    = 8'h0E, // back-tick/tilde (`/~)
	SC_1      = 8'h16,
	SC_2      = 8'h1E,
	SC_3      = 8'h26,
	SC_4      = 8'h25,
	SC_5      = 8'h2E,
	SC_6      = 8'h36,
	SC_7      = 8'h3D,
	SC_8      = 8'h3E,
	SC_9      = 8'h46,
	SC_0      = 8'h45,
	SC_SUB    = 8'h4E,
	SC_EQL    = 8'h55,
	SC_BSP    = 8'h66, // back-space

	// Row 2:
	SC_TAB    = 8'h0D,
	SC_Q      = 8'h15,
	SC_W      = 8'h1D,
	SC_E      = 8'h24,
	SC_R      = 8'h2D,
	SC_T      = 8'h2C,
	SC_Y      = 8'h35,
	SC_U      = 8'h3C,
	SC_I      = 8'h43,
	SC_O      = 8'h44,
	SC_P      = 8'h4D,
	SC_SQL    = 8'h54, // left brackets ([/{)
	SC_SQR    = 8'h5B, // right brackets (]/})
	SC_BSL    = 8'h5D, // back-slash/pipe (\/|)

	// Row 3:
	SC_CAPS   = 8'h58, // CapsLock (modifier, no event)
	SC_A      = 8'h1C,
	SC_S      = 8'h1B,
	SC_D      = 8'h23,
	SC_F      = 8'h2B,
	SC_G      = 8'h34,
	SC_H      = 8'h33,
	SC_J      = 8'h3B,
	SC_K      = 8'h42,
	SC_L      = 8'h4B,
	SC_SEM    = 8'h4C, // semicolon/colon (;/:)
	SC_TCK    = 8'h52, // forward-tick/double-quote ('/")
	SC_ENT    = 8'h5A, // Enter
			   // ext0: NumPad Enter

	// Row 4:
	SC_SHFL   = 8'h12, // LeftShift (modifier, no event)
	SC_Z      = 8'h1A,
	SC_X      = 8'h22,
	SC_C      = 8'h21,
	SC_V      = 8'h2A,
	SC_B      = 8'h32,
	SC_N      = 8'h31,
	SC_M      = 8'h3A,
	SC_COM    = 8'h41, // comma/less-than (,/<)
	SC_PER    = 8'h49, // period/greater-than (./>)
	SC_FSL    = 8'h4A, // forward-slash/question (//?)
			   // ext0: NumPad forward-slash
	SC_SHFR   = 8'h59, // RightShift (modifier, no event)

	// Row 5:
	SC_CTL    = 8'h14, // LeftCtrl (modifier, no event)
			   // ext0: RightCtrl (modifier, no event)
	SC_METL   = 8'h1F, // ext0: LeftMeta (modifier, no event)
	SC_ALT    = 8'h11, // LeftAlt (modifier, no event)
			   // ext0: RightAlt (modifier, no event)
	SC_SPC    = 8'h29, // space-bar
	SC_METR   = 8'h27, // ext0: RightMeta (modifier, no event)
	SC_MEN    = 8'h2F, // Menu (ext0)

	// NumPad:
	SC_NUML   = 8'h77, // NumLck (modifier, no event)
			   // Pause/Break (with ctl3)
	SC_KP_MUL = 8'h7C, // ext0: PrtScr (with shf3)
	SC_KP_SUB = 8'h7B,
	SC_KP_7   = 8'h6C, // ext0: Home
	SC_KP_8   = 8'h75, // ext0: ↑
	SC_KP_9   = 8'h7D, // ext0: PgUp
	SC_KP_ADD = 8'h79,
	SC_KP_4   = 8'h6B, // ext0: ←
	SC_KP_5   = 8'h73,
	SC_KP_6   = 8'h74, // ext0: →
	SC_KP_1   = 8'h69, // ext0: End
	SC_KP_2   = 8'h72, // ext0: ↓
	SC_KP_3   = 8'h7A, // ext0: PgDn
	SC_KP_0   = 8'h70, // ext0: Ins
	SC_KP_PER = 8'h71, // ext0: Del

	// Special:
	SC_PRT    = 8'h84, // PrtScr (with alt key pressed)
	SC_SCRL   = 8'h7E, // ScrLck (modifier, no event)
			   // ext0: Pause/Break (with ctrl key pressed)

	// State/Management:
	SC_EXT0   = 8'hE0, // ext0 mode
	SC_EXT1   = 8'hE1, // ext1 mode (Pause/Break ctl3 only)
	SC_BRK    = 8'hF0; // key release (a.k.a. "break") action

// keyboard context during an "actionable" keypress or chord:
// - produced by kbd_context
// - consumed by kbd_layout
typedef struct packed {
//	logic ext1; // ext1 mode keypress (NOTE: these never happen!)
	logic ext0; // ext0 mode keypress
	logic caps; // caps-lock is on
	logic numl; // num-lock is on
	logic scrl; // scroll-lock is on
	logic metl; // left meta key down
	logic metr; // right meta key down
	logic altl; // left alt key down
	logic altr; // right alt key down
	logic ctll; // left ctl key down
	logic ctlr; // right ctl key down
	logic ctl3; // ext1-mode "ctl" (only during Pause keypress)
	logic shfl; // left shift key down
	logic shfr; // right shift key down
	logic shf3; // ext0-mode "left shift" (only during PrSc keypress)
} key_ctx_t;

// byte vector properties for multi-byte sequences
// - produced by kbd_layout
// - consumed by kbd_compose
// E.g.: assign vec = {SW'('h1), {8'hXX,8'hXX,8'hXX,8'hXX,8'h41}}; // 'A'
localparam
	BW = 5,		// buffer content width, in bytes
	KW = (BW * 8),	// buffer content width, in bits
	SW = $clog2(BW);// size field width, in bits (size represents bytes)

typedef struct packed {
	logic [SW-1:0] len;
	logic [KW-1:0] key;
} keycode_t;

endpackage: kbd_pkg

`endif // KBD_SVH
