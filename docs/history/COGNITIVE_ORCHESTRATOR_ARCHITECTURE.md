# Cognitive Orchestrator Architecture

**Version:** 1.0  
**Date:** 2026-03-09  
**Status:** Integration and Enhancement Project  
**Foundation:** Existing Implementation in `adaptive-kernel/`

## Table of Contents

1. [Full Architecture Diagram](#1-full-architecture-diagram)
2. [Module Specifications](#2-module-specifications)
3. [Rust Kernel Interface Design](#3-rust-kernel-interface-design)
4. [Julia Cognitive Runtime Design](#4-julia-cognitive-runtime-design)
5. [IPC Protocol Specification](#5-ipc-protocol-specification)
6. [Folder Structure](#6-folder-structure)
7. [Example Code](#7-example-code)
8. [Pseudocode for Orchestrator Loop](#8-pseudocode-for-orchestrator-loop)
9. [Testing Suggestions](#9-testing-suggestions)
10. [Scaling Suggestions](#10-scaling-suggestions)

---

## 1. Full Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    COGNITIVE ORCHESTRATOR                                          │
│                                    ======================                                          │
│                                                                                                     │
│  ┌──────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                              AUTONOMOUS COGNITIVE LOOP (~100Hz)                              │  │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │  │
│  │  │  PERCEPTION │───▶│    GOAL     │───▶│   PLANNER   │───▶│   EXECUTOR  │───▶│  VERIFIER   │ │  │
│  │  │   ENGINE    │    │   ENGINE    │    │             │    │             │    │             │ │  │
│  │  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘ │  │
│  │        │                  │                  │                  │                  │        │  │
│  │        │                  │                  │                  │                  │        │  │
│  │        ▼                  ▼                  ▼                  ▼                  ▼        │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────────────┐    │  │
│  │  │                              MEMORY SYSTEM                                          │    │  │
│  │  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │    │  │
│  │  │   │  EPISODIC   │  │  SEMANTIC   │  │ PROCEDURAL  │  │      KNOWLEDGE GRAPH    │  │    │  │
│  │  │   │  MEMORY     │  │  MEMORY     │  │  MEMORY    │  │                         │  │    │  │
│  │  │   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────────┘  │    │  │
│  │  └─────────────────────────────────────────────────────────────────────────────────────┘    │  │
│  │                                                                                               │  │
│  │        ◀───────────────────────────────────────────────────────────────────────────▶        │  │
│  │                                    LOOP REPEAT                                              │  │
│  └──────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                              │                                                    │
│                                              ▼                                                    │
│  ┌────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                              DREAM SYSTEM (Oneiric)                                         │  │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────┐    │  │
│  │  │   MEMORY    │◀──▶│  SYNAPTIC   │◀──▶│HALLUCINATION│◀──▶│    SLEEP/DREAM          │    │  │
│  │  │   REPLAY    │    │HOMEOSTASIS  │    │  TRAINING   │    │    CONSOLIDATION         │    │  │
│  │  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────────────────┘    │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                              │                                                    │
└───────────────────────────────────────────────│──────────────────────────────────────────────────┘
                                               │
                    ┌──────────────────────────┼──────────────────────────┐
                    │                          │                          │
                    ▼                          ▼                          ▼
┌─────────────────────────────────┐  ┌──────────────────────┐  ┌─────────────────────────────┐
│    RUST SOVEREIGN KERNEL       │  │    IPC RING BUFFER   │  │    JULIA RUNTIME            │
│         (Ring 0)               │  │    (Shared Memory)   │  │    (User Space)             │
├─────────────────────────────────┤  ├──────────────────────┤  ├─────────────────────────────┤
│  ┌─────────────────────────┐  │  │  ┌────────────────┐   │  │  ┌────────────────────────┐  │
│  │ SECURITY POLICIES       │  │  │  │  0x01000000   │   │  │  │  COGNITIVE SUBSYSTEMS  │  │
│  │ - Capability Whitelist  │  │  │  │   - READ      │   │  │  │  ┌──────────────────┐   │  │
│  │ - Input Sanitization    │  │  │  │   - WRITE     │   │  │  │  │  • Perception    │   │  │
│  │ - Trust Scoring         │  │  │  │   - SYNC      │   │  │  │  │  • Goals          │   │  │
│  └─────────────────────────┘  │  │  └────────────────┘   │  │  │  │  • Planning        │   │  │
│  ┌─────────────────────────┐  │  │                      │   │  │  │  • Executor        │   │  │
│  │CAPABILITY REGISTRY      │  │  │  ┌────────────────┐   │  │  │  │  • Memory          │   │  │
│  │ - safe_shell            │  │  │  │  0x01100000    │   │  │  │  │  • Dream           │   │  │
│  │ - safe_write            │  │  │  │   - READ       │   │  │  │  └──────────────────┘   │  │
│  │ - safe_http_request     │  │  │  │   - WRITE      │   │  │  │  └────────────────────────┘  │
│  │ - observe_*              │  │  │  └────────────────┘   │  │  └─────────────────────────────┘
│  └─────────────────────────┘  │  │                      │   │
│  ┌─────────────────────────┐  │  │                      │   │
│  │  PROCESS SANDBOXING     │  │  │   Ed25519 + HMAC      │   │
│  │ - Memory Isolation      │  │  │   Message Auth        │   │
│  │ - Resource Limits       │  │  │                      │   │
│  └─────────────────────────┘  │  └──────────────────────────┘
│  ┌─────────────────────────┐  │
│  │RESOURCE SCHEDULER       │  │
│  │ - CPU Allocation        │  │
│  │ - Memory Quotas         │  │
│  └─────────────────────────┘  │
│  ┌─────────────────────────┐  │
│  │    IPC RING BUFFER     │  │
│  │ - Lock-free Ring Queue │  │
│  │ - Thread-safe Access   │  │
│  └─────────────────────────┘  │
└─────────────────────────────────┘
```

### Autonomous Cognitive Loop Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                           AUTONOMOUS COGNITIVE LOOP (OODA at ~100Hz)                        │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────┐
    │   OBSERVE    │ ◀─── System State (CPU, Memory, Processes, Network)
    │   (State)    │      External Events, User Input, Knowledge Updates
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   ORIENT     │ ◀─── Goal Engine: Generate goals from observed state
    │   (Goals)    │      Priority calculation, Intrinsic reward computation
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   DECIDE     │ ◀─── Planner: Create execution plans (HTN decomposition)
    │  (Planning)  │      Risk assessment, Resource estimation
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   ACT        │ ◀─── Executor: Convert plans to kernel-compliant actions
    │ (Execution)  │      Capability invocation via Kernel approval
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   VERIFY     │ ◀─── Validation: LLM output validation, WorldModel checks
    │(Verification)│     Outcome evaluation, Success/failure detection
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   LEARN      │ ◀─── Memory: Store episodes, Update Knowledge Graph
    │   (Memory)   │      Goal memory, Capability stats, Dream consolidation
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   REPEAT     │ ──▶ Back to OBSERVE (100Hz = 10ms per cycle)
    │              │      Or: Enter DREAM STATE if idle/low energy
    └──────────────┘
```

---

## 2. Module Specifications

### 2.1 Rust Sovereign Kernel Components

#### 2.1.1 Security Policies Module

**Purpose:** Enforce capability-based security, prevent unauthorized actions, sanitize all inputs.

**Responsibilities:**
- Capability whitelist enforcement
- Input sanitization (prompt injection prevention)
- Trust score computation
- Risk classification for all actions

**Public API:**
```julia
# From adaptive-kernel/kernel/security/
- approve_action(action::Dict) -> (Bool, String)
- validate_input(input::String) -> ValidationResult
- compute_trust_score(context::Dict) -> Float32
```

**Integration Points:**
- All Executor actions must pass through `KernelInterface.approve_action()`
- LLM outputs validated via `LLMOutputValidator`
- Input sanitization at all capability boundaries

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/kernel/trust/Trust.jl`](adaptive-kernel/kernel/trust/Trust.jl)
- See [`adaptive-kernel/cognition/security/InputSanitizer.jl`](adaptive-kernel/cognition/security/InputSanitizer.jl)

---

#### 2.1.2 Capability Registry

**Purpose:** Maintain whitelist of allowed capabilities with risk levels and resource requirements.

**Responsibilities:**
- Register/unregister capabilities
- Query capability availability
- Track resource requirements
- Version management

**Public API:**
```julia
- register_capability(name::Symbol, handler::Function, risk_level::Symbol)
- get_capability(name::Symbol) -> CapabilityInfo
- list_capabilities() -> Vector{Symbol}
- is_available(name::Symbol) -> Bool
```

**Current Capabilities:**
- `safe_shell` - Shell command execution (high risk)
- `safe_write` - File writing (medium risk)
- `safe_read` - File reading (low risk)
- `safe_http_request` - HTTP requests (medium risk)
- `observe_cpu`, `observe_memory`, `observe_filesystem`, `observe_network`, `observe_processes`

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/capabilities/`](adaptive-kernel/capabilities/)

---

#### 2.1.3 Process Sandboxing

**Purpose:** Isolate cognitive processes, prevent memory corruption, enforce resource limits.

**Responsibilities:**
- Memory region isolation
- CPU quota enforcement
- Process lifecycle management
- Crash containment

**Public API:**
```julia
- create_sandbox(config::SandboxConfig) -> SandboxHandle
- allocate_memory(handle, size::Int) -> Ptr
- enforce_quota(handle, resource::Symbol, limit::Int)
- terminate(handle)
```

**Current Status:** ⚠️ PARTIAL (shared memory region 0x01000000-0x01100000 defined)

---

#### 2.1.4 Resource Scheduler

**Purpose:** Allocate CPU, memory, and I/O resources across cognitive processes.

**Responsibilities:**
- Priority-based scheduling
- Resource quota management
- Load balancing
- Real-time resource monitoring

**Public API:**
```julia
- schedule(task::Task, priority::Priority) -> ScheduleResult
- allocate_cpu(quota::Float64) -> CPUHandle
- allocate_memory(bytes::Int) -> MemHandle
- get_load() -> LoadMetrics
```

**Current Status:** ✅ BASIC IMPLEMENTATION
- Loop interval: 5 seconds in GoalEngine
- Rate limits: 100 goals/hour total

---

#### 2.1.5 IPC Ring Buffer

**Purpose:** Lock-free communication between Julia runtime and Rust kernel.

**Responsibilities:**
- Shared memory management
- Lock-free ring queue operations
- Message serialization/deserialization
- Thread-safe read/write synchronization

**Public API:**
```julia
# From adaptive-kernel/kernel/ipc/RustIPC.jl
- init_ipc() -> Bool
- safe_shm_write(data::Vector{UInt8}) -> Int
- safe_shm_read() -> Vector{UInt8}
- get_ring_status() -> RingStatus
```

**Implementation Details:**
- Shared memory region: `0x01000000 - 0x01100000` (16MB)
- Ed25519 signatures for authentication
- HMAC-SHA256 for message integrity with replay protection

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/kernel/ipc/RustIPC.jl`](adaptive-kernel/kernel/ipc/RustIPC.jl)

---

### 2.2 Julia Cognitive Runtime Components

#### 2.2.1 Perception Engine

**Purpose:** Process external inputs and internal state to create unified perception.

**Responsibilities:**
- Sensor data fusion
- Language understanding
- State observation
- Event detection

**Public API:**
```julia
- perceive(input::Any) -> Perception
- observe_system_state() -> SystemState
- process_language(text::String) -> ParsedIntent
- detect_events(sensors::Vector{Sensor}) -> Vector{Event}
```

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/cognition/language/LanguageUnderstanding.jl`](adaptive-kernel/cognition/language/LanguageUnderstanding.jl)
- See [`adaptive-kernel/autonomy/state_observer.jl`](adaptive-kernel/autonomy/state_observer.jl)

---

#### 2.2.2 Goal Engine

**Purpose:** Generate, evaluate, and manage autonomous goals from observed state.

**Responsibilities:**
- Goal generation from state
- Priority assignment
- Intrinsic reward computation
- Goal lifecycle management
- Curiosity-driven exploration

**Public API:**
```julia
# From adaptive-kernel/autonomy/goal_engine.jl
- start()  # Start autonomous loop
- stop()   # Stop autonomous loop
- pause(reason::String)
- resume()
- status() -> Dict

# From adaptive-kernel/cognition/goals/GoalSystem.jl
- generate_goals(state::SystemState) -> Vector{Goal}
- evaluate_goal(goal::Goal) -> GoalScore
- compute_intrinsic_reward(goal::Goal) -> Float32
- create_goal(description::String, target_state::Vector) -> Goal
```

**Implementation Details:**
- Loop interval: 5 seconds
- Max goals per hour: 100
- Max execution time: 300 seconds
- Priority classes: CRITICAL(1), HIGH(2), NORMAL(3), BACKGROUND(4)

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/autonomy/goal_engine.jl`](adaptive-kernel/autonomy/goal_engine.jl)
- See [`adaptive-kernel/cognition/goals/GoalSystem.jl`](adaptive-kernel/cognition/goals/GoalSystem.jl)

---

#### 2.2.3 Planner

**Purpose:** Convert goals into executable plans using Hierarchical Task Network (HTN) decomposition.

**Responsibilities:**
- Goal decomposition
- Step sequencing
- Risk estimation
- Resource planning

**Public API:**
```julia
# From adaptive-kernel/autonomy/planner.jl
- create_plan(goal::Goal) -> Plan
- validate(plan::Plan) -> Bool
- estimate_duration(plan::Plan) -> Float64
- summarize(plan::Plan) -> String

# From adaptive-kernel/planning/AutonomousPlanner.jl
- create_learning_plan(topic::String) -> LearningPlan
- decompose_topic(topic::String) -> TopicDecomposition
- get_next_module!(plan::LearningPlan) -> StudyModule
```

**HTN Domain Mappings:**
```julia
:run_self_diagnostic     => [check_system_logs, verify_processes, check_memory_usage]
:optimize_runtime        => [analyze_system_metrics, identify_bottlenecks, adjust_parameters]
:compress_memory         => [analyze_memory, gc_collect, verify_improvement]
:cleanup_logs            => [analyze_log_size, archive_old_logs, delete_archived]
:verify_security         => [check_open_ports, verify_capabilities, audit_recent_actions]
:index_new_knowledge     => [scan_knowledge_base, update_index]
:update_embeddings       => [export_data, recompute_embeddings, update_store]
:check_disk_space        => [scan_filesystems, identify_large_files]
:backup_state            => [serialize_state, write_backup]
```

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/autonomy/planner.jl`](adaptive-kernel/autonomy/planner.jl)
- See [`adaptive-kernel/planning/AutonomousPlanner.jl`](adaptive-kernel/planning/AutonomousPlanner.jl)

---

#### 2.2.4 Task Scheduler

**Purpose:** Priority-based queue for goal scheduling with rate limiting.

**Responsibilities:**
- Priority queue management
- Duplicate prevention
- Rate limit enforcement
- Retry logic

**Public API:**
```julia
# From adaptive-kernel/autonomy/goal_scheduler.jl
- schedule(goal::Goal) -> Bool  # Returns false if duplicate/rate-limited
- next_goal() -> Union{Goal, Nothing}
- complete(goal_id::UUID)
- fail(goal_id::UUID, error::String)
- has_pending() -> Bool
- get_status() -> Dict
```

**Implementation Details:**
- Max queued goals: 50
- Max retry attempts: 3
- Completed goal history: 1000 entries

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/autonomy/goal_scheduler.jl`](adaptive-kernel/autonomy/goal_scheduler.jl)

---

#### 2.2.5 Executor

**Purpose:** Convert approved decisions into Kernel-compliant action execution.

**Responsibilities:**
- Decision validation
- Kernel action conversion
- Capability invocation
- Outcome tracking

**Public API:**
```julia
# From adaptive-kernel/cognition/agents/Executor.jl
- create_executor(id::String) -> ExecutorAgent
- generate_proposal(agent, perception, memory) -> AgentProposal
- validate_executable(decision, perception) -> (Bool, String)
- convert_to_kernel_action(decision, perception) -> String
- evaluate_decision(agent, decision, outcome, metrics) -> Dict
```

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/cognition/agents/Executor.jl`](adaptive-kernel/cognition/agents/Executor.jl)

---

#### 2.2.6 Verifier

**Purpose:** Validate LLM outputs and verify execution outcomes.

**Responsibilities:**
- JSON schema validation
- Whitelist enforcement
- Output sanitization
- Outcome evaluation

**Public API:**
```julia
# From adaptive-kernel/kernel/validation/LLMOutputValidator.jl
- validate_llm_output(json_string::String) -> ValidationResult
- sanitize_numeric(value, min, max) -> Float64

# From adaptive-kernel/kernel/validation/WorldModelValidator.jl
- validate_world_model(state::WorldState) -> ValidationResult
```

**Allowed Values:**
```julia
ALLOWED_INTENTS = ["task_execution", "information_query", "system_observation", 
                   "planning", "confirmation_request", "proactive_suggestion"]
ALLOWED_PRIORITIES = ["critical", "high", "medium", "low", "background"]
ALLOWED_CONTEXTS = ["preferences", "conversations", "knowledge", "none"]
```

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/kernel/validation/LLMOutputValidator.jl`](adaptive-kernel/kernel/validation/LLMOutputValidator.jl)

---

#### 2.2.7 Memory System

**Purpose:** Store and retrieve experiences, capability statistics, and adjust future planning.

**Responsibilities:**
- Episode storage
- Failure cataloging
- Capability statistics
- Memory compression
- Planning adjustments

**Public API:**
```julia
# From adaptive-kernel/memory/Memory.jl
- ingest_episode!(ms::MemoryStore, episode::Dict)
- compress_memory!(ms::MemoryStore; window::Int=10)
- failure_catalog(ms::MemoryStore) -> Vector{Dict}
- get_adjustments(ms::MemoryStore, capability_ids::Vector{String}) -> (Float32, Float32, Float32)
- decay_memory!(ms::MemoryStore, decay_rate::Float32)
```

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/memory/Memory.jl`](adaptive-kernel/memory/Memory.jl)

---

#### 2.2.8 Knowledge Graph

**Purpose:** Structured knowledge representation with entity-relation-event-belief model.

**Responsibilities:**
- Entity management
- Relation tracking
- Event logging
- Belief updates
- Path finding and inference

**Public API:**
```julia
# From adaptive-kernel/knowledge/KnowledgeGraph.jl
- add_entity!(graph, name::String, type::String; properties, confidence) -> Entity
- add_relation!(graph, source, target, relation_type; properties, confidence) -> Relation
- add_event!(graph, entity, event_type, properties) -> Event
- add_belief!(graph, entity, belief, confidence) -> Belief
- query_triples(graph, pattern) -> Vector{KnowledgeTriple}
- find_paths(graph, source, target, max_depth) -> Vector{Vector{Entity}}
- reason_inference(graph, entity) -> Vector{Belief}
```

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/knowledge/KnowledgeGraph.jl`](adaptive-kernel/knowledge/KnowledgeGraph.jl)

---

#### 2.2.9 Dream System (Oneiric)

**Purpose:** Offline cognitive processing through memory replay, synaptic homeostasis, and hallucination detection.

**Responsibilities:**
- Dream state management
- Memory replay selection
- Synaptic weight normalization
- Hallucination detection training
- Sleep cycle integration

**Public API:**
```julia
# From adaptive-kernel/cognition/oneiric/OneiricController.jl
- enter_dream_state!() -> OneiricState
- process_dream_cycle!() -> DreamResult
- exit_dream_state!() -> Summary
- should_enter_dream() -> Bool
- run_dream_processing!(duration::Float64)

# From adaptive-kernel/cognition/oneiric/MemoryReplay.jl
- replay_experiences!(config::ReplayConfig) -> Vector{ReplayedMemory}
- select_memories_for_replay(state) -> Vector{Memory}
- compute_replay_priority(memory, config) -> Float32
- should_trigger_replay() -> Bool
```

**Configuration:**
```julia
min_energy_for_dream::Float32 = 0.35f0
dream_duration_min::Float64 = 300.0   # 5 minutes
dream_duration_max::Float64 = 1800.0  # 30 minutes
cycle_interval::Float64 = 60.0        # 1 minute
idle_threshold::Float64 = 300.0       # 5 minutes
nightly_hour::Int = 2                 # 2 AM
```

**Current Status:** ✅ IMPLEMENTED
- See [`adaptive-kernel/cognition/oneiric/OneiricController.jl`](adaptive-kernel/cognition/oneiric/OneiricController.jl)
- See [`adaptive-kernel/cognition/oneiric/MemoryReplay.jl`](adaptive-kernel/cognition/oneiric/MemoryReplay.jl)
- See [`adaptive-kernel/cognition/consolidation/Sleep.jl`](adaptive-kernel/cognition/consolidation/Sleep.jl)

---

## 3. Rust Kernel Interface Design

### 3.1 Communication Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         JULIA RUNTIME (User Space)                                  │
│                                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────────────┐  │
│   │                          Kernel Interface Layer                              │  │
│   │  ┌─────────────────────────────────────────────────────────────────────────┐ │  │
│   │  │                     RustIPC Module (Safe API)                          │ │  │
│   │  │                                                                         │ │  │
│   │  │   safe_shm_write() ──▶┐                                                │ │  │
│   │  │                        │    ┌─────────────────────────────────────┐    │ │  │
│   │  │   safe_shm_read() ◀───│◀───│    Lock-Free Ring Buffer             │    │ │  │
│   │  │                       │    │    (Shared Memory 0x01000000)        │    │ │  │
│   │  │   get_ring_status() ──│───▶│                                     │    │ │  │
│   │  │                        │    └─────────────────────────────────────┘    │ │  │
│   │  │                                                                         │ │  │
│   │  │   ┌─────────────────────────────────────────────────────────────────────┐ │  │
│   │  │   │  Ed25519 Signatures + HMAC-SHA256                                 │ │  │
│   │  │   │  (Message Authentication & Replay Protection)                     │ │  │
│   │  │   └─────────────────────────────────────────────────────────────────────┘ │  │
│   │  └─────────────────────────────────────────────────────────────────────────┘ │  │
│   └─────────────────────────────────────────────────────────────────────────────┘  │
│                                              │                                      │
└───────────────────────────────────────────────│──────────────────────────────────────┘
                                               │
                                               │ FFI (dlsym)
                                               ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         RUST KERNEL (Ring 0)                                        │
│                                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────────────┐  │
│   │                              Kernel Core                                    │  │
│   │  ┌────────────────┐  ┌────────────────┐  ┌─────────────────────────────┐  │  │
│   │  │  Security      │  │  Capability    │  │  IPC Handler               │  │  │
│   │  │  Policies      │  │  Registry      │  │  - ShmLock (Mutex)         │  │  │
│   │  │  - approve     │  │  - safe_shell  │  │  - ShmWriteGuard           │  │  │
│   │  │  - validate    │  │  - safe_write  │  │  - Read/Write pointers    │  │  │
│   │  │  - sanitize    │  │  - observe_*   │  │                            │  │  │
│   │  └────────────────┘  └────────────────┘  └─────────────────────────────┘  │  │
│   │                                                                              │  │
│   │  ┌────────────────┐  ┌────────────────┐  ┌─────────────────────────────┐  │  │
│   │  │  Resource     │  │  Process       │  │  Trust System              │  │  │
│   │  │  Scheduler    │  │  Sandbox       │  │  - RiskClassifier          │  │  │
│   │  │  - CPU quota   │  │  - Isolation   │  │  - ConfirmationGate        │  │  │
│   │  │  - Mem limits │  │  - Crash guard  │  │  - FlowIntegrity          │  │  │
│   │  └────────────────┘  └────────────────┘  └─────────────────────────────┘  │  │
│   └─────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Julia Kernel Interface API

```julia
# From adaptive-kernel/kernel/kernel_interface.jl
module KernelInterface

"""
    get_system_state() -> Dict{String, Any}

Get the current system state directly from the kernel.
Replaces HTTP calls to localhost:8080/status
"""
function get_system_state()::Dict{String, Any}
    return Dict(
        "timestamp" => now(),
        "load" => Sys.loadavg()[1],
        "mem_free" => Sys.free_memory() / 2^30,
        "mem_total" => Sys.total_memory() / 2^30,
        "cpu_count" => Sys.CPU_THREADS,
        "approved_actions" => _kernel_state.approved_count,
        "rejected_actions" => _kernel_state.rejected_count,
        "active_threads" => Threads.nthreads(),
        "process_id" => getpid(),
        "uptime_seconds" => time()
    )
end

"""
    approve_action(action::Dict{String, Any}) -> (Bool, String)

Request kernel approval for an action.
This is the sovereignty gate - all autonomous actions must pass through here.
"""
function approve_action(action::Dict{String, Any})::Tuple{Bool, String}
    action_name = get(action, "name", "")
    action_type = get(action, "type", "")
    
    # Check blacklist
    if action_name in _kernel_state.blacklisted_actions
        _record_decision(action, false, "Blacklisted action")
        return false, "Action is blacklisted for security"
    end
    
    # Security checks
    if action_type == "http_request"
        # Block self-referential HTTP calls
        target = get(action, "target", "")
        if occursin("localhost", lowercase(target)) || 
           occursin("127.0.0.1", lowercase(target))
            return false, "Security: Self-referential HTTP calls are prohibited"
        end
    end
    
    # Approve if passed all checks
    _record_decision(action, true, "Approved")
    _kernel_state.approved_count += 1
    return true, "Approved"
end

"""
    execute_capability(name::Symbol, params::Dict) -> Result

Execute a capability via kernel.
"""
function execute_capability(name::Symbol, params::Dict)::Dict{String, Any}
    # ... implementation
end

end # module
```

### 3.3 IPC Message Format

```julia
# From adaptive-kernel/kernel/ipc/RustIPC.jl

# Message structure for IPC communication
struct IPCMessage
    header::IPCHeader      # Type, length, sequence number, timestamp
    payload::Vector{UInt8}  # Serialized JSON payload
    signature::Vector{UInt8}  # Ed25519 signature
    hmac::Vector{UInt8}     # HMAC-SHA256 for replay protection
end

# Message types
@enum IPCMessageType begin
    IPC_REQUEST = 1      # Julia -> Rust: Capability request
    IPC_RESPONSE = 2     # Rust -> Julia: Capability response
    IPC_EVENT = 3       # Rust -> Julia: Async event notification
    IPC_STATUS = 4      # Julia -> Rust: Status query
    IPC_SHUTDOWN = 5    # Julia -> Rust: Shutdown signal
end

# Ring buffer structure
struct RingBuffer
    read_ptr::Atomic{UInt64}    # Read position
    write_ptr::Atomic{UInt64}   # Write position
    capacity::UInt64             # Buffer capacity
    data::Vector{UInt8}          # Actual ring data
    lock::Mutex                  # Synchronization
end
```

---

## 4. Julia Cognitive Runtime Design

### 4.1 Perception Engine

```julia
# From adaptive-kernel/cognition/language/LanguageUnderstanding.jl
module LanguageUnderstanding

export understand, parse_intent, extract_entities, assess_confidence

"""
    understand(text::String, context::Dict) -> ParsedUnderstanding

Parse natural language input into structured cognitive representation.
"""
function understand(text::String, context::Dict = Dict())::ParsedUnderstanding
    # Tokenization, NER, intent classification, sentiment analysis
end

"""
    parse_intent(utterance::String) -> Intent

Extract user intent from natural language.
"""
function parse_intent(utterance::String)::Intent
    # Pattern matching + embedding similarity
end

end # module
```

### 4.2 Goal Generation System

```julia
# From adaptive-kernel/autonomy/goal_generator.jl
module GoalGenerator

"""
    generate(state::SystemState) -> Vector{Goal}

Generate potential goals from observed system state.
Uses curiosity-driven intrinsic reward computation.
"""
function generate(state::SystemState)::Vector{Goal}
    # Analyze state for anomalies, opportunities
    # Compute intrinsic rewards
    # Generate goal candidates
end

end # module

# From adaptive-kernel/cognition/goals/GoalSystem.jl
# Goal lifecycle:
# pending → active → completed
#         → abandoned  
#         → suspended
```

### 4.3 Planning System (HTN)

```julia
# From adaptive-kernel/autonomy/planner.jl
# Hierarchical Task Network decomposition

const GOAL_DECOMPOSITION = Dict{Symbol, Vector{PlanStep}}(
    :run_self_diagnostic => [
        PlanStep("check_system_logs", :read_logs, "Identify any errors in logs", :low, Dict()),
        PlanStep("verify_processes", :check_processes, "Confirm all critical processes running", :low, Dict()),
        PlanStep("check_memory_usage", :observe_memory, "Report memory usage", :low, Dict()),
    ],
    # ... more domain mappings
)

struct PlanStep
    action::String
    required_capability::Symbol
    expected_result::String
    risk_level::Symbol  # :low, :medium, :high
    params::Dict{String, Any}
end
```

### 4.4 Execution Pipeline

```julia
# From adaptive-kernel/autonomy/goal_executor.jl
module GoalExecutor

"""
    execute(plan::Plan, kernel::KernelInterface) -> ExecutionResult

Execute a plan through the kernel approval system.
"""
function execute(plan::Plan, kernel)::ExecutionResult
    for step in plan.steps
        # 1. Request kernel approval
        approved, reason = kernel.approve_action(Dict(
            "name" => step.action,
            "capability" => step.required_capability,
            "params" => step.params
        ))
        
        if !approved
            return ExecutionResult(success=false, reason=reason)
        end
        
        # 2. Execute capability
        result = kernel.execute_capability(step.required_capability, step.params)
        
        # 3. Verify outcome
        if result.status != :success
            return ExecutionResult(success=false, reason=result.error)
        end
    end
    
    return ExecutionResult(success=true)
end

end # module
```

---

## 5. IPC Protocol Specification

### 5.1 Based on Existing RustIPC.jl Implementation

```julia
# From adaptive-kernel/kernel/ipc/RustIPC.jl

"""
# RustIPC.jl - IPC Bridge to Rust Ring 0 Kernel

Architecture:
- Shared memory region: 0x01000000 - 0x01100000 (16MB)
- Ring buffer protocol with lock-free access
- Ed25519 signatures for authentication
- HMAC-SHA256 for message authentication with replay protection
"""

# Library paths for different platforms
const RUST_LIB_PATHS = [
    "Itheris/Brain/target/debug/libitheris.so",      # Linux debug
    "Itheris/Brain/target/release/libitheris.so",    # Linux release
    "Itheris/Brain/target/debug/libitheris.dylib",   # macOS debug
    "Itheris/Brain/target/release/libitheris.dylib", # macOS release
]

# Safe API (REQUIRED - raw unsafe operations deprecated)
safe_shm_write(data::Vector{UInt8})::Int
safe_shm_read()::Vector{UInt8}
get_ring_status()::RingMetrics

# Thread synchronization
# Julia MUST acquire ShmLock before any shared memory access
# Rust kernel handles internal synchronization with ShmWriteGuard
```

### 5.2 Message Flow

```
Julia Task                          Rust Kernel
    │                                    │
    │──── IPC_REQUEST (write to ring) ──│
    │     [serialize + sign + HMAC]     │
    │                                    │
    │<─── IPC_RESPONSE (read from ring) │
    │     [verify + deserialize]        │
    │                                    │
```

### 5.3 Security Requirements

1. **Deprecation Notice:** Raw `unsafe_store!` and `unsafe_load` are DEPRECATED
2. **Mandatory Safe API:** All access via `safe_shm_write()` and `safe_shm_read()`
3. **Mutex Acquisition:** Julia must acquire `ShmLock` before shared memory access
4. **Message Authentication:** Ed25519 signatures + HMAC-SHA256
5. **Replay Protection:** Sequence numbers and timestamps

---

## 6. Folder Structure

```
adaptive-kernel/
├── autonomy/                          # Autonomous goal loop
│   ├── goal_engine.jl                 # Main autonomous loop (5s interval)
│   ├── goal_generator.jl              # Goal generation from state
│   ├── goal_scheduler.jl             # Priority queue scheduling
│   ├── planner.jl                     # HTN planning
│   ├── goal_executor.jl               # Plan execution
│   ├── goal_evaluator.jl              # Outcome evaluation
│   ├── goal_memory.jl                 # Goal memory storage
│   └── state_observer.jl              # System state observation
│
├── brain/                             # Neural brain components
│   ├── Brain.jl                       # Main brain interface
│   └── NeuralBrainCore.jl             # Neural network core
│
├── capabilities/                      # Kernel-capable actions
│   ├── safe_shell.jl                  # Shell command execution
│   ├── safe_write.jl                  # File writing
│   ├── safe_http_request.jl           # HTTP requests
│   ├── observe_*.jl                   # System observation
│   └── ...                            # More capabilities
│
├── cognition/                         # Cognitive systems
│   ├── Cognition.jl                   # Main cognition module
│   ├── CognitiveLoop.jl               # Cognitive OODA loop
│   ├── ReAct.jl                       # Reasoning + Action
│   ├── types.jl                       # Cognitive type definitions
│   │
│   ├── agents/                        # Cognitive agents
│   │   ├── Executor.jl                # Action execution
│   │   ├── CodeAgent.jl               # Code generation
│   │   ├── Strategist.jl             # Strategic planning
│   │   └── ...                        # More agents
│   │
│   ├── goals/                         # Goal management
│   │   ├── GoalSystem.jl              # Autonomous goal formation
│   │   └── goals.jl                   # Goal types
│   │
│   ├── oneiric/                       # Dream system
│   │   ├── OneiricController.jl      # Dream state management
│   │   ├── MemoryReplay.jl            # Experience replay
│   │   ├── HallucinationTrainer.jl   # Hallucination detection
│   │   └── SynapticHomeostasis.jl    # Weight normalization
│   │
│   ├── consolidation/                 # Sleep system
│   │   └── Sleep.jl                   # Sleep cycle management
│   │
│   ├── language/                      # Language processing
│   │   └── LanguageUnderstanding.jl   # NLU
│   │
│   ├── learning/                      # Learning systems
│   │   └── OnlineLearning.jl          # Continuous learning
│   │
│   ├── metacognition/                 # Self-modeling
│   │   └── SelfModel.jl               # Self-awareness
│   │
│   ├── worldmodel/                    # World modeling
│   │   └── WorldModel.jl              # Reality modeling
│   │
│   ├── security/                      # Cognitive security
│   │   ├── InputSanitizer.jl          # Prompt injection prevention
│   │   └── InputSanitizerIntegration.jl
│   │
│   └── spine/                         # Decision spine
│       ├── DecisionSpine.jl          # Decision aggregation
│       └── Commitment.jl             # Commitment tracking
│
├── kernel/                            # Kernel interface
│   ├── Kernel.jl                      # Main kernel
│   ├── kernel_interface.jl            # Julia-Kernel API
│   ├── ServiceManager.jl              # Service management
│   ├── StateValidator.jl              # State validation
│   │
│   ├── ipc/                           # IPC communication
│   │   ├── RustIPC.jl                 # Rust kernel IPC
│   │   └── IPCKeyManagement.jl        # Key management
│   │
│   ├── security/                      # Kernel security
│   │   ├── Crypto.jl                  # Cryptography
│   │   └── KeyManagement.jl           # Key management
│   │
│   ├── trust/                          # Trust system
│   │   ├── Trust.jl                   # Trust interface
│   │   ├── ConfirmationGate.jl       # Action confirmation
│   │   ├── RiskClassifier.jl          # Risk assessment
│   │   └── FlowIntegrity.jl           # Flow security
│   │
│   └── validation/                    # Output validation
│       ├── LLMOutputValidator.jl      # LLM output validation
│       └── WorldModelValidator.jl    # World model validation
│
├── knowledge/                         # Knowledge systems
│   ├── KnowledgeGraph.jl              # Knowledge graph
│   ├── KnowledgeAPI.jl                # Knowledge API
│   └── GraphDatabase.jl              # Graph storage
│
├── memory/                            # Memory systems
│   └── Memory.jl                      # Episodic memory
│
├── planning/                          # Planning systems
│   ├── Planner.jl                     # Base planner
│   └── AutonomousPlanner.jl          # Long-horizon planning
│
├── integration/                       # Integration code
│   └── Conversions.jl                 # Type conversions
│
├── iot/                               # IoT integration
│   └── IoTBridge.jl
│
├── mcp/                               # Model Context Protocol
│   └── ModelContextProtocol.jl
│
├── persistence/                       # State persistence
│   ├── Persistence.jl                 # General persistence
│   └── Checkpointer.jl               # State checkpoints
│
└── harness/                           # Testing harness
    └── run.jl                         # Test runner
```

---

## 7. Example Code

### 7.1 Goal Engine

```julia
# From adaptive-kernel/autonomy/goal_engine.jl
module GoalEngine

using Dates
using UUIDs

const LOOP_INTERVAL_SECONDS = 5
const MAX_GOALS_PER_HOUR = 100
const MAX_EXECUTION_TIME = 300

mutable struct EngineState
    running::Bool
    loop_count::Int
    goals_generated::Int
    goals_completed::Int
    goals_failed::Int
    last_error::Union{String, Nothing}
    paused::Bool
    pause_reason::Union{String, Nothing}
end

function start()
    _initialize()
    _engine_state.running = true
    
    while _engine_state.running
        if _engine_state.paused
            sleep(LOOP_INTERVAL_SECONDS)
            continue
        end
        _cycle()
        sleep(LOOP_INTERVAL_SECONDS)
    end
end

function _cycle()
    _engine_state.loop_count += 1
    
    # Step 1: Observe system state
    state = StateObserver.observe()
    
    # Step 2: Generate goals from state
    potential_goals = GoalGenerator.generate(state)
    
    # Step 3: Schedule goals
    for goal in potential_goals
        GoalScheduler.schedule(goal)
    end
    
    # Step 4: Get next goal
    next = GoalScheduler.next_goal()
    
    if next !== nothing
        # Step 5: Create execution plan
        plan = Planner.create_plan(next)
        
        if Planner.validate(plan)
            # Step 6: Kernel approval
            approved, reason = KernelInterface.approve_action(Dict(
                "name" => string(next.name),
                "type" => "goal_execution",
                "goal_id" => string(next.id)
            ))
            
            if approved
                # Step 7: Execute plan
                result = GoalExecutor.execute(plan, KernelInterface)
                
                # Step 8: Evaluate result
                evaluation = GoalEvaluator.evaluate(next, plan, result, state_before, state_after)
                
                # Step 9: Update memory
                GoalMemory.store(next, plan, result, evaluation)
            end
        end
    end
end

end # module
```

### 7.2 Planner (HTN)

```julia
# From adaptive-kernel/autonomy/planner.jl
module Planner

using Dates
using UUIDs

struct PlanStep
    action::String
    required_capability::Symbol
    expected_result::String
    risk_level::Symbol
    params::Dict{String, Any}
end

struct Plan
    id::UUID
    goal_id::UUID
    goal_name::Symbol
    steps::Vector{PlanStep}
    created_at::DateTime
    estimated_duration::Float64
end

const GOAL_DECOMPOSITION = Dict{Symbol, Vector{PlanStep}}(
    :run_self_diagnostic => [
        PlanStep("check_system_logs", :read_logs, "Identify errors", :low, Dict()),
        PlanStep("verify_processes", :check_processes, "Confirm processes", :low, Dict()),
        PlanStep("check_memory_usage", :observe_memory, "Report memory", :low, Dict()),
    ],
    :optimize_runtime => [
        PlanStep("analyze_system_metrics", :observe_cpu, "CPU bottlenecks", :low, Dict()),
        PlanStep("identify_bottlenecks", :analyze_logs, "Performance issues", :low, Dict()),
        PlanStep("adjust_parameters", :configure_system, "Apply optimizations", :medium, Dict()),
    ],
    # ... more mappings
)

function create_plan(goal::Goal)::Plan
    steps = get(GOAL_DECOMPOSITION, goal.name, PlanStep[])
    
    return Plan(
        uuid4(),
        goal.id,
        goal.name,
        steps,
        now(),
        length(steps) * 10.0
    )
end

function validate(plan::Plan)::Bool
    return !isempty(plan.steps)
end

end # module
```

### 7.3 Task Scheduler

```julia
# From adaptive-kernel/autonomy/goal_scheduler.jl
module GoalScheduler

using Dates
using UUIDs
using DataStructures

struct ScheduledGoal
    goal::Goal
    scheduled_at::DateTime
    attempts::Int
    last_error::Union{String, Nothing}
end

mutable struct SchedulerState
    queue::PriorityQueue{UUID, ScheduledGoal}
    completed_ids::Set{UUID}
    rate_limits::Dict{Symbol, Int}
end

function schedule(goal::Goal)::Bool
    # Check duplicate
    goal.id in _scheduler_state.completed_ids && return false
    haskey(_scheduler_state.queue, goal.id) && return false
    
    # Rate limiting
    !_check_rate_limit(goal) && return false
    
    # Add to priority queue
    scheduled = ScheduledGoal(goal, now(), 0, nothing)
    priority_value = _get_priority_value(goal.priority)
    enqueue!(_scheduler_state.queue, goal.id, scheduled, priority_value)
    
    return true
end

function next_goal()::Union{Goal, Nothing}
    isempty(_scheduler_state.queue) && return nothing
    
    _, scheduled = dequeue_pair!(_scheduler_state.queue)
    scheduled.attempts += 1
    
    # Retry logic.attempts < 
    if scheduled3
        enqueue!(_scheduler_state.queue, scheduled.goal.id, scheduled, 
                 _get_priority_value(scheduled.goal.priority))
    end
    
    return scheduled.goal
end

end # module
```

### 7.4 Executor

```julia
# From adaptive-kernel/cognition/agents/Executor.jl
module Executor

function generate_proposal(
    agent::ExecutorAgent,
    perception::Dict{String, Any},
    memory::TacticalMemory
)::AgentProposal
    
    pending_decision = get(perception, "pending_decision", "")
    
    if isempty(pending_decision)
        return AgentProposal(agent.id, :executor, "maintain_state", 0.9,
            reasoning="No pending decisions - maintain current state", weight=1.0)
    end
    
    # Validate executable
    is_executable, validation_msg = validate_executable(pending_decision, perception)
    
    if !is_executable
        return AgentProposal(agent.id, :executor, "reject: $validation_msg", 0.95,
            reasoning="Decision failed validation", weight=1.0)
    end
    
    # Convert to kernel action
    executable_action = convert_to_kernel_action(pending_decision, perception)
    
    return AgentProposal(agent.id, :executor, executable_action, 0.85,
        reasoning="Converted to executable form", weight=1.0)
end

function convert_to_kernel_action(decision::String, perception::Dict)::String
    action_type = lowercase(split(decision, ":")[1])
    
    capability_map = Dict(
        "execute" => "safe_execute",
        "write" => "safe_write",
        "read" => "safe_read",
        "http" => "safe_http_request",
        "shell" => "safe_shell"
    )
    
    capability = get(capability_map, action_type, "unknown")
    params = get(perception, "action_params", Dict{String, Any}())
    
    return "$capability:$(json(params))"
end

end # module
```

### 7.5 Verifier

```julia
# From adaptive-kernel/kernel/validation/LLMOutputValidator.jl
module LLMOutputValidator

const ALLOWED_INTENTS = Set([
    "task_execution", "information_query", "system_observation",
    "planning", "confirmation_request", "proactive_suggestion"
])

const ALLOWED_PRIORITIES = Set([
    "critical", "high", "medium", "low", "background"
])

struct ValidationResult
    is_valid::Bool
    error_message::Union{String, Nothing}
    sanitized_data::Union{Dict{String, Any}, Nothing}
end

function validate_llm_output(json_string::String)::ValidationResult
    # Parse JSON
    data = JSON.parse(json_string)
    
    # Validate intent
    intent = get(data, "intent", "")
    intent in ALLOWED_INTENTS || return ValidationResult("Invalid intent: $intent")
    
    # Validate priority
    priority = get(data, "priority", "")
    priority in ALLOWED_PRIORITIES || return ValidationResult("Invalid priority: $priority")
    
    # Sanitize numeric values
    if haskey(data, "value")
        data["value"] = sanitize_numeric(data["value"], 0.0, 1.0)
    end
    
    return ValidationResult(data)
end

function sanitize_numeric(value, min, max)::Float64
    return clamp(Float64(value), min, max)
end

end # module
```

### 7.6 Memory System

```julia
# From adaptive-kernel/memory/Memory.jl
module Memory

mutable struct MemoryStore
    episodes::Vector{Dict{String,Any}}
    failures::Vector{Dict{String,Any}}
    capability_stats::Dict{String, Dict{String,Any}}
    last_compaction::DateTime
    stats_lock::ReentrantLock
end

function ingest_episode!(ms::MemoryStore, episode::Dict{String,Any})
    push!(ms.episodes, episode)
    
    lock(ms.stats_lock) do
        aid = get(episode, "action_id", "unknown")
        stats = get(ms.capability_stats, aid, Dict("success"=>0, "fail"=>0, "sum_error"=>0.0, "count"=>0))
        
        if get(episode, "result", false)
            stats["success"] += 1
        else
            stats["fail"] += 1
            push!(ms.failures, episode)
        end
        
        pe = Float64(get(episode, "prediction_error", 0.0))
        stats["sum_error"] += pe
        stats["count"] += 1
        ms.capability_stats[aid] = stats
    end
end

function get_adjustments(ms::MemoryStore, capability_ids::Vector{String})
    cost_mul = 1.0f0
    reward_mul = 1.0f0
    unc_off = 0.0f0
    
    for id in capability_ids
        stats = get(ms.capability_stats, id, nothing)
        if stats !== nothing && stats["count"] > 0
            avg_err = stats["sum_error"] / stats["count"]
            success_rate = stats["success"] / stats["count"]
            
            # Adjust based on historical performance
            cost_mul *= (1.0f0 + Float32(avg_err))
            reward_mul *= Float32(success_rate)
            unc_off += Float32(avg_err * 0.1)
        end
    end
    
    return cost_mul, reward_mul, unc_off
end

end # module
```

### 7.7 Dream System

```julia
# From adaptive-kernel/cognition/oneiric/OneiricController.jl
module OneiricController

@with_kw mutable struct OneiricConfig
    min_energy_for_dream::Float32 = 0.35f0
    dream_duration_min::Float64 = 300.0
    dream_duration_max::Float64 = 1800.0
    cycle_interval::Float64 = 60.0
    enable_replay::Bool = true
    enable_hallucination_training::Bool = true
    enable_homeostasis::Bool = true
end

function enter_dream_state!()::OneiricState
    state = OneiricState(
        phase=:entering,
        energy=0.0f0,
        start_time=time(),
        cycles_completed=0
    )
    
    if config.enable_replay
        MemoryReplay.replay_experiences!(config)
    end
    
    if config.enable_homeostasis
        SynapticHomeostasis.normalize_weights()
    end
    
    return state
end

function should_enter_dream()::Bool
    # Enter dream if: idle, low energy, or scheduled time
    idle_time = time() - last_activity_time
    return (idle_time > config.idle_threshold) || 
           (system_energy < config.min_energy_for_dream) ||
           (current_hour() == config.nightly_hour)
end

end # module
```

---

## 8. Pseudocode for Orchestrator Loop

### Master OODA Loop at ~100Hz

```
// Cognitive Orchestrator - Main Loop
// Target: 100Hz = 10ms per cycle
// Actual: GoalEngine at 5s interval, cognitive loop faster

const CYCLE_TIME_MS = 10  // 100Hz target
const MAIN_LOOP_FREQUENCY = 100

function orchestrator_main():
    initialize()
    
    while running:
        start_time = current_time_ms()
        
        // === OODA LOOP ===
        
        // O: OBSERVE - Gather all inputs
        perception = perceive(
            user_input=read_user_input(),
            system_state=StateObserver.observe(),
            sensors=read_sensors(),
            knowledge=query_knowledge_graph()
        )
        
        // O: ORIENT - Generate goals from perception  
        goals = GoalEngine.generate_goals(perception)
        
        // D: DECIDE - Plan and select actions
        for goal in goals:
            GoalScheduler.schedule(goal)
        
        selected_goal = GoalScheduler.next_goal()
        
        if selected_goal != null:
            plan = Planner.create_plan(selected_goal)
            
            if Planner.validate(plan):
                // Request kernel approval
                approved, reason = KernelInterface.approve_action(
                    name=plan.goal_name,
                    type="plan_execution",
                    params=plan.steps
                )
                
                if approved:
                    // A: ACT - Execute plan
                    result = Executor.execute(plan, KernelInterface)
                    
                    // Verify execution
                    verified = Verifier.verify(result, plan.expected_outcome)
                    
                    if verified:
                        // L: LEARN - Store in memory
                        Memory.ingest_episode(
                            goal=selected_goal,
                            plan=plan,
                            result=result,
                            success=true
                        )
                        
                        GoalScheduler.complete(selected_goal.id)
                    else:
                        Memory.ingest_episode(
                            goal=selected_goal,
                            plan=plan, 
                            result=result,
                            success=false
                        )
                        
                        GoalScheduler.fail(selected_goal.id, "Verification failed")
                else:
                    log("Kernel rejected: $reason")
                    GoalScheduler.fail(selected_goal.id, reason)
        
        // Dream system: If idle, process offline
        if GoalScheduler.has_pending() == false:
            if OneiricController.should_enter_dream():
                OneiricController.run_dream_processing!(
                    duration=config.dream_duration_min
                )
        
        // === CYCLE COMPLETION ===
        
        elapsed = current_time_ms() - start_time
        if elapsed < CYCLE_TIME_MS:
            sleep(CYCLE_TIME_MS - elapsed)  // Maintain 100Hz
        
        // Telemetry
        telemetry = Dict(
            cycle_time_ms=elapsed,
            goals_generated=goals_generated_this_cycle,
            goals_completed=goals_completed_this_cycle,
            memory_episodes=total_episodes,
            loop_count=loop_count++
        )


// Perception Pipeline
function perceive(user_input, system_state, sensors, knowledge):
    // 1. Language understanding
    parsed = LanguageUnderstanding.understand(user_input)
    
    // 2. Intent classification
    intent = LanguageUnderstanding.parse_intent(parsed)
    
    // 3. Entity extraction
    entities = LanguageUnderstanding.extract_entities(parsed)
    
    // 4. Confidence assessment
    confidence = LanguageUnderstanding.assess_confidence(parsed)
    
    return Perception(
        raw_input=user_input,
        parsed=parsed,
        intent=intent,
        entities=entities,
        confidence=confidence,
        system_state=system_state,
        knowledge_context=knowledge
    )


// Memory consolidation (runs in background)
function memory_consolidation():
    // 1. Compress episodes
    Memory.compress_memory!(window=10)
    
    // 2. Update knowledge graph
    for episode in recent_episodes:
        KnowledgeGraph.add_event(
            entity=episode.goal,
            event_type="execution",
            properties=episode.result
        )
    
    // 3. Calculate adjustments for planning
    adjustments = Memory.get_adjustments(all_capabilities)
    Planner.apply_adjustments(adjustments)
```

---

## 9. Testing Suggestions

### 9.1 Goal Engine Testing

```julia
# Test goal generation
@testset "Goal Generation" begin
    state = SystemState(cpu=0.95, memory=0.85)
    goals = GoalGenerator.generate(state)
    
    @test length(goals) > 0
    @test all(g.priority > 0 for g in goals)
    
    # High CPU should trigger optimization goal
    @test any(g.name == :optimize_runtime for g in goals)
end

# Test goal scheduling
@testset "Goal Scheduling" begin
    goal = Goal(:test_goal, priority=0.8)
    result = GoalScheduler.schedule(goal)
    
    @test result == true
    @test GoalScheduler.has_pending() == true
    
    # Duplicate should fail
    result2 = GoalScheduler.schedule(goal)
    @test result2 == false
end
```

### 9.2 Planner Testing

```julia
# Test HTN decomposition
@testset "Planner HTN" begin
    goal = Goal(:run_self_diagnostic)
    plan = Planner.create_plan(goal)
    
    @test length(plan.steps) == 3
    @test plan.steps[1].action == "check_system_logs"
    @test Planner.validate(plan) == true
end

# Test unknown goal
@testset "Unknown Goal" begin
    goal = Goal(:unknown_goal_type)
    plan = Planner.create_plan(goal)
    
    @test length(plan.steps) == 0
    @test Planner.validate(plan) == false
end
```

### 9.3 Memory System Testing

```julia
# Test episode ingestion
@testset "Memory Episodes" begin
    ms = MemoryStore()
    
    episode = Dict(
        "action_id" => "test_action",
        "result" => true,
        "prediction_error" => 0.1,
        "cycle" => 1
    )
    
    Memory.ingest_episode!(ms, episode)
    
    @test length(ms.episodes) == 1
    @test ms.capability_stats["test_action"]["success"] == 1
end

# Test adjustments
@testset "Planning Adjustments" begin
    ms = MemoryStore()
    
    # Add successful episodes
    for i in 1:10
        Memory.ingest_episode!(ms, Dict("action_id"=>"test", "result"=>true, "prediction_error"=>0.1))
    end
    
    # Add failures
    for i in 1:5
        Memory.ingest_episode!(ms, Dict("action_id"=>"test", "result"=>false, "prediction_error"=>0.5))
    end
    
    cost, reward, unc = Memory.get_adjustments(ms, ["test"])
    
    @test cost > 1.0  # More errors = higher cost
    @test reward < 1.0  # Not 100% success
end
```

### 9.4 IPC Testing

```julia
# Test IPC communication
@testset "Rust IPC" begin
    # Initialize IPC
    result = RustIPC.init_ipc()
    @test result == true
    
    # Test round-trip
    message = Dict("test" => "data", "value" => 42)
    encoded = JSON.json(message)
    
    RustIPC.safe_shm_write(Vector{UInt8}(encoded))
    response = RustIPC.safe_shm_read()
    
    @test !isempty(response)
end
```

### 9.5 Verifier Testing

```julia
# Test LLM output validation
@testset "LLM Validator" begin
    valid_json = """{"intent": "task_execution", "priority": "high", "value": 0.5}"""
    result = LLMOutputValidator.validate_llm_output(valid_json)
    
    @test result.is_valid == true
    
    # Test invalid intent
    invalid_json = """{"intent": "malicious_command", "priority": "high"}"""
    result = LLMOutputValidator.validate_llm_output(invalid_json)
    
    @test result.is_valid == false
    @test contains(result.error_message, "Invalid intent")
end
```

### 9.6 Integration Testing

```julia
# Full loop integration test
@testset "Full Orchestrator Loop" begin
    # Initialize all components
    KernelInterface.init()
    GoalEngine._initialize()
    
    # Create and schedule a goal
    state = StateObserver.observe()
    goals = GoalGenerator.generate(state)
    
    for goal in goals
        GoalScheduler.schedule(goal)
    end
    
    selected = GoalScheduler.next_goal()
    
    if selected != nothing
        plan = Planner.create_plan(selected)
        
        if Planner.validate(plan)
            approved, _ = KernelInterface.approve_action(Dict(
                "name" => string(plan.goal_name),
                "type" => "test"
            ))
            
            @test approved == true
        end
    end
end
```

---

## 10. Scaling Suggestions

### 10.1 Distributed Cognition Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                          DISTRIBUTED COGNITIVE SYSTEM                               │
└─────────────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────┐
                    │   Load Balancer │  (Route requests, health checks)
                    │   :8000          │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Cognitive Node │  │  Cognitive Node │  │  Cognitive Node │
│    :8001        │  │    :8002        │  │    :8003        │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│  - Perception   │  │  - Perception   │  │  - Perception   │
│  - Goals        │  │  - Goals        │  │  - Goals        │
│  - Planning     │  │  - Memory       │  │  - Executor     │
│  - Local Mem    │  │  - Knowledge     │  │  - Verifier     │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                    ┌────────┴────────┐
                    │  Shared State   │
                    │  (Redis/etcd)   │
                    │                 │
                    │  - Goals Queue  │
                    │  - Memory Store │
                    │  - Knowledge    │
                    │  - Trust Scores │
                    └─────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Rust Kernel    │  │  Rust Kernel    │  │  Rust Kernel    │
│  Node A         │  │  Node B         │  │  Node C         │
│  (Sovereign)    │  │  (Sovereign)    │  │  (Sovereign)    │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### 10.2 Horizontal Scaling Strategy

1. **Stateless Cognitive Nodes**
   - Each node runs independent OODA loops
   - Share state via distributed cache (Redis)
   - No single point of failure

2. **Specialized Roles**
   - Perception nodes: Process inputs
   - Planning nodes: Generate plans
   - Execution nodes: Run capabilities
   - Memory nodes: Store/retrieve experiences

3. **Shared Kernel Interface**
   - All nodes communicate with Rust kernels
   - Kernel approval still centralized per node
   - Trust scores synchronized across nodes

### 10.3 IPC Scaling

```julia
# Current: Single shared memory region
# Future: Multiple ring buffers per core

struct DistributedIPC
    per_core_buffers::Vector{RingBuffer}  # One per CPU core
    aggregator::Channel{IPCMessage}      # Cross-core message aggregation
    global_state::SharedState            # Synchronized via etcd/Redis
end

# Message routing
function route_message(msg::IPCMessage)::Int
    # Hash-based routing to minimize cross-core communication
    core = hash(msg.header.sender) % n_cores()
    return core
end
```

### 10.4 Memory Scaling

```julia
# Distributed memory system
struct DistributedMemory
    local_store::MemoryStore           # Hot data (recent episodes)
    remote_store::RedisConnection       # Warm data (last 24h)
    archive_store::S3Bucket             # Cold data (older)
    
    # Replication factor for critical episodes
    const REPLICATION = 3
end

function ingest_episode!(dm::DistributedMemory, episode::Dict)
    # Always store locally for low latency
    ingest_episode!(dm.local_store, episode)
    
    # Replicate critical episodes
    if episode_importance(episode) > 0.9
        for _ in 1:dm.REPLICATION
            Redis.push(dm.remote_store, episode)
        end
    end
    
    # Archive old episodes
    if dm.local_store.size > LOCAL_LIMIT
        S3.upload(dm.archive_store, local_store.evict())
    end
end
```

### 10.5 Performance Targets

| Metric | Current | Scaled Target |
|--------|---------|---------------|
| Loop Frequency | ~0.2Hz (5s) | 100Hz |
| Goals/minute | ~10 | 1000 |
| Memory Episodes | 1000 | 1M+ |
| Knowledge Triples | 10K | 100M+ |
| Latency (p99) | 100ms | 10ms |

---

## Appendix: File Mapping

| Component | Implementation File |
|-----------|-------------------|
| Goal Engine | [`adaptive-kernel/autonomy/goal_engine.jl`](adaptive-kernel/autonomy/goal_engine.jl) |
| Goal Generator | [`adaptive-kernel/autonomy/goal_generator.jl`](adaptive-kernel/autonomy/goal_generator.jl) |
| Goal Scheduler | [`adaptive-kernel/autonomy/goal_scheduler.jl`](adaptive-kernel/autonomy/goal_scheduler.jl) |
| Planner | [`adaptive-kernel/autonomy/planner.jl`](adaptive-kernel/autonomy/planner.jl) |
| Executor | [`adaptive-kernel/cognition/agents/Executor.jl`](adaptive-kernel/cognition/agents/Executor.jl) |
| Verifier | [`adaptive-kernel/kernel/validation/LLMOutputValidator.jl`](adaptive-kernel/kernel/validation/LLMOutputValidator.jl) |
| Memory | [`adaptive-kernel/memory/Memory.jl`](adaptive-kernel/memory/Memory.jl) |
| Knowledge Graph | [`adaptive-kernel/knowledge/KnowledgeGraph.jl`](adaptive-kernel/knowledge/KnowledgeGraph.jl) |
| Dream System | [`adaptive-kernel/cognition/oneiric/OneiricController.jl`](adaptive-kernel/cognition/oneiric/OneiricController.jl) |
| Memory Replay | [`adaptive-kernel/cognition/oneiric/MemoryReplay.jl`](adaptive-kernel/cognition/oneiric/MemoryReplay.jl) |
| Kernel Interface | [`adaptive-kernel/kernel/kernel_interface.jl`](adaptive-kernel/kernel/kernel_interface.jl) |
| Rust IPC | [`adaptive-kernel/kernel/ipc/RustIPC.jl`](adaptive-kernel/kernel/ipc/RustIPC.jl) |
| Goal System | [`adaptive-kernel/cognition/goals/GoalSystem.jl`](adaptive-kernel/cognition/goals/GoalSystem.jl) |
| Autonomous Planner | [`adaptive-kernel/planning/AutonomousPlanner.jl`](adaptive-kernel/planning/AutonomousPlanner.jl) |

---

*Document generated for ITHERIS Cognitive Orchestrator Integration Project*
