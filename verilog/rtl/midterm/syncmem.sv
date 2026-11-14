// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

// Ready/Valid wrapper around synchronous (ROM, RAM) memory
//
//         ┌─────────────────────────────────────────────┐
//         │               ┌─────────────┐        RV_ROM │
//         │               │     ROM     │               │
//   ──/──>│ i_addr    ─/─>│ addr  rdata ├─/─>   o_rdata ├──/──>
//   ─────>│ i_valid       └─────────────┘       o_valid ├─────>
//   <─────┤ i_ready                             o_ready │<─────
//         │                                             │
//   ──/──>│ i_ptdat     ...pass-thru data...    o_ptdat ├──/──>
//         └─────────────────────────────────────────────┘
//         ┌─────────────────────────────────────────────┐
//         │               ┌─────────────┐        RV_RAM │
//         │               │     RAM     │               │
//   ──/──>│ i_addr    ─/─>│ addr        │               │
//   ─────>│ i_wren    ───>│ wren        │               │
//   ──/──>│ i_wdata   ─/─>│ wdata rdata ├─/─>   o_rdata ├──/──>
//   ─────>│ i_valid       └─────────────┘       o_valid ├─────>
//   <─────┤ i_ready                             o_ready │<─────
//         │                                             │
//   ──/──>│ i_ptdat     ...pass-thru data...    o_ptdat ├──/──>
//         └─────────────────────────────────────────────┘

// synchronous ROM:
// NOTE: behavioral model only: use "as-is", treat as a "black-box";
//       assume that no "improvements" are allowed to "facilitate"
//       easier implementation of the ready/valid wrapper!!!
module sync_rom #(
	parameter FN = "",
	parameter AW = 8,
	parameter DW = 32
)(
	input  logic [AW-1:0] addr,
	output logic [DW-1:0] rdata,
	input  logic          clk
);

	// size of memory array (number of words):
	localparam NUMW = 2 ** AW;

	// memory array:
	logic [DW-1:0] mem[0:NUMW-1];

	// initialization:
	initial begin
		if ($bits(FN) > 8)
			$readmemh(FN, mem);
		else
			// ensure (addr == data) to facilitate debugging:
			/* verilator lint_off WIDTHEXPAND */
			/* verilator lint_off WIDTHTRUNC */
			for (int i = 0; i < NUMW; i++)
				mem[i] = i;
	end

	// synchronous read on each clock edge:
	always_ff @(posedge clk) begin
		rdata <= mem[addr];
	end

endmodule: sync_rom

// synchronous RAM:
// NOTE: behavioral model only: use "as-is", treat as a "black-box";
//       assume that no "improvements" are allowed to "facilitate"
//       easier implementation of the ready/valid wrapper!!!
module sync_ram #(
	parameter FN = "",
	parameter AW = 8,
	parameter DW = 32
)(
	input  logic [AW-1:0] addr,
	input  logic          wren,
	input  logic [DW-1:0] wdata,
	output logic [DW-1:0] rdata,
	input  logic          clk
);

	// size of memory array (number of words):
	localparam NUMW = 2 ** AW;

	// memory array:
	logic [DW-1:0] mem[0:NUMW-1];

	// initialization:
	initial begin
		if ($bits(FN) > 8)
			$readmemh(FN, mem);
		else
			// ensure (addr == data) to facilitate debugging:
			/* verilator lint_off WIDTHEXPAND */
			/* verilator lint_off WIDTHTRUNC */
			for (int i = 0; i < NUMW; i++)
				mem[i] = i;
	end

	// synchronous write/read on each clock edge:
	always_ff @(posedge clk) begin
		if (wren) begin
			mem[addr] <= wdata;
		end
		rdata <= mem[addr];
	end

endmodule: sync_ram

