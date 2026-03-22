import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


@cocotb.test()
async def smoke_test_top_level(dut):
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 20)

    assert int(dut.user_project.core.gen_busy.value) == 1
    assert int(dut.user_project.core.player_x.value) == 0
    assert int(dut.user_project.core.player_y.value) == 0

    initial_hsync = int(dut.uo_out.value[7])
    changed = False
    for _ in range(900):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value[7]) != initial_hsync:
            changed = True
            break

    assert changed, "hsync never toggled during smoke test"


@cocotb.test()
async def vga_sync_smoke(dut):
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 25)

    initial_vsync = int(dut.uo_out.value[3])
    saw_hsync_high = False
    for _ in range(1200):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value[7]) == 1:
            saw_hsync_high = True
            break

    assert saw_hsync_high, "hsync never asserted"
    assert int(dut.uo_out.value[3]) in (0, 1)
    assert initial_vsync in (0, 1)
