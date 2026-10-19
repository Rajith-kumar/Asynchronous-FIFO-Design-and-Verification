# Asynchronous FIFO — Dual-Clock RTL Design and Verification

A **parameterizable asynchronous FIFO** written in Verilog HDL for transferring ordered data between **independent write and read clock domains**. The design uses Gray-coded pointers, two-flop pointer synchronizers, and full/empty detection. Tested with Xilinx Vivado 2024.2 for a Kintex-7 FPGA target.

> **Project status:** RTL was synthesized and placed/routed in Vivado. The provided utilization and routed timing figures are from actual Vivado reports. The initial testbench full-condition check was observed; **a final full-testbench PASS log has not yet been provided for this repository**. Timing meets the *specified internal clock constraints*, but the design still requires I/O timing, Gray-bus CDC constraints, and CDC/reset review before hardware signoff.

## Highlights

- Independent write and read clocks; **first-word-fall-through (FWFT)** read interface.
- Parameterized data width and power-of-two FIFO depth.
- Binary pointers for memory addressing and Gray pointers for clock-domain crossing.
- Two-stage flip-flop synchronizers for pointer transfer (`ASYNC_REG` attributes included).
- Full/empty flag generation, with writes blocked on `full` and reads blocked on `empty`.
- Reproducible Verilog testbench with independent clocks, randomized traffic, scoreboarding, and drain checks.
- Vivado FPGA synthesis and routed timing reports for the default configuration.

## Architecture

```text
           WRITE CLOCK DOMAIN                       READ CLOCK DOMAIN

 wr_data --> [ FIFO memory: 2^ADDR_WIDTH entries ] --> rd_data (FWFT)
   wr_en --> [ Write enable / address ]              [ Read address ] <-- rd_en
                  ^                                       ^
                  |                                       |
             Write binary ptr                       Read binary ptr
                  |                                       |
             Write Gray ptr                        Read Gray ptr
                  |                                       |
                  +--> 2-FF synchronizer --> empty compare (read domain)
                  ^                                       |
                  |                                       v
           full compare <-- 2-FF synchronizer <-- Read Gray ptr
           (write domain)
```

Pointers carry an extra wrap bit to distinguish `full` from `empty`. Only Gray-coded pointers are crossed; each pointer's comparison is performed in the receiving clock domain. Because the pointers take multiple cycles to synchronize, status flags can update conservatively.

## Project files

A suggested clean GitHub layout:

```text
Asynchronous-FIFO-RTL-Design/
├── README.md
├── rtl/
│   └── async_fifo.v
├── tb/
│   └── tb_async_fifo.v
├── constraints/
│   └── async_fifo.xdc             # Add your actual Vivado XDC
└── results/
    ├── utilization_report.txt    # Export from Vivado
    ├── timing_summary.txt        # Export from Vivado
    ├── simulation_log.txt        # Add after complete PASS/FAIL run
    └── waveform.png              # Optional waveform screenshot
```

Only include files you actually have. Do **not** commit Vivado `*.cache`, `*.runs`, `*.sim`, `.Xil`, or other generated temporary directories.

## Parameters and interface

| Parameter | Default | Meaning |
|---|---:|---|
| `DATA_WIDTH` | 16 | Number of bits per FIFO word |
| `ADDR_WIDTH` | 3 | FIFO address bits (`ADDR_WIDTH >= 2`) |
| `DEPTH` | 8 | `2**ADDR_WIDTH` entries, derived internally |

| Signal | Direction | Description |
|---|---|---|
| `wr_clk` | Input | Write-domain clock |
| `wr_rst_n` | Input | Active-low write-domain reset |
| `wr_en` | Input | Write request |
| `wr_data[DATA_WIDTH-1:0]` | Input | Data to write |
| `full` | Output | Write-side full flag |
| `rd_clk` | Input | Read-domain clock |
| `rd_rst_n` | Input | Active-low read-domain reset |
| `rd_en` | Input | Read request |
| `rd_data[DATA_WIDTH-1:0]` | Output | Combinational FIFO-head data (valid when `!empty`) |
| `empty` | Output | Read-side empty flag |

On a positive edge of `wr_clk`, a write is **accepted** only if `wr_en && !full`. On a positive edge of `rd_clk`, a read is **consumed** only if `rd_en && !empty`. The head data is visible without asserting `rd_en` when the FIFO is nonempty; this is an FWFT-style asynchronous-read interface.

**Reset assumption:** Assert both resets together at initialization; independent reset of one active domain is not supported by this implementation. Coordinate reset release appropriately for real hardware.

## How to simulate in Xilinx Vivado

1. Create a **new RTL project** in Vivado 2024.2.
2. Add `rtl/async_fifo.v` under **Design Sources**.
3. Add `tb/tb_async_fifo.v` under **Simulation Sources**.
4. Set **`tb_async_fifo` as Simulation Top**.
5. Choose **Run Behavioral Simulation**.
6. In the Tcl Console, enter:

   ```tcl
   run all
   ```

7. Review the Tcl Console for the **final** `PASS` or `FAIL` message. An initial `CHECK: full flag asserted after 8 accepted writes` confirms only the initial fill check, **not** the entire regression.

