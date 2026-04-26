SIM ?= iverilog
RUN ?= vvp
SIMV ?= simv
VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim

RTL := rtl/rv32i_core.v rtl/sram_1cycle.v rtl/little_soc.v
TB  := tb/little_soc_tb.v

.PHONY: sim questa clean

sim:
	$(SIM) -g2005-sv -o $(SIMV) $(RTL) $(TB)
	$(RUN) $(SIMV)

questa:
	$(VLIB) work
	$(VLOG) -sv $(RTL) $(TB)
	$(VSIM) -c little_soc_tb -do "run -all; quit"

clean:
	rm -rf $(SIMV) work transcript vsim.wlf
