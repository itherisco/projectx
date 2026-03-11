# ProjectX - Comprehensive Documentation Index

## Overview

ProjectX is a **Neuro-Symbolic Autonomous Cognitive System** that merges high-level LLM reasoning with low-level deterministic safety. The system implements a cognitive architecture inspired by the Free Energy Principle (FEP), combining symbolic reasoning with neural networks in a bio-mimetic design.

**Core Philosophy**: Minimal, deterministic kernels + composable capabilities = safe, auditable AI.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Directory Structure](#directory-structure)
3. [Core Components](#core-components)
4. [Cognitive Architecture](#cognitive-architecture)
5. [Safety & Security](#safety--security)
6. [Testing](#testing)
7. [Configuration](#configuration)
8. [API Reference](#api-reference)

---

## Architecture Overview

### System Layers Diagram

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

### Key Design Principles

1. **Auditability**: A 400-line kernel is fully reviewable by a single engineer in one afternoon
2. **Determinism**: All decisions are reproducible and traceable
3. **Safety-by-default**: High-risk actions require explicit permission
4. **Composability**: Plug-and-play capability architecture
5. **Separation of Concerns**: Kernel reasons; capabilities execute

---

## Directory Structure

```
projectx/
├── README.md                          # Main project documentation
├── Manifest.md                        # Architecture manifest
├── config.toml                        # Configuration template
├── Project.toml                       # Julia project file
│
├── jarvis/                            # Main Jarvis system (Julia)
│   ├── src/
│   │   ├── Jarvis.jl                 # Main entry point
│   │   ├── SystemIntegrator.jl        # System orchestration
│   │   ├── types.jl                  # Core type definitions
│   │   ├── bridge/                   # Communication bridges
│   │   │   ├── CommunicationBridge.jl
│   │   │   └── OpenClawBridge.jl
│   │   ├── llm/                      # LLM integration
│   │   │   └── LLMBridge.jl
│   │   ├── memory/                   # Memory systems
│   │   │   ├── VectorMemory.jl
│   │   │   └── SemanticMemory.jl
│   │   └── orchestration/
│   │       └── TaskOrchestrator.jl
│   ├── ui/                           # Dashboard UI (TypeScript)
│   └── README.md
│
├── adaptive-kernel/                   # Cognitive kernel (Julia)
│   ├── kernel/
│   │   ├── Kernel.jl                 # Core kernel logic (~278 lines)
│   │   ├── Homeostatic.jl            # Homeostatic regulation
│   │   ├── Metacognition.jl          # Self-awareness
│   │   └── ProjectXConfig.jl         # Configuration
│   ├── cognition/
│   │   ├── Cognition.jl              # Main cognition module
│   │   ├── CognitiveArchitecture.jl # Full cognitive architecture
│   │   ├── Attention.jl              # Posner's attention model
│   │   ├── GlobalWorkspace.jl        # Global Workspace Theory
│   │   ├── Curiosity.jl              # Curiosity-driven learning
│   │   ├── Vision.jl                 # Visual context processing
│   │   ├── types.jl                  # Cognition types
│   │   ├── agents/
│   │   │   ├── Agents.jl             # Multi-agent system
│   │   │   ├── Executor.jl           # Execution agent
│   │   │   ├── Strategist.jl         # Strategic planning agent
│   │   │   ├── Auditor.jl            # Audit agent
│   │   │   └── EvolutionEngine.jl     # Evolution agent
│   │   ├── feedback/
│   │   │   └── PainFeedback.jl       # Pain-driven feedback
│   │   ├── reality/
│   │   │   └── RealityIngestion.jl   # Reality signal processing
│   │   └── spine/
│   │       ├── DecisionSpine.jl       # Decision-making spine
│   │       ├── Commitment.jl          # Commitment tracking
│   │       ├── ConflictResolution.jl # Conflict resolution
│   │       └── ProposalAggregation.jl # Proposal aggregation
│   ├── capabilities/                 # System capabilities
│   │   ├── safe_shell.jl             # Safe shell execution
│   │   ├── safe_http_request.jl      # Safe HTTP requests
│   │   ├── observe_cpu.jl            # CPU observation
│   │   ├── observe_filesystem.jl    # Filesystem observation
│   │   ├── observe_network.jl        # Network observation
│   │   ├── analyze_logs.jl           # Log analysis
│   │   ├── write_file.jl             # File writing
│   │   ├── github/                   # GitHub operations
│   │   └── finance/                  # Financial data
│   ├── planning/
│   │   ├── Planner.jl                # Base planner
│   │   └── HierarchicalPlanner.jl    # Hierarchical planning
│   ├── memory/
│   │   ├── Memory.jl                 # Base memory
│   │   ├── VectorStore.jl            # Vector storage
│   │   ├── WorkingMemory.jl           # Working memory
│   │   └── ProceduralMemory.jl       # Procedural memory
│   ├── world/                        # World integration layer
│   │   ├── WorldInterface.jl         # External action execution
│   │   ├── AuthorizationPipeline.jl  # Action authorization
│   │   ├── ReflectionEngine.jl       # Outcome-based learning
│   │   ├── GoalDecomposition.jl      # Strategic planning
│   │   ├── CommandAuthority.jl       # Command parsing
│   │   ├── FailureContainment.jl    # Failure handling
│   │   └── Phase5Kernel.jl           # Integration module
│   ├── security/
│   │   ├── Ed25519.jl                # Ed25519 signatures
│   │   ├── generate_keys.jl          # Key generation
│   │   └── keys/                     # Key storage
│   ├── tests/                        # Test suite
│   ├── registry/
│   │   └── capability_registry.json  # Capability registry
│   ├── harness/
│   │   └── run.jl                    # Event loop harness
│   └── docs/                         # Documentation
│       ├── README.md
│       ├── DESIGN.md
│       ├── START_HERE.md
│       └── CORE_DOCTRINE.md
│
├── cognitive-sandbox/                 # Wasm sandbox (Rust)
│   ├── src/
│   │   ├── lib.rs                   # Wasmtime host runtime
│   │   └── main.rs                  # Entry point
│   ├── modules/                      # Wasm agent modules
│   │   ├── sentry.wat               # Sentry agent
│   │   ├── librarian.wat             # Librarian agent
│   │   └── action.wat               # Action agent
│   └── README.md
│
├── itheris_shell/                   # Rust shell (Pillar 2 - Active Watchdog)
│   ├── src/
│   │   ├── main.rs                  # Main entry with watchdog
│   │   ├── bridge.rs                # Julia-Rust bridge
│   │   ├── capabilities_gate.rs     # Capabilities gate
│   │   └── types.rs                 # Type definitions
│   └── Cargo.toml
│
├── itheris_link/                    # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/
│   │   │   ├── models/
│   │   │   ├── services/
│   │   │   └── theme/
│   │   └── features/
│   │       ├── authority_center/
│   │       ├── kill_switch/
│   │       ├── settings/
│   │       └── the_stream/
│   └── pubspec.yaml
│
└── active-inference/                 # Active inference (Julia)
    ├── ActiveInference.jl           # Core FEP implementation
    └── test_active_inference.jl
```

---

## Core Components

### 1. Adaptive Kernel (Safety Valve)

**Purpose**: Minimal cognitive kernel for safe decision making

**Key Files**:
- [`adaptive-kernel/kernel/Kernel.jl`](adaptive-kernel/kernel/Kernel.jl) - Core kernel (~278 lines)
- [`adaptive-kernel/types.jl`](adaptive-kernel/types.jl) - Type definitions
- [`adaptive-kernel/harness/run.jl`](adaptive-kernel/harness/run.jl) - Event loop harness

**Key Features**:
- ≤400 lines of auditable code
- Deterministic decision logic: `score = priority × (reward - risk)`
- Permission-gated action execution
- Append-only event logging

### 2. Jarvis System (Neuro-Symbolic)

**Purpose**: Main neuro-symbolic system with LLM integration

**Key Files**:
- [`jarvis/src/Jarvis.jl`](jarvis/src/Jarvis.jl) - Main entry point
- [`jarvis/src/SystemIntegrator.jl`](jarvis/src/SystemIntegrator.jl) - System orchestration
- [`jarvis/src/llm/LLMBridge.jl`](jarvis/src/llm/LLMBridge.jl) - LLM integration

### 3. ITHERIS Brain

**Purpose**: Reinforcement learning brain with neural networks

**Key Files**:
- [`itheris.jl`](itheris.jl) - Brain core implementation
- [`adaptive-kernel/cognition/`](adaptive-kernel/cognition/) - Cognitive agents

### 4. Cognitive Sandbox

**Purpose**: Wasmtime runtime for WebAssembly agent modules

**Key Files**:
- [`cognitive-sandbox/src/lib.rs`](cognitive-sandbox/src/lib.rs) - Host runtime
- [`cognitive-sandbox/modules/`](cognitive-sandbox/modules/) - Wasm modules

---

## Cognitive Architecture

### Multi-Agent System

The system implements a multi-agent cognitive architecture with four specialized agents:

1. **Executor Agent** - Executes decisions
2. **Strategist Agent** - Strategic planning
3. **Auditor Agent** - Safety and compliance checking
4. **Evolution Engine Agent** - Learning and adaptation

### Cognitive Cycle (OODA Loop)

```
Observe → Orient → Decide → Act → Rest
```

### Memory Systems

1. **Working Memory** - Short-term context
2. **Procedural Memory** - Learned procedures
3. **Vector Store** - Semantic memory
4. **Episodic Memory** - Experience tracking

### Attention & Consciousness

- **Posner's Model** - Attention control
- **Global Workspace Theory** - Consciousness simulation

---

## Safety & Security

### Core Doctrine

Immutable principles that cannot be overridden:

| Rule ID | Type | Description |
|---------|------|-------------|
| invariant_001 | INVARIANT | No Self-Destructive Actions |
| invariant_002 | INVARIANT | Preserve Operational Capability |
| invariant_003 | INVARIANT | No Unauthorized Capability Execution |
| constraint_001 | CONSTRAINT | Respect User Intent |
| constraint_002 | CONSTRAINT | No Data Destruction |

### Security Features

1. **Ed25519 Signatures** - Command signing and verification
2. **HCB Protocol** - Hardware-backed command verification
3. **Active Watchdog** - SIGKILL enforcement for cognitive locks
4. **Fail-Closed Authorization** - Block by default

### World Interface

The Phase 5 kernel provides a comprehensive world integration layer:

- **AuthorizationPipeline** - Multi-stage action authorization
- **ReflectionEngine** - Outcome-based learning
- **FailureContainment** - Failure handling and recovery

---

## Testing

### Test Files

| File | Description |
|------|-------------|
| [`adaptive-kernel/tests/unit_kernel_test.jl`](adaptive-kernel/tests/unit_kernel_test.jl) | Kernel unit tests |
| [`adaptive-kernel/tests/unit_capability_test.jl`](adaptive-kernel/tests/unit_capability_test.jl) | Capability tests |
| [`adaptive-kernel/tests/integration_test.jl`](adaptive-kernel/tests/integration_test.jl) | Integration tests |
| [`adaptive-kernel/tests/test_sovereign_cognition.jl`](adaptive-kernel/tests/test_sovereign_cognition.jl) | Sovereign cognition tests |
| [`adaptive-kernel/tests/test_phase3.jl`](adaptive-kernel/tests/test_phase3.jl) | Phase 3 tests |
| [`adaptive-kernel/tests/test_phase5_kernel.jl`](adaptive-kernel/tests/test_phase5_kernel.jl) | Phase 5 kernel tests |
| [`adaptive-kernel/tests/test_veto_integration.jl`](adaptive-kernel/tests/test_veto_integration.jl) | Veto integration tests |

### Running Tests

```bash
# Unit tests
cd adaptive-kernel
julia --project=. -e 'include("tests/unit_kernel_test.jl")'
julia --project=. -e 'include("tests/unit_capability_test.jl")'

# Integration tests
julia --project=. -e 'include("tests/integration_test.jl")'
```

---

## Configuration

### Main Configuration File

[`config.toml`](config.toml) - System configuration

Key sections:
- `[communication]` - STT/TTS providers
- `[llm]` - LLM provider and model
- `[openclaw]` - OpenClaw endpoint

### Kernel Configuration

[`adaptive-kernel/kernel/ProjectXConfig.jl`](adaptive-kernel/kernel/ProjectXConfig.jl) - Kernel configuration

---

## API Reference

### Kernel Functions

```julia
# Initialize kernel
kernel = init_kernel(config)

# Run single cycle
kernel, action, result = step_once(kernel, candidates, execute_capability, permission_handler)

# Run continuous loop
kernel = run_loop(kernel, candidates, execute_capability, permission_handler, cycles)
```

### Capability Interface

```julia
# Metadata function
function meta()::Dict{String, Any}
    return Dict(
        "id" => "my_capability",
        "name" => "My Capability",
        "cost" => 0.1,
        "risk" => "low",
        "reversible" => true
    )
end

# Execute function
function execute(params::Dict{String, Any})::Dict{String, Any}
    return Dict("success" => true, "effect" => "Did something")
end
```

---

## Documentation Files

| File | Description |
|------|-------------|
| [README.md](README.md) | Main project README |
| [Manifest.md](Manifest.md) | Architecture manifest |
| [adaptive-kernel/README.md](adaptive-kernel/README.md) | Adaptive kernel docs |
| [adaptive-kernel/DESIGN.md](adaptive-kernel/DESIGN.md) | Design rationale |
| [adaptive-kernel/START_HERE.md](adaptive-kernel/START_HERE.md) | Getting started guide |
| [adaptive-kernel/CORE_DOCTRINE.md](adaptive-kernel/CORE_DOCTRINE.md) | Core doctrine implementation |
| [adaptive-kernel/world/README.md](adaptive-kernel/world/README.md) | Phase 5 world interface |
| [jarvis/README.md](jarvis/README.md) | Jarvis system docs |
| [cognitive-sandbox/README.md](cognitive-sandbox/README.md) | Wasm sandbox docs |

---

## Technology Stack

- **Primary Language**: Julia 1.10+
- **Secondary Language**: Rust
- **Neural Networks**: Flux.jl
- **WebAssembly**: Wasmtime
- **Memory**: Vector stores (Qdrant-compatible)
- **LLMs**: OpenAI GPT-4o, Anthropic Claude 3.5

---

## Development Status

| Component | Status |
|-----------|--------|
| Adaptive Kernel | Stable |
| LLM Bridge | Stable |
| Cognitive Architecture | In Development |
| Active Inference | In Development |
| Memory Bridge | Stable |
| Cognitive Sandbox | Experimental |
| Jarvis UI | Beta |

---

*Documentation generated for ProjectX - Neuro-Symbolic Autonomous Cognitive System*
