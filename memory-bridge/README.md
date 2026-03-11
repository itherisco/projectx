# Memory Bridge - Phase 3 of ITHERIS Ω

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Directory Structure](#directory-structure)
4. [Data Flow](#data-flow)
   - [1. Sensory Observation (Rust → Julia)](#1-sensory-observation-rust--julia)
   - [2. Active Inference Processing (Julia)](#2-active-inference-processing-julia)
   - [3. Inference Response (Julia → Rust)](#3-inference-response-julia--rust)
5. [Shared Memory Protocol](#shared-memory-protocol)
   - [Memory Regions](#memory-regions)
   - [Synchronization](#synchronization)
6. [Usage](#usage)
   - [Rust Side](#rust-side)
   - [Julia Side](#julia-side)
7. [Technical Specifications](#technical-specifications)
8. [HDC Integration](#hdc-integration)
9. [Completion Criteria](#completion-criteria)
10. [Files Created](#files-created)

## Overview

This module implements the **Shared Memory Bridge** between the Rust Wasmtime Host (Phase 1) and the Julia Active Inference Engine (Phase 2). It enables the cognitive loop where Rust writes sensory data and Julia reads it to update HDC vectors.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ITHERIS Ω Cognitive Loop                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [Rust Sentry] ──► [Shared Memory] ──► [Julia Active Inference]            │
│         │                ↑                       │                           │
│         │                │                       ▼                           │
│         │          [HDC Vectors] ◄── [Prediction Error]                     │
│         │                ↑                       │                           │
│         │                │                       ▼                           │
│  [Rust Action] ◄── [Shared Memory] ◄── [Policy Selection]                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
memory-bridge/
├── rust/                    # Rust side of the bridge
│   ├── src/
│   │   └── lib.rs          # Shared memory implementation
│   └── Cargo.toml
├── julia/                   # Julia side of the bridge
│   ├── src/
│   │   ├── MemoryBridge.jl     # Core shared memory client
│   │   └── BridgeIntegration.jl # Integration with ActiveInference
│   └── Project.toml
├── test_bridge.jl          # Test script
└── README.md               # This file
```

## Data Flow

### 1. Sensory Observation (Rust → Julia)
- **Source**: Sentry (anomaly detection), Librarian, or Action
- **Data**: Timestamp, source, data type, raw values
- **Format**: JSON serialized to shared memory file

### 2. Active Inference Processing (Julia)
- Read observation from shared memory
- Compute prediction error using generative model
- Update HDC vectors for conceptual associations
- Minimize free energy

### 3. Inference Response (Julia → Rust)
- Prediction error
- Predicted values
- Updated HDC bindings
- Selected policy
- Free energy value

## Shared Memory Protocol

### Memory Regions
- `itheris_observations.shm` - Sensory observations from Rust
- `itheris_inference.shm` - Inference responses from Julia  
- `itheris_hdc.shm` - HDC vector bindings

### Synchronization
- File-based locks for mutual exclusion
- Event files for signaling new data
- Polling-based notification (10-100 Hz)

## Usage

### Rust Side

```rust
use memory_bridge::{MemoryBridge, SensorySource, DataType};
use std::sync::Arc;

// Create bridge
let bridge = Arc::new(MemoryBridge::new("/tmp/itheris_shm".into()).unwrap());

// Write sensory observation (from Sentry)
let obs_id = bridge.write_sensory(vec![1.0, 2.0, 3.0]);

// Write anomaly detection
let anomaly_id = bridge.write_anomaly(vec![1.5, 2.5], "high");

// Wait for inference response
if let Some(response) = bridge.wait_for_inference(5000, obs_id) {
    println!("Prediction error: {}", response.prediction_error);
    println!("Free energy: {}", response.free_energy);
}
```

### Julia Side

```julia
using MemoryBridge
using BridgeIntegration

# Create cognitive bridge
bridge = create_cognitive_bridge()
initialize_bridge(bridge)

# Run cognitive loop
run_full_cognitive_loop(bridge, timeout_ms=5000)

# Or run continuous loop
run_continuous(bridge, duration_s=60.0)
```

## Technical Specifications

- **Memory**: Memory-mapped files (mmap) via file I/O
- **Serialization**: JSON for structured data exchange
- **Synchronization**: File-based locks + event notification
- **Frequency**: Supports 10-100 Hz sensor data

## HDC Integration

The bridge integrates with the HDC (Hyperdimensional Computing) memory:

- **Binding**: Element-wise multiplication of HD vectors
- **Bundling**: Addition of HD vectors
- **Recall**: Cosine similarity for retrieval

## Completion Criteria

✅ Rust code structure for shared memory writing  
✅ Julia code for shared memory reading  
✅ Sensory data format (timestamp, source, data type, raw values)  
✅ Cognitive loop integration  
✅ Synchronization primitives (locks, atomic operations)  
✅ Complete cognitive loop: sense → infer → act

## Files Created

1. `memory-bridge/rust/src/lib.rs` - Rust shared memory implementation
2. `memory-bridge/rust/Cargo.toml` - Rust package configuration
3. `memory-bridge/julia/src/MemoryBridge.jl` - Julia shared memory client
4. `memory-bridge/julia/src/BridgeIntegration.jl` - Integration with ActiveInference
5. `memory-bridge/julia/Project.toml` - Julia package configuration
6. `memory-bridge/test_bridge.jl` - Test script
7. `memory-bridge/README.md` - This documentation
