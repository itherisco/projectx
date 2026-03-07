# PHASE 0 Forensic Analysis: CODEBASE_MAP.md

> **Classification**: Forensic Documentation  
> **Phase**: PHASE 0 - Baseline Analysis  
> **Generated**: 2026-03-07  
> **System State**: Security Score 23/100 | Cognitive Completeness 47% | IPC Fallback Mode

---

## 1. Full Module Tree

```
projectx/
├── adaptive-kernel/                    # Julia cognitive kernel
│   ├── cognition/                     # Core cognitive processing
│   │   ├── Cognition.jl               # Main cognition orchestrator (38.9KB)
│   │   ├── ReAct.jl                   # Reasoning engine (29.7KB)
│   │   ├── types.jl                   # Cognitive type definitions (18.1KB)
│   │   ├── agents/                    # Specialized cognitive agents
│   │   │   ├── Agents.jl              # Agent orchestration
│   │   │   ├── Auditor.jl             # Security auditing agent
│   │   │   ├── CodeAgent.jl           # Code generation/execution
│   │   │   ├── EvolutionEngine.jl     # Evolutionary optimization
│   │   │   ├── Executor.jl            # Action execution
│   │   │   ├── MindMapAgent.jl        # Concept mapping
│   │   │   ├── PolicyValidator.jl     # Policy compliance
│   │   │   ├── Strategist.jl          # Strategic planning
│   │   │   └── WebSearchAgent.jl      # Web information retrieval
│   │   ├── attention/                 # Attention mechanisms
│   │   │   └── Attention.jl           # Attention scoring (17KB)
│   │   ├── consolidation/             # Memory consolidation
│   │   │   └── Sleep.jl               # Sleep-based consolidation (25.9KB)
│   │   ├── feedback/                  # Emotional/feedback systems
│   │   │   ├── Emotions.jl            # Emotional processing (22.3KB)
│   │   │   └── PainFeedback.jl        # Pain/error feedback (7.6KB)
│   │   ├── goals/                     # Goal management
│   │   │   ├── goals.jl               # Goal definitions
│   │   │   └── GoalSystem.jl          # Goal orchestration (20.5KB)
│   │   ├── language/                  # Language processing
│   │   │   └── LanguageUnderstanding.jl # NLP (22.8KB)
│   │   ├── learning/                   # Learning systems
│   │   │   └── OnlineLearning.jl     # Real-time learning (19.1KB)
│   │   ├── metacognition/              # Self-awareness
│   │   │   └── SelfModel.jl           # Self-representation (33KB)
│   │   ├── reality/                    # Reality ingestion
│   │   │   └── RealityIngestion.jl   # Sensor input (6KB)
│   │   ├── security/                   # Security layer
│   │   │   ├── InputSanitizer.jl      # Input validation (26.3KB)
│   │   │   ├── InputSanitizerIntegration.jl
│   │   │   └── InputSanitizerTests.jl
│   │   ├── spine/                      # Decision spine
│   │   │   ├── Commitment.jl          # Action commitment (4.2KB)
│   │   │   ├── ConflictResolution.jl # Conflict handling (6.9KB)
│   │   │   ├── DecisionSpine.jl       # Core decisions (20.5KB)
│   │   │   └── ProposalAggregation.jl # Proposal merging
│   │   └── worldmodel/                 # World modeling
│   │       └── WorldModel.jl          # World representation (41.5KB)
│   ├── kernel/                         # Kernel-level operations
│   │   └── security/
│   │       └── KeyManagement.jl       # Key management (40.7KB) ⚠️ XOR CIPHER
│   ├── memory/                         # Memory systems
│   │   └── Memory.jl                  # Memory operations (4KB)
│   ├── planning/                       # Planning systems
│   │   ├── AutonomousPlanner.jl       # Auto-planning (18.3KB)
│   │   └── Planner.jl                 # Base planner
│   ├── sandbox/                        # Execution sandbox
│   │   └── ExecutionSandbox.jl        # Sandboxed execution (3.7KB)
│   ├── registry/                       # Tool/capability registry
│   │   ├── capability_registry.json   # Registry data
│   │   └── ToolRegistry.jl             # Tool management
│   ├── integration/                    # Integration layer
│   │   └── Conversions.jl             # Type conversions (11.7KB)
│   ├── harness/                        # Test harness
│   │   └── run.jl                      # Execution harness (6.2KB)
│   ├── tests/                          # Test suite (extensive)
│   └── COGNITIVE_CYCLE_TRACE.md        # Execution trace
│
├── Itheris/                            # Rust cognitive kernel
│   ├── Brain/
│   │   └── Src/
│   │       ├── main.rs                # Entry point (30.2KB)
│   │       ├── lib.rs                 # Library interface (6.6KB)
│   │       ├── kernel.rs              # Kernel core (7.2KB)
│   │       ├── boot.rs                # Boot sequence (4.3KB)
│   │       ├── crypto.rs              # Cryptography (7.4KB) ⚠️ XOR CIPHER
│   │       ├── crypto_version_manager.rs # Key rotation (21KB)
│   │       ├── api_bridge.rs          # API bridging (7KB)
│   │       ├── catastrophe.rs         # Failure handling (4.9KB)
│   │       ├── database.rs            # Data storage (5KB)
│   │       ├── debate.rs              # Argumentation (5.5KB)
│   │       ├── federation.rs          # Multi-agent federation (5.5KB)
│   │       ├── ffi_tests.rs           # FFI test suite (20.3KB)
│   │       ├── iot_bridge.rs          # IoT integration (6.5KB)
│   │       ├── ledger.rs              # Transaction ledger (4.9KB)
│   │       ├── llm_advisor.rs         # LLM integration (3.1KB)
│   │       ├── monitoring.rs          # System monitoring (5.2KB)
│   │       ├── state.rs               # State management (3.8KB)
│   │       ├── threat_model.rs        # Threat modeling (5.4KB)
│   │       ├── validation.txt         # Validation rules
│   │       ├── warden_validation_tests.rs # Security tests (45.7KB)
│   │       ├── boot/                  # Low-level boot
│   │       │   ├── gdt.rs            # GDT setup (6.5KB)
│   │       │   ├── idt.rs            # IDT setup (12.3KB)
│   │       │   ├── paging.rs         # Memory paging (12.9KB)
│   │       │   └── mod.rs
│   │       └── boot_sequence/         # Boot orchestration
│   │           ├── ignition_sequence.rs # Ignition (20.2KB)
│   │           └── mod.rs
│   └── Brain/Cargo.toml               # Rust dependencies
│
├── jarvis/                             # Training/inference
│   └── src/brain/
│       └── BrainTrainer.jl            # Neural training
│
├── plans/                              # Implementation plans
│   ├── JARVIS_IMPLEMENTATION_BLUEPRINT.md
│   ├── JARVIS_NEUROSYMBOLIC_ARCHITECTURE.md
│   ├── JARVIS_EXECUTABLE_ARCHITECTURE.md
│   ├── phase1_integration_glue_plan.md
│   └── phase6_minimal_implementation_plan.md
│
├── config.toml                         # Main configuration
├── SYSTEM_ARCHITECTURE.md              # Architecture overview
├── SECURITY.md                         # Security documentation
├── STATUS.md                           # System status
└── API_REFERENCE.md                    # API documentation
```

