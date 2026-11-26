// Integration netlist for LVS. Ports and hierarchy match hdl/gl.
// The public layout is an abstract, so the mask image is not in this netlist.

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
