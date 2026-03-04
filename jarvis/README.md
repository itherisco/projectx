# Project Jarvis - Neuro-Symbolic Autonomous System

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Julia](https://img.shields.io/badge/Julia-1.8+-9558B2)
![Status](https://img.shields.io/badge/status-Active-green)

## Overview

**Project Jarvis** is a cutting-edge Neuro-Symbolic Autonomous System that merges high-level LLM reasoning with low-level deterministic safety. It evolves the existing ProjectX codebase into a fully integrated, proactive personal assistant.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PROJECT JARVIS ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     CEREBRAL CORTEX (LLM Layer)                     │   │
│  │                                                                       │   │
│  │  ┌─────────────┐  ┌──────────────────┐  ┌─────────────────────────┐  │   │
│  │  │  GPT-4o    │  │  Claude 3.5      │  │  Natural Language      │  │   │
│  │  │  Bridge    │  │  Bridge          │  │  Parser                │  │   │
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
│  │                    ADAPTIVE KERNEL (Safety Valve)                   │   │
│  │                                                                       │   │
│  │   ┌───────────────────────────────────────────────────────────────┐  │   │
│  │   │              Deterministic Formula                             │  │   │
│  │   │        score = priority × (reward − risk)                     │  │   │
│  │   └───────────────────────────────────────────────────────────────┘  │   │
│  │                                                                       │   │
│  │   ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐    │   │
│  │   │  Whitelist   │  │  Audit Log   │  │  Trust Level          │    │   │
│  │   │  Enforcement │  │  (events.log)│  │  (TRUST_BLOCKED→FULL)│    │   │
│  │   └──────────────┘  └──────────────┘  └────────────────────────┘    │   │
│  │                                                                       │   │
│  │   Capabilities: Shell, HTTP, IoT, File Operations                    │   │
│  └───────────────────────────┬────────────────────────────────────────────┘   │
│                              │                                                 │
│                              ▼                                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    SEMANTIC MEMORY (Long-Term)                      │   │
│  │                                                                       │   │
│  │   ┌───────────────┐  ┌───────────────┐  ┌───────────────────────┐   │   │
│  │   │  Vector DB   │  │  RAG Engine  │  │  Memory Collections  │   │   │
│  │   │  (Qdrant/   │  │  (Retrieval  │  │  • User Preferences  │   │   │
│  │   │   HNSW)     │  │   Augmented  │  │  • Conversations     │   │   │
│  │   │             │  │   Generation) │  │  • Project Knowledge │   │   │
│  │   └───────────────┘  └───────────────┘  └───────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    MULTIMODAL INTERFACES                             │   │
│  │                                                                       │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌────────────────────────────┐ │   │
│  │   │   Voice     │  │   Vision    │  │   Communication           │ │   │
│  │   │  (Whisper   │  │   (VLM)     │  │   Bridge                 │ │   │
│  │   │   STT)      │  │  GPT-4V/    │  │   • Confirmation         │ │   │
│  │   │  (ElevenLab │  │  Claude-V    │  │   • Trust Checking       │ │   │
│  │   │   TTS)      │  │             │  │                            │ │   │
│  │   └─────────────┘  └─────────────┘  └────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                 PROACTIVE PLANNING (TaskOrchestrator)               │   │
│  │                                                                       │   │
│  │   • Periodic WorldState Scanning                                     │   │
│  │   • Optimization Suggestions ("CPU high, throttle tasks?")          │   │
│  │   • Safety Alerts                                                   │   │
│  │   • Automation Recommendations                                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    SYSTEM INTEGRATOR                                  │   │
│  │              (Central Nervous System)                                │   │
│  │                                                                       │   │
│  │   ┌───────────────────────────────────────────────────────────────┐  │   │
│  │   │                    run_cycle()                                 │  │   │
│  │   │   1. Observe → 2. Perceive → 3. Infer → 4. Approve          │  │   │
│  │   │   5. Execute → 6. Learn  → 7. Suggest                      │  │   │
│  │   └───────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Cerebral Cortex (LLM Layer)

| Component | File | Description |
|-----------|------|-------------|
| LLMBridge | [`src/llm/LLMBridge.jl`](src/llm/LLMBridge.jl) | Async bridge to GPT-4o/Claude 3.5 |
| Intent Parser | Built-in | Parses natural language into Goal objects |
| 12D Vector Builder | Built-in | Creates PerceptionVector for ITHERIS |

### 2. ITHERIS Reinforcement Brain

| Component | Source | Description |
|-----------|--------|-------------|
| BrainCore | [`itheris.jl`](../../itheris.jl) | Flux.jl neural network |
| Episodic Learning | Built-in | Learns from Safety Valve outcomes |
| Action Proposals | Built-in | Neural output for kernel evaluation |

### 3. Adaptive Kernel (Safety Valve)

| Component | Source | Description |
|-----------|--------|-------------|
| Kernel | [`adaptive-kernel/kernel/Kernel.jl`](../../adaptive-kernel/kernel/Kernel.jl) | Deterministic decision making |
| Whitelist | [`adaptive-kernel/capabilities/`](../../adaptive-kernel/capabilities/) | Allowed actions |
| Audit Log | `events.log` | All action logging |

**Deterministic Formula:**
```
score = priority × (reward − risk)
```

### 4. Semantic Memory

| Component | File | Description |
|-----------|------|-------------|
| VectorStore | [`src/memory/VectorMemory.jl`](src/memory/VectorMemory.jl) | In-memory HNSW |
| RAG Engine | Built-in | Retrieval Augmented Generation |
| Collections | - | User Preferences, Conversations, Knowledge |

### 5. Multimodal Interfaces

| Component | File | Description |
|-----------|------|-------------|
| Voice (STT) | [`src/bridge/CommunicationBridge.jl`](src/bridge/CommunicationBridge.jl) | OpenAI Whisper |
| Voice (TTS) | Same | ElevenLabs/Coqui |
| Vision (VLM) | Same | GPT-4V/Claude-V |

### 6. Proactive Planning

| Component | File | Description |
|-----------|------|-------------|
| TaskOrchestrator | [`src/orchestration/TaskOrchestrator.jl`](src/orchestration/TaskOrchestrator.jl) | Periodic optimization scanning |
| Suggestions | Built-in | Proactive user recommendations |

### 7. System Integrator

| Component | File | Description |
|-----------|------|-------------|
| Central Hub | [`src/SystemIntegrator.jl`](src/SystemIntegrator.jl) | Orchestrates all components |
| Execution Loop | [`run_cycle()`](src/SystemIntegrator.jl:151) | Main cognitive cycle |

## File Structure

```
jarvis/
├── Project.toml              # Julia package manifest
├── README.md                # This file
└── src/
    ├── Jarvis.jl            # Main entry point
    ├── SystemIntegrator.jl # Central Nervous System
    ├── types.jl            # Core type definitions
    ├── llm/
    │   └── LLMBridge.jl    # LLM communication
    ├── memory/
    │   └── VectorMemory.jl # Semantic storage + RAG
    ├── orchestration/
    │   └── TaskOrchestrator.jl # Proactive planning
    └── bridge/
        └── CommunicationBridge.jl # Voice/Vision
```

## Usage

### Quick Start

```julia
using Jarvis

# Initialize the system
system = Jarvis.start()

# Process a user request
result = process_user_request(system, "Check the CPU usage")
println(result["response"])

# Run a cognitive cycle
cycle_result = run_cycle(system)

# Get system status
status = get_system_status(system)
println("Current cycle: ", status["current_cycle"])

# Shutdown gracefully
shutdown(system)
```

### Configuration

```julia
using Jarvis
using Jarvis.JarvisTypes
using Jarvis.LLMBridge

# Custom configuration
config = JarvisConfig(
    llm = LLMConfig(
        provider = :openai,
        api_key = "your-key",
        model = "gpt-4o"
    ),
    communication = CommunicationConfig(
        require_confirmation_threshold = TRUST_STANDARD
    ),
    proactive_scan_interval = Second(30)
)

system = start(config)
```

## Trust Levels

| Level | Value | Allowed Actions |
|-------|-------|----------------|
| `TRUST_BLOCKED` | 0 | None |
| `TRUST_RESTRICTED` | 1 | Read-only |
| `TRUST_LIMITED` | 2 | Non-destructive |
| `TRUST_STANDARD` | 3 | Most actions |
| `TRUST_FULL` | 4 | All (with audit) |

### 8. BrainTrainer (Neural Training)

| Component | File | Description |
|-----------|------|-------------|
| Training Loop | [`src/brain/BrainTrainer.jl`](src/brain/BrainTrainer.jl) | Training with checkpoint/restore |
| Checkpointing | Built-in | Crash recovery support |
| Experience Buffer | Built-in | Stores experiences for learning |

## Safety Features

1. **Kernel Sovereignty**: `execute(action) ⇒ kernel.state.last_decision == APPROVED`
2. **Deterministic Kernel**: All actions scored by `priority × (reward − risk)`
3. **Decision Types**: APPROVED, DENIED, STOPPED (with fail-closed default)
4. **Confidence Threshold**: Brain proposals require confidence >= 0.7
5. **Audit Logging**: Every action recorded in `events.log`
6. **Edge Case Handling**: brain nothing → kernel heuristics; kernel denial → graceful handling

## Integration with ProjectX

The system integrates existing ProjectX components:

- **ITHERIS Brain** → Neural decision making
- **Adaptive Kernel** → Safety validation
- **Capabilities** → Tool execution

## Development Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ COMPLETE | ITHERIS Brain Integration |
| Phase 2 | ✅ COMPLETE | Kernel Sovereignty Enforcement |
| Phase 3 | ✅ COMPLETE | SystemIntegrator Integration |
| Phase 4 | ✅ COMPLETE | Testing (55 tests passing) |

### Completed Features

- [x] Core architecture design
- [x] SystemIntegrator implementation
- [x] LLM Bridge (async)
- [x] Vector Memory (HNSW-like)
- [x] TaskOrchestrator (proactive)
- [x] CommunicationBridge (hooks)
- [x] ITHERIS Brain Integration
- [x] Kernel Sovereignty Enforcement
- [x] Complete Cognitive Cycle (6 phases)
- [x] Capability Registry Integration

### Known Issues (Non-blocking)

- Type mismatch in Kernel.approve() - uses Any for flexibility
- Empty config handling needs graceful defaults

## Requirements

- Julia 1.8+
- Flux.jl (Neural Engine)
- HTTP.jl (API calls)
- JSON.jl (Serialization)

## License

Internal Project - All Rights Reserved

