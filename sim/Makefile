# =============================================================================
# Makefile — 10GBASE-R PCS Simulation (Icarus Verilog)
# =============================================================================

IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave

RTL_DIR  = ../rtl
TB_DIR   = ../tb/verilog

# RTL Sources
RTL_SRCS = \
    $(RTL_DIR)/pcs_10g_enc_64b66b.v \
    $(RTL_DIR)/pcs_10g_dec_64b66b.v \
    $(RTL_DIR)/pcs_10g_scrambler.v \
    $(RTL_DIR)/pcs_10g_descrambler.v \
    $(RTL_DIR)/pcs_10g_tx_gearbox.v \
    $(RTL_DIR)/pcs_10g_rx_gearbox.v \
    $(RTL_DIR)/pcs_10g_block_sync.v \
    $(RTL_DIR)/pcs_10g_ber_monitor.v \
    $(RTL_DIR)/pcs_10g_top.v

# Include path
INC = -I$(RTL_DIR)

# Common flags
IVFLAGS = -g2012 -Wall $(INC)

# ==== Targets ====

.PHONY: all top encoder scrambler clean wave help

all: top encoder scrambler

# Full PCS loopback test
top: tb_pcs_10g.vvp
	$(VVP) $< | tee top_results.log

tb_pcs_10g.vvp: $(TB_DIR)/tb_pcs_10g.v $(RTL_SRCS)
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# Encoder unit test
encoder: tb_encoder.vvp
	$(VVP) $< | tee encoder_results.log

tb_encoder.vvp: $(TB_DIR)/tb_pcs_10g_encoder.v $(RTL_DIR)/pcs_10g_enc_64b66b.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# Scrambler unit test
scrambler: tb_scrambler.vvp
	$(VVP) $< | tee scrambler_results.log

tb_scrambler.vvp: $(TB_DIR)/tb_scrambler.v $(RTL_DIR)/pcs_10g_scrambler.v $(RTL_DIR)/pcs_10g_descrambler.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# Waveform viewer
wave:
	$(GTKWAVE) tb_pcs_10g.vcd &

clean:
	rm -f *.vvp *.vcd *.log *.lxt2

help:
	@echo "Targets:"
	@echo "  all        - Run all tests"
	@echo "  top        - Run full PCS loopback test"
	@echo "  encoder    - Run encoder unit test"
	@echo "  scrambler  - Run scrambler unit test"
	@echo "  wave       - Open waveform viewer"
	@echo "  clean      - Remove generated files"
