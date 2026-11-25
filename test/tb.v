`default_nettype none
`timescale 1ns / 1ps

/* This testbench instantiates the Tiny Tapeout wrapper, exposes readable
   aliases for the SPI/DAC signals, and includes a passive SPI Mode (0,0)
   monitor so cocotb and waveform viewers (GTKWave / Surfer) can inspect the
   decoded DAC configuration and 12-bit analog ramp code.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // Top-level Tiny Tapeout DUT instantiation:
  tt_um_oscarc_507_mcp4921_spi user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // active-low reset
  );

  // Readable aliases for external pins (safe for both RTL and Gate-Level sims)
  wire [1:0] res_sel  = ui_in[1:0];
  wire       spi_cs_n = uo_out[0];
  wire       spi_sdi  = uo_out[1];
  wire       spi_sck  = uo_out[2];

  // Passive SPI Mode (0,0) monitor: samples SDI on posedge SCK, latches on posedge CS_N
  reg [15:0] spi_rx_shift;
  reg [3:0]  dac_cfg_rx;
  reg [11:0] dac_code_rx;

  always @(posedge spi_sck or negedge rst_n) begin
    if (!rst_n)
      spi_rx_shift <= 16'd0;
    else if (!spi_cs_n)
      spi_rx_shift <= {spi_rx_shift[14:0], spi_sdi};
  end

  always @(posedge spi_cs_n or negedge rst_n) begin
    if (!rst_n) begin
      dac_cfg_rx  <= 4'd0;
      dac_code_rx <= 12'd0;
    end else begin
      dac_cfg_rx  <= spi_rx_shift[15:12];
      dac_code_rx <= spi_rx_shift[11:0];
    end
  end

endmodule

`default_nettype wire
