# little_soc

`little_soc` is a compact RV32I system-on-chip written in Verilog. It contains a
multi-cycle RISC-V CPU and a single-port SRAM model with standard address, data,
chip-select, write-enable, and byte-enable signals.

## Contents

- `rtl/rv32i_core.v` - multi-cycle RV32I CPU core.
- `rtl/sram_1cycle.v` - register-backed SRAM model with 1-cycle read latency.
- `rtl/tpu_sram.v` - register-modeled SRAM block used by TPU local storage.
- `rtl/tpu_pe.v` - systolic-array processing element (MAC + forwarding).
- `rtl/tpu_systolic_array.v` - PE mesh and wavefront data scheduling.
- `rtl/tensorpu.v` - TPU MMIO controller with SRAM-backed matrix buffers.
- `rtl/little_soc.v` - SoC top level that connects the CPU and SRAM.
- `tb/little_soc_tb.v` - smoke-test testbench.
- `tb/tensorpu_tb.v` - standalone TPU matrix-multiply testbench.
- `sw/smoke.hex` - hex image loaded by the smoke test.
- `Makefile` - convenience targets for simulation.

## CPU Scope

The CPU implements the base RV32I integer instruction set needed for small
bare-metal programs:

- Integer arithmetic and logical operations.
- Immediate arithmetic and logical operations.
- Loads and stores with byte enables.
- Conditional branches.
- `JAL`, `JALR`, `LUI`, and `AUIPC`.
- `EBREAK` as a simulation halt instruction.

Floating-point, compressed instructions, atomics, interrupts, privilege modes,
and CSRs are intentionally out of scope. The reset vector is address `0x00000000`.
Unsupported instructions, misaligned instruction fetches, and misaligned data
accesses halt the core.

## Memory Interface

The CPU exposes a simple SRAM-style interface:

```verilog
mem_cs      // chip select
mem_we      // write enable
mem_be[3:0] // byte write enable
mem_addr    // byte address
mem_wdata   // write data
mem_rdata   // read data returned after one clock
```

The SRAM model is word-organized internally and accepts byte addresses. Reads
are synchronous: when `cs` is asserted, `rdata` updates on the next rising clock
edge. Writes use `be` to update individual byte lanes.

## TPU (Systolic Array)

The TPU remains memory-mapped at `TPU_BASE_ADDR` in `little_soc` and is still
controlled by CPU loads/stores. Internally it is split into modules:

- `tensorpu`: register decode, run-state machine, SRAM load/store orchestration.
- `tpu_sram`: local matrix storage for A/B/C (register-simulated SRAM).
- `tpu_systolic_array`: NxN PE grid with wavefront feed scheduling.
- `tpu_pe`: per-cell multiply-accumulate and A/B forwarding.

Current MMIO map (offset from TPU base):

- `0x00` control (`bit0=start`, `bit1=clear_done`)
- `0x04` status (`bit0=busy`, `bit1=done`)
- `0x08` config (`{rows, cols}` both equal to `DIM`)
- `0x10..` A matrix words (row-major)
- `0x40..` B matrix words (row-major)
- `0x80..` C matrix words (row-major)

## Running the Smoke Test

With Icarus Verilog installed:

```sh
make sim
```

For standalone TPU verification:

```sh
make sim_tpu
```

With Questa or ModelSim installed:

```sh
make questa
```

The testbench loads a small program into SRAM, executes it, stores `12` at
address `0x60`, reloads it, verifies a taken branch, and halts on `EBREAK`.
