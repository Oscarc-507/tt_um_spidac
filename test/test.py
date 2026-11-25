# SPDX-FileCopyrightText: © 2026 Oscar Ramirez (Oscarc-507)
# SPDX-License-Identifier: Apache-2.0

import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, First, RisingEdge

EXPECTED_CFG = 0b0011  # MCP4921: DAC_A, unbuffered VREF, 1x gain, active mode


def check_unused_pins(dut):
    """Verify all unused outputs and bidirectional enables remain 0."""
    uo_val = int(dut.uo_out.value)
    assert (uo_val >> 3) == 0, f"Unused uo_out[7:3] must be 0, got {bin(uo_val)}"
    assert int(dut.uio_out.value) == 0, f"uio_out must be 0, got {dut.uio_out.value}"
    assert int(dut.uio_oe.value) == 0, f"uio_oe must be 0, got {dut.uio_oe.value}"


async def reset_dut(dut, res_mode=0):
    """Apply active-low reset rst_n=0 with a known ui_in[1:0] mode."""
    dut.ena.value = 1
    dut.uio_in.value = 0
    dut.ui_in.value = res_mode & 0x3
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    check_unused_pins(dut)
    assert int(dut.spi_cs_n.value) == 1, "spi_cs_n must be high during reset"
    assert int(dut.spi_sck.value) == 0, "spi_sck must be low during reset"
    dut.rst_n.value = 1


async def capture_spi_frame(dut):
    """Capture one 16-bit SPI Mode (0,0) frame and verify 16 SCK edges."""
    if int(dut.spi_cs_n.value) != 0:
        await FallingEdge(dut.spi_cs_n)

    shift_val = 0
    bit_count = 0
    cs_rise = RisingEdge(dut.spi_cs_n)
    sck_rise = RisingEdge(dut.spi_sck)

    while True:
        trig = await First(sck_rise, cs_rise)
        if trig is cs_rise:
            break
        shift_val = ((shift_val << 1) | int(dut.spi_sdi.value)) & 0xFFFF
        bit_count += 1

    check_unused_pins(dut)
    assert bit_count == 16, f"Expected 16 SCK rising edges per frame, got {bit_count}"

    cfg = (shift_val >> 12) & 0xF
    code = shift_val & 0xFFF
    return cfg, code


@cocotb.test()
async def test_reset_and_idle(dut):
    """Verify active-low reset invariants and unused pin ties."""
    clock = Clock(dut.clk, 20, unit="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut, res_mode=0b10)
    await ClockCycles(dut.clk, 2)
    assert int(dut.spi_cs_n.value) == 0, "spi_cs_n should assert low after reset release"


@cocotb.test()
async def test_ramp_resolutions(dut):
    """Verify 8-bit, 10-bit, and 12-bit sawtooth ramps over SPI Mode (0,0)."""
    clock = Clock(dut.clk, 20, unit="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    is_gates = os.environ.get("GATES") == "yes"

    # (mode, step, frame_count) — full wrap-around in RTL, fast sample in GL_TEST
    test_cases = [
        (0b00, 16, 260),
        (0b01, 4, 32 if is_gates else 1030),
        (0b10, 1, 32 if is_gates else 4100),
        (0b11, 1, 16),
    ]

    for mode, step, num_frames in test_cases:
        dut._log.info(f"Testing mode={mode:02b}, step={step}, frames={num_frames}")
        await reset_dut(dut, res_mode=mode)

        for frame_idx in range(num_frames):
            cfg, code = await capture_spi_frame(dut)
            expected_code = (frame_idx * step) & 0xFFF
            assert cfg == EXPECTED_CFG, (
                f"Mode {mode:02b} frame {frame_idx}: expected cfg={EXPECTED_CFG:#06b}, got {cfg:#06b}"
            )
            assert code == expected_code, (
                f"Mode {mode:02b} frame {frame_idx}: expected code={expected_code}, got {code}"
            )


@cocotb.test()
async def test_dynamic_resolution_switch(dut):
    """Verify clean on-the-fly resolution changes without asserting rst_n."""
    clock = Clock(dut.clk, 20, unit="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    await reset_dut(dut, res_mode=0b10)  # Start in 12-bit mode

    # Run 6 frames in 12-bit mode
    for frame_idx in range(6):
        cfg, code = await capture_spi_frame(dut)
        assert cfg == EXPECTED_CFG
        assert code == frame_idx

    # Switch dynamically to 8-bit mode (LSBs [3:0] must become 0 after sync)
    dut.ui_in.value = 0b00
    prev_code = None
    for idx in range(6):
        cfg, code = await capture_spi_frame(dut)
        assert cfg == EXPECTED_CFG
        if idx >= 2:
            assert (code & 0xF) == 0, f"8-bit mode must mask LSBs [3:0], got {code:#05x}"
            if prev_code is not None:
                assert code == ((prev_code + 16) & 0xFFF)
            prev_code = code

    # Switch dynamically to 10-bit mode (LSBs [1:0] must become 0 after sync)
    dut.ui_in.value = 0b01
    prev_code = None
    for idx in range(6):
        cfg, code = await capture_spi_frame(dut)
        assert cfg == EXPECTED_CFG
        if idx >= 2:
            assert (code & 0x3) == 0, f"10-bit mode must mask LSBs [1:0], got {code:#05x}"
            if prev_code is not None:
                assert code == ((prev_code + 4) & 0xFFF)
            prev_code = code
