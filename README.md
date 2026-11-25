![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout GF180 — MCP4921 SPI Ramp Generator

- [Read the documentation for project](docs/info.md)
- [Changelog of SystemVerilog-to-TinyTapeout adaptations](codes_log.md)
- [Step-by-step adaptation workflow](workflow.md)

## Overview

This repository contains an ASIC implementation of a configurable **8 / 10 / 12-bit sawtooth ramp generator** with an **SPI Mode (0,0)** master interface targeting the **Microchip MCP4921** 12-bit DAC, adapted for the **Tiny Tapeout GlobalFoundries 180 nm (`gf180mcuD`)** shuttle using LibreLane.

### Top Module & Pinout

- **Top module:** `tt_um_oscarc_507_mcp4921_spi` ([src/project.v](src/project.v))
- **Submodules:** [src/control.v](src/control.v), [src/div_clk.v](src/div_clk.v), [src/ramp_gen.v](src/ramp_gen.v), [src/shift_reg.v](src/shift_reg.v)

| Pin | Name | Direction | Function |
| :--- | :--- | :--- | :--- |
| `ui_in[1:0]` | `RES_SEL[1:0]` | Input | `00` = 8-bit, `01` = 10-bit, `10`/`11` = 12-bit |
| `uo_out[0]` | `SPI_CS_N` | Output | Active-low Chip Select |
| `uo_out[1]` | `SPI_SDI` | Output | Serial Data Output (MOSI) |
| `uo_out[2]` | `SPI_SCK` | Output | Serial Clock (`clk / 8`) |

## Verification

- Testbench wrapper & cocotb suite: [test/tb.v](test/tb.v), [test/test.py](test/test.py), [test/Makefile](test/Makefile)
- Run RTL simulation (requires `iverilog`, `make`, and `cocotb`):
  ```sh
  cd test
  make -B
  ```