---

## 2. File Responsibilities

### 2.1 Julia Kernel (adaptive-kernel/)

| File | Responsibility | Status |
|------|----------------|--------|
| [`Cognition.jl`](adaptive-kernel/cognition/Cognition.jl) | Main cognitive orchestrator, coordinates all cognitive modules | ⚠️ Disconnected emotions/learning |
| [`ReAct.jl`](adaptive-kernel/cognition/ReAct.jl) | Reasoning + Acting loop implementation | ✅ Operational |
| [`WorldModel.jl`](adaptive-kernel/cognition/worldmodel/WorldModel.jl) | Internal world representation | ✅ Core component |
| [`DecisionSpine.jl`](adaptive-kernel/cognition/spine/DecisionSpine.jl) | Decision making backbone | ✅ Functional |
| [`Emotions.jl`](adaptive-kernel/cognition/feedback/Emotions.jl) | Emotional processing | ⚠️ Disconnected from main loop |
| [`OnlineLearning.jl`](adaptive-kernel/cognition/learning/OnlineLearning.jl) | Real-time learning | ⚠️ Disconnected from main loop |
| [`InputSanitizer.jl`](adaptive-kernel/cognition/security/InputSanitizer.jl) | Input validation/sanitization | ⚠️ Bypassable |
| [`KeyManagement.jl`](adaptive-kernel/kernel/security/KeyManagement.jl) | Cryptographic key management | ⚠️ Uses XOR cipher |
| [`ExecutionSandbox.jl`](adaptive-kernel/sandbox/ExecutionSandbox.jl) | Sandboxed code execution | ⚠️ Incomplete |
| [`Sleep.jl`](adaptive-kernel/cognition/consolidation/Sleep.jl) | Memory consolidation during "sleep" | ✅ Implemented |

