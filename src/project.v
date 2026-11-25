/*
 * Copyright (c) 2026 Oscar Ramirez (Oscarc-507)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_oscarc_507_mcp4921_spi (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    wire        div_en;
    wire        ramp_en;
    wire        done;
    wire        pulse;
    wire        cs_n;
    wire        sdi;
    wire        sck;
    wire [11:0] dac_data;

    control m0_control (
        .clk     (clk),
        .rst_n   (rst_n),
        .done    (done),
        .div_en  (div_en),
        .ramp_en (ramp_en),
        .cs_n    (cs_n)
    );

    div_clk m1_div_clk (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (div_en),
        .sck   (sck),
        .pulse (pulse)
    );

    ramp_gen m2_ramp_gen (
        .clk      (clk),
        .rst_n    (rst_n),
        .en       (ramp_en),
        .res_sel  (ui_in[1:0]),
        .dac_data (dac_data)
    );

    shift_reg m3_shift_reg (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (div_en),
        .pulse (pulse),
        .data  (dac_data),
        .done  (done),
        .sdi   (sdi)
    );

    // Map SPI outputs to dedicated output pins; tie unused outputs to 0
    assign uo_out  = {5'b00000, sck, sdi, cs_n};
    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;

    // Tie unused inputs to prevent linter warnings
    wire _unused = &{ena, ui_in[7:2], uio_in, 1'b0};

endmodule

`default_nettype wire
