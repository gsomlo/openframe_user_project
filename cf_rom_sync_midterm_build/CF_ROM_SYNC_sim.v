`timescale 1ns / 1ps

// Ideal functional model of CF_ROM_SYNC with a programmed 1K×8 image.
// Not silicon-verified. Do not add this file to OpenLane VERILOG_FILES.
//
// Assumed protocol:
//   * RST high on posedge CLK clears the output register
//   * EN high on posedge CLK captures mem[A]
//   * OE high drives DO; OE low is high-Z

module CF_ROM_SYNC_core (
    vpwr,
    vgnd,
    vpb,
    vnb,
    DO,
    A,
    EN,
    CLK,
    RST,
    OE
);
    input vpwr;
    input vgnd;
    input vpb;
    input vnb;
    output [7:0] DO;
    input [9:0] A;
    input EN;
    input CLK;
    input RST;
    input OE;

    reg [7:0] mem [0:1023];
    reg [7:0] q;

    initial begin
        // ROM content is specific to each instance:
        $readmemh($sformatf("%m.rom"), mem);
    end

    always @(posedge CLK or posedge RST) begin
        if (RST)
            q <= 8'h00;
        else if (EN)
            q <= mem[A];
    end

    assign DO = OE ? q : 8'hzz;
endmodule

module CF_ROM_SYNC (
    vpwr,
    vgnd,
    DO,
    A,
    EN,
    CLK,
    RST,
    OE
);
    input vpwr;
    input vgnd;
    output [7:0] DO;
    input [9:0] A;
    input EN;
    input CLK;
    input RST;
    input OE;
    CF_ROM_SYNC_core u_core (
        .vpwr(vpwr),
        .vgnd(vgnd),
        .vpb(vpwr),
        .vnb(vgnd),
        .DO(DO),
        .A(A),
        .EN(EN),
        .CLK(CLK),
        .RST(RST),
        .OE(OE)
    );
endmodule
