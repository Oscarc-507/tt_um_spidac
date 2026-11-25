/*
 * Copyright (c) 2026 Oscar Ramirez (Oscarc-507)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module control (
    input  wire clk,
    input  wire rst_n,
    input  wire done,
    output wire div_en,
    output wire ramp_en,
    output wire cs_n
);

    // Gray-coded FSM states so cs_n = ~state[0] transitions glitch-free (START -> SEND)
    localparam [1:0] IDLE  = 2'b00;
    localparam [1:0] START = 2'b01;
    localparam [1:0] SEND  = 2'b11;
    localparam [1:0] WAIT  = 2'b10;

    reg [1:0] state;
    reg [1:0] next_state;
    reg [1:0] cont_clk;

    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Inter-frame wait cycle counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cont_clk <= 2'd0;
        else if (state == START)
            cont_clk <= 2'd0;
        else if (state == WAIT)
            cont_clk <= cont_clk + 2'd1;
    end

    // Next-state combinational logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    next_state = START;
            START:   next_state = SEND;
            SEND:    if (done) next_state = WAIT;
            WAIT:    if (cont_clk == 2'd3) next_state = START;
            default: next_state = IDLE;
        endcase
    end

    assign cs_n    = ~state[0];
    assign div_en  = (state == SEND);
    assign ramp_en = (state == WAIT) && (cont_clk == 2'd3);

endmodule

`default_nettype wire
