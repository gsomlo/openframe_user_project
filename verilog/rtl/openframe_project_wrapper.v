// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

// make a multi-tile ROM (4 x 9, i.e., 4096 x 72bit):
module cf_rom_sync_grid #(
	parameter TDW =  8, // tile (bank) data width
	parameter TAW = 10, // tile (bank) address width
	parameter AAW =  2, // additional address width (in bits)
	parameter NCOL = 9  // number of horizontal tiles (i.e., "columns")
) (
	input wire L0,
	input wire L1,
`ifdef USE_POWER_PINS
	input  wire                vpwr,
	input  wire                vgnd,
`endif // USE_POWER_PINS
	output wire [NCOL*TDW-1:0] DO,
	input  wire  [AAW+TAW-1:0] A,
	input  wire                CLK
);

	localparam NROW = 1 << AAW;

	// one-hot decoder:
	wire [AAW-1:0] row_adr;
	assign row_adr = A[AAW+TAW-1:TAW];
	reg [NROW-1:0] row_oe;
	always @(posedge CLK) begin // always_ff
		row_oe <= {NROW{L0}};
		row_oe[row_adr] <= L1;
	end

	generate
		genvar row, col;
		for (row = 0; row < NROW; row++) begin : r
			for (col = 0; col < NCOL; col++) begin : c
				CF_ROM_SYNC rom_tile (
`ifdef USE_POWER_PINS
					.vpwr(vpwr),
					.vgnd(vgnd),
`endif // USE_POWER_PINS
					.DO(DO[(col+1)*TDW-1:col*TDW]),
					.A(A[TAW-1:0]),
					.EN(L1),  // always enabled
					.CLK(CLK),
					.RST(L0), // never needs reset
					.OE(row_oe[row])
				);
			end
		end
	endgenerate
endmodule

// make a multi-tile RAM (8 x 2, i.e., 8192 x 64bit):
module cf_sram_grid #(
	parameter TDW = 32, // tile (bank) data width
	parameter TAW = 10, // tile (bank) address width
	parameter AAW =  3, // additional address width (in bits)
	parameter NCOL = 2  // number of horizontal tiles (i.e., "columns)
) (
	input wire L0,
	input wire L1,
`ifdef USE_POWER_PINS
	input  wire                vpwr,
	input  wire                vgnd,
`endif // USE_POWER_PINS
	output wire [NCOL*TDW-1:0] DO,
	input  wire [NCOL*TDW-1:0] DI,
	input  wire  [AAW+TAW-1:0] AD,
	input  wire                wren, // ~R_WB
	input  wire                CLKin
);

	localparam NROW = 1 << AAW;

	// one-hot decoder:
	wire [AAW-1:0] row_adr;
	assign row_adr = AD[AAW+TAW-1:TAW];
	reg [NROW-1:0] row_sel; // enable row matching current cycle req.
	always @* begin
		row_sel = {NROW{L0}};
		row_sel[row_adr] = L1;
	end
	reg [NROW-1:0] row_sel_reg; // output selected by *previous* cycle req.
	always @(posedge CLKin) begin
		row_sel_reg <= row_sel;
	end

	// collect output from each row:
	wire [NCOL*TDW-1:0] RDO [0:NROW-1];

	generate
		genvar row, col;
		for (row = 0; row < NROW; row++) begin : r
			for (col = 0; col < NCOL; col++) begin : c
				CF_SRAM_1024x32 sram_tile (
`ifdef USE_POWER_PINS
					.vgnd(vgnd),
					.vnb(vgnd),
					.vpb(vpwr),
					.vpwra(vpwr),
					.vpwrm(vpwr),
					.vpwrp(vpwr),
`endif // USE_POWER_PINS
					.vpwrac(L1),
					.vpwrpc(L1),

					.DO(RDO[row][(col+1)*TDW-1:col*TDW]),
					.ScanOutCC(),      // ignore
					.AD(AD[TAW-1:0]),
					.BEN({TDW{L1}}), // always full enable
					.CLKin(CLKin),
					.DI(DI[(col+1)*TDW-1:col*TDW]),
					.EN(row_sel[row]),
					.R_WB(~wren),
					// disable all inputs below this point:
					.ScanInCC(L0),
					.ScanInDL(L0),
					.ScanInDR(L0),
					.SM(L0),
					.TM(L0),
					.WLBI(L0),
					.WLOFF(L0)
				);
			end
		end
	endgenerate

	// output row selected by prev. cycle's request (AD -> row_sel_reg):
	reg [NCOL*TDW-1:0] comb_do;
	int i;
	always @* begin
		comb_do = {(NCOL*TDW){L0}};
		for (i = 0; i < NROW; i++) begin
			comb_do = comb_do |
				  (RDO[i] & {(NCOL*TDW){row_sel_reg[i]}});
		end
	end
	assign DO = comb_do;

