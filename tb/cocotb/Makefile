# Makefile for cocotb testbench — 10GBASE-R PCS Core

# Simulator
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Source files
VERILOG_SOURCES = \
    $(PWD)/../../rtl/pcs_10g_enc_64b66b.v \
    $(PWD)/../../rtl/pcs_10g_dec_64b66b.v \
    $(PWD)/../../rtl/pcs_10g_scrambler.v \
    $(PWD)/../../rtl/pcs_10g_descrambler.v \
    $(PWD)/../../rtl/pcs_10g_tx_gearbox.v \
    $(PWD)/../../rtl/pcs_10g_rx_gearbox.v \
    $(PWD)/../../rtl/pcs_10g_block_sync.v \
    $(PWD)/../../rtl/pcs_10g_ber_monitor.v \
    $(PWD)/../../rtl/pcs_10g_top.v

# Include path for params header
COMPILE_ARGS += -I$(PWD)/../../rtl

# Top-level module
TOPLEVEL = pcs_10g_top

# Python test module
MODULE = test_pcs_10g

# Waveform dump
SIM_ARGS += -lxt2

include $(shell cocotb-config --makefiles)/Makefile.sim
