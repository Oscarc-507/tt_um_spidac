/*
 * Copyright (c) 2026 Oscar Ramirez (Oscarc-507)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module shift_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire        pulse,
    input  wire [11:0] data,
    output wire        done,
    output wire        sdi
);

    // MCP4921 config bits: DAC_A (0), unbuffered VREF (0), 1x gain (1), active mode (1)
    localparam [3:0] CONFIG_DATA = 4'b0011;

    reg [3:0]  cont_bits;
    reg [15:0] tmp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmp       <= 16'd0;
            cont_bits <= 4'd0;
        end else if (!en) begin
            tmp       <= {CONFIG_DATA, data};
            cont_bits <= 4'd0;
        end else if (pulse) begin
            tmp       <= {tmp[14:0], 1'b0};
            cont_bits <= cont_bits + 4'd1;
        end
    end

    assign sdi  = tmp[15];
    assign done = en && pulse && (cont_bits == 4'd15);

endmodule

`default_nettype wire
