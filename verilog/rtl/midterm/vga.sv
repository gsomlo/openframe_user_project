// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`include "video.svh"

// See: https://projectf.io/posts/video-timings-vga-720p-1080p/
//
// hline:   ┊<┄┄┄┄┄┄┄ htotal ┄┄┄┄┄┄┄>┊                        ┊
//          ┊hbpw┌──────────┐hfpw┊hsw┊    ┌──────────┐        ┊
// visible: ─────┘   hvpw   └─────────────┘          └─────────┈
//          ┌────────────────────┐   ┌────────────────────┐   ┌┈
// hsync_n: ┘                    └───┘                    └───┘
//
// measured in pixels:
// htotal: total horz. line width
// hbpw:   horz. back porch width
// hvpw:   horz. visible pixel width
// hfpw:   horz. front porch width
// hsw:    horz. sync width (neg. polarity)
//
// vline:   ┊<┄┄┄┄┄┄┄ vtotal ┄┄┄┄┄┄┄>┊                        ┊
//          ┊vbpw┌──────────┐vfpw┊vsw┊    ┌──────────┐        ┊
// visible: ─────┘   vvlw   └─────────────┘          └─────────┈
//          ┌────────────────────┐   ┌────────────────────┐   ┌┈
// vsync_n: ┘                    └───┘                    └───┘
//
// measured in hlines:
// vtotal: total vert. hline count
// vbpw:   vert. back porch width
// vvlw:   vert. visible line count
// vfpw:   vert. front porch width
// vsw:    vert. sync width (neg. polarity)
module vga_phy (
	// input: pixel data (vga rgb color)
	input  video_pkg::vga_rgb_t pxl_data,
	// NOTE: `pxl_valid` signal ignored, as there's no recourse if
	//       we're ready, but there's no valid pixel data available!!!
	// This is a real-time situation, so producer MUST ensure
	// that there will always be available valid data to consume)!!!
	input  logic pxl_valid,
	output logic pxl_ready,

	// signal that a new rendered frame's pixels will be needed imminently:
	output logic frm_rndr_start,

	// output signals for VGA DAC:
	output logic hsync_n,
	output logic vsync_n,
	output logic blank_n, // active pixel (needed by de2-115 vga dac)
	output logic [7:0] pxl_r, pxl_g, pxl_b,

	input  logic clk,
	input  logic rst
);

	// horiz. and vert. position counters:
	logic [video_pkg::VGA_HCW-1:0] hcnt;
	logic [video_pkg::VGA_VCW-1:0] vcnt;

	always_ff @(posedge clk) begin
		if (rst) begin
			hcnt <= 0;
			vcnt <= 0;
		end else begin
			if (hcnt == video_pkg::VGA_HTOTAL[video_pkg::VGA_HCW-1:0] - 1) begin
				hcnt <= 0;
				if (vcnt == video_pkg::VGA_VTOTAL[video_pkg::VGA_VCW-1:0] - 1) begin
					vcnt <= 0;
				end else begin
					vcnt <= vcnt + 1;
				end
			end else begin
				hcnt <= hcnt + 1;
			end
		end
	end

	// combinationally calculated sync. & blank attributes:
	logic comb_hsync_n, comb_vsync_n, comb_blank_n, h_vis, v_vis;

	// stay high outside of sync window at the end of a hline or frame:
	assign comb_hsync_n = (hcnt < (video_pkg::VGA_HTOTAL - video_pkg::VGA_HSW));
	assign comb_vsync_n = (vcnt < (video_pkg::VGA_VTOTAL - video_pkg::VGA_VSW));

	// visibility starts after back porch, ends before front porch:
	assign h_vis = (hcnt >= video_pkg::VGA_HBPW) & (hcnt < (video_pkg::VGA_HBPW + video_pkg::VGA_HVPW));
	assign v_vis = (vcnt >= video_pkg::VGA_VBPW) & (vcnt < (video_pkg::VGA_VBPW + video_pkg::VGA_VVLW));

	// stay high while visible:
	assign comb_blank_n = h_vis & v_vis;

	// visible means we consume/handshake a pixel from input/producer
	// (remember, we assume pxl_valid is always true):
	assign pxl_ready = comb_blank_n;

	// render-pipeline-depth before first visible pixel:
	assign frm_rndr_start = (vcnt == video_pkg::VGA_VBPW) &
				(hcnt == video_pkg::VGA_HBPW - video_pkg::RNDR_PIPE_DEPTH);

	// output pixel color
	logic [7:0] pxl_rNext, pxl_gNext, pxl_bNext;
	assign pxl_rNext = pxl_data.r;
	assign pxl_gNext = pxl_data.g;
	assign pxl_bNext = pxl_data.b;

	// expose only *registered* versions of sync, blank, and pixel color:
	always_ff @(posedge clk) begin
		if (rst) begin
			hsync_n <= 1; // no hsync
			vsync_n <= 1; // no vsync
			blank_n <= 0; // yes blank
			pxl_r   <= 0;
			pxl_g   <= 0;
			pxl_b   <= 0;
		end else begin
			hsync_n <= comb_hsync_n;
			vsync_n <= comb_vsync_n;
			blank_n <= comb_blank_n;
			pxl_r   <= pxl_rNext;
			pxl_g   <= pxl_gNext;
			pxl_b   <= pxl_bNext;
		end
	end

endmodule: vga_phy