endmodule

/*
 *-------------------------------------------------------------
 *
 * openframe_project_wrapper
 *
 * This wrapper enumerates all of the pins available to the
 * user for the user openframe project.
 *
 * Written by Tim Edwards
 * March 27, 2023
 * Efabless Corporation
 *
 *-------------------------------------------------------------
 */
module openframe_project_wrapper (
`ifdef USE_POWER_PINS
    inout vdda,		// User area 0 3.3V supply
    inout vdda1,	// User area 1 3.3V supply
    inout vdda2,	// User area 2 3.3V supply
    inout vssa,		// User area 0 analog ground
    inout vssa1,	// User area 1 analog ground
    inout vssa2,	// User area 2 analog ground
    inout vccd,		// Common 1.8V supply
    inout vccd1,	// User area 1 1.8V supply
    inout vccd2,	// User area 2 1.8v supply
    inout vssd,		// Common digital ground
    inout vssd1,	// User area 1 digital ground
    inout vssd2,	// User area 2 digital ground
    inout vddio,	// Common 3.3V ESD supply
    inout vssio,	// Common ESD ground
`endif

    /* Signals exported from the frame area to the user project */
    /* The user may elect to use any of these inputs.		*/

    input	 porb_h,	// power-on reset, sense inverted, 3.3V domain
    input	 porb_l,	// power-on reset, sense inverted, 1.8V domain
    input	 por_l,		// power-on reset, noninverted, 1.8V domain
    input	 resetb_h,	// master reset, sense inverted, 3.3V domain
    input	 resetb_l,	// master reset, sense inverted, 1.8V domain
    input [31:0] mask_rev,	// 32-bit user ID, 1.8V domain

    /* GPIOs.  There are 44 GPIOs (19 left, 19 right, 6 bottom). */
    /* These must be configured appropriately by the user project. */

    /* Basic bidirectional I/O.  Input gpio_in_h is in the 3.3V domain;  all
     * others are in the 1.8v domain.  OEB is output enable, sense inverted.
     */
    input  [`OPENFRAME_IO_PADS-1:0] gpio_in,
    input  [`OPENFRAME_IO_PADS-1:0] gpio_in_h,
    output [`OPENFRAME_IO_PADS-1:0] gpio_out,
    output [`OPENFRAME_IO_PADS-1:0] gpio_oeb,
    output [`OPENFRAME_IO_PADS-1:0] gpio_inp_dis,	// a.k.a. ieb

    /* Pad configuration.  These signals are usually static values.
     * See the documentation for the sky130_fd_io__gpiov2 cell signals
     * and their use.
     */
    output [`OPENFRAME_IO_PADS-1:0] gpio_ib_mode_sel,
    output [`OPENFRAME_IO_PADS-1:0] gpio_vtrip_sel,
    output [`OPENFRAME_IO_PADS-1:0] gpio_slow_sel,
    output [`OPENFRAME_IO_PADS-1:0] gpio_holdover,
    output [`OPENFRAME_IO_PADS-1:0] gpio_analog_en,
    output [`OPENFRAME_IO_PADS-1:0] gpio_analog_sel,
    output [`OPENFRAME_IO_PADS-1:0] gpio_analog_pol,
    output [`OPENFRAME_IO_PADS-1:0] gpio_dm2,
    output [`OPENFRAME_IO_PADS-1:0] gpio_dm1,
    output [`OPENFRAME_IO_PADS-1:0] gpio_dm0,

    /* These signals correct directly to the pad.  Pads using analog I/O
     * connections should keep the digital input and output buffers turned
     * off.  Both signals connect to the same pad.  The "noesd" signal
     * is a direct connection to the pad;  the other signal connects through
     * a series resistor which gives it minimal ESD protection.  Both signals
     * have basic over- and under-voltage protection at the pad.  These
     * signals may be expected to attenuate heavily above 50MHz.
     */
    inout  [`OPENFRAME_IO_PADS-1:0] analog_io,
    inout  [`OPENFRAME_IO_PADS-1:0] analog_noesd_io,

    /* These signals are constant one and zero in the 1.8V domain, one for
     * each GPIO pad, and can be looped back to the control signals on the
     * same GPIO pad to set a static configuration at power-up.
     */
    input  [`OPENFRAME_IO_PADS-1:0] gpio_loopback_one,
    input  [`OPENFRAME_IO_PADS-1:0] gpio_loopback_zero
);
        wire clk;
	wire rst;
	wire  [3:0] midterm_in;
	wire [28:0] midterm_out;

	wire [11:0] rom_addr;
	wire [71:0] rom_data;

	wire [12:0] ram_addr;
	wire        ram_wren;
	wire [39:0] ram_wdata;
	wire [39:0] ram_rdata;

	    /* NOTE:  Openframe signals not used in picosoc:	*/
	    /* porb_h:    3.3V domain signal			*/
	    /* resetb_h:  3.3V domain signal			*/
	    /* gpio_in_h: 3.3V domain signals			*/
	    /* analog_io: analog signals			*/
	    /* analog_noesd_io: analog signals			*/

	// main project module:
	user_proj_midterm mprj (
`ifdef USE_POWER_PINS
		.vccd1(vccd1),
		.vssd1(vssd1),
`endif // USE_POWER_PINS
		.wb_clk_i(clk),
		.wb_rst_i(rst),

		.io_in(midterm_in),
		.io_out(midterm_out),

		.rom_addr(rom_addr),
		.rom_data(rom_data),

		.ram_addr(ram_addr),
		.ram_wren(ram_wren),
		.ram_wdata(ram_wdata),
		.ram_rdata(ram_rdata)
	);

	// memory module(s):
	cf_rom_sync_grid rom_grid (
		.L0(gpio_loopback_zero[0]),
		.L1(gpio_loopback_one[0]),
`ifdef USE_POWER_PINS
		.vpwr(vccd1),
		.vgnd(vssd1),
`endif
		.DO(rom_data),
		.A(rom_addr),
		.CLK(clk)
	);
	cf_sram_grid sram_grid (
		.L0(gpio_loopback_zero[0]),
		.L1(gpio_loopback_one[0]),
`ifdef USE_POWER_PINS
		.vpwr(vccd1),
		.vgnd(vssd1),
`endif // USE_POWER_PINS
		.DO(ram_rdata),
		.DI(ram_wdata),
		.AD(ram_addr),
		.wren(ram_wren),
		.CLKin(clk)
	);

	(* keep *) vccd1_connection vccd1_connection ();
	(* keep *) vssd1_connection vssd1_connection ();

	// CF_gpio_config modes
	// 0: analog
	// 1: input
	// 2: input pull down
	// 3: input pull up
	// 4: output
	// 5: bidirectional

        CF_gpio_config #(.MODE(3'd1)) gpio_clk_config ( // clk input at gpio 0
          .io_out(),
          .io_in(clk),
          .io_oeb(),
          .gpio_zero(gpio_loopback_zero[0]),
          .gpio_one(gpio_loopback_one[0]),
          .gpio_in(gpio_in[0]),
          .gpio_dm({gpio_dm2[0], gpio_dm1[0], gpio_dm0[0]}),
          .gpio_inp_dis(gpio_inp_dis[0]),
          .gpio_oeb_out(gpio_oeb[0]),
          .gpio_out_val(gpio_out[0]),
          .gpio_analog_en(gpio_analog_en[0]),
          .gpio_analog_sel(gpio_analog_sel[0]),
          .gpio_analog_pol(gpio_analog_pol[0]),
          .gpio_ib_mode_sel(gpio_ib_mode_sel[0]),
          .gpio_vtrip_sel(gpio_vtrip_sel[0]),
          .gpio_slow_sel(gpio_slow_sel[0]),
          .gpio_holdover(gpio_holdover[0])
        );
        
	CF_gpio_config #(.MODE(3'd2)) gpio_rst_config ( // rst pdown in @ gpio 1
          .io_out(),
          .io_in(rst),
          .io_oeb(),
          .gpio_zero(gpio_loopback_zero[1]),
          .gpio_one(gpio_loopback_one[1]),
          .gpio_in(gpio_in[1]),
          .gpio_dm({gpio_dm2[1], gpio_dm1[1], gpio_dm0[1]}),
          .gpio_inp_dis(gpio_inp_dis[1]),
          .gpio_oeb_out(gpio_oeb[1]),
          .gpio_out_val(gpio_out[1]),
          .gpio_analog_en(gpio_analog_en[1]),
          .gpio_analog_sel(gpio_analog_sel[1]),
          .gpio_analog_pol(gpio_analog_pol[1]),
          .gpio_ib_mode_sel(gpio_ib_mode_sel[1]),
          .gpio_vtrip_sel(gpio_vtrip_sel[1]),
          .gpio_slow_sel(gpio_slow_sel[1]),
          .gpio_holdover(gpio_holdover[1])
        );

	genvar i;

        generate
          for (i = 0; i < 4; i++) begin : gpio_in_cfg
            CF_gpio_config #(.MODE(3'd1)) gpio_in_config (
              .io_out(),
              .io_in(midterm_in[i]),
              .io_oeb(),
              .gpio_zero(gpio_loopback_zero[i + 2]),
              .gpio_one(gpio_loopback_one[i + 2]),
              .gpio_in(gpio_in[i + 2]),
              .gpio_dm({gpio_dm2[i + 2], gpio_dm1[i + 2], gpio_dm0[i + 2]}),
              .gpio_inp_dis(gpio_inp_dis[i + 2]),
              .gpio_oeb_out(gpio_oeb[i + 2]),
              .gpio_out_val(gpio_out[i + 2]),
              .gpio_analog_en(gpio_analog_en[i + 2]),
              .gpio_analog_sel(gpio_analog_sel[i + 2]),
              .gpio_analog_pol(gpio_analog_pol[i + 2]),
              .gpio_ib_mode_sel(gpio_ib_mode_sel[i + 2]),
              .gpio_vtrip_sel(gpio_vtrip_sel[i + 2]),
              .gpio_slow_sel(gpio_slow_sel[i + 2]),
              .gpio_holdover(gpio_holdover[i + 2])
            );
          end
        endgenerate

        generate
          for (i = 0; i < 29; i++) begin : gpio_out_cfg
            CF_gpio_config #(.MODE(3'd4)) gpio_out_config (
              .io_out(midterm_out[i]),
              .io_in(),
              .io_oeb(),
              .gpio_zero(gpio_loopback_zero[i + 6]),
              .gpio_one(gpio_loopback_one[i + 6]),
              .gpio_in(gpio_in[i + 6]),
              .gpio_dm({gpio_dm2[i + 6], gpio_dm1[i + 6], gpio_dm0[i + 6]}),
              .gpio_inp_dis(gpio_inp_dis[i + 6]),
              .gpio_oeb_out(gpio_oeb[i + 6]),
              .gpio_out_val(gpio_out[i + 6]),
              .gpio_analog_en(gpio_analog_en[i + 6]),
              .gpio_analog_sel(gpio_analog_sel[i + 6]),
              .gpio_analog_pol(gpio_analog_pol[i + 6]),
              .gpio_ib_mode_sel(gpio_ib_mode_sel[i + 6]),
              .gpio_vtrip_sel(gpio_vtrip_sel[i + 6]),
              .gpio_slow_sel(gpio_slow_sel[i + 6]),
              .gpio_holdover(gpio_holdover[i + 6])
            );
          end
        endgenerate

        generate
          for (i = 35; i < `OPENFRAME_IO_PADS; i++) begin : gpio_unused_cfg
            CF_gpio_config #(.MODE(3'd0)) gpio_u_cfg (
              .io_out(),
              .io_in(),
              .io_oeb(),
              .gpio_zero(gpio_loopback_zero[i]),
              .gpio_one(gpio_loopback_one[i]),
              .gpio_in(gpio_in[i]),
              .gpio_dm({gpio_dm2[i], gpio_dm1[i], gpio_dm0[i]}),
              .gpio_inp_dis(gpio_inp_dis[i]),
              .gpio_oeb_out(gpio_oeb[i]),
              .gpio_out_val(gpio_out[i]),
              .gpio_analog_en(gpio_analog_en[i]),
              .gpio_analog_sel(gpio_analog_sel[i]),
              .gpio_analog_pol(gpio_analog_pol[i]),
              .gpio_ib_mode_sel(gpio_ib_mode_sel[i]),
              .gpio_vtrip_sel(gpio_vtrip_sel[i]),
              .gpio_slow_sel(gpio_slow_sel[i]),
              .gpio_holdover(gpio_holdover[i])
            );
          end
        endgenerate

endmodule	// openframe_project_wrapper
