// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`default_nettype none

// dynamically select a `slice` from a bit `vector`, based on a given `index`
module vec_slice_sel #(
	parameter SL = 12, // slice width
	parameter NS =  6, // number of slices
	parameter MSF = 1  // direction (vec[0]=MSS if 1; vec[0]=LSS if 0;)
) (
	input  logic      [NS*SL-1:0] vector, // [VW-1:0]
	input  logic [$clog2(NS)-1:0] index,  // [IW-1:0]
	output logic         [SL-1:0] slice
);

	// NOTE: Quartus 25.1std doesn't allow these before the i/o list,
	// but at least we get to use them within the module body:
	localparam
		VW = NS * SL,    // vector width
		IW = $clog2(NS); // index width

	// unpacked intermediate array of slices:
	logic [SL-1:0] array[NS];
	generate
		genvar i;
		for (i = 0; i < NS; i++) begin : vector2array
			if (MSF) begin
				assign array[i] = vector[VW-(i*SL+1) -: SL];
			end else begin
				assign array[i] = vector[i*SL +: SL];
			end
		end
	endgenerate

	// select slice as per `index`:
	always_comb begin
		slice = SL'('hXX);
		for (int i = 0; i < NS; i++) begin
			if (index == IW'(i)) begin
				slice = array[i];
			end
		end
	end

endmodule: vec_slice_sel

`ifdef TB_SLICE
// // verilator --binary -DTB_SLICE --top tb_slice vec_slice_sel.sv
// // iverilog -g2005-sv -DTB_SLICE -s tb_slice -o tb_slice vec_slice_sel.sv
module tb_slice ();

	localparam
		SL = 8, // slice width
		NS = 5; // number of slices

	localparam IW = $clog2(NS); // index width
	localparam VW = NS * SL;    // vector width

	logic clk;
	always #5 clk <= ~clk;

	logic [VW-1:0] vector;
	logic [IW-1:0] index;
	logic [SL-1:0] slice_dn, slice_up;

	// DUT:
	vec_slice_sel #(
		.SL(SL),
		.NS(NS),
		.MSF(0)
	) dut_dn (
		.vector(vector),
		.index(index),
		.slice(slice_dn)
	);
	vec_slice_sel #(
		.SL(SL),
		.NS(NS),
		.MSF(1)
	) dut_up (
		.vector(vector),
		.index(index),
		.slice(slice_up)
	);

	initial begin
		clk = 0;
		// dn:       4      3      2      1      0
		//           ↓      ↓      ↓      ↓      ↓
		vector = {8'hAB, 8'hBC, 8'hCD, 8'hDE, 8'hEF};
		//           ↑      ↑      ↑      ↑      ↑
		// up:       0      1      2      3      4
		repeat (128) begin
			@(posedge clk);
			$display("idx=%0h, dn=%0h, up=%0h",
				 index, slice_dn, slice_up);
`ifdef VERILATOR
			index = $random[IW-1:0];
`else
			index = $random;
`endif
		end
		$finish;
	end

endmodule: tb_slice
`endif // TB_SLICE
