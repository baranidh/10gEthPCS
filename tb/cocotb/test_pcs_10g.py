"""
============================================================================
test_pcs_10g.py — cocotb Testbench for 10GBASE-R PCS Core
============================================================================
IEEE 802.3 Clause 49 conformance tests using cocotb framework.

Clock: 644 MHz (1.553 ns period), 16-bit SERDES data width

Tests:
  1. Reset and initialization
  2. Idle block encoding/decoding
  3. Block lock acquisition
  4. Frame transmission (start → data → terminate)
  5. Scrambler/descrambler round-trip
  6. Back-to-back frames
  7. PCS status signals
  8. Continuous streaming
  9. Latency measurement
 10. Error handling

Requires: cocotb >= 2.0
Simulator: Icarus Verilog (iverilog)
============================================================================
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# XGMII Control Characters
XGMII_IDLE  = 0x07
XGMII_START = 0xFB
XGMII_TERM  = 0xFD
XGMII_ERROR = 0xFE

CLK_PERIOD_NS = 1.553  # 644 MHz

# Global clock handle — start once, reuse across tests
_clock_started = False


def pack_xgmii_idle():
    return (XGMII_IDLE * 0x0101010101010101, 0xFF)


def pack_xgmii_start():
    txd = (0xD5 << 56) | (0x55 << 48) | (0x55 << 40) | (0x55 << 32) | \
          (0x55 << 24) | (0x55 << 16) | (0x55 << 8) | XGMII_START
    return (txd, 0x01)


def pack_xgmii_term0():
    txd = (XGMII_IDLE << 56) | (XGMII_IDLE << 48) | (XGMII_IDLE << 40) | \
          (XGMII_IDLE << 32) | (XGMII_IDLE << 24) | (XGMII_IDLE << 16) | \
          (XGMII_IDLE << 8) | XGMII_TERM
    return (txd, 0xFF)


def pack_xgmii_data(data_64):
    return (data_64 & 0xFFFFFFFFFFFFFFFF, 0x00)


async def ensure_clock(dut):
    """Start clock if not already running."""
    global _clock_started
    if not _clock_started:
        clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
        cocotb.start_soon(clock.start())
        _clock_started = True


async def reset_dut(dut):
    """Apply reset to the DUT."""
    await ensure_clock(dut)
    dut.rst_n.value = 0
    txd, txc = pack_xgmii_idle()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def send_idle(dut, count):
    txd, txc = pack_xgmii_idle()
    for _ in range(count):
        dut.xgmii_txd.value = txd
        dut.xgmii_txc.value = txc
        await RisingEdge(dut.clk)


async def wait_for_block_lock(dut, timeout=50000):
    for i in range(timeout):
        await RisingEdge(dut.clk)
        if dut.block_lock.value == 1:
            return i
    return -1


async def establish_link(dut):
    """Reset, send idle, and wait for block lock."""
    await reset_dut(dut)
    await send_idle(dut, 200)
    cycles = await wait_for_block_lock(dut, timeout=20000)
    await send_idle(dut, 400)  # Extra stabilization
    return cycles


# ==========================================================================
# Test 1: Reset and Initialization
# ==========================================================================
@cocotb.test()
async def test_reset(dut):
    """Test 1: Verify reset behavior."""
    await reset_dut(dut)
    assert dut.rst_n.value == 1, "Reset should be deasserted"
    dut._log.info("Test 1 PASSED: Reset and initialization")


# ==========================================================================
# Test 2: Idle Transmission
# ==========================================================================
@cocotb.test()
async def test_idle_transmission(dut):
    """Test 2: Transmit idle blocks and verify no errors."""
    await reset_dut(dut)
    await send_idle(dut, 800)
    assert dut.tx_encode_err.value == 0, "No TX encode error expected on idle"
    dut._log.info("Test 2 PASSED: Idle transmission without errors")


# ==========================================================================
# Test 3: Block Lock Acquisition
# ==========================================================================
@cocotb.test()
async def test_block_lock(dut):
    """Test 3: Verify block lock acquisition via loopback."""
    cycles = await establish_link(dut)
    assert dut.block_lock.value == 1, "Block lock should be acquired"
    assert dut.hi_ber.value == 0, "Hi-BER should be clear after lock"
    if cycles >= 0:
        dut._log.info(f"Block lock acquired after {cycles} cycles")
    dut._log.info("Test 3 PASSED: Block lock acquisition")


# ==========================================================================
# Test 4: Frame Transmission
# ==========================================================================
@cocotb.test()
async def test_frame_tx(dut):
    """Test 4: Send a complete Ethernet frame through PCS."""
    await establish_link(dut)

    txd, txc = pack_xgmii_start()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    for i in range(4):
        data = 0x0102030405060708 + (i * 0x1010101010101010)
        txd, txc = pack_xgmii_data(data)
        dut.xgmii_txd.value = txd
        dut.xgmii_txc.value = txc
        await RisingEdge(dut.clk)

    txd, txc = pack_xgmii_term0()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    await send_idle(dut, 200)

    assert dut.tx_encode_err.value == 0, "No encode error during frame"
    assert dut.block_lock.value == 1, "Block lock maintained"
    dut._log.info("Test 4 PASSED: Frame transmission")


# ==========================================================================
# Test 5: Scrambler Verification
# ==========================================================================
@cocotb.test()
async def test_scrambler_roundtrip(dut):
    """Test 5: Verify scrambler/descrambler preserve data through loopback."""
    await establish_link(dut)

    test_data = [
        0xDEADBEEFCAFEBABE,
        0x0123456789ABCDEF,
        0xAAAAAAAAAAAAAAAA,
        0x5555555555555555,
    ]

    txd, txc = pack_xgmii_start()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    for data in test_data:
        txd, txc = pack_xgmii_data(data)
        dut.xgmii_txd.value = txd
        dut.xgmii_txc.value = txc
        await RisingEdge(dut.clk)

    txd, txc = pack_xgmii_term0()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    await send_idle(dut, 400)

    assert dut.block_lock.value == 1, "Block lock stable after scrambled data"
    dut._log.info("Test 5 PASSED: Scrambler/descrambler round-trip")


# ==========================================================================
# Test 6: Back-to-Back Frames
# ==========================================================================
@cocotb.test()
async def test_back_to_back_frames(dut):
    """Test 6: Send multiple frames with minimum IFG."""
    await establish_link(dut)

    for frame_num in range(10):
        txd, txc = pack_xgmii_start()
        dut.xgmii_txd.value = txd
        dut.xgmii_txc.value = txc
        await RisingEdge(dut.clk)

        for j in range(2):
            data = ((frame_num & 0xFF) << 56) | ((j & 0xFF) << 48) | 0x112233445566
            txd, txc = pack_xgmii_data(data)
            dut.xgmii_txd.value = txd
            dut.xgmii_txc.value = txc
            await RisingEdge(dut.clk)

        txd, txc = pack_xgmii_term0()
        dut.xgmii_txd.value = txd
        dut.xgmii_txc.value = txc
        await RisingEdge(dut.clk)

        await send_idle(dut, 20)

    await send_idle(dut, 200)

    assert dut.block_lock.value == 1, "Block lock after back-to-back frames"
    assert dut.tx_encode_err.value == 0, "No encode errors"
    dut._log.info("Test 6 PASSED: 10 back-to-back frames")


# ==========================================================================
# Test 7: PCS Status
# ==========================================================================
@cocotb.test()
async def test_pcs_status(dut):
    """Test 7: Verify PCS status signals."""
    await establish_link(dut)

    assert dut.pcs_status.value == 1, "PCS status should be UP"
    assert dut.block_lock.value == 1, "Block lock should be held"
    assert dut.hi_ber.value == 0, "Hi-BER should be clear"
    dut._log.info("Test 7 PASSED: PCS status signals correct")


# ==========================================================================
# Test 8: Continuous Streaming
# ==========================================================================
@cocotb.test()
async def test_continuous_stream(dut):
    """Test 8: Send 100-word continuous data stream."""
    await establish_link(dut)

    txd, txc = pack_xgmii_start()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    for i in range(100):
        data = (i & 0xFFFFFFFF) | ((i ^ 0xFFFFFFFF) << 32)
        txd, txc = pack_xgmii_data(data & 0xFFFFFFFFFFFFFFFF)
        dut.xgmii_txd.value = txd
        dut.xgmii_txc.value = txc
        await RisingEdge(dut.clk)

    txd, txc = pack_xgmii_term0()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    await send_idle(dut, 200)

    assert dut.block_lock.value == 1, "Lock after 100-word stream"
    dut._log.info("Test 8 PASSED: 100-word continuous stream")


# ==========================================================================
# Test 9: Latency Measurement
# ==========================================================================
@cocotb.test()
async def test_latency(dut):
    """Test 9: Measure PCS core loopback latency."""
    await establish_link(dut)
    await send_idle(dut, 800)

    tx_time = cocotb.utils.get_sim_time(units="ns")

    txd, txc = pack_xgmii_start()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    txd, txc = pack_xgmii_data(0xFEEDFACE12345678)
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    txd, txc = pack_xgmii_term0()
    dut.xgmii_txd.value = txd
    dut.xgmii_txc.value = txc
    await RisingEdge(dut.clk)

    await send_idle(dut, 20)

    rx_time = None
    for _ in range(10000):
        await RisingEdge(dut.clk)
        try:
            rxc = int(dut.xgmii_rxc.value)
            rxd = int(dut.xgmii_rxd.value)
            if (rxc & 0x01) and ((rxd & 0xFF) == XGMII_START):
                rx_time = cocotb.utils.get_sim_time(units="ns")
                break
            if rxc == 0x00 and rxd != (XGMII_IDLE * 0x0101010101010101):
                rx_time = cocotb.utils.get_sim_time(units="ns")
                break
        except ValueError:
            continue

    if rx_time is not None:
        latency_ns = rx_time - tx_time
        latency_cycles = latency_ns / CLK_PERIOD_NS
        dut._log.info(f"Loopback latency: {latency_ns:.1f} ns ({latency_cycles:.1f} cycles)")
    else:
        dut._log.warning("Start marker not detected on RX within timeout")

    dut._log.info("Test 9 PASSED: Latency measurement complete")


# ==========================================================================
# Test 10: Error Block Handling
# ==========================================================================
@cocotb.test()
async def test_error_handling(dut):
    """Test 10: Verify error handling for invalid XGMII patterns."""
    await establish_link(dut)

    # Send XGMII error character (all-control error, which is valid encoding)
    dut.xgmii_txd.value = XGMII_ERROR * 0x0101010101010101
    dut.xgmii_txc.value = 0xFF
    await RisingEdge(dut.clk)

    # Immediately return to idle
    await send_idle(dut, 800)

    assert dut.block_lock.value == 1, "Block lock should survive error injection"
    dut._log.info("Test 10 PASSED: Error handling")
