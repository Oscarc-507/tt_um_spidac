/*
 * Copyright (c) 2026 Oscar Ramirez (Oscarc-507)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module div_clk (
    input  wire clk,
    input  wire rst_n,
    input  wire en,
    output wire sck,
    output wire pulse
);

    reg [2:0] cont;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cont <= 3'd0;
        else if (en)
            cont <= cont + 3'd1;
        else
            cont <= 3'd0;
    end

    assign sck   = cont[2];
    assign pulse = en && (cont == 3'd7);

endmodule

`default_nettype wire
