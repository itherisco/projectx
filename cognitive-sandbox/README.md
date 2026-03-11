# Cognitive Sandbox - Wasmtime Runtime Host

**Phase 1 of ITHERIS Ω Bio-mimetic Cognitive Architecture**

A Wasmtime-based runtime host for dynamically loading and executing WebAssembly agent modules in the holonic swarm system.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
   - [Core Components](#core-components)
   - [WASM Interface Contract](#wasm-interface-contract)
3. [Building](#building)
   - [Prerequisites](#prerequisites)
   - [Build the Rust project](#build-the-rust-project)
   - [Build Wasm modules](#build-wasm-modules-optional)
4. [Usage](#usage)
   - [CLI Commands](#cli-commands)
   - [Programmatic Usage](#programmatic-usage)
5. [IPC Mechanism](#ipc-mechanism)
6. [Logging](#logging)
7. [Project Structure](#project-structure)
8. [Phase Status](#phase-status)
9. [License](#license)

## Overview

This module provides the foundational infrastructure for hot-loading agent Wasm modules:

- **Sentry Agent**: Threat detection and monitoring
- **Librarian Agent**: Memory and knowledge management  
- **Action Agent**: Execution and task handling

## Architecture

### Core Components

- [`HostRuntime`](src/lib.rs:88): Main runtime managing Wasmtime engine and module instances
- [`AgentModule`](src/lib.rs:70): Represents a loaded Wasm agent module
- [`AgentInstance`](src/lib.rs:80): Live instance with execution context
- [`IpcChannel`](src/lib.rs:165): Julia↔Rust inter-process communication

### WASM Interface Contract

All agent modules must implement:

```wasm
;; Required exports
(export "init" (func $init))        ;; Initialize agent
(export "process" (func $process))  ;; Main processing function

;; Optional exports
(export "get_threat_level" ...)      ;; Sentry-specific
(export "query" ...)                 ;; Librarian-specific
(export "execute" ...)               ;; Action-specific
```

Required imports from host:

```wasm
(import "host" "log" (func $log (param i32 i32 i32)))
(import "host" "allocate" (func $allocate (param i32) (result i32)))
(import "host" "deallocate" (func $deallocate (param i32 i32)))
(import "host" "get_agent_id" (func $get_agent_id (result i32)))
```

## Building

### Prerequisites

- Rust 1.70+
- wasmtime 14.0

### Build the Rust project

```bash
cd cognitive-sandbox
cargo build --release
```

### Build Wasm modules (optional)

Requires [WABT](https://github.com/WebAssembly/wabt):

```bash
chmod +x build_wasm.sh
./build_wasm.sh
```

Or install wat2wasm and manually compile:

```bash
wat2wasm modules/sentry.wat -o target/wasm/sentry.wasm
wat2wasm modules/librarian.wat -o target/wasm/librarian.wasm
wat2wasm modules/action.wat -o target/wasm/action.wasm
```

## Usage

### CLI Commands

```bash
# Load a Wasm module
cargo run -- load target/wasm/sentry.wasm sentry

# List loaded modules
cargo run -- list-modules

# Instantiate as Sentry agent
cargo run -- instantiate <module-id> sentry

# Invoke a function
cargo run -- invoke <instance-id> process 0 0

# Hot-swap an instance
cargo run -- hot-swap <module-id> <instance-id>

# Run demonstration
cargo run -- demo
```

### Programmatic Usage

```rust
use cognitive_sandbox::{HostRuntime, AgentType};

let mut runtime = HostRuntime::new()?;

// Load module
let module_id = runtime.load_module("sentry.wasm", "sentry")?;

// Instantiate
let instance_id = runtime.instantiate(module_id, AgentType::Sentry)?;

// Invoke
let result = runtime.invoke(instance_id, "process", &[0, 0])?;

// Hot-swap
let new_instance_id = runtime.hot_swap(new_module_id, instance_id)?;
```

## IPC Mechanism

The runtime provides an IPC channel for Julia↔Rust communication:

```rust
use cognitive_sandbox::{IpcMessage, IpcChannel};

// Send to Julia
let msg = IpcMessage::new("rust", "julia", payload);
ipc_channel.send(msg);

// Receive from Julia
if let Some(msg) = ipc_channel.receive() {
    // Handle message
}
```

## Logging

Logs are written to:
- Console (stdout)
- `logs/cognitive-sandbox.log` (rolling, daily rotation)

Log levels: DEBUG, INFO, WARN, ERROR

## Project Structure

```
cognitive-sandbox/
├── Cargo.toml
├── src/
│   ├── lib.rs      # Core runtime implementation
│   └── main.rs     # CLI entry point
├── modules/
│   ├── sentry.wat      # Sentry agent source
│   ├── librarian.wat  # Librarian agent source
│   └── action.wat     # Action agent source
├── build_wasm.sh   # Wasm build script
└── README.md
```

## Phase Status

- ✅ Phase 1: Wasmtime host runtime (complete)
- ⏳ Phase 2: Full Active Inference brain
- ⏳ Phase 3: eBPF kernel probes

## License

Same as ITHERIS Ω project.