The included Verilog testbench uses a **10 ns write clock and 14 ns read clock** (100 MHz and approximately 71.43 MHz in simulation). It tests filling the FIFO, attempts to write while full, overlapping pseudo-random write/read traffic, ordered data comparisons, pointer wraparound, draining, and a timeout.

**Expected success-message format** (illustrative only; not a recorded test result):

```text
CHECK: full flag asserted after 8 accepted writes
PASS: <N> FIFO words verified in order
PASS: blocked writes=<X>; blocked reads=<Y>
PASS: different clock domains, full/empty, wraparound and drain exercised
```

Record the real console output in `results/simulation_log.txt` once you have confirmed it. A waveform screenshot can show `wr_clk`, `rd_clk`, `wr_en`, `rd_en`, `wr_data`, `rd_data`, `full`, `empty`, and pointer signals.

## Synthesis results (measured)

**Tool:** AMD/Xilinx Vivado 2024.2  
**FPGA target:** Kintex-7 `xc7k70tfbv676-1`  
**RTL configuration:** `DATA_WIDTH=16`, `ADDR_WIDTH=3` (8 words × 16 bits)

| FPGA resource | Post-synthesis utilization |
|---|---:|
| Slice LUTs | **58** |
| Slice registers / flip-flops | **160** |
| F7 multiplexers | 16 |
| Block RAM tiles | 0 |
| DSP slices | 0 |
| BUFG | 2 |
| Inferred latches | **0** |
| Black boxes | **0** |

This small FIFO was mapped to flip-flops and logic rather than block RAM. The design uses asynchronous head-data reading and includes a distributed-memory style attribute; **do not describe it as a BRAM-based FIFO**. These are post-synthesis counts, not final post-route resource counts.

## Routed timing results (measured, scoped)

**Tool:** Vivado 2024.2, routed design, Kintex-7 `xc7k70tfbv676-1`.

| Clock / metric | Reported value |
|---|---:|
| Write-clock constraint | **10.000 ns (100 MHz)** |
| Read-clock constraint | **12.500 ns (80 MHz)** |
| Worst negative setup slack (WNS) | **+7.603 ns** |
| Worst hold slack (WHS) | **+0.108 ns** |
| Total negative slack (TNS) | **0.000 ns** |
| Total hold slack (THS) | **0.000 ns** |
| Failing internal setup / hold endpoints | **0 / 0** |

Vivado reported **"All user specified timing constraints are met"** for the paths that were constrained. **This is not a measurement of maximum supported frequency**; 100 MHz and 80 MHz are user-selected clock targets, distinct from the testbench read-clock rate.

### Timing / CDC limitations

The timing report also reports **20 inputs without input-delay constraints** and **18 outputs without output-delay constraints**, and the asynchronous cross-domain paths were excluded from ordinary setup/hold timing using clock groups. Therefore:

- Internal clock-domain paths meet the configured clock periods; **system-level I/O timing is not signed off**.
- The Gray-pointer crossings need physical CDC review, including pointer-bus skew/maximum-delay treatment as appropriate; merely declaring the clocks asynchronous does not guarantee all sampled Gray bits stay coherent.
- Synchronizers need structural CDC checking, placement review, and reset-release analysis before real hardware deployment.
- Behavioral simulation does not model analog metastability. Formal verification and on-board validation have not been reported.

## How to reproduce synthesis and timing

1. Set **`async_fifo` as Design Top** (do not synthesize the testbench).
2. Choose the target device `xc7k70tfbv676-1` if you want comparable results.
3. Add an XDC with intended write/read clock periods. The measured timing run used:

   ```tcl
   create_clock -name wr_clk -period 10.000 [get_ports wr_clk]
   create_clock -name rd_clk -period 12.500 [get_ports rd_clk]
   set_clock_groups -asynchronous -group [get_clocks wr_clk] -group [get_clocks rd_clk]
   ```

   **Example only:** this is *not* a complete signoff-quality CDC or board I/O constraint set. Add constraints appropriate to the actual integration and review pointer crossing timing rather than relying only on global false paths.

4. Run **Synthesis** and save **Report Utilization**.
5. Run **Implementation** through **Route Design** and save **Report Timing Summary** (including unconstrained paths).
6. If proceeding to hardware, review **Report CDC**, reset behavior, clock/pin constraints, and interface requirements.

## Design limitations and next steps

- The FWFT, asynchronous-read architecture is suitable as a **small educational FIFO**; larger FPGA FIFOs may benefit from a synchronous-read BRAM implementation or vendor FIFO IP.
- The FIFO depth must be a power of two, and `ADDR_WIDTH` is required to be at least 2 for the pointer-comparison indexing used here.
- Full and empty flags may deassert later than strictly necessary because synchronized pointers have latency.
- The two resets must be coordinated. Independent in-service resets are not supported.
- Suggested future verification: additional clock ratios, simultaneous boundary transactions, reset sequencing, assertion-based checks, CDC analysis, and hardware integration.

## Skills demonstrated

**Verilog HDL · RTL Design · Digital Electronics · Dual-Clock FIFOs · Gray Coding · Clock-Domain Crossing · Testbench Development · FPGA Synthesis · Static Timing Analysis · Xilinx Vivado**

## License

Add a license of your choice if you want to define reuse permissions for the public repository.
