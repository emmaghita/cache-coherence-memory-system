# Cache Coherence Memory System (VHDL)

This project implements a simplified **dual-core memory hierarchy** with private L1 caches and a centralized memory controller.  
The system demonstrates how hardware maintains **cache coherence** in a multi-core environment using the **MSI (Modified -Shared - Invalid) protocol** and a **snoopy bus architecture**.

The design was implemented in **VHDL using Xilinx Vivado**.

---

## System Architecture

The system models a dual-core processor architecture consisting of:

- Two processing cores (Core 0 and Core 1)
- Two private L1 caches
- A centralized memory controller
- A shared main memory module

The components communicate over a **shared bus** where transactions are monitored by all caches using a **snooping mechanism**.

According to the project architecture diagram, the Memory Controller acts as the central interconnect between the two caches and the main memory. 

---

## Key Concepts Implemented

### Dual-Core Cache System
Each processor core has its own local cache.  
This introduces the **cache coherence problem**, where different caches may hold different copies of the same memory location.

---

### MSI Cache Coherence Protocol

The system maintains data consistency using the **MSI protocol**, which defines three states for every cache line:

- **Modified (M)** - the cache contains the only updated copy; memory is stale
- **Shared (S)** - the cache line is clean and may exist in multiple caches
- **Invalid (I)** - the cache line is not valid

The protocol ensures:

- write propagation between caches
- correct ordering of writes
- read-after-write consistency

---

### Snoopy Bus Architecture

All caches monitor the shared bus to detect transactions from other cores.  
This **bus snooping mechanism** allows caches to:

- detect remote reads or writes
- invalidate local copies when necessary
- supply modified data to other caches if required

---

### Memory Controller (Central Arbiter)

The **Memory Controller** coordinates communication between caches and main memory.

Responsibilities include:

- bus arbitration between cores
- managing memory transactions
- broadcasting snoop requests
- coordinating cache-to-cache transfers

To resolve simultaneous access requests, the controller implements a **Round-Robin arbitration policy** that alternates priority between cores to prevent starvation

---

### Write-Back Cache Policy

The cache uses a **write-back policy**, meaning:

- writes update the cache first
- main memory is updated only when a modified cache line is evicted

This reduces memory traffic and improves performance

---

### Write-Allocate Policy

On a write miss:

1. The cache fetches the entire memory line.
2. The CPU modifies the desired byte.
3. The cache maintains the updated line locally.

This ensures cache blocks always remain complete and consistent.

---

## Hardware Modules

Main VHDL components in the project:

| Module | Description |
|------|------|
| `cache.vhd` | Top-level cache module |
| `cache_controller.vhd` | FSM controlling cache operations |
| `cache_datapath.vhd` | Data storage (data array, tag array, MSI state) |
| `memory_ctrl.vhd` | Central memory controller and bus arbiter |
| `MainMemory.vhd` | Behavioral model of main memory |
| `tlm.vhd` | Top-level module connecting all components |
| `MMU_package.vhd` | Global constants and protocol types |

---

## Simulation

The system was validated using behavioral simulations that test:

- cache read misses
- shared data access
- write invalidation
- ownership transfer between cores
- conflict eviction and write-back
- simultaneous bus contention

These scenarios confirm the correct implementation of the **MSI protocol and memory arbitration logic**.

---

## Tools

- VHDL
- Xilinx Vivado
- Behavioral Simulation