// ready/valid wrapper around synchronous ROM:
module ready_valid_srom #(
	parameter FN = "",
	parameter AW = 8,
	parameter DW = 32,
	parameter TW = 16  // pass-thru data width
)(
	// upstream/input/slave interface (address):
	input  logic [AW-1:0] i_addr,
	input  logic          i_valid,
	output logic          i_ready,
	input  logic [TW-1:0] i_ptdat,

	// downstream/output/master interface (data):
	output logic [DW-1:0] o_rdata,
	output logic          o_valid,
	input  logic          o_ready,
	output logic [TW-1:0] o_ptdat,

	input  logic clk,
	input  logic rst
);

	// intermediate ROM wires:
	logic [DW-1:0] rom_rdata;
	logic          rom_valid;

	// pass-thru data delay register:
	logic [TW-1:0] rom_ptdat;

	// sequentially keep track of input conditions:
	always_ff @(posedge clk) begin
		if (rst) begin
			rom_valid <= 0;
			rom_ptdat <= 0;
		end else begin
			// `rom_valid` is 1 clk cycle behind input handshake:
			rom_valid <= i_valid & i_ready;
			// maintain pass-thru data during memory lookup cycle:
			rom_ptdat <= i_ptdat;
		end
	end

	// ROM instance:
	sync_rom #(
		.FN(FN),
		.AW(AW),
		.DW(DW)
	) inst_sync_rom (
		.addr(i_addr),
		.rdata(rom_rdata),
		.clk(clk)
	);

	// valid/ready "lookahead" sync fifo instance:
	valid_ready_sync_fifo #(
		.DW(DW+TW),
		.PW(2), // correct but suboptimal throughput at .PW(1)
		.ENABLE_I_READY_2(1) // `i_ready` = min. *two* free fifo slots!
	) inst_lookahead_sync_fifo_simple (
		.i_data({rom_rdata, rom_ptdat}),
		.i_valid(rom_valid),
		.i_ready(i_ready), // at least *two* free fifo slots !
		.o_data({o_rdata, o_ptdat}),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

endmodule: ready_valid_srom

// ready/valid wrapper around synchronous RAM:
module ready_valid_sram #(
	parameter FN = "",
	parameter AW = 8,
	parameter DW = 32,
	parameter TW = 16  // pass-thru data width
)(
	// upstream/input/slave interface (address, wren, wdata):
	input  logic [AW-1:0] i_addr,
	input  logic          i_wren,
	input  logic [DW-1:0] i_wdata,
	input  logic          i_valid,
	output logic          i_ready,
	input  logic [TW-1:0] i_ptdat,

	// downstream/output/master interface (rdata):
	output logic [DW-1:0] o_rdata,
	output logic          o_valid,
	input  logic          o_ready,
	output logic [TW-1:0] o_ptdat,

	input  logic clk,
	input  logic rst
);

	// intermediate RAM wires:
	logic [DW-1:0] ram_rdata;
	logic          ram_valid;

	// pass-thru data delay register:
	logic [TW-1:0] ram_ptdat;

	// lookahead ">= 2 free fifo slots" read-ready signal:
	logic rd_rdy_2;

	// `i_ready` is always true for writes, depends on fifo for reads:
	assign i_ready = i_wren | rd_rdy_2;

	// input handshake conditions:
	logic i_rd_handshake, i_wr_handshake;
	assign i_rd_handshake = ~i_wren & i_valid & rd_rdy_2;
	assign i_wr_handshake =  i_wren & i_valid;

	// sequentially keep track of input conditions:
	always_ff @(posedge clk) begin
		if (rst) begin
			ram_valid <= 0;
			ram_ptdat <= 0;
		end else begin
			// `ram_valid` is 1 clk cycle behind inp. rd handshake:
			ram_valid <= i_rd_handshake;
			// maintain pass-thru data during memory lookup cycle:
			ram_ptdat <= i_ptdat;
		end
	end

	// RAM instance:
	sync_ram #(
		.FN(FN),
		.AW(AW),
		.DW(DW)
	) inst_sync_ram (
		.addr(i_addr),
		.wren(i_wr_handshake),
		.wdata(i_wdata),
		.rdata(ram_rdata),
		.clk(clk)
	);

	// valid/ready "lookahead" sync fifo instance:
	valid_ready_sync_fifo #(
		.DW(DW+TW),
		.PW(2), // correct but suboptimal throughput at .PW(1)
		.ENABLE_I_READY_2(1) // `i_ready` = min. *two* free fifo slots!
	) inst_lookahead_sync_fifo_simple (
		.i_data({ram_rdata, ram_ptdat}),
		.i_valid(ram_valid),
		.i_ready(rd_rdy_2), // at least *two* free fifo slots !
		.o_data({o_rdata, o_ptdat}),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

endmodule: ready_valid_sram

// ready/valid wrapper around *external* synchronous RAM:
module ready_valid_sram_ext #(
	parameter AW = 8,
	parameter DW = 32,
	parameter TW = 16  // pass-thru data width
)(
	// upstream/input/slave interface (address, wren, wdata):
	input  logic [AW-1:0] i_addr,
	input  logic          i_wren,
	input  logic [DW-1:0] i_wdata,
	input  logic          i_valid,
	output logic          i_ready,
	input  logic [TW-1:0] i_ptdat,

	// downstream/output/master interface (rdata):
	output logic [DW-1:0] o_rdata,
	output logic          o_valid,
	input  logic          o_ready,
	output logic [TW-1:0] o_ptdat,

	// RAM interface:
	output logic [AW-1:0] ram_addr,
	output logic          ram_wren,
	output logic [DW-1:0] ram_wdata,
	input  logic [DW-1:0] ram_rdata,

	input  logic clk,
	input  logic rst
);

	// intermediate RAM wires:
	logic          ram_valid;

	// pass-thru data delay register:
	logic [TW-1:0] ram_ptdat;

	// lookahead ">= 2 free fifo slots" read-ready signal:
	logic rd_rdy_2;

	// `i_ready` is always true for writes, depends on fifo for reads:
	assign i_ready = i_wren | rd_rdy_2;

	// input handshake conditions:
	logic i_rd_handshake, i_wr_handshake;
	assign i_rd_handshake = ~i_wren & i_valid & rd_rdy_2;
	assign i_wr_handshake =  i_wren & i_valid;

	assign ram_addr  = i_addr;
	assign ram_wren  = i_wr_handshake;
	assign ram_wdata = i_wdata;

	// sequentially keep track of input conditions:
	always_ff @(posedge clk) begin
		if (rst) begin
			ram_valid <= 0;
			ram_ptdat <= 0;
		end else begin
			// `ram_valid` is 1 clk cycle behind inp. rd handshake:
			ram_valid <= i_rd_handshake;
			// maintain pass-thru data during memory lookup cycle:
			ram_ptdat <= i_ptdat;
		end
	end

	// valid/ready "lookahead" sync fifo instance:
	valid_ready_sync_fifo #(
		.DW(DW+TW),
		.PW(2), // correct but suboptimal throughput at .PW(1)
		.ENABLE_I_READY_2(1) // `i_ready` = min. *two* free fifo slots!
	) inst_lookahead_sync_fifo_simple (
		.i_data({ram_rdata, ram_ptdat}),
		.i_valid(ram_valid),
		.i_ready(rd_rdy_2), // at least *two* free fifo slots !
		.o_data({o_rdata, o_ptdat}),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

endmodule: ready_valid_sram_ext

// valid/ready FIFO implemented with single-ported SRAM:
module vr_fifo_sram #(
	parameter DW = 32,
	parameter PW = 8
) (
	// input/write interface:
	input  logic [DW-1:0] i_data,
	input  logic          i_valid,
	output logic          i_ready,
	// output/read interface:
	output logic [DW-1:0] o_data,
	output logic          o_valid,
	input  logic          o_ready,
	// ctrl:
	input logic clk,
	input logic rst
);

	// write and read pointers:
	logic [PW-1:0] wptr, rptr, wptrNext, rptrNext;

	// utilization counter, "not empty" and `i_ready` ("not full") signals:
	logic [PW:0] util, utilNext;
	logic not_empty;
	assign not_empty = |util;   // (util > 0)
	assign i_ready   = ~util[PW]; // (util < 2**PW) -- only checking MSB

	// input handshake:
	logic i_handshake;
	assign i_handshake = i_valid & i_ready;

	// handover between SRAM and "short lookahead" FIFO:
	logic [DW-1:0] ram_data;
	logic ram_rdy_2, ram_valid, ram_validNext;

	// SRAM instance:
	sync_ram #(
		.AW(PW),
		.DW(DW)
	) inst_sync_ram (
		.addr(i_handshake ? wptr : rptr),
		.wren(i_handshake),
		.wdata(i_data),
		.rdata(ram_data),
		.clk(clk)
	);

	// valid/ready "lookahead" sync "short" fifo instance:
	valid_ready_sync_fifo #(
		.DW(DW),
		.PW(2),
		.ENABLE_I_READY_2(1) // `i_ready` = min. *two* free fifo slots!
	) inst_lookahead_sync_fifo_simple (
		.i_data(ram_data),
		.i_valid(ram_valid),
		.i_ready(ram_rdy_2), // at least *two* free fifo slots !
		.o_data(o_data),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// combinational logic:
	always_comb begin
		// by default, keep register values steady:
		wptrNext = wptr;
		rptrNext = rptr;
		utilNext = util;
		// by default, SRAM read output not valid:
		ram_validNext = 0;

		// prefer writes (writes & reads are mutually exclusive):
		if (i_handshake) begin
			wptrNext = wptr + 1;
			utilNext = util + 1;
		end else if (not_empty & ram_rdy_2) begin
			rptrNext = rptr + 1;
			utilNext = util - 1;
			ram_validNext = 1;
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			wptr      <= 0;
			rptr      <= 0;
			util      <= 0;
			ram_valid <= 0;
		end else begin
			wptr      <= wptrNext;
			rptr      <= rptrNext;
			util      <= utilNext;
			ram_valid <= ram_validNext;
		end
	end

endmodule: vr_fifo_sram

// NOTE: using
// 	[local]param[eter] FN = "foo.hex";
// 	if ($bits(FN) > 8) ...
// instead of the "proper" systemverilog syntax
// 	[local]param[eter] string FN = "foo.hex";
// 	if (FN.len() > 0) ...
// because many current synthesis tools (e.g., Quartus 25.1std) are unable
// to properly handle the latter!
// Also note that $bits("") yields 8, since "" is the same as "\0" (even
// though $bits("foo") yields 3, NOT 4)!!!

`ifdef TB_ROM
// // verilator --binary --trace -DTB_ROM --top tb_rom syncmem.sv valid_ready.sv
// // iverilog -g2005-sv -DTB_ROM -s tb_rom -o tb_rom syncmem.sv valid_ready.sv
// // tb_rom > o.log; paste <(grep i_addr o.log) <(grep o_rdata o.log)
module tb_rom ();

	// parameters:
	localparam NC = 256; // clock cycles to simulate
	localparam FN = "syncmem.hex"; // mem[a] = a (for easy testing)
	localparam AW =   8; // address width
	localparam DW =  32; // data width
	localparam TW =  16; // pass-thru data width

	// provide clk, rst:
	logic clk, rst;
	initial begin
		clk = 1;
		rst = 1;
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
	logic [AW-1:0] i_addr;
	logic [DW-1:0] o_rdata;
	logic [TW-1:0] i_ptdat, o_ptdat;
	logic i_valid, i_ready, o_valid, o_ready;
	ready_valid_srom #(
		.FN(FN),
		.AW(AW),
		.DW(DW),
		.TW(TW)
	) dut (
		.i_addr(i_addr),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.i_ptdat(i_ptdat),
		.o_rdata(o_rdata),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.o_ptdat(o_ptdat),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_valid <= 0;
			i_addr  <= 0;
			i_ptdat <= 0;
			o_ready <= 0;
		end else begin
`ifdef VERILATOR
			// upstream/master/producer:
			i_valid <= $random[0];
			i_addr  <= $random[AW-1:0];
			i_ptdat <= $random[TW-1:0];
			// downstream/slave/consumer:
			o_ready <= $random[0];
`else
			// upstream/master/producer:
			i_valid <= $random;
			i_addr  <= $random;
			i_ptdat <= $random;
			// downstream/slave/consumer:
			o_ready <= $random;
`endif
			// show address on upstream/master/producer handshake:
			if (i_valid & i_ready)
				$display("[%04t] i_addr=%h i_ptdat=%h",
					 $time, i_addr, i_ptdat);
			// show data on downstream/slave/consumer handshake:
			if (o_valid & o_ready)
				$display("[%04t] o_rdata=%h o_ptdat=%h",
					 $time, o_rdata, o_ptdat);
			// NOTE: input address stream MUST match output data!!!

			// NOTE: uncomment below to test for throughput!
			//
			// bursty, always-valid address provider:
//			i_valid <= 1;
			//
			// bursty, always-ready data consumer:
//			o_ready <= 1;
			//
			// NOTE: when both provider and consumer are set to
			// support a handshake on each clock cycle, we'd like
			// each address to be followed by matching data on the
			// immediately following clock cycle (10 time units
			// later), without additional delay imposed by the
			// implementation!!!
		end
	end

endmodule: tb_rom
`endif // TB_ROM

`ifdef TB_RAM
// // verilator --binary --trace -DTB_RAM --top tb_ram syncmem.sv valid_ready.sv
// // iverilog -g2005-sv -DTB_RAM -s tb_ram -o tb_ram syncmem.sv valid_ready.sv
// // tb_ram > o.log; paste <(grep i_wren=0 o.log) <(grep o_rdata o.log)
module tb_ram ();

	// parameters:
	localparam NC = 256; // clock cycles to simulate
	localparam FN = "syncmem.hex"; // mem[a] = a (for easy testing)
	localparam AW =   8; // address width
	localparam DW =  32; // data width
	localparam TW =  16; // pass-thru data width

	// provide clk, rst:
	logic clk, rst;
	initial begin
		clk = 1;
		rst = 1;
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
	logic [AW-1:0] i_addr, tmpaddr;
	logic [DW-1:0] i_wdata, o_rdata, tmpdata;
	logic [TW-1:0] i_ptdat, o_ptdat;
	logic i_wren, i_valid, i_ready, o_valid, o_ready;
	ready_valid_sram #(
		.FN(FN),
		.AW(AW),
		.DW(DW),
		.TW(TW)
	) dut (
		.i_addr(i_addr),
		.i_wren(i_wren),
		.i_wdata(i_wdata),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.i_ptdat(i_ptdat),
		.o_rdata(o_rdata),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.o_ptdat(o_ptdat),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_addr  <= 0;
			i_wren  <= 0;
			i_wdata <= 0;
			i_valid <= 0;
			i_ptdat <= 0;
			o_ready <= 0;
		end else begin
`ifdef VERILATOR
			// upstream/master/producer:
			i_valid <= $random[0];
			i_wren  <= $random[0];
			tmpaddr  = $random[AW-1:0];
			tmpdata  = $random[DW-1:0];
			i_ptdat <= $random[TW-1:0];
			// downstream/slave/consumer:
			o_ready <= $random[0];
`else
			// upstream/master/producer:
			i_valid <= $random;
			i_wren  <= $random;
			tmpaddr  = $random;
			tmpdata  = $random;
			i_ptdat <= $random;
			// downstream/slave/consumer:
			o_ready <= $random;
`endif
			// keep LSB(data) == addr, for easy debugging:
			i_addr  <= tmpaddr;
			i_wdata <= {tmpdata[DW-1:AW], tmpaddr};
			// show input on upstream/master/producer handshake:
			if (i_valid & i_ready)
		$display("[%04t] i_addr=%h i_ptdat=%h i_wren=%b i_wdata=%h",
			 $time, i_addr, i_ptdat, i_wren, i_wdata);
			// show rdata on downstream/slave/consumer handshake:
			if (o_valid & o_ready)
			  $display("[%04t]\t o_rdata=%h o_ptdat=%h",
				   $time, o_rdata, o_ptdat);

			// NOTE: uncomment below to test for throughput!
			//
			// bursty, always-valid address provider:
//			i_valid <= 1;
			//
			// bursty, always-ready data consumer:
//			o_ready <= 1;
		end
	end

endmodule: tb_ram
`endif // TB_RAM

`ifdef TB_FFO
// // verilator --binary --trace -DTB_FFO --top tb_ffo syncmem.sv valid_ready.sv
// // iverilog -g2005-sv -DTB_FFO -s tb_ffo -o tb_ffo syncmem.sv valid_ready.sv
// // tb_ffo > o.log; paste <(grep i_d o.log) <(grep o_d o.log)
module tb_ffo ();

	// parameters:
	localparam NC = 256; // clock cycles to simulate
	localparam DW =   8; // data width
	localparam PW =   7; // address/pointer width

	// provide clk, rst:
	logic clk, rst;
	initial begin
		clk = 1;
		rst = 1;
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
	logic [DW-1:0] i_data, o_data;
	logic          i_valid, i_ready, o_valid, o_ready;
	vr_fifo_sram #(
		.DW(DW),
		.PW(PW)
	) dut (
		.i_data(i_data),
		.i_valid(i_valid),
		.i_ready(i_ready),
		.o_data(o_data),
		.o_valid(o_valid),
		.o_ready(o_ready),
		.clk(clk),
		.rst(rst)
	);

	// exercise the DUT:
	always @(posedge clk) begin
		if (rst) begin
			i_valid <= 0;
			i_data  <= 0;
			o_ready <= 0;
		end else begin
`ifdef VERILATOR
			// upstream/master/producer:
			i_valid <= $random[0];
			i_data  <= $random[DW-1:0];
			// downstream/slave/consumer:
			o_ready <= $random[0];
`else
			// upstream/master/producer:
			i_valid <= $random;
			i_data  <= $random;
			// downstream/slave/consumer:
			o_ready <= $random;
`endif
			// show input on upstream/master/producer handshake:
			if (i_valid & i_ready)
				$display("[%04t] i_data=0x%h", $time, i_data);
			// show output on downstream/slave/consumer handshake:
			if (o_valid & o_ready)
				$display("[%04t] o_data=0x%h", $time, o_data);

			// NOTE: uncomment below to test for throughput!
			//
			// bursty, always-valid address provider:
//			if ($time <= 1300) i_valid <= 1;
			//
			// bursty, always-ready data consumer:
//			o_ready <= 1;
		end
	end

endmodule: tb_ffo
`endif // TB_FFO
