SIM ?= iverilog
RUN ?= vvp
SIMV ?= simv
VLIB ?= vlib
VLOG ?= vlog
VSIM ?= vsim

RTL := rtl/rv32i_core.v rtl/sram_1cycle.v rtl/tpu_sram.v rtl/tpu_pe.v rtl/tpu_systolic_array.v rtl/tensorpu.v rtl/little_soc.v
TB  := tb/little_soc_tb.v

.PHONY: sim sim_tpu questa clean

TPU_TB := tb/tensorpu_tb.v

sim:
	$(SIM) -g2005-sv -o $(SIMV) $(RTL) $(TB)
	$(RUN) $(SIMV)

sim_tpu:
	$(SIM) -g2005-sv -o $(SIMV) rtl/tpu_sram.v rtl/tpu_pe.v rtl/tpu_systolic_array.v rtl/tensorpu.v $(TPU_TB)
	$(RUN) $(SIMV)

questa:
	$(VLIB) work
	$(VLOG) -sv $(RTL) $(TB)
	$(VSIM) -c little_soc_tb -do "run -all; quit"

clean:
	rm -rf $(SIMV) work transcript vsim.wlf