### 2.2 Rust Kernel (Itheris/Brain/Src/)

| File | Responsibility | Status |
|------|----------------|--------|
| [`main.rs`](Itheris/Brain/Src/main.rs) | Entry point, kernel initialization | ✅ Boot sequence functional |
| [`kernel.rs`](Itheris/Brain/Src/kernel.rs) | Core kernel logic | ⚠️ Not running (fallback mode) |
| [`crypto.rs`](Itheris/Brain/Src/crypto.rs) | Cryptographic operations | ⚠️ XOR cipher in use |
| [`crypto_version_manager.rs`](Itheris/Brain/Src/crypto_version_manager.rs) | Key rotation/version management | ⚠️ Weak foundation |
| [`ffi_tests.rs`](Itheris/Brain/Src/ffi_tests.rs) | FFI boundary tests | ⚠️ Multiple vulnerabilities |
| [`warden_validation_tests.rs`](Itheris/Brain/Src/warden_validation_tests.rs) | Security validation | ⚠️ Critical failures detected |
| [`boot_sequence/ignition_sequence.rs`](Itheris/Brain/Src/boot_sequence/ignition_sequence.rs) | System boot orchestration | ✅ Functional |

---

## 3. Inter-Module Dependencies

### 3.1 Julia Module Dependency Graph

```
Cognition.jl (Orchestrator)
├── ReAct.jl
│   └── DecisionSpine.jl
│       ├── ProposalAggregation.jl
│       ├── ConflictResolution.jl
│       └── Commitment.jl
├── WorldModel.jl
│   └── RealityIngestion.jl
├── Attention.jl
├── LanguageUnderstanding.jl
├── GoalSystem.jl
│   └── goals.jl
├── Emotions.jl ← DISCONNECTED ⚠️
├── PainFeedback.jl
├── OnlineLearning.jl ← DISCONNECTED ⚠️
├── SelfModel.jl (Metacognition)
├── InputSanitizer.jl ← BYPASSABLE ⚠️
└── Memory.jl
```

### 3.2 Rust Module Dependency Graph

```
main.rs (Entry)
├── kernel.rs
│   ├── state.rs
│   ├── catastrophe.rs
│   └── monitoring.rs
├── crypto.rs ← XOR CIPHER ⚠️
├── crypto_version_manager.rs
├── api_bridge.rs
├── ffi_tests.rs ← VULNERABLE ⚠️
└── boot_sequence/
    ├── ignition_sequence.rs
    └── boot/ (gdt, idt, paging)
```

---

## 4. Rust↔Julia Communication Paths

### 4.1 FFI Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Julia Runtime (Primary)                  │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   ccall()    │    │   ccall()    │    │   jlrs       │  │
│  │  invocations │    │   wrapper    │    │  integration │  │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘  │
│         │                   │                   │          │
│  ───────┴───────────────────┴───────────────────┴────────  │
│                        FFI Boundary                         │
│  ───────────────────────────────────────────────────────────│
└────────┬───────────────────┬───────────────────┬────────────┘
         │                   │                   │
┌────────┴───────────────────┴───────────────────┴────────────┐
│                    Rust Kernel (Itheris)                      │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  extern "C" │    │  Shared      │    │  Ring Buffer │  │
│  │  exports    │    │  Memory      │    │  IPC         │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 IPC Communication Channels

| Channel | Type | Status | Purpose |
|---------|------|--------|---------|
| [`diagnose_ipc.jl`](diagnose_ipc.jl) | Shared Memory | ⚠️ Fallback Mode | Julia↔Rust communication |
| Ring Buffer | Lock-free | ⚠️ Unstable | High-frequency messages |
| FFI ccall | Direct | ⚠️ Vulnerable | Function calls across boundary |

### 4.3 Key FFI Bindings

From [`test_rust_ipc_ffi.jl`](adaptive-kernel/tests/test_rust_ipc_ffi.jl):
- `rust_kernel_init()` - Initialize Rust kernel
- `rust_send_message()` - Send message to Rust
- `rust_recv_message()` - Receive message from Rust
- `rust_kernel_shutdown()` - Shutdown kernel

---

## 5. Execution Lifecycle

### 5.1 System Boot Sequence

