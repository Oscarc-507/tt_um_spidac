<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This design implements a continuous sawtooth waveform generator that streams 16-bit SPI Mode (0,0) frames to an external Microchip **MCP4921** 12-bit DAC.

The architecture is partitioned into four cooperating Verilog modules inside `tt_um_oscarc_507_mcp4921_spi`:

1. **`control` (`src/control.v`)**: A 4-state Gray-coded finite state machine (`IDLE`, `START`, `SEND`, `WAIT`) that sequences each SPI transfer. Using Gray encoding ensures `SPI_CS_N` (`~state[0]`) transitions cleanly without combinational glitches between `START` and `SEND`. After 16 bits are transmitted (`done`), the FSM holds `SPI_CS_N` high for 4 system clock cycles (`WAIT`) and asserts `ramp_en` for one cycle to advance the DAC sample.
2. **`div_clk` (`src/div_clk.v`)**: Divides the system clock `clk` by 8 to generate `SPI_SCK` (`cont[2]`, 50% duty cycle) and a single-cycle `pulse` at `cont == 3'd7` (falling edge of `SPI_SCK`) to shift the next bit onto `SPI_SDI`. At `clk = 50 MHz`, `SPI_SCK = 6.25 MHz` (well within the MCP4921 maximum 20 MHz SPI clock).
3. **`ramp_gen` (`src/ramp_gen.v`)**: Synchronizes `ui_in[1:0]` (`RES_SEL1`, `RES_SEL0`) through a 2-flip-flop synchronizer (defaulting to 12-bit mode after reset) and advances a 12-bit accumulator by a selectable step size, masking unused LSBs so switching resolution on the fly produces clean MSB-aligned steps:
   - `ui_in[1:0] = 2'b00`: 8-bit resolution (step = 16, 256 steps/period, `dac_data = {count[11:4], 4'b0000}`)
   - `ui_in[1:0] = 2'b01`: 10-bit resolution (step = 4, 1024 steps/period, `dac_data = {count[11:2], 2'b00}`)
   - `ui_in[1:0] = 2'b10` or `2'b11`: 12-bit resolution (step = 1, 4096 steps/period, `dac_data = count`)
4. **`shift_reg` (`src/shift_reg.v`)**: Loads the 16-bit MCP4921 SPI word `{4'b0011, dac_data}` while `div_en` is low and shifts MSB-first on each `pulse`, asserting `done` on the 16th bit (`cont_bits == 4'd15`). The fixed configuration nibble `4'b0011` selects DAC channel A (`0`), unbuffered `VREF` (`0`), 1x output gain (`1`), and active output mode (`1`).

### Pin Mapping

| Tiny Tapeout Pin | Signal | Direction | Description |
| :--- | :--- | :--- | :--- |
| `ui_in[0]` | `RES_SEL0` | Input | Resolution select bit 0 |
| `ui_in[1]` | `RES_SEL1` | Input | Resolution select bit 1 (`00`=8b, `01`=10b, `10`/`11`=12b) |
| `uo_out[0]` | `SPI_CS_N` | Output | Active-low SPI Chip Select |
| `uo_out[1]` | `SPI_SDI` | Output | SPI Serial Data Output (MOSI to MCP4921 `SDI`) |
| `uo_out[2]` | `SPI_SCK` | Output | SPI Serial Clock (`clk / 8`, Mode 0,0) |
| `uo_out[7:3]` | Unused | Output | Tied to `0` |
| `uio[7:0]` | Unused | Bidir | Configured as inputs (`uio_oe = 0`, `uio_out = 0`) |

## How to test

1. Apply a clock on `clk` (e.g., 50 MHz or slower for lab probing) and pulse `rst_n` low (`0`) for at least 2 clock cycles, then release `rst_n = 1`.
2. Set `ui_in[1:0]` to select the desired sawtooth resolution (`00` = 8-bit, `01` = 10-bit, `10` or `11` = 12-bit). You can also toggle `ui_in[1:0]` dynamically while running.
3. Monitor `uo_out[0]` (`SPI_CS_N`), `uo_out[1]` (`SPI_SDI`), and `uo_out[2]` (`SPI_SCK`) on a logic analyzer or connect them to an MCP4921 DAC and observe `VOUT` on an oscilloscope.
4. For RTL simulation, run `make -B` inside `test/` using cocotb and Icarus Verilog.

## External hardware

- **Microchip MCP4921** 12-bit DAC with SPI interface:
  - `MCP4921 VDD` -> 3.3V / 5V (matching IO level) with decoupling capacitor (0.1 uF)
  - `MCP4921 VSS` -> GND
  - `MCP4921 VREF` -> Reference voltage (`<= VDD`, e.g., 3.3V or precision reference)
  - `MCP4921 CS_N` (pin 2) <- `uo_out[0]` (`SPI_CS_N`)
  - `MCP4921 SCK` (pin 3) <- `uo_out[2]` (`SPI_SCK`)
  - `MCP4921 SDI` (pin 4) <- `uo_out[1]` (`SPI_SDI`)
  - `MCP4921 LDAC_N` (pin 5) -> GND (latches DAC register automatically on rising edge of `CS_N`)
  - `MCP4921 VOUT` (pin 8) -> Oscilloscope probe or analog load
- Optional 2-position DIP switch or jumper header on `ui_in[1:0]` with pull-down/pull-up resistors to select 8-bit, 10-bit, or 12-bit ramp resolution.
