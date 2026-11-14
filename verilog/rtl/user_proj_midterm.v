`default_nettype none

module user_proj_midterm (
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,

    // IOs
    input   [3:0] io_in,
    output [28:0] io_out,

    // ROM interface
    output [11:0] rom_addr,
    input  [71:0] rom_data,

    // RAM interface
    output [12:0] ram_addr,
    output        ram_wren,
    output [39:0] ram_wdata,
    input  [39:0] ram_rdata
);

    terminal_top /* #(
        .CLK_FREQ(25000000),
        .BAUDRATE(115200)
    ) */ terminal (
        // uart:
        .uart_rxd(io_in[0]),
        .uart_txd(io_out[0]),
        .uart_rts(io_in[1]), // unreliable (UART_RTS == 0 with usb dongle)
        .uart_cts(io_out[1]),
        // ps/2:
        .ps2_clk(io_in[2]),
        .ps2_dat(io_in[3]),
        // vga:
        .vga_hsync_n(io_out[2]),
        .vga_vsync_n(io_out[3]),
        .vga_blank_n(io_out[4]), // specific to the DE2-115 VGA DAC!
        .vga_pxl_r(io_out[12:5]),
        .vga_pxl_g(io_out[20:13]),
        .vga_pxl_b(io_out[28:21]),
        // ROM interface:
        .rom_addr(rom_addr),
        .rom_data(rom_data),
        // RAM interface:
        .ram_addr(ram_addr),
        .ram_wren(ram_wren),
        .ram_wdata(ram_wdata),
        .ram_rdata(ram_rdata),
        // control:
        .clk(wb_clk_i),
        .rst(wb_rst_i)
    );

endmodule

`default_nettype wire
