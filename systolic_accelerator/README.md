# Self-repairing systolic neural accelerator

This subproject implements the project described in the accompanying brief:
an 8×8 signed-int8 weight-stationary MAC array with one spare column, online
checksum detection, a test-sweep localiser, runtime logical remapping, and
runtime fault injection.

The existing LLVM strength-reduction pass in the repository is kept intact;
this accelerator lives under `systolic_accelerator/` so both projects can be
built and reviewed independently.

## What is implemented

- `rtl/self_repairing_systolic.sv` — parameterized synthesizable core.
- `rtl/variants.sv` — named baseline and PPA-oriented wrappers.
- `tb/self_repairing_systolic_tb.sv` — Icarus regression test with a golden
  matrix-vector product, injected stuck-at fault, detection, localisation,
  spare-column repair, and post-repair equivalence checks.
- `openlane/config.json` — OpenLane 2 configuration targeting Sky130 HD.

The baseline evaluates each column's multiply-accumulate chain directly. The
optimized variant registers the products to shorten the critical path and
adds two activity reductions: zero-skipping for zero operands and a clock
enable around the product register bank for zero activations. Both variants
share the same repair controller and test interface, so PPA changes can be
compared without changing functionality.

The checksum is implemented as an output-channel invariant:

```text
sum(observed active outputs) == sum(golden active outputs)
```

This is the dimensionally correct form of the ABFT relation for a vector times
weight-matrix operation. On a mismatch, the controller sweeps all physical
columns with an all-ones test vector, retires the first failing column, copies
its weights into the spare, and updates the logical-to-physical map. If the
spare has already been consumed, the affected logical channel is zeroed and
`degraded` asserts, modelling graceful degradation after resource exhaustion.

## Run the RTL regression

From this directory:

```sh
make test
```

The test produces `build/systolic.vcd` for waveform inspection. The project
uses Icarus in this environment; the same sources are SystemVerilog-2012 and
can be compiled with Verilator or cocotb in CI.

## PPA experiment path

OpenLane 2 is intentionally kept separate from functional simulation. Once an
OpenLane 2 + Sky130 installation is available:

```sh
openlane openlane/config.json
```

Run the command once with `DESIGN_NAME=sr_systolic_baseline` and once with
`DESIGN_NAME=sr_systolic_optimized`. Record post-route area, worst slack, and
activity-annotated power. The optimized design trades product registers and a
two-cycle inference latency for a shorter arithmetic path and lower switching
when activations are sparse or zero-heavy.

The current container does not include OpenLane 2, Verilator, or cocotb, so the
checked-in Icarus test is the runnable local verification target here. No ASIC
area or power number is invented in the absence of a completed Sky130 run.

