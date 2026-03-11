# ProjectX - Neuro-Symbolic Autonomous Cognitive System

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Julia](https://img.shields.io/badge/Julia-1.10+-9558B2)
![Rust](https://img.shields.io/badge/Rust-stable-b7410e)
![Status](https://img.shields.io/badge/status-Active-green)

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Key Components](#key-components)
4. [System Layers](#system-layers)
   - [1. Communication Layer](#1-communication-layer-cerebral-cortex)
   - [2. ITHERIS Brain](#2-itheris-brain-the-brain)
   - [3. Adaptive Kernel](#3-adaptive-kernel-safety-valve)
   - [4. Semantic Memory](#4-semantic-memory-qdrant)
5. [Directory Structure](#directory-structure)
6. [Quick Start](#quick-start)
   - [Prerequisites](#prerequisites)
   - [Installation](#installation)
   - [Running the Adaptive Kernel](#running-the-adaptive-kernel)
   - [Running Tests](#running-tests)
7. [Adaptive Kernel Design](#adaptive-kernel-design)
   - [Core Abstractions](#core-abstractions)
8. [Dual-Process Architecture](#dual-process-architecture)
9. [Configuration](#configuration)
10. [Technology Stack](#technology-stack)
11. [Safety Features](#safety-features)
12. [Development Status](#development-status)
13. [License](#license)
14. [Documentation](#documentation)

## Overview

**ProjectX** is a cutting-edge Neuro-Symbolic Autonomous System that merges high-level LLM reasoning with low-level deterministic safety. It implements a cognitive architecture inspired by the Free Energy Principle (FEP), combining symbolic reasoning with neural networks in a bio-mimetic design.

The system evolves from the ITHERIS Brain to a fully integrated, proactive personal assistant with safety-first design principles.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PROJECTX ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     CEREBRAL CORTEX (LLM Layer)                     │   │
│  │                                                                       │   │
│  │  ┌─────────────┐  ┌──────────────────┐  ┌─────────────────────────┐  │   │
│  │  │  GPT-4o    │  │  Claude 3.5       │  │  Natural Language      │  │   │
│  │  │  Bridge    │  │  Bridge           │  │  Parser                │  │   │
│  │  └──────┬──────┘  └────────┬─────────┘  └───────────┬─────────────┘  │   │
│  │         │                  │                       │                  │   │
│  │         └──────────────────┼───────────────────────┘                  │   │
│  │                            │                                          │   │
│  │                    ┌──────▼──────┐                                    │   │
│  │                    │   LLMBridge │  ◄─── Async LLM Communication     │   │
│  │                    └──────┬──────┘                                    │   │
│  └───────────────────────────┼────────────────────────────────────────────┘   │
│                              │                                                 │
│                              ▼                                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                  ITHERIS REINFORCEMENT BRAIN                         │   │
│  │                                                                       │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │                    BrainCore (itheris.jl)                      │ │   │
│  │  │                                                                  │ │   │
│  │  │   12-Dimensional Feature Vector ──► Neural Network ──► Actions │ │   │
│  │  │                                                                  │ │   │
│  │  │   • Episodic Learning      • Dream/Imagination                  │ │   │
│  │  │   • Action Proposals       • Value Estimation                   │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  └───────────────────────────┬────────────────────────────────────────────┘   │
│                              │                                                 │
│                              ▼                                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    ADAPTIVE KERNEL (Safety Valve)                    │   │
│  │                                                                       │   │
│  │  • ≤400 lines of auditable Julia code                                │   │
│  │  • Deterministic decision logic                                     │   │
│  │  • Permission-gated action execution                                │   │
│  │  • Append-only event logging                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Components

| Component | Language | Description |
|-----------|----------|-------------|
| **jarvis/** | Julia | Main neuro-symbolic system with LLM integration |
| **adaptive-kernel/** | Julia | Minimal cognitive kernel (≤400 lines) for safe decision making |
| **active-inference/** | Julia | Active inference engine based on Free Energy Principle |
| **cognitive-sandbox/** | Rust | Wasmtime runtime for WebAssembly agent modules |
| **memory-bridge/** | Julia/Rust | Shared memory bridge between Rust and Julia |
| **jarvis_nerves/** | Rust | System 1 (reflex) + System 2 (reasoning) driver |

## System Layers

### 1. Communication Layer (Cerebral Cortex)
- Text Input Gateway
- Intent Recognition Engine
- Goal Constructor + Feature Encoder

### 2. ITHERIS Brain (The Brain)
- 12D Feature Vector
- Flux.jl Neural Network
- Thought Output

### 3. Adaptive Kernel (Safety Valve)
- Goal Manager
- Action Selector
- Permission Handler
- Capability Registry

### 4. Semantic Memory (Qdrant)
- Preference Vector Store
- Context History
- Knowledge Base

## Directory Structure

```
projectx/
├── README.md                    # This file
├── Manifest.md                  # Architecture manifest
├── config.toml                  # Configuration template
├── Project.toml                # Julia project file
│
├── jarvis/                     # Main Jarvis system (Julia)
│   ├── src/
│   │   ├── Jarvis.jl          # Main entry point
│   │   ├── SystemIntegrator.jl # System orchestration
│   │   ├── types.jl           # Core type definitions
│   │   ├── bridge/            # Communication bridges
│   │   ├── llm/               # LLM integration
│   │   ├── memory/            # Memory systems
│   │   └── orchestration/     # Task orchestration
│   └── ui/                    # Dashboard UI (TypeScript)
│
├── adaptive-kernel/            # Cognitive kernel (Julia)
│   ├── kernel/                # Core kernel logic
│   ├── cognition/             # Cognitive agents
│   ├── capabilities/          # System capabilities
│   ├── planning/              # Hierarchical planning
│   ├── memory/                # Vector store
│   └── tests/                 # Test suite
│
├── active-inference/          # Active inference (Julia)
│   ├── ActiveInference.jl    # Core FEP implementation
│   └── test_active_inference.jl
│
├── cognitive-sandbox/         # Wasm sandbox (Rust)
│   ├── src/
│   │   ├── lib.rs            # Wasmtime host runtime
│   │   └── main.rs           # Entry point
│   └── modules/              # Wasm agent modules
│
├── memory-bridge/             # Julia-Rust bridge
│   ├── rust/                 # Rust shared memory
│   └── julia/                # Julia client
│
└── jarvis_nerves/             # Rust driver
    └── src/
        ├── main.rs           # Entry point
        └── reflex/           # System 1 reflex layer
```

## Quick Start

### Prerequisites

- Julia 1.10+
- Rust (stable)
- Docker (for OpenClaw tools)

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd projectx
```

2. Install Julia dependencies:
```bash
cd adaptive-kernel
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

3. Configure the system:
```bash
cp config.toml.template config.toml
# Edit config.toml with your API keys
```

### Running the Adaptive Kernel

```bash
cd adaptive-kernel
julia --project=. harness/run.jl --cycles 20
```

### Running Tests

```bash
# Unit tests
cd adaptive-kernel
julia --project=. -e 'include("tests/unit_kernel_test.jl")'
julia --project=. -e 'include("tests/unit_capability_test.jl")'

# Integration tests
julia --project=. -e 'include("tests/integration_simulation_test.jl")'
```

## Adaptive Kernel Design

The adaptive kernel is the safety core of the system. It is intentionally minimal (≤400 lines) to ensure:

1. **Auditability**: Fully reviewable by a single engineer in one afternoon
2. **Determinism**: All decisions are reproducible and traceable
3. **Safety**: High-risk actions require explicit permission
4. **Composability**: Plug-and-play capability architecture

### Core Abstractions

```julia
mutable struct KernelState
    cycle::Int
    goals::Vector{Goal}
    world::WorldState
    active_goal_id::String
    episodic_memory::Vector{Dict{String, Any}}
    self_metrics::Dict{String, Float32}  # confidence, energy, focus
    last_action::Union{ActionProposal, Nothing}
    last_reward::Float32
    last_prediction_error::Float32
end
```

## Dual-Process Architecture

The system implements a dual-process architecture inspired by Kahneman's Thinking, Fast and Slow:

- **System 1 (Reflex)**: Fast, rule-based command handling via the `jarvis_nerves` reflex module
- **System 2 (Reasoning)**: Deep cognitive processing via the Julia adaptive kernel

## Configuration

Key configuration options in `config.toml`:

```toml
[communication]
stt_provider = "openai"      # Speech-to-text
tts_provider = "elevenlabs" # Text-to-speech

[openclaw]
endpoint = "http://localhost:3000"

[llm]
provider = "openai"          # LLM provider
model = "gpt-4o"
```

## Technology Stack

- **Primary Language**: Julia 1.10+
- **Secondary Language**: Rust
- **Neural Networks**: Flux.jl
- **WebAssembly**: Wasmtime
- **Memory**: Vector stores (Qdrant-compatible)
- **LLMs**: OpenAI GPT-4o, Anthropic Claude 3.5

## Safety Features

1. **Permission Checks**: High-risk actions require explicit approval
2. **Append-Only Audit Trail**: Every action is logged immutably
3. **Sandboxing**: Capabilities write to isolated sandbox directory
4. **Energy Accounting**: Self-metrics track confidence and energy
5. **Reflection**: Kernel updates self-model after each action

## Development Status

| Component | Status |
|-----------|--------|
| Adaptive Kernel | Stable |
| LLM Bridge | Stable |
| Active Inference | In Development |
| Memory Bridge | Stable |
| Cognitive Sandbox | Experimental |
| Jarvis UI | Beta |

## License

Internal project - All rights reserved.

## Documentation

- [Adaptive Kernel README](adaptive-kernel/README.md)
- [Jarvis README](jarvis/README.md)
- [Cognitive Sandbox README](cognitive-sandbox/README.md)
- [Memory Bridge README](memory-bridge/README.md)
- [Manifest](Manifest.md)
- [Design Rationale](adaptive-kernel/DESIGN.md)