```
1. Power On
   │
   ├──→ Itheris/Boot (Rust)
   │    ├── GDT Setup (gdt.rs)
   │    ├── IDT Setup (idt.rs)
   │    ├── Paging Initialization (paging.rs)
   │    └── Ignition Sequence (ignition_sequence.rs)
   │
   └──→ Julia Runtime Start
        ├── Load adaptive-kernel/
        ├── Initialize cognition modules
        ├── Start 136.1 Hz cognitive loop
        └── Attempt Rust kernel connection
             │
             └── [FALLBACK MODE] ── IPC failed, Julia-only operation
```

### 5.2 Cognitive Loop (136.1 Hz)

```
┌─────────────────────────────────────────────────────────────────┐
│                    136.1 Hz Cognitive Cycle                     │
│                    (~7.35ms per iteration)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────┐    ┌───────────┐    ┌────────────┐                │
│  │PERCEPTION│───▶│WORLD MODEL│───▶│  MEMORY    │                │
│  │         │    │           │    │            │                │
│  │Reality  │    │WorldModel │    │Episodic,   │                │
│  │Ingestion│    │.jl        │    │Semantic,   │                │
│  └─────────┘    └───────────┘    │Working     │                │
│                                  └────────────┘                │
│                                        │                        │
│                                        ▼                        │
│  ┌─────────┐    ┌───────────┐    ┌────────────┐                │
│  │  ACTION │◀───│ DECISION  │◀───│ REASONING  │                │
│  │         │    │           │    │            │                │
│  │Commitment│    │Decision   │    │ReAct.jl    │                │
│  │.jl      │    │Spine.jl   │    │            │                │
│  └─────────┘    └───────────┘    └────────────┘                │
│                           │                                      │
│                           ▼                                      │
│                    ┌───────────┐                                 │
│                    │ATTENTION  │                                 │
│                    │Filter     │                                 │
│                    │Priority   │                                 │
│                    └───────────┘                                 │
│                                                                  │
│  ⚠️ BROKEN LINKS:                                               │
│     - Emotions.jl ──▶ DecisionSpine (DISCONNECTED)             │
│     - OnlineLearning.jl ──▶ WorldModel (DISCONNECTED)         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 State Machine

```
                    ┌─────────────────┐
                    │   INITIALIZED   │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
         ┌──────────│    STARTING     │◀──────────┐
         │          └────────┬────────┘           │
         │                   │                    │
         ▼                   ▼                    ▼
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│  RUST RUNNING  │  │   FALLBACK     │  │   ERROR        │
│                │  │   (Julia-only) │  │   STATE        │
│ Kernel active  │  │ IPC failed     │  │ Crash detected │
│ FFI operational│  │ Reduced cogn.  │  │                │
└───────┬────────┘  └───────┬────────┘  └────────────────┘
        │                    │
        ▼                    ▼
   [Normal Ops]         [Degraded]
```

---

## 6. Critical Findings Summary

### Module Health Matrix

| Module Category | Status | Score | Critical Issues |
|-----------------|--------|-------|-----------------|
| Cognitive Core | ⚠️ Partial | 47% | Emotions/learning disconnected |
| Security | ❌ Critical | 23/100 | XOR cipher, bypassable sanitization |
| IPC/FFI | ⚠️ Fallback | N/A | Rust kernel not running |
| Memory | ✅ Functional | - | Working memory operational |
| Planning | ✅ Functional | - | Autonomous planner working |

### Dependency Issues

1. **Broken Links**:
   - [`Emotions.jl`](adaptive-kernel/cognition/feedback/Emotions.jl) → [`DecisionSpine.jl`](adaptive-kernel/cognition/spine/DecisionSpine.jl) - NOT CONNECTED
   - [`OnlineLearning.jl`](adaptive-kernel/cognition/learning/OnlineLearning.jl) → [`WorldModel.jl`](adaptive-kernel/cognition/worldmodel/WorldModel.jl) - NOT CONNECTED

2. **Security Gaps**:
   - [`KeyManagement.jl`](adaptive-kernel/kernel/security/KeyManagement.jl) uses XOR cipher
   - [`crypto.rs`](Itheris/Brain/Src/crypto.rs) uses XOR cipher
   - [`InputSanitizer.jl`](adaptive-kernel/cognition/security/InputSanitizer.jl) is bypassable

3. **IPC Failure**:
   - Rust kernel not running
   - Fallback mode active
   - [`diagnize_ipc.jl`](diagnose_ipc.jl) confirms fallback state

---

*End of CODEBASE_MAP.md*
