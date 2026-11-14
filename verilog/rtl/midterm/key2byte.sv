// Copyright (C) 2026 Carnegie Mellon University
// Author: Gabriel L. Somlo <somlo@cmu.edu>

`include "kbd.svh"

// convert multi-byte keycodes into sequence of bytes (characters)
// NOTE: if multiple keycode sources are to be supported, this module
//       will also be responsible for sending each individual keycode
//       "atomically", i.e., without interleaving its bytes with those
//       belonging to a "competing" keycode!
module keycode_to_char (
	// consume key codes (e.g., produced by the layout module):
	input  kbd_pkg::keycode_t key_vec,
	input  logic     key_valid,
	output logic     key_ready,

	// produce ascii bytes (characters) to be forwarded via uart_tx:
	output logic [7:0] out_char,
	output logic       out_valid,
	input  logic       out_ready,

	input logic clk,
	input logic rst
);

	// store bytes from input:
	logic [kbd_pkg::KW-1:0] key, keyNext;
	// index into input key array:
	logic [kbd_pkg::SW:0] idx, idxNext; // NOTE: (SW+1) wide to reserve idx == -1
				   //       for use by the handshake protocol!

	// select indexed slice from key vector (out_char = key[idx]):
	vec_slice_sel #(
		.SL($bits(out_char)),  // slices are one byte in width
		.NS(kbd_pkg::BW), // there are BW byte-sized slices in a vector
		.MSF(0)  // we want the least-significant byte at index 0
	) inst_vec_slice_sel (
		.vector(key),
			     /* verilator lint_off WIDTHTRUNC */
		.index(idx), // implicitly truncates MSB (i.e., idx[SW])
		.slice(out_char)
	);

	// accept input if consumer is waiting or no valid uncollected output
	// (but *only* once said valid uncollected output is the *last* byte)
	assign key_ready = (out_ready | ~out_valid) &
			   (idx == 0 | &idx); // 0 or -1

	// handshake conditions for input & output interfaces:
	logic i_handshake, o_handshake;
	assign i_handshake = (key_valid & key_ready);
	assign o_handshake = (out_valid & out_ready);

        // next value for out_valid
        logic out_validNext;

	// combinational logic:
	always_comb begin
		// by default, keep registers steady:
		keyNext       = key;
		idxNext       = idx;
		out_validNext = out_valid;

		if (i_handshake) begin
			keyNext       = key_vec.key;
			idxNext       = key_vec.len - 1;
			out_validNext = 1;
		end else if (o_handshake) begin
			idxNext = idx - 1;
			if (idx == 0) begin
				out_validNext = 0;
			end
		end
	end

	// sequential logic:
	always_ff @(posedge clk) begin
		if (rst) begin
			key       <= 0;
			idx       <= 0;
			out_valid <= 0;
		end else begin
			key       <= keyNext;
			idx       <= idxNext;
			out_valid <= out_validNext;
		end
	end

endmodule: keycode_to_char
