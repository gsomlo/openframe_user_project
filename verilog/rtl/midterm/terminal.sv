// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`include "kbd.svh"
`include "video.svh"

module ps2_to_uart #(
	parameter CLK_FREQ = 25000000  //  25MHz
) (
	// ps/2 keyboard pins:
	input  logic ps2_clk,
	input  logic ps2_dat,
	// uart tx valid/ready pins:
	output logic [7:0] uart_tx_data,
	output logic       uart_tx_valid,
	input  logic       uart_tx_ready,
	// control:
	input logic clk,
	input logic rst
);

	// raw scancode stream from pyhsical keyboard:
	logic [7:0] raw_sc;
	logic raw_valid, raw_ready;
	ps2rx #(
		.CLK_FREQ(CLK_FREQ)
	) inst_ps2rx (
		.ps2clk(ps2_clk),
		.ps2dat(ps2_dat),
		.data_out(raw_sc),
		.data_out_valid(raw_valid),
		.data_out_ready(raw_ready),
		.clk(clk),
		.rst(rst)
	);

	// convert raw scancodes into context-augmented "chords":
	logic [7:0] key_sc;
	kbd_pkg::key_ctx_t   key_ctx;
	logic key_valid, key_ready;
	kbd_context inst_kbd_context (
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

	// parse "chords" and context into keycode vectors
	// (NOTE: zero-length kc_vec means "compose"):
	kbd_pkg::keycode_t kc_vec;
	logic kc_valid, kc_ready;
	kbd_layout inst_kbd_layout (
		.i_key_sc(key_sc),
		.i_key_ctx(key_ctx),
		.i_key_valid(key_valid),
		.i_key_ready(key_ready),
		.o_key_vec(kc_vec),
		.o_key_valid(kc_valid),
		.o_key_ready(kc_ready),
		.clk(clk),
		.rst(rst)
	);

	// compose: when zero_length kc_vec, collect ko_vec as hex from kbd:
	kbd_pkg::keycode_t ko_vec;
	logic ko_valid, ko_ready;
	kbd_compose inst_kbd_compose (
		.i_key_vec(kc_vec),
		.i_key_valid(kc_valid),
		.i_key_ready(kc_ready),
		.o_key_vec(ko_vec),
		.o_key_valid(ko_valid),
		.o_key_ready(ko_ready),
		.clk(clk),
		.rst(rst)
	);

	// serialize (layout or composed) keycode into bytes for uart-tx:
	keycode_to_char inst_keycode_to_char (
		.key_vec(ko_vec),
		.key_valid(ko_valid),
		.key_ready(ko_ready),
		.out_char(uart_tx_data),
		.out_valid(uart_tx_valid),
		.out_ready(uart_tx_ready),
		.clk(clk),
		.rst(rst)
	);

endmodule: ps2_to_uart

module uart_to_vga (
	// uart rx valid/ready pins:
	input  logic [7:0] uart_rx_data,
	input  logic       uart_rx_valid,
	output logic       uart_rx_ready,
	// vga digital output:
	output logic       vga_hsync_n,
	output logic       vga_vsync_n,
	output logic       vga_blank_n,
	output logic [7:0] vga_pxl_r,
	output logic [7:0] vga_pxl_g,
	output logic [7:0] vga_pxl_b,
	// ROM interface:
	output logic [video_pkg::GLP_AW-1:0] rom_addr,
	input  logic [video_pkg::GLP_DW-1:0] rom_data,
	// RAM interface:
	output logic [video_pkg::SCR_BUF_AW-1:0] ram_addr,
	output logic                  ram_wren,
	output logic [video_pkg::SCR_BUF_DW-1:0] ram_wdata,
	input  logic [video_pkg::SCR_BUF_DW-1:0] ram_rdata,

	// control:
	input logic clk,
	input logic rst
);

	// buffer incoming uart-rx data into a FIFO:
	logic [7:0] vt_data;
	logic vt_valid, vt_ready;
	valid_ready_sync_fifo #(
		.DW(8),
		.PW(9) // 2^9 = 512 byte SRAM
	) inst_valid_ready_sync_fifo (
		.i_data(uart_rx_data),
		.i_valid(uart_rx_valid),
		.i_ready(uart_rx_ready),
		.o_data(vt_data),
		.o_valid(vt_valid),
		.o_ready(vt_ready),
		.clk(clk),
		.rst(rst)
	);

	// vt52 parser, produces write data for `scr_display_buf`, mutually
	// exclusive w.r.t. the render pipeline:
	logic [video_pkg::SCR_BUF_AW-1:0] gl_adr;
	video_pkg::glyph_box_t            gl_box;
	logic gl_valid, gl_ready;
	// also publishes bell trigger, viewport & cursor address:
	logic bell;
	logic [video_pkg::SCR_BUF_AW-1:0] vp_base, crs_adr;
	vt52_parser inst_vt52_parser (
		.i_data(vt_data),
		.i_valid(vt_valid),
		.i_ready(vt_ready),
		.o_glyphadr(gl_adr),
		.o_glyphbox(gl_box),
		.o_valid(gl_valid),
		.o_ready(gl_ready),
		.bell(bell),
		.vp_base(vp_base),
		.crs_adr(crs_adr),
		.clk(clk),
		.rst(rst)
	);

	// frame render pipeline starts by sweeping the screen "raster":
	logic frm_rndr_start; // from `vga_phy`, req. to start render pipeline
	video_pkg::blink_sig_t         s_blink;
	video_pkg::scr_pos_t           s_pos;
	logic [video_pkg::CHR_WCW-1:0] s_col;
	logic s_border, s_done, s_valid, s_ready;
	scr_sweep_raster inst_scr_sweep_raster (
		.frm_rndr_start(frm_rndr_start),
		.bell(bell),
		.blink(s_blink),
		.pos(s_pos),
		.col(s_col),
		.border(s_border),
		.done(s_done),
		.valid(s_valid),
		.ready(s_ready),
		.clk(clk),
		.rst(rst)
	);

	// raster sweep position -> display buffer address (rel. to viewport):
	logic [video_pkg::SCR_BUF_AW-1:0] a_addr;
	logic    [video_pkg::CHR_WCW-1:0] a_col;
	logic a_border, a_done, a_valid, a_ready;
	scr_pos_to_addr inst_scr_pos_to_addr (
		.vp_base(vp_base),
		.i_pos(s_pos),
		.i_col(s_col),
		.i_border(s_border),
		.i_done(s_done),
		.i_valid(s_valid),
		.i_ready(s_ready),
		.o_addr(a_addr),
		.o_col(a_col),
		.o_border(a_border),
		.o_done(a_done),
		.o_valid(a_valid),
		.o_ready(a_ready),
		.clk(clk),
		.rst(rst)
	);

	// screen buffer: in render mode, convert disp. buf addr to glyph box:
	video_pkg::glyph_box_t         d_glyphbox;
	logic [video_pkg::CHR_WCW-1:0] d_col;
	logic d_border, d_cursor, d_valid, d_ready;
	scr_display_buf inst_scr_display_buf (
		.crs_adr(crs_adr),
		.start(frm_rndr_start),
		.w_addr(gl_adr),
		.w_glyphbox(gl_box),
		.w_valid(gl_valid),
		.w_ready(gl_ready),
		.i_addr(a_addr),
		.i_col(a_col),
		.i_border(a_border),
		.i_done(a_done),
		.i_valid(a_valid),
		.i_ready(a_ready),
		.o_glyphbox(d_glyphbox),
		.o_col(d_col),
		.o_border(d_border),
		.o_cursor(d_cursor),
		.o_valid(d_valid),
		.o_ready(d_ready),
		.ram_addr(ram_addr),
		.ram_wren(ram_wren),
		.ram_wdata(ram_wdata),
		.ram_rdata(ram_rdata),
		.clk(clk),
		.rst(rst)
	);

	// glyph box utf field -> fontROM address (pass-thru other attributes):
	logic  [video_pkg::GLP_AW-1:0] u_addr;
	logic [video_pkg::CHR_WCW-1:0] u_col;
	video_pkg::pass_attr_t         u_attr;
	logic u_valid, u_ready;
	utf_enc_to_addr inst_utf_enc_to_addr (
		.i_glyphbox(d_glyphbox),
		.i_col(d_col),
		.i_border(d_border),
		.i_cursor(d_cursor),
		.i_valid(d_valid),
		.i_ready(d_ready),
		.o_addr(u_addr),
		.o_col(u_col),
		.o_attr(u_attr),
		.o_valid(u_valid),
		.o_ready(u_ready),
		.clk(clk),
		.rst(rst)
	);

	// lookup font data given address & column (pass-thru other attributes):
	logic [video_pkg::CHR_HIGH-1:0] g_col_bits;
	video_pkg::pass_attr_t          g_attr;
	logic g_valid, g_ready;
	glyph_font_lookup inst_glyph_font_lookup (
		.i_addr(u_addr),
		.i_col(u_col),
		.i_attr(u_attr),
		.i_valid(u_valid),
		.i_ready(u_ready),
		.o_col_bits(g_col_bits),
		.o_attr(g_attr),
		.o_valid(g_valid),
		.o_ready(g_ready),
		.rom_addr(rom_addr),
		.rom_data(rom_data),
		.clk(clk),
		.rst(rst)
	);

	// serialize a pixel column into a stream of vga pixels:
	video_pkg::vga_rgb_t pxl_data;
	logic pxl_valid, pxl_ready;
	pxl_col_serialize inst_pxl_col_serialize (
		.blink(s_blink),
		.chr_col_bits(g_col_bits),
		.chr_attr(g_attr),
		.chr_col_valid(g_valid),
		.chr_col_ready(g_ready),
		.pxl_data(pxl_data),
		.pxl_valid(pxl_valid),
		.pxl_ready(pxl_ready),
		.clk(clk),
		.rst(rst)
	);

	// vga phy:
	vga_phy inst_vga_phy (
		.pxl_data(pxl_data),
		.pxl_valid(pxl_valid),
		.pxl_ready(pxl_ready),
		.frm_rndr_start(frm_rndr_start),
		.hsync_n(vga_hsync_n),
		.vsync_n(vga_vsync_n),
		.blank_n(vga_blank_n),
		.pxl_r(vga_pxl_r),
		.pxl_g(vga_pxl_g),
		.pxl_b(vga_pxl_b),
		.clk(clk),
		.rst(rst)
	);

endmodule: uart_to_vga

module terminal_top #(
	parameter CLK_FREQ = 25000000, //  25MHz
	parameter BAUDRATE =   115200
) (
	// uart pins:
	input  logic uart_rxd,
	output logic uart_txd,
	input  logic uart_rts,
	output logic uart_cts,
	// ps/2 keyboard pins:
	input  logic ps2_clk,
	input  logic ps2_dat,
	// VGA digital output pins:
	output logic       vga_hsync_n,
	output logic       vga_vsync_n,
	output logic       vga_blank_n,
	output logic [7:0] vga_pxl_r,
	output logic [7:0] vga_pxl_g,
	output logic [7:0] vga_pxl_b,
	// ROM interface
	output logic [video_pkg::GLP_AW-1:0] rom_addr,
	input  logic [video_pkg::GLP_DW-1:0] rom_data,
	// RAM interface:
	output logic [video_pkg::SCR_BUF_AW-1:0] ram_addr,
	output logic                  ram_wren,
	output logic [video_pkg::SCR_BUF_DW-1:0] ram_wdata,
	input  logic [video_pkg::SCR_BUF_DW-1:0] ram_rdata,
	// control:
	input logic clk,
	input logic rst
);

	// uart and internal ready/valid tx & rx streams:
	logic [7:0] uart_tx_data, uart_rx_data;
	logic uart_tx_valid, uart_tx_ready, uart_rx_valid, uart_rx_ready;
	uart #(
		.CLK_FREQ(CLK_FREQ),
		.BAUDRATE(BAUDRATE)
	) inst_uart (
		.rxd(uart_rxd),
		.txd(uart_txd),
		.rts(uart_rts),
		.cts(uart_cts),
		.data_in(uart_tx_data),
		.data_in_valid(uart_tx_valid),
		.data_in_ready(uart_tx_ready),
		.data_out(uart_rx_data),
		.data_out_valid(uart_rx_valid),
		.data_out_ready(uart_rx_ready),
		.clk(clk),
		.rst(rst)
	);

	// connect ps/2 to uart-tx stream:
	ps2_to_uart #(
		.CLK_FREQ(CLK_FREQ)
	) inst_ps2_to_uart (
		.ps2_clk(ps2_clk),
		.ps2_dat(ps2_dat),
		.uart_tx_data(uart_tx_data),
		.uart_tx_valid(uart_tx_valid),
		.uart_tx_ready(uart_tx_ready),
		.clk(clk),
		.rst(rst)
	);

	// connect uart_rx stream to vga:
	uart_to_vga inst_uart_to_vga (
		.uart_rx_data(uart_rx_data),
		.uart_rx_valid(uart_rx_valid),
		.uart_rx_ready(uart_rx_ready),
		.vga_hsync_n(vga_hsync_n),
		.vga_vsync_n(vga_vsync_n),
		.vga_blank_n(vga_blank_n),
		.vga_pxl_r(vga_pxl_r),
		.vga_pxl_g(vga_pxl_g),
		.vga_pxl_b(vga_pxl_b),
		.rom_addr(rom_addr),
		.rom_data(rom_data),
		.ram_addr(ram_addr),
		.ram_wren(ram_wren),
		.ram_wdata(ram_wdata),
		.ram_rdata(ram_rdata),
		.clk(clk),
		.rst(rst)
	);

endmodule: terminal_top

`ifdef TBTOPTX
// // verilator --binary --trace -DTBTOPTX --top tb_toptx *.sv
module tb_toptx ();

	// parameters:
	localparam
		PS2_FREQ =    10000, // 10kHz
		BAUDRATE =   115200,
		CLK_FREQ = 25000000; // 25MHz

	// provide clk, rst:
	logic clk, rst;
	initial begin
		clk     = 1;
		rst     = 1;
		#22 rst = 0;
	end
	always #5 clk <= ~clk;

