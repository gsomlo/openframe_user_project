// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`include "video.svh"

/*
Starting point used for color intensity values:
    https://github.com/ThomasDickey/old-xterm/blob/master/256colres.h

- compat colors 00..0f were adjusted to (re-)use color cube intensities,
  for better compression (via Boolean optimization of `unique case`)

- color (6x6x6) cube levels (0..5) are: 0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF;

- for 0x10 ≤ idx ≤ 0xE7, levels (0..5) are calculated as follows:
    lvl_r =  (idx - 16) / 36
    lvl_g = ((idx - 16) % 36) / 6
    lvl_b =  (idx - 16) % 6
  this is implemented as a `unique case` lookup table (that is subsequently
  subjected to Boolean optimization during synthesis), to avoid implementing
  integer division and remainder operations arithmetically.

- for 0xE8 ≤ idx ≤ 0xFF (grayscale levels), the arithmetic derivation was
  simplified to
    (idx - 231) * 10

- when the entire `unique case` is fully specified with *constant* values
  (including grayscale), two observations can be made: (1) yosys optimizes
  a combinational Boolean logic design *really* *well*, utilizing only
  309 cells, and (2) Quartus 25.1 attempts to infer a 24-bit-word ROM, and
  errors out in the process.

- when grayscale values are calculated arithmetically (by defining the
  ARITHMETIC_ANSI_GRAYSCALE macro), ROM inference is precluded, and our
  observations change to: (1) yosys optimization is *much* *weaker*, with
  utilization growing to 1284 cells, and (2) Quartus 25.1 no longer tries
  to infer a ROM, being able to successfully compile the design.

- yosys tests were conducted as follows:
    read -sv2012 [-DARITHMETIC_ANSI_GRAYSCALE] ansi_palette.sv
    synth -top palette_comb

- splitting out the `unique case` statement into dedicated blocks per RGB
  color component yields two advantages: (1) when attempting to infer three
  8-bit-word ROMs, Quartus 25.1 no longer errors out, and (2) yosys-optimized
  cell utilization drops to 302 cells (from 309) when fully specified with
  constants (including grayscale), and, respectively, to 994 cells (from
  1284) when grayscale levels are calculated with ARITHMETIC_ANSI_GRAYSCALE.

- finally, when Quartus 25.1 is forced to avoid ROM inference (by specifying
  `set_global_assignment -name AUTO_ROM_RECOGNITION OFF` in the project (qsf)
  file, the fit and map reports show no meaningful difference in utilization
  whether color components are calculated together or via separate blocks,
  or whether grayscale intensities are computed arithmetically or enumerated
  via constants as part of the `unique case` statement(s). Also, the reports
  show no difference when compared to utilization when 8-bit ROM inference
  is attempted. Seemingly, ROM inference is *always* unsuccessful, it's just
  a matter of whether or not the word size of the attempted ROM itself leads
  to Quartus 25.1 crashing!
*/
`undef ARITHMETIC_ANSI_GRAYSCALE
module palette_comb (
	input  logic [7:0] index,
	output video_pkg::vga_rgb_t   color
);

`ifdef ARITHMETIC_ANSI_GRAYSCALE
	// grayscale index (and x8, x2 multiples), and intensity level:
	logic [7:0] gsc_idx, gsc_idx8, gsc_idx2, gsc_lvl;
	assign gsc_idx  = index - 8'hE7;
	assign gsc_idx8 = {gsc_idx[4:0], 3'b0}; // gsc_idx * 8 (<< 3)
	assign gsc_idx2 = {gsc_idx[6:0], 1'b0}; // gsc_idx * 2 (<< 1)
	assign gsc_lvl  = gsc_idx8 + gsc_idx2;  // gsc_idx * 10 (x8 + x2)
`endif // ARITHMETIC_ANSI_GRAYSCALE

	// NOTE: split out by color component, to prevent synthesis
	// (e.g., Quartus) from attempting to elaborate a 24-bit ROM!
	always_comb begin
		// red:
		unique case (index)
		8'h00, 8'h02, 8'h04, 8'h06, 8'h0A, 8'h0C, 8'h0E, 8'h10,
		8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17, 8'h18,
		8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F, 8'h20,
		8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27, 8'h28,
		8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F, 8'h30,
		8'h31, 8'h32, 8'h33:
			color.r = 8'h00;
		8'h08, 8'h34, 8'h35, 8'h36, 8'h37, 8'h38, 8'h39, 8'h3A,
		8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F, 8'h40, 8'h41, 8'h42,
		8'h43, 8'h44, 8'h45, 8'h46, 8'h47, 8'h48, 8'h49, 8'h4A,
		8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F, 8'h50, 8'h51, 8'h52,
		8'h53, 8'h54, 8'h55, 8'h56, 8'h57:
			color.r = 8'h5F;
		8'h01, 8'h03, 8'h05, 8'h58, 8'h59, 8'h5A, 8'h5B, 8'h5C,
		8'h5D, 8'h5E, 8'h5F, 8'h60, 8'h61, 8'h62, 8'h63, 8'h64,
		8'h65, 8'h66, 8'h67, 8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C,
		8'h6D, 8'h6E, 8'h6F, 8'h70, 8'h71, 8'h72, 8'h73, 8'h74,
		8'h75, 8'h76, 8'h77, 8'h78, 8'h79, 8'h7A, 8'h7B:
			color.r = 8'h87;
		8'h07, 8'h7C, 8'h7D, 8'h7E, 8'h7F, 8'h80, 8'h81, 8'h82,
		8'h83, 8'h84, 8'h85, 8'h86, 8'h87, 8'h88, 8'h89, 8'h8A,
		8'h8B, 8'h8C, 8'h8D, 8'h8E, 8'h8F, 8'h90, 8'h91, 8'h92,
		8'h93, 8'h94, 8'h95, 8'h96, 8'h97, 8'h98, 8'h99, 8'h9A,
		8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F:
			color.r = 8'hAF;
		8'hA0, 8'hA1, 8'hA2, 8'hA3, 8'hA4, 8'hA5, 8'hA6, 8'hA7,
		8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC, 8'hAD, 8'hAE, 8'hAF,
		8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6, 8'hB7,
		8'hB8, 8'hB9, 8'hBA, 8'hBB, 8'hBC, 8'hBD, 8'hBE, 8'hBF,
		8'hC0, 8'hC1, 8'hC2, 8'hC3:
			color.r = 8'hD7;
		8'h09, 8'h0B, 8'h0D, 8'h0F, 8'hC4, 8'hC5, 8'hC6, 8'hC7,
		8'hC8, 8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD, 8'hCE, 8'hCF,
		8'hD0, 8'hD1, 8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD6, 8'hD7,
		8'hD8, 8'hD9, 8'hDA, 8'hDB, 8'hDC, 8'hDD, 8'hDE, 8'hDF,
		8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE4, 8'hE5, 8'hE6, 8'hE7:
			color.r = 8'hFF;
`ifdef ARITHMETIC_ANSI_GRAYSCALE
		8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC, 8'hED, 8'hEE, 8'hEF,
		8'hF0, 8'hF1, 8'hF2, 8'hF3, 8'hF4, 8'hF5, 8'hF6, 8'hF7,
		8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD, 8'hFE, 8'hFF:
			color.r = gsc_lvl;
`else // not ARITHMETIC_ANSI_GRAYSCALE
		8'hE8:	color.r = 8'h0A;
		8'hE9:	color.r = 8'h14;
		8'hEA:	color.r = 8'h1E;
		8'hEB:	color.r = 8'h28;
		8'hEC:	color.r = 8'h32;
		8'hED:	color.r = 8'h3C;
		8'hEE:	color.r = 8'h46;
		8'hEF:	color.r = 8'h50;
		8'hF0:	color.r = 8'h5A;
		8'hF1:	color.r = 8'h64;
		8'hF2:	color.r = 8'h6E;
		8'hF3:	color.r = 8'h78;
		8'hF4:	color.r = 8'h82;
		8'hF5:	color.r = 8'h8C;
		8'hF6:	color.r = 8'h96;
		8'hF7:	color.r = 8'hA0;
		8'hF8:	color.r = 8'hAA;
		8'hF9:	color.r = 8'hB4;
		8'hFA:	color.r = 8'hBE;
		8'hFB:	color.r = 8'hC8;
		8'hFC:	color.r = 8'hD2;
		8'hFD:	color.r = 8'hDC;
		8'hFE:	color.r = 8'hE6;
		8'hFF:	color.r = 8'hF0;
`endif // ARITHMETIC_ANSI_GRAYSCALE
		endcase
		// green:
		unique case (index)
		8'h00, 8'h01, 8'h04, 8'h05, 8'h09, 8'h0C, 8'h0D, 8'h10,
		8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h34, 8'h35, 8'h36,
		8'h37, 8'h38, 8'h39, 8'h58, 8'h59, 8'h5A, 8'h5B, 8'h5C,
		8'h5D, 8'h7C, 8'h7D, 8'h7E, 8'h7F, 8'h80, 8'h81, 8'hA0,
		8'hA1, 8'hA2, 8'hA3, 8'hA4, 8'hA5, 8'hC4, 8'hC5, 8'hC6,
		8'hC7, 8'hC8, 8'hC9:
			color.g = 8'h00;
		8'h08, 8'h16, 8'h17, 8'h18, 8'h19, 8'h1A, 8'h1B, 8'h3A,
		8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F, 8'h5E, 8'h5F, 8'h60,
		8'h61, 8'h62, 8'h63, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86,
		8'h87, 8'hA6, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hCA,
		8'hCB, 8'hCC, 8'hCD, 8'hCE, 8'hCF:
			color.g = 8'h5F;
		8'h02, 8'h03, 8'h06, 8'h1C, 8'h1D, 8'h1E, 8'h1F, 8'h20,
		8'h21, 8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h64,
		8'h65, 8'h66, 8'h67, 8'h68, 8'h69, 8'h88, 8'h89, 8'h8A,
		8'h8B, 8'h8C, 8'h8D, 8'hAC, 8'hAD, 8'hAE, 8'hAF, 8'hB0,
		8'hB1, 8'hD0, 8'hD1, 8'hD2, 8'hD3, 8'hD4, 8'hD5:
			color.g = 8'h87;
		8'h07, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27, 8'h46,
		8'h47, 8'h48, 8'h49, 8'h4A, 8'h4B, 8'h6A, 8'h6B, 8'h6C,
		8'h6D, 8'h6E, 8'h6F, 8'h8E, 8'h8F, 8'h90, 8'h91, 8'h92,
		8'h93, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6, 8'hB7, 8'hD6,
		8'hD7, 8'hD8, 8'hD9, 8'hDA, 8'hDB:
			color.g = 8'hAF;
		8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h4C, 8'h4D,
		8'h4E, 8'h4F, 8'h50, 8'h51, 8'h70, 8'h71, 8'h72, 8'h73,
		8'h74, 8'h75, 8'h94, 8'h95, 8'h96, 8'h97, 8'h98, 8'h99,
		8'hB8, 8'hB9, 8'hBA, 8'hBB, 8'hBC, 8'hBD, 8'hDC, 8'hDD,
		8'hDE, 8'hDF, 8'hE0, 8'hE1:
			color.g = 8'hD7;
		8'h0A, 8'h0B, 8'h0E, 8'h0F, 8'h2E, 8'h2F, 8'h30, 8'h31,
		8'h32, 8'h33, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57,
		8'h76, 8'h77, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h9A, 8'h9B,
		8'h9C, 8'h9D, 8'h9E, 8'h9F, 8'hBE, 8'hBF, 8'hC0, 8'hC1,
		8'hC2, 8'hC3, 8'hE2, 8'hE3, 8'hE4, 8'hE5, 8'hE6, 8'hE7:
			color.g = 8'hFF;
`ifdef ARITHMETIC_ANSI_GRAYSCALE
		8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC, 8'hED, 8'hEE, 8'hEF,
		8'hF0, 8'hF1, 8'hF2, 8'hF3, 8'hF4, 8'hF5, 8'hF6, 8'hF7,
		8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD, 8'hFE, 8'hFF:
			color.g = gsc_lvl;
`else // not ARITHMETIC_ANSI_GRAYSCALE
		8'hE8:	color.g = 8'h0A;
		8'hE9:	color.g = 8'h14;
		8'hEA:	color.g = 8'h1E;
		8'hEB:	color.g = 8'h28;
		8'hEC:	color.g = 8'h32;
		8'hED:	color.g = 8'h3C;
		8'hEE:	color.g = 8'h46;
		8'hEF:	color.g = 8'h50;
		8'hF0:	color.g = 8'h5A;
		8'hF1:	color.g = 8'h64;
		8'hF2:	color.g = 8'h6E;
		8'hF3:	color.g = 8'h78;
		8'hF4:	color.g = 8'h82;
		8'hF5:	color.g = 8'h8C;
		8'hF6:	color.g = 8'h96;
		8'hF7:	color.g = 8'hA0;
		8'hF8:	color.g = 8'hAA;
		8'hF9:	color.g = 8'hB4;
		8'hFA:	color.g = 8'hBE;
		8'hFB:	color.g = 8'hC8;
		8'hFC:	color.g = 8'hD2;
		8'hFD:	color.g = 8'hDC;
		8'hFE:	color.g = 8'hE6;
		8'hFF:	color.g = 8'hF0;
`endif // ARITHMETIC_ANSI_GRAYSCALE
		endcase
		// blue:
		unique case (index)
		8'h00, 8'h01, 8'h02, 8'h03, 8'h09, 8'h0A, 8'h0B, 8'h10,
		8'h16, 8'h1C, 8'h22, 8'h28, 8'h2E, 8'h34, 8'h3A, 8'h40,
		8'h46, 8'h4C, 8'h52, 8'h58, 8'h5E, 8'h64, 8'h6A, 8'h70,
		8'h76, 8'h7C, 8'h82, 8'h88, 8'h8E, 8'h94, 8'h9A, 8'hA0,
		8'hA6, 8'hAC, 8'hB2, 8'hB8, 8'hBE, 8'hC4, 8'hCA, 8'hD0,
		8'hD6, 8'hDC, 8'hE2:
			color.b = 8'h00;
		8'h08, 8'h11, 8'h17, 8'h1D, 8'h23, 8'h29, 8'h2F, 8'h35,
		8'h3B, 8'h41, 8'h47, 8'h4D, 8'h53, 8'h59, 8'h5F, 8'h65,
		8'h6B, 8'h71, 8'h77, 8'h7D, 8'h83, 8'h89, 8'h8F, 8'h95,
		8'h9B, 8'hA1, 8'hA7, 8'hAD, 8'hB3, 8'hB9, 8'hBF, 8'hC5,
		8'hCB, 8'hD1, 8'hD7, 8'hDD, 8'hE3:
			color.b = 8'h5F;
		8'h04, 8'h05, 8'h06, 8'h12, 8'h18, 8'h1E, 8'h24, 8'h2A,
		8'h30, 8'h36, 8'h3C, 8'h42, 8'h48, 8'h4E, 8'h54, 8'h5A,
		8'h60, 8'h66, 8'h6C, 8'h72, 8'h78, 8'h7E, 8'h84, 8'h8A,
		8'h90, 8'h96, 8'h9C, 8'hA2, 8'hA8, 8'hAE, 8'hB4, 8'hBA,
		8'hC0, 8'hC6, 8'hCC, 8'hD2, 8'hD8, 8'hDE, 8'hE4:
			color.b = 8'h87;
		8'h07, 8'h13, 8'h19, 8'h1F, 8'h25, 8'h2B, 8'h31, 8'h37,
		8'h3D, 8'h43, 8'h49, 8'h4F, 8'h55, 8'h5B, 8'h61, 8'h67,
		8'h6D, 8'h73, 8'h79, 8'h7F, 8'h85, 8'h8B, 8'h91, 8'h97,
		8'h9D, 8'hA3, 8'hA9, 8'hAF, 8'hB5, 8'hBB, 8'hC1, 8'hC7,
		8'hCD, 8'hD3, 8'hD9, 8'hDF, 8'hE5:
			color.b = 8'hAF;
		8'h14, 8'h1A, 8'h20, 8'h26, 8'h2C, 8'h32, 8'h38, 8'h3E,
		8'h44, 8'h4A, 8'h50, 8'h56, 8'h5C, 8'h62, 8'h68, 8'h6E,
		8'h74, 8'h7A, 8'h80, 8'h86, 8'h8C, 8'h92, 8'h98, 8'h9E,
		8'hA4, 8'hAA, 8'hB0, 8'hB6, 8'hBC, 8'hC2, 8'hC8, 8'hCE,
		8'hD4, 8'hDA, 8'hE0, 8'hE6:
			color.b = 8'hD7;
		8'h0C, 8'h0D, 8'h0E, 8'h0F, 8'h15, 8'h1B, 8'h21, 8'h27,
		8'h2D, 8'h33, 8'h39, 8'h3F, 8'h45, 8'h4B, 8'h51, 8'h57,
		8'h5D, 8'h63, 8'h69, 8'h6F, 8'h75, 8'h7B, 8'h81, 8'h87,
		8'h8D, 8'h93, 8'h99, 8'h9F, 8'hA5, 8'hAB, 8'hB1, 8'hB7,
		8'hBD, 8'hC3, 8'hC9, 8'hCF, 8'hD5, 8'hDB, 8'hE1, 8'hE7:
			color.b = 8'hFF;
`ifdef ARITHMETIC_ANSI_GRAYSCALE
		8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC, 8'hED, 8'hEE, 8'hEF,
		8'hF0, 8'hF1, 8'hF2, 8'hF3, 8'hF4, 8'hF5, 8'hF6, 8'hF7,
		8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD, 8'hFE, 8'hFF:
			color.b = gsc_lvl;
`else // not ARITHMETIC_ANSI_GRAYSCALE
		8'hE8:	color.b = 8'h0A;
		8'hE9:	color.b = 8'h14;
		8'hEA:	color.b = 8'h1E;
		8'hEB:	color.b = 8'h28;
		8'hEC:	color.b = 8'h32;
		8'hED:	color.b = 8'h3C;
		8'hEE:	color.b = 8'h46;
		8'hEF:	color.b = 8'h50;
		8'hF0:	color.b = 8'h5A;
		8'hF1:	color.b = 8'h64;
		8'hF2:	color.b = 8'h6E;
		8'hF3:	color.b = 8'h78;
		8'hF4:	color.b = 8'h82;
		8'hF5:	color.b = 8'h8C;
		8'hF6:	color.b = 8'h96;
		8'hF7:	color.b = 8'hA0;
		8'hF8:	color.b = 8'hAA;
		8'hF9:	color.b = 8'hB4;
		8'hFA:	color.b = 8'hBE;
		8'hFB:	color.b = 8'hC8;
		8'hFC:	color.b = 8'hD2;
		8'hFD:	color.b = 8'hDC;
		8'hFE:	color.b = 8'hE6;
		8'hFF:	color.b = 8'hF0;
`endif // ARITHMETIC_ANSI_GRAYSCALE
		endcase
	end

endmodule: palette_comb

module palette_comb_old (
	input  logic [7:0] index,
	output video_pkg::vga_rgb_t   color
);

`ifdef ARITHMETIC_ANSI_GRAYSCALE
	// grayscale index (and x8, x2 multiples), and intensity level:
	logic [7:0] gsc_idx, gsc_idx8, gsc_idx2, gsc_lvl;
	assign gsc_idx  = index - 8'hE7;
	assign gsc_idx8 = {gsc_idx[4:0], 3'b0}; // gsc_idx * 8 (<< 3)
	assign gsc_idx2 = {gsc_idx[6:0], 1'b0}; // gsc_idx * 2 (<< 1)
	assign gsc_lvl  = gsc_idx8 + gsc_idx2;  // gsc_idx * 10 (x8 + x2)
`endif // ARITHMETIC_ANSI_GRAYSCALE

	// cube color intensity levels are highly redundant and compressible:
	always_comb begin
		unique case (index)
		// compat colors:
		8'h00: color = {8'h00, 8'h00, 8'h00}; // black
		8'h01: color = {8'h87, 8'h00, 8'h00}; // d. red
		8'h02: color = {8'h00, 8'h87, 8'h00}; // d. green
		8'h03: color = {8'h87, 8'h87, 8'h00}; // d. yellow
		8'h04: color = {8'h00, 8'h00, 8'h87}; // d. blue
		8'h05: color = {8'h87, 8'h00, 8'h87}; // d. magenta
		8'h06: color = {8'h00, 8'h87, 8'h87}; // d. cyan
		8'h07: color = {8'hAF, 8'hAF, 8'hAF}; // d. wht (l. gry)
		8'h08: color = {8'h5F, 8'h5F, 8'h5F}; // l. blk (d. gry)
		8'h09: color = {8'hFF, 8'h00, 8'h00}; // red
		8'h0A: color = {8'h00, 8'hFF, 8'h00}; // green
		8'h0B: color = {8'hFF, 8'hFF, 8'h00}; // yellow
		8'h0C: color = {8'h00, 8'h00, 8'hFF}; // blue
		8'h0D: color = {8'hFF, 8'h00, 8'hFF}; // magenta
		8'h0E: color = {8'h00, 8'hFF, 8'hFF}; // cyan
		8'h0F: color = {8'hFF, 8'hFF, 8'hFF}; // white
		// 6x6x6 cube colors:
		8'h10: color = {8'h00, 8'h00, 8'h00}; // black
		8'h11: color = {8'h00, 8'h00, 8'h5F};
		8'h12: color = {8'h00, 8'h00, 8'h87};
		8'h13: color = {8'h00, 8'h00, 8'hAF};
		8'h14: color = {8'h00, 8'h00, 8'hD7};
		8'h15: color = {8'h00, 8'h00, 8'hFF};
		8'h16: color = {8'h00, 8'h5F, 8'h00};
		8'h17: color = {8'h00, 8'h5F, 8'h5F};
		8'h18: color = {8'h00, 8'h5F, 8'h87};
		8'h19: color = {8'h00, 8'h5F, 8'hAF};
		8'h1A: color = {8'h00, 8'h5F, 8'hD7};
		8'h1B: color = {8'h00, 8'h5F, 8'hFF};
		8'h1C: color = {8'h00, 8'h87, 8'h00};
		8'h1D: color = {8'h00, 8'h87, 8'h5F};
		8'h1E: color = {8'h00, 8'h87, 8'h87};
		8'h1F: color = {8'h00, 8'h87, 8'hAF};
		8'h20: color = {8'h00, 8'h87, 8'hD7};
		8'h21: color = {8'h00, 8'h87, 8'hFF};
		8'h22: color = {8'h00, 8'hAF, 8'h00};
		8'h23: color = {8'h00, 8'hAF, 8'h5F};
		8'h24: color = {8'h00, 8'hAF, 8'h87};
		8'h25: color = {8'h00, 8'hAF, 8'hAF};
		8'h26: color = {8'h00, 8'hAF, 8'hD7};
		8'h27: color = {8'h00, 8'hAF, 8'hFF};
		8'h28: color = {8'h00, 8'hD7, 8'h00};
		8'h29: color = {8'h00, 8'hD7, 8'h5F};
		8'h2A: color = {8'h00, 8'hD7, 8'h87};
		8'h2B: color = {8'h00, 8'hD7, 8'hAF};
		8'h2C: color = {8'h00, 8'hD7, 8'hD7};
		8'h2D: color = {8'h00, 8'hD7, 8'hFF};
		8'h2E: color = {8'h00, 8'hFF, 8'h00};
		8'h2F: color = {8'h00, 8'hFF, 8'h5F};
		8'h30: color = {8'h00, 8'hFF, 8'h87};
		8'h31: color = {8'h00, 8'hFF, 8'hAF};
		8'h32: color = {8'h00, 8'hFF, 8'hD7};
		8'h33: color = {8'h00, 8'hFF, 8'hFF};
		8'h34: color = {8'h5F, 8'h00, 8'h00};
		8'h35: color = {8'h5F, 8'h00, 8'h5F};
		8'h36: color = {8'h5F, 8'h00, 8'h87};
		8'h37: color = {8'h5F, 8'h00, 8'hAF};
		8'h38: color = {8'h5F, 8'h00, 8'hD7};
		8'h39: color = {8'h5F, 8'h00, 8'hFF};
		8'h3A: color = {8'h5F, 8'h5F, 8'h00};
		8'h3B: color = {8'h5F, 8'h5F, 8'h5F};
		8'h3C: color = {8'h5F, 8'h5F, 8'h87};
		8'h3D: color = {8'h5F, 8'h5F, 8'hAF};
		8'h3E: color = {8'h5F, 8'h5F, 8'hD7};
		8'h3F: color = {8'h5F, 8'h5F, 8'hFF};
		8'h40: color = {8'h5F, 8'h87, 8'h00};
		8'h41: color = {8'h5F, 8'h87, 8'h5F};
		8'h42: color = {8'h5F, 8'h87, 8'h87};
		8'h43: color = {8'h5F, 8'h87, 8'hAF};
		8'h44: color = {8'h5F, 8'h87, 8'hD7};
		8'h45: color = {8'h5F, 8'h87, 8'hFF};
		8'h46: color = {8'h5F, 8'hAF, 8'h00};
		8'h47: color = {8'h5F, 8'hAF, 8'h5F};
		8'h48: color = {8'h5F, 8'hAF, 8'h87};
		8'h49: color = {8'h5F, 8'hAF, 8'hAF};
		8'h4A: color = {8'h5F, 8'hAF, 8'hD7};
		8'h4B: color = {8'h5F, 8'hAF, 8'hFF};
		8'h4C: color = {8'h5F, 8'hD7, 8'h00};
		8'h4D: color = {8'h5F, 8'hD7, 8'h5F};
		8'h4E: color = {8'h5F, 8'hD7, 8'h87};
		8'h4F: color = {8'h5F, 8'hD7, 8'hAF};
		8'h50: color = {8'h5F, 8'hD7, 8'hD7};
		8'h51: color = {8'h5F, 8'hD7, 8'hFF};
		8'h52: color = {8'h5F, 8'hFF, 8'h00};
		8'h53: color = {8'h5F, 8'hFF, 8'h5F};
		8'h54: color = {8'h5F, 8'hFF, 8'h87};
		8'h55: color = {8'h5F, 8'hFF, 8'hAF};
		8'h56: color = {8'h5F, 8'hFF, 8'hD7};
		8'h57: color = {8'h5F, 8'hFF, 8'hFF};
		8'h58: color = {8'h87, 8'h00, 8'h00};
		8'h59: color = {8'h87, 8'h00, 8'h5F};
		8'h5A: color = {8'h87, 8'h00, 8'h87};
		8'h5B: color = {8'h87, 8'h00, 8'hAF};
		8'h5C: color = {8'h87, 8'h00, 8'hD7};
		8'h5D: color = {8'h87, 8'h00, 8'hFF};
		8'h5E: color = {8'h87, 8'h5F, 8'h00};
		8'h5F: color = {8'h87, 8'h5F, 8'h5F};
		8'h60: color = {8'h87, 8'h5F, 8'h87};
		8'h61: color = {8'h87, 8'h5F, 8'hAF};
		8'h62: color = {8'h87, 8'h5F, 8'hD7};
		8'h63: color = {8'h87, 8'h5F, 8'hFF};
		8'h64: color = {8'h87, 8'h87, 8'h00};
		8'h65: color = {8'h87, 8'h87, 8'h5F};
		8'h66: color = {8'h87, 8'h87, 8'h87};
		8'h67: color = {8'h87, 8'h87, 8'hAF};
		8'h68: color = {8'h87, 8'h87, 8'hD7};
		8'h69: color = {8'h87, 8'h87, 8'hFF};
		8'h6A: color = {8'h87, 8'hAF, 8'h00};
		8'h6B: color = {8'h87, 8'hAF, 8'h5F};
		8'h6C: color = {8'h87, 8'hAF, 8'h87};
		8'h6D: color = {8'h87, 8'hAF, 8'hAF};
		8'h6E: color = {8'h87, 8'hAF, 8'hD7};
		8'h6F: color = {8'h87, 8'hAF, 8'hFF};
		8'h70: color = {8'h87, 8'hD7, 8'h00};
		8'h71: color = {8'h87, 8'hD7, 8'h5F};
		8'h72: color = {8'h87, 8'hD7, 8'h87};
		8'h73: color = {8'h87, 8'hD7, 8'hAF};
		8'h74: color = {8'h87, 8'hD7, 8'hD7};
		8'h75: color = {8'h87, 8'hD7, 8'hFF};
		8'h76: color = {8'h87, 8'hFF, 8'h00};
		8'h77: color = {8'h87, 8'hFF, 8'h5F};
		8'h78: color = {8'h87, 8'hFF, 8'h87};
		8'h79: color = {8'h87, 8'hFF, 8'hAF};
		8'h7A: color = {8'h87, 8'hFF, 8'hD7};
		8'h7B: color = {8'h87, 8'hFF, 8'hFF};
		8'h7C: color = {8'hAF, 8'h00, 8'h00};
		8'h7D: color = {8'hAF, 8'h00, 8'h5F};
		8'h7E: color = {8'hAF, 8'h00, 8'h87};
		8'h7F: color = {8'hAF, 8'h00, 8'hAF};
		8'h80: color = {8'hAF, 8'h00, 8'hD7};
		8'h81: color = {8'hAF, 8'h00, 8'hFF};
		8'h82: color = {8'hAF, 8'h5F, 8'h00};
		8'h83: color = {8'hAF, 8'h5F, 8'h5F};
		8'h84: color = {8'hAF, 8'h5F, 8'h87};
		8'h85: color = {8'hAF, 8'h5F, 8'hAF};
		8'h86: color = {8'hAF, 8'h5F, 8'hD7};
		8'h87: color = {8'hAF, 8'h5F, 8'hFF};
		8'h88: color = {8'hAF, 8'h87, 8'h00};
		8'h89: color = {8'hAF, 8'h87, 8'h5F};
		8'h8A: color = {8'hAF, 8'h87, 8'h87};
		8'h8B: color = {8'hAF, 8'h87, 8'hAF};
		8'h8C: color = {8'hAF, 8'h87, 8'hD7};
		8'h8D: color = {8'hAF, 8'h87, 8'hFF};
		8'h8E: color = {8'hAF, 8'hAF, 8'h00};
		8'h8F: color = {8'hAF, 8'hAF, 8'h5F};
		8'h90: color = {8'hAF, 8'hAF, 8'h87};
		8'h91: color = {8'hAF, 8'hAF, 8'hAF};
		8'h92: color = {8'hAF, 8'hAF, 8'hD7};
		8'h93: color = {8'hAF, 8'hAF, 8'hFF};
		8'h94: color = {8'hAF, 8'hD7, 8'h00};
		8'h95: color = {8'hAF, 8'hD7, 8'h5F};
		8'h96: color = {8'hAF, 8'hD7, 8'h87};
		8'h97: color = {8'hAF, 8'hD7, 8'hAF};
		8'h98: color = {8'hAF, 8'hD7, 8'hD7};
		8'h99: color = {8'hAF, 8'hD7, 8'hFF};
		8'h9A: color = {8'hAF, 8'hFF, 8'h00};
		8'h9B: color = {8'hAF, 8'hFF, 8'h5F};
		8'h9C: color = {8'hAF, 8'hFF, 8'h87};
		8'h9D: color = {8'hAF, 8'hFF, 8'hAF};
		8'h9E: color = {8'hAF, 8'hFF, 8'hD7};
		8'h9F: color = {8'hAF, 8'hFF, 8'hFF};
		8'hA0: color = {8'hD7, 8'h00, 8'h00};
		8'hA1: color = {8'hD7, 8'h00, 8'h5F};
		8'hA2: color = {8'hD7, 8'h00, 8'h87};
		8'hA3: color = {8'hD7, 8'h00, 8'hAF};
		8'hA4: color = {8'hD7, 8'h00, 8'hD7};
		8'hA5: color = {8'hD7, 8'h00, 8'hFF};
		8'hA6: color = {8'hD7, 8'h5F, 8'h00};
		8'hA7: color = {8'hD7, 8'h5F, 8'h5F};
		8'hA8: color = {8'hD7, 8'h5F, 8'h87};
		8'hA9: color = {8'hD7, 8'h5F, 8'hAF};
		8'hAA: color = {8'hD7, 8'h5F, 8'hD7};
		8'hAB: color = {8'hD7, 8'h5F, 8'hFF};
		8'hAC: color = {8'hD7, 8'h87, 8'h00};
		8'hAD: color = {8'hD7, 8'h87, 8'h5F};
		8'hAE: color = {8'hD7, 8'h87, 8'h87};
		8'hAF: color = {8'hD7, 8'h87, 8'hAF};
		8'hB0: color = {8'hD7, 8'h87, 8'hD7};
		8'hB1: color = {8'hD7, 8'h87, 8'hFF};
		8'hB2: color = {8'hD7, 8'hAF, 8'h00};
		8'hB3: color = {8'hD7, 8'hAF, 8'h5F};
		8'hB4: color = {8'hD7, 8'hAF, 8'h87};
		8'hB5: color = {8'hD7, 8'hAF, 8'hAF};
		8'hB6: color = {8'hD7, 8'hAF, 8'hD7};
		8'hB7: color = {8'hD7, 8'hAF, 8'hFF};
		8'hB8: color = {8'hD7, 8'hD7, 8'h00};
		8'hB9: color = {8'hD7, 8'hD7, 8'h5F};
		8'hBA: color = {8'hD7, 8'hD7, 8'h87};
		8'hBB: color = {8'hD7, 8'hD7, 8'hAF};
		8'hBC: color = {8'hD7, 8'hD7, 8'hD7};
		8'hBD: color = {8'hD7, 8'hD7, 8'hFF};
		8'hBE: color = {8'hD7, 8'hFF, 8'h00};
		8'hBF: color = {8'hD7, 8'hFF, 8'h5F};
		8'hC0: color = {8'hD7, 8'hFF, 8'h87};
		8'hC1: color = {8'hD7, 8'hFF, 8'hAF};
		8'hC2: color = {8'hD7, 8'hFF, 8'hD7};
		8'hC3: color = {8'hD7, 8'hFF, 8'hFF};
		8'hC4: color = {8'hFF, 8'h00, 8'h00};
		8'hC5: color = {8'hFF, 8'h00, 8'h5F};
		8'hC6: color = {8'hFF, 8'h00, 8'h87};
		8'hC7: color = {8'hFF, 8'h00, 8'hAF};
		8'hC8: color = {8'hFF, 8'h00, 8'hD7};
		8'hC9: color = {8'hFF, 8'h00, 8'hFF};
		8'hCA: color = {8'hFF, 8'h5F, 8'h00};
		8'hCB: color = {8'hFF, 8'h5F, 8'h5F};
		8'hCC: color = {8'hFF, 8'h5F, 8'h87};
		8'hCD: color = {8'hFF, 8'h5F, 8'hAF};
		8'hCE: color = {8'hFF, 8'h5F, 8'hD7};
		8'hCF: color = {8'hFF, 8'h5F, 8'hFF};
		8'hD0: color = {8'hFF, 8'h87, 8'h00};
		8'hD1: color = {8'hFF, 8'h87, 8'h5F};
		8'hD2: color = {8'hFF, 8'h87, 8'h87};
		8'hD3: color = {8'hFF, 8'h87, 8'hAF};
		8'hD4: color = {8'hFF, 8'h87, 8'hD7};
		8'hD5: color = {8'hFF, 8'h87, 8'hFF};
		8'hD6: color = {8'hFF, 8'hAF, 8'h00};
		8'hD7: color = {8'hFF, 8'hAF, 8'h5F};
		8'hD8: color = {8'hFF, 8'hAF, 8'h87};
		8'hD9: color = {8'hFF, 8'hAF, 8'hAF};
		8'hDA: color = {8'hFF, 8'hAF, 8'hD7};
		8'hDB: color = {8'hFF, 8'hAF, 8'hFF};
		8'hDC: color = {8'hFF, 8'hD7, 8'h00};
		8'hDD: color = {8'hFF, 8'hD7, 8'h5F};
		8'hDE: color = {8'hFF, 8'hD7, 8'h87};
		8'hDF: color = {8'hFF, 8'hD7, 8'hAF};
		8'hE0: color = {8'hFF, 8'hD7, 8'hD7};
		8'hE1: color = {8'hFF, 8'hD7, 8'hFF};
		8'hE2: color = {8'hFF, 8'hFF, 8'h00};
		8'hE3: color = {8'hFF, 8'hFF, 8'h5F};
		8'hE4: color = {8'hFF, 8'hFF, 8'h87};
		8'hE5: color = {8'hFF, 8'hFF, 8'hAF};
		8'hE6: color = {8'hFF, 8'hFF, 8'hD7};
		8'hE7: color = {8'hFF, 8'hFF, 8'hFF}; // white
		// grayscale colors:
`ifdef ARITHMETIC_ANSI_GRAYSCALE
		// arithmetic grayscale level derivation forces optimized
		// Boolean logic, and inhibits (24-bit) ROM inference:
		8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC, 8'hED, 8'hEE, 8'hEF,
		8'hF0, 8'hF1, 8'hF2, 8'hF3, 8'hF4, 8'hF5, 8'hF6, 8'hF7,
		8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD, 8'hFE, 8'hFF:
			color = {gsc_lvl, gsc_lvl, gsc_lvl};
`else // not ARITHMETIC_ANSI_GRAYSCALE
		// NOTE: having a fully-enumerated unique case will cause
		// Quartus to (try, unsuccessfully) to infer a 24-bit ROM!
		8'hE8: color = {8'h0A, 8'h0A, 8'h0A};
		8'hE9: color = {8'h14, 8'h14, 8'h14};
		8'hEA: color = {8'h1E, 8'h1E, 8'h1E};
		8'hEB: color = {8'h28, 8'h28, 8'h28};
		8'hEC: color = {8'h32, 8'h32, 8'h32};
		8'hED: color = {8'h3C, 8'h3C, 8'h3C};
		8'hEE: color = {8'h46, 8'h46, 8'h46};
		8'hEF: color = {8'h50, 8'h50, 8'h50};
		8'hF0: color = {8'h5A, 8'h5A, 8'h5A};
		8'hF1: color = {8'h64, 8'h64, 8'h64};
		8'hF2: color = {8'h6E, 8'h6E, 8'h6E};
		8'hF3: color = {8'h78, 8'h78, 8'h78};
		8'hF4: color = {8'h82, 8'h82, 8'h82};
		8'hF5: color = {8'h8C, 8'h8C, 8'h8C};
		8'hF6: color = {8'h96, 8'h96, 8'h96};
		8'hF7: color = {8'hA0, 8'hA0, 8'hA0};
		8'hF8: color = {8'hAA, 8'hAA, 8'hAA};
		8'hF9: color = {8'hB4, 8'hB4, 8'hB4};
		8'hFA: color = {8'hBE, 8'hBE, 8'hBE};
		8'hFB: color = {8'hC8, 8'hC8, 8'hC8};
		8'hFC: color = {8'hD2, 8'hD2, 8'hD2};
		8'hFD: color = {8'hDC, 8'hDC, 8'hDC};
		8'hFE: color = {8'hE6, 8'hE6, 8'hE6};
		8'hFF: color = {8'hF0, 8'hF0, 8'hF0};
`endif // ARITHMETIC_ANSI_GRAYSCALE
		endcase
	end

endmodule: palette_comb_old

`ifdef TBPALETTE
// // verilator --binary -DTBPALETTE --top tbpalette ansi_palette.sv
module tbpalette ();
	logic clk;
	logic [7:0] index;
	video_pkg::vga_rgb_t   color;

	palette_comb inst_palette_comb (
		.index(index),
		.color(color)
	);

	always #5 clk <= ~clk;

	initial begin
		clk = 0;
		index = 0;
		repeat (256) begin
			@(posedge clk);
`ifdef ARITHMETIC_ANSI_GRAYSCALE
			$display("%h:%h%h%h %b", index,
				color.r, color.g, color.b,
				inst_palette_comb.gsc_idx);
`else // not ARITHMETIC_ANSI_GRAYSCALE
			$display("%h:%h%h%h", index, color.r, color.g, color.b);
`endif // ARITHMETIC_ANSI_GRAYSCALE
			index++;
		end
		$finish;
	end

endmodule: tbpalette
`endif // TBPALETTE
