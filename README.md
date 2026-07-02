# Asynchronous FIFO with CDC-Aware Class-Based CRV Testbench

![Status](https://img.shields.io/badge/Status-Verification%20In%20Progress-yellow)
![RTL](https://img.shields.io/badge/RTL-Verilog-blue)
![Testbench](https://img.shields.io/badge/Testbench-SystemVerilog%20CRV-green)
![Roadmap](https://img.shields.io/badge/Roadmap-UVM%20Upgrade-orange)

A fully functional **asynchronous FIFO** designed in Verilog with Gray code pointer synchronization for safe Clock Domain Crossing (CDC). Verified using a structured **class-based constrained-random verification (CRV) testbench** in SystemVerilog, with separate clocking infrastructure for the write and read domains.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [RTL Design](#rtl-design)
- [Verification Environment](#verification-environment)
- [CDC Handling](#cdc-handling)
- [Simulation & Tool Flow](#simulation--tool-flow)
- [Current Status](#current-status)
- [Roadmap](#roadmap)

---

## Project Overview

Asynchronous FIFOs are a fundamental building block in digital systems wherever data must cross between two independent clock domains — common in SoCs, NoC interfaces, and mixed-frequency pipelines. The key challenge is avoiding metastability and ensuring correct full/empty flag generation across an asynchronous boundary.

This project covers the complete RTL-to-verification flow:

- **RTL**: Parameterizable async FIFO with Gray code synchronizers and safe flag generation
- **Testbench**: Class-based CRV environment with separate write and read drivers, each operating in their own clock domain via dedicated clocking blocks
- **Planned**: Functional coverage, SVA assertions, and a full UVM testbench upgrade

---

## Architecture

```
  Write Domain (wr_clk)          |          Read Domain (rd_clk)
  ─────────────────────────────  |  ────────────────────────────────
  Write Driver                   |         Read Driver
       │                         |              │
  Clocking Block (wr_clk)        |    Clocking Block (rd_clk)
       │                         |              │
  wr_en, wr_data ──────────────► FIFO ◄──────── rd_en
                                 │
                         ┌───────┴───────┐
                         │  Dual-Port    │
                         │  SRAM / RAM   │
                         └───────┬───────┘
                    ┌────────────┴─────────────┐
                    │     Gray Code Pointers    │
                    │  wr_ptr ──sync──► rd_clk  │
                    │  rd_ptr ──sync──► wr_clk  │
                    └──────────────────────────┘
                         full (wr domain)
                         empty (rd domain)
```

---

## RTL Design

### Parameters

| Parameter   | Default | Description                        |
|-------------|--------:|------------------------------------|
| `DATA_WIDTH`|       8 | Width of each FIFO data word        |
| `DEPTH`     |      16 | Number of entries (must be power of 2) |
| `ADDR_WIDTH`|       4 | `$clog2(DEPTH)`, auto-derived       |

### Key Design Decisions

**Gray Code Pointers** — Write and read pointers are converted to Gray code before being passed through 2-FF synchronizers into the opposite clock domain. This ensures only one bit toggles per pointer increment, eliminating the multi-bit metastability hazard of binary pointers crossing an async boundary.

**Full/Empty Flag Generation** — Flags are generated after synchronization, making them conservative (FIFO may have more space than `full` indicates, or more data than `empty` indicates) but always safe — no false empty reads or false full writes.

**2-FF Synchronizer** — Each synchronized pointer passes through two back-to-back flip-flops clocked in the destination domain, providing one full clock cycle for metastability to resolve before the pointer is used.

### File Structure

```
rtl/
├── async_fifo.v           # Top-level FIFO wrapper
├── fifo_mem.v             # Dual-port synchronous RAM
├── sync_r2w.v             # Read-to-write pointer synchronizer
├── sync_w2r.v             # Write-to-read pointer synchronizer
├── rptr_empty.v           # Read pointer + empty flag logic (rd_clk)
└── wptr_full.v            # Write pointer + full flag logic (wr_clk)
```

---

## Verification Environment

The testbench is a **class-based SystemVerilog CRV environment** with components cleanly separated by responsibility and clock domain.

### Components

| Component         | Description |
|-------------------|-------------|
| `transaction`     | Data object holding `wr_data`, `rd_data`, `wr_en`, `rd_en` |
| `generator`       | Produces constrained-random transaction streams |
| `driver`          | Drives both write and read sides using dedicated clocking blocks per domain |
| `monitor`         | Samples both write and read sides using dedicated clocking blocks per domain |
| `scoreboard`      | Receives write and read data via two separate mailboxes; checks against queue-based reference model |
| `environment`     | Instantiates and connects all components |
| `testbench top`   | DUT instantiation, clock generation, interface binding |

### CDC-Aware Clocking Strategy

The interface defines **four clocking blocks** — two for the write domain (drive and sample) and two for the read domain (drive and sample) — each locked to its respective clock. The driver and monitor use these domain-specific clocking blocks to ensure no signal is ever driven or sampled across an async boundary, which would mask real CDC bugs.

```systemverilog
//write clock domain blocks
clocking cb_wr @(posedge wr_clk);
    output din, wr_en, wr_rst_n;
    input  full;
endclocking

clocking cb_wr_mon @(posedge wr_clk);
    input  din, wr_en, wr_rst_n, full;   
endclocking
//read clock domain blocks
clocking cb_rd @(posedge rd_clk);
    output rd_en, rd_rst_n;
    input  dout, empty;
endclocking

clocking cb_rd_mon @(posedge rd_clk);
    input  rd_en, rd_rst_n, dout, empty; 
endclocking
```

The monitor pushes captured transactions to the scoreboard through **two separate mailboxes** — one for the write domain and one for the read domain — keeping the two data streams cleanly decoupled until the scoreboard correlates them.

### Test Scenarios

- **Basic write then read** — Fill FIFO partially, drain, check data integrity
- **Full condition** — Write until `full` asserts; verify no data is lost
- **Empty condition** — Read from empty FIFO; verify `empty` flag and no spurious data
- **Simultaneous read/write** — Concurrent random traffic across both clock domains
- **Clock ratio stress** — Write clock faster than read clock and vice versa
- **Back-to-back transactions** — Verify no stalls or flag glitches under sustained throughput

---

## CDC Handling

| Technique | Where Used |
|-----------|------------|
| Gray code pointer encoding | `wptr_full.v`, `rptr_empty.v` before crossing |
| 2-FF synchronizer | `sync_r2w.v`, `sync_w2r.v` for pointer domain crossing |
| 4 domain-specific clocking blocks | Drive and monitor isolation per clock domain in the TB interface |
| Conservative flag generation | `full` / `empty` derived post-synchronization |

---
Waveform Analysis
Reset & Initialization (t=50 to t=120)
wr_rst_n deasserts first at around t=50, releasing the write domain. rd_rst_n deasserts later at around t=120, releasing the read domain. This staggered reset sequence is intentional — in real systems the two clock domains may come out of reset independently, and the FIFO must handle this safely.
empty asserts cleanly to 1 immediately after reset, correctly indicating the FIFO is empty before any transactions begin. This confirms the read pointer and empty flag logic initializes correctly in the read domain.
full remains X during the window between wr_rst_n and rd_rst_n deasserting. This is expected behaviour — the full flag is computed by comparing the write pointer against the synchronized read pointer (wq2_rptr). Since the read domain is still in reset during this window, wq2_rptr has not yet produced a valid value in the write domain, making the full comparison indeterminate. Once rd_rst_n deasserts and the CDC synchronizer produces valid output, full resolves correctly.
rd_en and wr_en remain X during reset, as the driver has not yet begun sending transactions. This is correct — the driver waits until both resets deassert before the environment starts running.
Active Transaction Phase (t=120 onwards)
From t=120, both resets are deasserted and the environment begins driving transactions. wr_en and rd_en begin toggling with the 70/30 weighted distribution defined in the transaction constraints, producing a realistic mix of concurrent read and write activity across the two independent clock domains (wr_clk period = 10ns, rd_clk period = 17ns).
The asynchronous relationship between wr_clk and rd_clk is clearly visible — the two clocks are not aligned and have no phase relationship, which is the core CDC challenge this design addresses.
![Waveform](Screenshot%2026-07-02%120623.png)

## Simulation & Tool Flow

**Tools used:**
- QuestaSim (primary simulation)
- EDA Playground with Aldec Riviera-PRO
- GTKWave for waveform analysis

**Running the simulation (QuestaSim):**
```tcl
vlog rtl/*.v tb/*.sv
vsim -novopt tb_top
run -all
```

---

## Current Status

| Area | Status |
|------|--------|
| RTL Design | ✅ Complete |
| Class-based CRV testbench | ✅ Complete |
| CDC-aware clocking blocks | ✅ Complete |
| Scoreboard / reference model | ✅ Complete |
| Functional Coverage | 🔲 Planned |
| SVA Assertions | 🔲 Planned |
| UVM testbench | 🔲 Planned |

---

## Roadmap

### Phase 2 — Coverage & Assertions

- **Functional coverage**: Covergroups tracking write/read under full/empty conditions, simultaneous concurrent access, and clock frequency ratio bins
- **SVA assertions**: Formal properties for `empty` / `full` flag correctness, no data loss, no spurious reads, pointer monotonicity, and CDC synchronizer stage count
- Bind-based assertion checker to keep RTL clean

### Phase 3 — UVM Testbench Upgrade

- Migrate to full UVM architecture: `uvm_sequence_item`, `uvm_sequencer`, `uvm_driver`, `uvm_monitor`, `uvm_scoreboard`, `uvm_env`, `uvm_agent`
- Separate UVM agents for write and read domains
- Sequence library: directed corner-case sequences + constrained-random sequences
- UVM register model (RAL) consideration for parameterized depth/width
- Regression-ready with UVM phases and factory overrides

---

## Key Concepts Demonstrated

- **Clock Domain Crossing (CDC)** — Gray code encoding + 2-FF synchronization
- **Constrained-Random Verification (CRV)** — Class-based transaction generation
- **Clocking block discipline** — Domain-isolated drivers and monitors
- **Reference model verification** — Queue-based scoreboard for data integrity checking
- **Parameterizable RTL** — Configurable depth and width

---

*Part of an ongoing VLSI verification portfolio targeting RTL Design and Functional Verification roles at semiconductor companies.*