/*
	// record signal waveforms
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(3); // 3 submodule layers deep
	end
*/

	// DUT (and associated wires, dependencies):

	// uart pins:
	logic uart_rxd, uart_txd, uart_rts, uart_cts;
	// ps/2 keyboard pins:
	logic ps2_clk, ps2_dat;
	// VGA digital output pins:
	logic vga_hsync_n, vga_vsync_n, vga_blank_n;
	logic [7:0] vga_pxl_r, vga_pxl_g, vga_pxl_b;
	// ROM interface
	logic [video_pkg::GLP_AW-1:0] rom_addr;
	logic [video_pkg::GLP_DW-1:0] rom_data;
	// RAM interface:
	logic [video_pkg::SCR_BUF_AW-1:0] ram_addr;
	logic ram_wren;
	logic [video_pkg::SCR_BUF_DW-1:0] ram_wdata, ram_rdata;

	assign uart_rts = 1'b1; // assume host always ready

	// ROM instance external to top-level terminal module:
	sync_rom #(
		.FN("chargen/utfglphrom.hex"),
		.AW(video_pkg::GLP_AW),
		.DW(video_pkg::GLP_DW)
	) inst_sync_rom (
		.addr(rom_addr),
		.rdata(rom_data),
		.clk(clk)
	);

	// RAM instance external to top-level terminal module:
	sync_ram #(
		.AW(video_pkg::SCR_BUF_AW),
		.DW(video_pkg::SCR_BUF_DW)
	) inst_sync_ram (
		.addr(ram_addr),
		.wren(ram_wren),
		.wdata(ram_wdata),
		.rdata(ram_rdata),
		.clk(clk)
	);

	terminal_top #(
		.CLK_FREQ(CLK_FREQ),
		.BAUDRATE(BAUDRATE)
	) dut (
		// uart:
		.uart_rxd(uart_rxd),
		.uart_txd(uart_txd),
		.uart_rts(uart_rts),
		.uart_cts(uart_cts),
		// ps/2:
		.ps2_clk(ps2_clk),
		.ps2_dat(ps2_dat),
		// vga:
		.vga_hsync_n(vga_hsync_n),
		.vga_vsync_n(vga_vsync_n),
		.vga_blank_n(vga_blank_n),
		.vga_pxl_r(vga_pxl_r),
		.vga_pxl_g(vga_pxl_g),
		.vga_pxl_b(vga_pxl_b),
		// ROM interface:
		.rom_addr(rom_addr),
		.rom_data(rom_data),
		// RAM interface:
		.ram_addr(ram_addr),
		.ram_wren(ram_wren),
		.ram_wdata(ram_wdata),
		.ram_rdata(ram_rdata),
		// control:
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:

	localparam
		INIT_DELAY = 500,
		PS2_NUM_BITS = 11,
		PS2_BIT_WIDTH = CLK_FREQ / PS2_FREQ,
		UART_NUM_BITS = 10,
		UART_BIT_WIDTH = CLK_FREQ / BAUDRATE;

/* deliver 'a' (0x1C) scancode event to `ps2_clk`, `ps2_data` inputs:
    1... 1  0  1  0  1  0  1  0  1  0  1  0  1  0  1  0  1  0  1  0  1  0  1...
ps2_clk┄┄───┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌─┄┄
         ┊  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘
         ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊  ┊
         ┊  v  ┊  v  ┊  v  ┊  v  ┊  v  ┊  v  ┊  v  ┊  v  ┊  v  ┊  v  ┊  v  ┊
ps2_dat     0  ╳  1  ╳  2  ╳  3  ╳  4  ╳  5  ╳  6  ╳  7  ╳  8  ╳  9  ╳  A  ├┄┄┄
      0...     0     0     1     1     1     0     0     0    x=0    1     1...
         └───────────────────────────────────────────────────────────┘
       start  LSB                   ...                 MSB   par  stop

       <-- 8765 4321
16'h1C=16'b0001_1100                              xor(00011100x) = 1  =>  x = 0
*/
	logic [11:0] ps2_data_bits;
	assign ps2_dat = ps2_data_bits[0];
	initial begin
		// start with PS/2 clock "at rest":
		ps2_clk = 1'b1;

		// wait for a while before we begin:
		repeat (INIT_DELAY) @(posedge clk);

		// operate the PS/2 clock 22 times (11 bits):
		repeat (2 * PS2_NUM_BITS) begin
			repeat (PS2_BIT_WIDTH / 2) @(posedge clk);
			ps2_clk = ~ps2_clk;
		end

	end
	always_ff @(posedge ps2_clk) begin
		if (rst)
			ps2_data_bits <= 12'b1100_0011_1000;
		else
			ps2_data_bits <= {1'b1, ps2_data_bits[11:1]};
	end

/* expect corresponding ascii 'a' (0x61) byte to go out over `uart_txd`:
               start                                stop
baud_slot: ┊   ┊   ┊LSB┊   ┊   ┊   ┊   ┊   ┊   ┊MSB┊   ┊
uart_txd ┄┄────┐ 0 ┌───┐ 0   0   0   0 ┌───────┐ 0 ┌────┄┄
               └───┘ 1 └───────────────┘ 1   1 └───┘ 1
*/
	logic [9:0] uart_out;
	initial begin
		// wait for the "start" bit on uart_txd
		@(negedge uart_txd);
		// get to the "middle" of the start bit:
		repeat (UART_BIT_WIDTH / 2) @(posedge clk);

		// sample `uart_txd` over a period covering a TX byte:
		repeat (UART_NUM_BITS) begin
			// $display("[%0t] uart_txd=%b", $time, uart_txd);
			uart_out = {uart_txd, uart_out[9:1]};
			repeat (UART_BIT_WIDTH) @(posedge clk);
		end

		// check result:
		if (uart_out[0] == 1'b0 &&
		    uart_out[9] == 1'b1 &&
		    uart_out[8:1] == 8'h61)
			$display("Test OK.");
		else
			$display("Test FAIL!!!");

		$finish;
	end

endmodule: tb_toptx
`endif // TBTOPTX

`ifdef TBTOPRX
// // verilator --binary --trace -DTBTOPRX --top tb_toprx *.sv
module tb_toprx ();

	// parameters:
	localparam
		BAUDRATE =   115200,
		CLK_FREQ = 25000000; // 25MHz

	// provide clk, rst:
	logic clk, rst;
	initial begin
		clk     = 1;
		rst     = 1;
		#22 rst = 0;
	end
	always #5 clk <= ~clk;

/*
	// record signal waveforms
	initial begin
		$dumpfile("foo.vcd");
		$dumpvars(3); // 3 submodule layers deep
	end
*/

	// DUT (and associated wires, dependencies):

	// uart pins:
	logic uart_rxd, uart_txd, uart_rts, uart_cts;
	// ps/2 keyboard pins:
	logic ps2_clk, ps2_dat;
	// VGA digital output pins:
	logic vga_hsync_n, vga_vsync_n, vga_blank_n;
	logic [7:0] vga_pxl_r, vga_pxl_g, vga_pxl_b;
	// ROM interface
	logic [video_pkg::GLP_AW-1:0] rom_addr;
	logic [video_pkg::GLP_DW-1:0] rom_data;
	// RAM interface:
	logic [video_pkg::SCR_BUF_AW-1:0] ram_addr;
	logic ram_wren;
	logic [video_pkg::SCR_BUF_DW-1:0] ram_wdata, ram_rdata;

	assign uart_rts = 1'b1; // assume host always ready

	// ROM instance external to top-level terminal module:
	sync_rom #(
		.FN("chargen/utfglphrom.hex"),
		.AW(video_pkg::GLP_AW),
		.DW(video_pkg::GLP_DW)
	) inst_sync_rom (
		.addr(rom_addr),
		.rdata(rom_data),
		.clk(clk)
	);

	// RAM instance external to top-level terminal module:
	sync_ram #(
		.AW(video_pkg::SCR_BUF_AW),
		.DW(video_pkg::SCR_BUF_DW)
	) inst_sync_ram (
		.addr(ram_addr),
		.wren(ram_wren),
		.wdata(ram_wdata),
		.rdata(ram_rdata),
		.clk(clk)
	);

	terminal_top #(
		.CLK_FREQ(CLK_FREQ),
		.BAUDRATE(BAUDRATE)
	) dut (
		// uart:
		.uart_rxd(uart_rxd),
		.uart_txd(uart_txd),
		.uart_rts(uart_rts),
		.uart_cts(uart_cts),
		// ps/2:
		.ps2_clk(ps2_clk),
		.ps2_dat(ps2_dat),
		// vga:
		.vga_hsync_n(vga_hsync_n),
		.vga_vsync_n(vga_vsync_n),
		.vga_blank_n(vga_blank_n),
		.vga_pxl_r(vga_pxl_r),
		.vga_pxl_g(vga_pxl_g),
		.vga_pxl_b(vga_pxl_b),
		// ROM interface:
		.rom_addr(rom_addr),
		.rom_data(rom_data),
		// RAM interface:
		.ram_addr(ram_addr),
		.ram_wren(ram_wren),
		.ram_wdata(ram_wdata),
		.ram_rdata(ram_rdata),
		// control:
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:

	localparam
		INIT_DELAY = 500,
		UART_NUM_BITS = 10,
		UART_BIT_WIDTH = CLK_FREQ / BAUDRATE;

/* deliver ascii 'a' (0x61) byte to `uart_rxd` input:
               start                                stop
baud_slot: ┊   ┊   ┊LSB┊   ┊   ┊   ┊   ┊   ┊   ┊MSB┊   ┊
uart_rxd ┄┄────┐ 0 ┌───┐ 0   0   0   0 ┌───────┐ 0 ┌────┄┄
               └───┘ 1 └───────────────┘ 1   1 └───┘ 1
*/
	logic [10:0] uart_data_bits;
	assign uart_rxd = uart_data_bits[0];
	initial begin
		// initialize `uart_rx` data bit sequence:
		uart_data_bits = 11'b1_0110_0001_01;

		// wait for a while before we begin:
		repeat (INIT_DELAY) @(posedge clk);

		// send data bits to `uart_rx`:
		repeat (UART_NUM_BITS) begin
			uart_data_bits = {1'b1, uart_data_bits[10:1]};
			repeat (UART_BIT_WIDTH) @(posedge clk);
		end
	end

/* expect corresponding pixels for 'a' to be displayed at screen(0,0):
⬛⬛⬛⬛⬛⬛⬛⬛⬛⬛⬛⬛
⬛⬛⬛⬛⬛⬛⬜⬜⬜⬜⬛⬛
⬛⬛⬛⬛⬛⬜⬛⬜⬛⬜⬛⬛
⬛⬛⬛⬛⬛⬜⬛⬜⬛⬜⬛⬛
⬛⬛⬛⬛⬛⬜⬛⬜⬛⬜⬛⬛
⬛⬛⬛⬛⬛⬛⬛⬛⬜⬛⬛⬛
The corresponding bit pattern is 72'h000_03c_054_054_054_008
*/
	localparam SHOW_PIXELS = 0;
	logic glyph_pxl;
	logic [71:0] glyph_pat;
	initial begin
		// skip scan lines until we reach the last character column:
		repeat ((video_pkg::SCR_COLS - 1) * video_pkg::CHR_WIDE) @(posedge vga_blank_n);

		// for each scan line in the last character column:
		repeat (video_pkg::CHR_WIDE) begin

			// get to the top of each scan line:
			@(posedge vga_blank_n);

			// skip two border pixels:
			repeat (2) @(posedge clk);

			// grab glyph box pixel column:
			repeat (video_pkg::CHR_HIGH) begin
				@(posedge clk);
				// this works with the default colors
				// (fgc=8'hE0, bgc=8'h16) without the need for
				// explicit color-setting escape sequences:
				glyph_pxl = vga_pxl_r[0];
				glyph_pat = {glyph_pat[70:0], glyph_pxl};
				if (SHOW_PIXELS)
					$write("%s", glyph_pxl ? "⬜" : "⬛");
			end
			if (SHOW_PIXELS)
				$display("");
		end

		// check result:
		if (glyph_pat == 72'h000_03c_054_054_054_008)
			$display("Test OK.");
		else
			$display("Test FAIL!!!");

		$finish;
	end

endmodule: tb_toprx
`endif // TBTOPRX
