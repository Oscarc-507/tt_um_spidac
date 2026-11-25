/*
 * Copyright (c) 2026 Oscar Ramirez (Oscarc-507)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module ramp_gen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,        // 1-cycle pulse at the end of each SPI frame
    input  wire [1:0]  res_sel,   // 00=8b, 01=10b, 10/11=12b
    output reg  [11:0] dac_data
);

    // 2-FF synchronizer for external resolution selection inputs
    reg [1:0] res_ff1;
    reg [1:0] res_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            res_ff1  <= 2'b10; // Default to 12-bit resolution
            res_sync <= 2'b10;
        end else begin
            res_ff1  <= res_sel;
            res_sync <= res_ff1;
        end
    end

    // Step size selection according to active resolution
    reg [11:0] step;
    always @(*) begin
        case (res_sync)
            2'b00:   step = 12'd16; // 8-bit  (2^4 = 16) -> 256 steps
            2'b01:   step = 12'd4;  // 10-bit (2^2 = 4)  -> 1024 steps
            default: step = 12'd1;  // 12-bit (2^0 = 1)  -> 4096 steps
        endcase
    end

    // 12-bit sawtooth accumulator
    reg [11:0] count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 12'd0;
        else if (en)
            count <= count + step;
    end

    // LSB masking for clean transitions when changing resolution on the fly
    always @(*) begin
        case (res_sync)
            2'b00:   dac_data = {count[11:4], 4'b0000}; // 8-bit MSB-justified
            2'b01:   dac_data = {count[11:2], 2'b00};   // 10-bit MSB-justified
            default: dac_data = count;                  // Full 12-bit
        endcase
    end

endmodule

`default_nettype wire
