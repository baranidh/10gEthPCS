# =============================================================================
# pcs_10g_timing.xdc — Timing Constraints for 10GBASE-R PCS Core
# =============================================================================
# Target: Xilinx UltraScale+ FPGA
# Clock: 644 MHz (from GTH TXOUTCLK / RXOUTCLK via BUFG_GT)
# Data width: 16-bit SERDES interface (16 × 644 MHz ≈ 10.3 Gbps)
# =============================================================================

# ---- Primary Clock ----
# The PCS core clock comes from the GTH transceiver's recovered clock
# User must create this clock constraint based on their GTH configuration
# Example: GTH TXOUTCLK → BUFG_GT → PCS core clk
# 644 MHz → 1.553 ns period

create_clock -period 1.553 -name pcs_clk [get_pins {u_bufg_gt/O}]

# If using separate TX and RX clocks from GTH:
# create_clock -period 1.553 -name pcs_txclk [get_pins {u_bufg_gt_tx/O}]
# create_clock -period 1.553 -name pcs_rxclk [get_pins {u_bufg_gt_rx/O}]

# ---- Input Constraints (XGMII from MAC) ----
# Adjust these based on your MAC-to-PCS timing
set_input_delay -clock pcs_clk -max 0.5 [get_ports {xgmii_txd[*] xgmii_txc[*]}]
set_input_delay -clock pcs_clk -min 0.1 [get_ports {xgmii_txd[*] xgmii_txc[*]}]

# ---- Output Constraints (XGMII to MAC) ----
set_output_delay -clock pcs_clk -max 0.5 [get_ports {xgmii_rxd[*] xgmii_rxc[*]}]
set_output_delay -clock pcs_clk -min 0.1 [get_ports {xgmii_rxd[*] xgmii_rxc[*]}]

# ---- GTH/SERDES Interface Constraints ----
# These should be automatically handled by GTH IP but listed for reference
# set_input_delay -clock pcs_clk -max 0.3 [get_ports {gth_rxdata[*] gth_rxheader[*]}]
# set_output_delay -clock pcs_clk -max 0.3 [get_ports {gth_txdata[*] gth_txheader[*]}]

# ---- False Paths ----
# Status signals are asynchronous / slow-changing — can be false-pathed
set_false_path -to [get_ports {block_lock hi_ber pcs_status rx_link_up}]
set_false_path -to [get_ports {ber_count[*] errored_blocks[*]}]
set_false_path -to [get_ports {pcs_status_ll}]
set_false_path -from [get_ports {status_read}]

# ---- Max Delay on Reset ----
set_false_path -from [get_ports {rst_n}]

# ---- Placement Hints ----
# Keep PCS logic close to GTH transceiver for minimum routing delay
# set_property LOC GTHE4_CHANNEL_X0Y0 [get_cells {u_gth_channel}]
# create_pblock pblock_pcs
# add_cells_to_pblock pblock_pcs [get_cells {u_pcs/*}]
# resize_pblock pblock_pcs -add {CLOCKREGION_X0Y0:CLOCKREGION_X0Y0}
