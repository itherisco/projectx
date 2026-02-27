# JARVIS Project - Complete Technical Documentation

**Version:** 1.0.0  
**Last Updated:** 2026-02-24  
**Julia Version:** 1.10+

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Core Components](#core-components)
4. [Type System](#type-system)
5. [Module Documentation](#module-documentation)
6. [Cognitive Cycle](#cognitive-cycle)
7. [Safety & Trust Model](#safety--trust-model)
8. [Integration Guide](#integration-guide)
9. [API Reference](#api-reference)
10. [Configuration](#configuration)

---

## Implementation Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ COMPLETE | ITHERIS Brain Integration |
| Phase 2 | ✅ COMPLETE | Kernel Sovereignty Enforcement |
| Phase 3 | ✅ COMPLETE | SystemIntegrator Integration |
| Phase 4 | ✅ COMPLETE | Testing (55 tests passing) |

---

## Executive Summary

**Project Jarvis** is a cutting-edge Neuro-Symbolic Autonomous System that merges high-level LLM reasoning with low-level deterministic safety. It evolves the existing ProjectX codebase into a fully integrated, proactive personal assistant.

The system integrates three major subsystems:

| Subsystem | Purpose | Authority |
|-----------|---------|-----------|
| **ITHERIS Brain** | Neural decision making, action proposals | Advisory only |
| **Adaptive Kernel** | Deterministic safety validation | Sovereign authority |
| **Cerebral Cortex** | Natural language understanding | Input processing |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PROJECT JARVIS ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     CEREBRAL CORTEX (LLM Layer)                     │   │
│  │                                                                       │   │
│  │  ┌─────────────┐  ┌──────────────────┐  ┌─────────────────────────┐  │   │
│  │  │  GPT-4o    │  │  Claude 3.5       │  │  Natural Language       │  │   │
│  │  │  Bridge    │  │  Bridge           │  │  Parser                 │  │   │
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

---

## Core Components

### File Structure

```
jarvis/
├── Project.toml              # Julia package manifest
├── README.md                # Project overview
└── src/
    ├── Jarvis.jl            # Main entry point
    ├── SystemIntegrator.jl # Central Nervous System
    ├── types.jl            # Core type definitions
    ├── llm/
    │   └── LLMBridge.jl    # LLM communication (GPT-4o, Claude)
    ├── memory/
    │   ├── VectorMemory.jl # Semantic storage + RAG
    │   └── SemanticMemory.jl # Action outcome memory
    ├── orchestration/
    │   └── TaskOrchestrator.jl # Proactive planning
    └── bridge/
        ├── CommunicationBridge.jl # Voice/Vision
        └── OpenClawBridge.jl # Tool container interface
```

---

## Type System

### Trust Levels

The system implements a five-level trust model for action authorization:

```julia
@enum TrustLevel begin
    TRUST_BLOCKED = 0      # No actions allowed
    TRUST_RESTRICTED = 1   # Only read-only actions
    TRUST_LIMITED = 2      # Non-destructive actions only  
    TRUST_STANDARD = 3      # Most actions allowed
    TRUST_FULL = 4          # All actions allowed (with audit)
end
```

| Level | Value | Allowed Actions |
|-------|-------|----------------|
| `TRUST_BLOCKED` | 0 | None |
| `TRUST_RESTRICTED` | 1 | Read-only |
| `TRUST_LIMITED` | 2 | Non-destructive |
| `TRUST_STANDARD` | 3 | Most actions |
| `TRUST_FULL` | 4 | All (with audit) |

### System Status

```julia
@enum SystemStatus begin
    STATUS_BOOTING
    STATUS_INITIALIZING
    STATUS_RUNNING
    STATUS_PAUSED
    STATUS_ERROR
    STATUS_SHUTDOWN
end
```

### Action Categories

```julia
@enum ActionCategory begin
    ACTION_READ      # Observations, queries
    ACTION_WRITE     # File operations
    ACTION_EXECUTE   # Shell commands, HTTP requests
    ACTION_IOT       # IoT device control
    ACTION_SYSTEM    # System modifications
end
```

### Goal Priorities

```julia
@enum GoalPriority begin
    PRIORITY_CRITICAL = 5
    PRIORITY_HIGH = 4
    PRIORITY_MEDIUM = 3
    PRIORITY_LOW = 2
    PRIORITY_BACKGROUND = 1
end
```

---

## Module Documentation

### 1. SystemIntegrator (Central Nervous System)

The [`SystemIntegrator`](jarvis/src/SystemIntegrator.jl) module serves as the central hub that orchestrates all components.

**Key Functions:**

| Function | Description |
|----------|-------------|
| [`initialize_jarvis()`](jarvis/src/SystemIntegrator.jl:240) | Initialize the complete Jarvis system |
| [`run_cycle()`](jarvis/src/SystemIntegrator.jl:515) | Execute one complete cognitive cycle |
| [`process_user_request()`](jarvis/src/SystemIntegrator.jl) | Process natural language user request |
| [`get_system_status()`](jarvis/src/SystemIntegrator.jl) | Get current system status |
| [`shutdown()`](jarvis/src/SystemIntegrator.jl) | Graceful shutdown |

**New Exported Functions (Phase 3):**

| Function | Description |
|----------|-------------|
| [`_load_capability_registry()`](jarvis/src/SystemIntegrator.jl:1135) | Load capability registry from JSON |
| [`_get_capability_by_id()`](jarvis/src/SystemIntegrator.jl:1185) | Get capability by ID |
| [`_execute_capability()`](jarvis/src/SystemIntegrator.jl:1232) | Execute a capability |
| [`_handle_brain_nothing()`](jarvis/src/SystemIntegrator.jl:1300) | Handle brain returning nothing |
| [`_handle_kernel_denial()`](jarvis/src/SystemIntegrator.jl:1345) | Handle kernel denial |

**Key Structures:**

```julia
struct JarvisConfig
    llm::LLMConfig
    communication::CommunicationConfig
    orchestrator::OrchestratorConfig
    vector_store_path::String
    kernel_config_path::String
    proactive_scan_interval::Second
    log_level::Symbol
    events_log_path::String
end

mutable struct JarvisSystem
    config::JarvisConfig
    vector_store::VectorStore
    semantic_memory::SemanticMemoryStore
    llm_bridge::LLMConfig
    kernel::KernelWrapper
    brain::BrainWrapper
    state::JarvisState
    conversation_history::Vector{ConversationEntry}
    pending_suggestions::Vector{ProactiveSuggestion}
    cycle_times::Vector{Float64}
    last_proactive_scan::DateTime
    logger::Logger
end
```

### 2. LLMBridge (Cerebral Cortex)

The [`LLMBridge`](jarvis/src/llm/LLMBridge.jl) module provides async communication with LLM providers (GPT-4o, Claude 3.5).

**Configuration:**

```julia
struct LLMConfig
    provider::Symbol        # :openai, :anthropic
    api_key::String
    model::String
    max_tokens::Int
    temperature::Float32
    base_url::String
    timeout::Int           # HTTP timeout in seconds
end
```

**Key Functions:**

| Function | Description |
|----------|-------------|
| [`parse_user_intent()`](jarvis/src/llm/LLMBridge.jl:212) | Parse natural language into JarvisGoal |
| [`generate_response()`](jarvis/src/llm/LLMBridge.jl:387) | Generate natural language response |
| [`build_perception_vector_from_nl()`](jarvis/src/llm/LLMBridge.jl:435) | Extract 12D vector from description |
| [`async_llm_request()`](jarvis/src/llm/LLMBridge.jl:129) | Make async request to LLM API |

**Features:**
- Async HTTP requests using `@spawn`
- Mock parsing for demo mode (no API key required)
- Conversation history context
- RAG context retrieval

### 3. VectorMemory (Semantic Storage)

The [`VectorMemory`](jarvis/src/memory/VectorMemory.jl) module implements an in-memory HNSW-like vector store for semantic search.

**Key Features:**
- Deterministic embeddings (SHA256-based, reproducible)
- Cosine similarity search
- Multiple collections: `:user_preferences`, `:conversations`, `:project_knowledge`
- L2 normalization
- JSON persistence

**Key Functions:**

| Function | Description |
|----------|-------------|
| [`generate_embedding()`](jarvis/src/memory/VectorMemory.jl:72) | Generate deterministic 384D embedding |
| [`search()`](jarvis/src/memory/VectorMemory.jl:156) | Semantic similarity search |
| [`rag_retrieve()`](jarvis/src/memory/VectorMemory.jl:319) | RAG context retrieval |
| [`store_conversation!()`](jarvis/src/memory/VectorMemory.jl:231) | Store conversation entry |
| [`store_preference!()`](jarvis/src/memory/VectorMemory.jl:262) | Store user preference |
| [`store_knowledge!()`](jarvis/src/memory/VectorMemory.jl:292) | Store project knowledge |

### 4. SemanticMemory (Action Outcomes)

The [`SemanticMemory`](jarvis/src/memory/SemanticMemory.jl) module stores action outcomes for learning from past experiences.

**Key Concept:**
The neuro-symbolic learning mechanism adjusts expected rewards based on similar past outcomes:

```julia
adjusted_reward = expected_reward * (1 + α * avg_error)
```

Where α is the learning factor and avg_error comes from similar past actions.

**Key Functions:**

| Function | Description |
|----------|-------------|
| [`store_action_outcome!()`](jarvis/src/memory/SemanticMemory.jl:201) | Store action execution result |
| [`recall_similar_outcomes()`](jarvis/src/memory/SemanticMemory.jl:242) | Query similar past outcomes |
| [`adjust_expected_reward()`](jarvis/src/memory/SemanticMemory.jl:298) | Adjust reward based on history |
| [`get_action_statistics()`](jarvis/src/memory/SemanticMemory.jl:356) | Get historical statistics for action |

### 5. TaskOrchestrator (Proactive Planning)

The [`TaskOrchestrator`](jarvis/src/orchestration/TaskOrchestrator.jl) module provides proactive suggestions based on system state analysis.

**Key Functions:**

| Function | Description |
|----------|-------------|
| [`analyze_and_suggest()`](jarvis/src/orchestration/TaskOrchestrator.jl:226) | Main orchestration function |
| [`check_system_health()`](jarvis/src/orchestration/TaskOrchestrator.jl:81) | Analyze system metrics |
| [`generate_optimization_suggestions()`](jarvis/src/orchestration/TaskOrchestrator.jl:145) | Generate optimization suggestions |
| [`schedule_proactive_tasks()`](jarvis/src/orchestration/TaskOrchestrator.jl:277) | Schedule auto-applicable tasks |

**Suggestion Categories:**
- `:optimization` - Performance improvements
- `:safety` - Security alerts
- `:productivity` - Task automation
- `:resource` - Resource management

### 6. CommunicationBridge (Multimodal)

The [`CommunicationBridge`](jarvis/src/bridge/CommunicationBridge.jl) module handles voice (STT/TTS) and vision (VLM) modalities.

**Voice Features:**
- Whisper STT (OpenAI)
- ElevenLabs TTS
- Real-time audio with PortAudio
- Silence detection
- Phrase caching for low latency

**Key Types:**

```julia
struct VoiceInput
    audio_data::Vector{UInt8}
    sample_rate::Int
    duration_ms::Int
    transcript::Union{String, Nothing}
    timestamp::DateTime
end

struct VoiceOutput
    text::String
    audio_data::Union{Vector{UInt8}, Nothing}
    voice_id::String
    timestamp::DateTime
end

struct VisionInput
    image_data::Vector{UInt8}
    mime_type::String
    description::Union{String, Nothing}
    analysis::Union{Dict{String, Any}, Nothing}
    timestamp::DateTime
end
```

### 7. OpenClawBridge (Tool Container)

The [`OpenClawBridge`](jarvis/src/bridge/OpenClawBridge.jl) module interfaces with OpenClaw Docker containers for tool execution.

**Available Tools:**

| Category | Tools |
|----------|-------|
| **Productivity** | `google_calendar_insert`, `google_calendar_list` |
| **Communication** | `gmail_send`, `gmail_read` |
| **System** | `system_shell`, `system_info` |
| **Web** | `web_search`, `web_fetch` |
| **Filesystem** | `file_read`, `file_write`, `file_list` |
| **Interface** | `notification_send` |
| **Entertainment** | `spotify_play`, `spotify_control` |

**Risk Levels:**
- Low (0.1-0.3): Read operations, notifications
- Medium (0.4-0.6): File writes, calendar
- High (0.7-1.0): Shell execution (requires `TRUST_FULL`)

### 8. BrainTrainer (Neural Training)

The [`BrainTrainer`](jarvis/src/brain/BrainTrainer.jl) module provides training, checkpointing, and restoration capabilities for the ITHERIS Brain.

**Key Features:**
- Training loop with configurable batch size and learning rate
- Checkpoint creation for crash recovery
- Restoration from checkpoint files
- Experience buffer management

**Key Functions:**

| Function | Description |
|----------|-------------|
| [`train_brain!()`](jarvis/src/brain/BrainTrainer.jl:134) | Main training loop |
| [`brain_checkpoint()`](jarvis/src/brain/BrainTrainer.jl:231) | Create checkpoint for crash recovery |
| [`restore_brain!()`](jarvis/src/brain/BrainTrainer.jl:295) | Restore brain from checkpoint |
| [`save_checkpoint()`](jarvis/src/brain/BrainTrainer.jl:87) | Save checkpoint to file |
| [`load_checkpoint()`](jarvis/src/brain/BrainTrainer.jl:106) | Load checkpoint from file |

**Training Configuration:**

```julia
struct TrainingConfig
    batch_size::Int           # Default: 32
    learning_rate::Float32    # Default: 0.001
    gamma::Float32           # Discount factor, Default: 0.95
    target_update_freq::Int  # Default: 100
    save_freq::Int           # Default: 1000
    max_epochs::Int          # Default: 100
    min_experiences::Int     # Default: 100
end
```

**Checkpoint Structure:**

```julia
struct BrainCheckpoint
    id::UUID                  # Unique identifier
    timestamp::DateTime       # Creation time
    brain_state::Dict         # Serialized brain state
    training_step::Int        # Current training step
    epoch::Int                # Current epoch
    loss::Float32            # Training loss
    metadata::Dict            # Additional metadata
end
```

---

## Cognitive Cycle

The main cognitive cycle is implemented in [`run_cycle()`](jarvis/src/SystemIntegrator.jl:392), which executes seven steps:

```
┌─────────────────────────────────────────────────────────────────┐
│                      run_cycle()                                │
├─────────────────────────────────────────────────────────────────┤
│  1. OBSERVE    → _observe_world()                              │
│     Collect system metrics, events, active goals               │
│                                                                 │
│  2. PERCEIVE   → _build_perception()                           │
│     Create 12D PerceptionVector for ITHERIS                    │
│                                                                 │
│  3. INFER      → _brain_infer()                                │
│     ITHERIS brain proposes action (ADVISORY ONLY)              │
│                                                                 │
│  4. APPROVE     → _kernel_approval()                            │
│     Kernel validates and scores action (SOVEREIGN)              │
│                                                                 │
│  5. EXECUTE    → _execute_action()                             │
│     Run approved action via capabilities                        │
│                                                                 │
│  6. LEARN      → _learn()                                      │
│     Update semantic memory, compute reward                     │
│                                                                 │
│  7. SUGGEST    → _proactive_scan()                             │
│     Generate proactive suggestions                              │
└─────────────────────────────────────────────────────────────────┘
```

### 12-Dimensional Perception Vector

The perception vector captures the world state in 12 dimensions:

| Index | Dimension | Range | Description |
|-------|-----------|-------|-------------|
| 1 | `cpu_load` | [0,1] | CPU utilization |
| 2 | `memory_usage` | [0,1] | Memory utilization |
| 3 | `disk_io` | [0,1] | Disk I/O rate |
| 4 | `network_latency` | [0,1] | Network latency |
| 5 | `overall_severity` | [0,1] | Aggregate threat level |
| 6 | `threat_count` | [0,1] | Normalized threat count |
| 7 | `file_count` | [0,1] | Normalized file count |
| 8 | `change_rate` | [0,1] | Rate of file changes |
| 9 | `process_count` | [0,1] | Normalized process count |
| 10 | `energy_level` | [0,1] | System energy/battery |
| 11 | `confidence` | [0,1] | Model confidence |
| 12 | `user_activity` | [0,1] | User activity level |

---

## Safety & Trust Model

### Kernel Decision Types

The kernel returns one of three decisions:

| Decision | Meaning | Conditions |
|----------|---------|------------|
| `APPROVED` | Action can execute | confidence > 0.5, risk < 0.7, priority > 0.3 |
| `DENIED` | Action not approved | High risk, low confidence, low priority, or validation failure |
| `STOPPED` | System should stop | Critically low energy (< 0.1) |

### Kernel Sovereignty

**SECURITY CRITICAL:** The Adaptive Kernel has SOVEREIGN authority over execution. No action executes without kernel approval.

```
Brain (ITHERIS) ──PROPOSES──► Kernel ──APPROVES──► Execution
     Advisory              Sovereign          Only if
     Only                  Authority          Approved
```

### Deterministic Scoring Formula

All actions are scored using:

```
score = priority × (reward − risk)
```

Where:
- `priority`: Goal priority (0-1)
- `reward`: Expected reward (0-1)
- `risk`: Estimated risk (0-1)

Actions with negative scores are DENIED.

### Trust Level Requirements

| Action Risk | Required Trust |
|-------------|---------------|
| Low (0.1-0.3) | `TRUST_LIMITED` |
| Medium (0.4-0.6) | `TRUST_STANDARD` |
| High (0.7-1.0) | `TRUST_FULL` |

### Safety Features

1. **Deterministic Kernel**: All actions scored by `priority × (reward − risk)`
2. **Whitelist Enforcement**: Only pre-approved capabilities executable
3. **Audit Logging**: Every action recorded in `events.log`
4. **Trust Levels**: High-risk actions require `trust_level > 0.8`
5. **Confirmation Gate**: User must confirm potentially dangerous operations

---

## Integration Guide

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

### Custom Configuration

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

### Integration with Adaptive Kernel

The system automatically loads the Adaptive Kernel from `../adaptive-kernel` if available:

```julia
# Kernel is sovereign authority
if system.kernel.initialized
    # Use kernel for safety validation
    approved_action = _kernel_approval(system, proposal, perception)
end
```

---

## API Reference

### Jarvis Module Exports

```julia
# Core
SystemIntegrator
JarvisTypes

# Submodules
LLMBridge
VectorMemory
TaskOrchestrator
CommunicationBridge

# Types
JarvisTypes.JarvisSystem
JarvisTypes.JarvisConfig
JarvisTypes.JarvisState
JarvisTypes.JarvisGoal
JarvisTypes.PerceptionVector
JarvisTypes.ActionProposal
JarvisTypes.ExecutableAction
JarvisTypes.TrustLevel
JarvisTypes.SystemStatus

# Functions
SystemIntegrator.initialize_jarvis
SystemIntegrator.run_cycle
SystemIntegrator.process_user_request
SystemIntegrator.get_system_status
SystemIntegrator.shutdown

# Configuration
JarvisTypes.LLMConfig
JarvisTypes.CommunicationConfig
JarvisTypes.OrchestratorConfig

# Vector Memory
VectorMemory.VectorStore
VectorMemory.store!
VectorMemory.search
VectorMemory.rag_retrieve
```

---

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `JARVIS_LLM_API_KEY` | LLM API key | (empty) |
| `JARVIS_STT_API_KEY` | Whisper API key | (empty) |
| `JARVIS_TTS_API_KEY` | ElevenLabs API key | (empty) |

### Default Paths

| Path | Description |
|------|-------------|
| `./jarvis_vector_store.json` | Vector store persistence |
| `./jarvis_events.log` | Event audit log |
| `../adaptive-kernel/` | Adaptive Kernel module |

### Default Parameters

| Parameter | Default Value |
|-----------|---------------|
| Proactive scan interval | 60 seconds |
| Trust level (initial) | `TRUST_RESTRICTED` |
| LLM timeout | 30 seconds |
| Vector store embedding dim | 384 |
| HNSW ef_construction | 16 |
| HNSW m | 8 |

---

## Development Status

| Component | Status |
|-----------|--------|
| Core architecture design | ✅ Complete |
| SystemIntegrator implementation | ✅ Complete |
| LLM Bridge (async) | ✅ Complete |
| Vector Memory (HNSW-like) | ✅ Complete |
| TaskOrchestrator (proactive) | ✅ Complete |
| CommunicationBridge (hooks) | ✅ Complete |
| Full ITHERIS integration | 🔄 In Progress |
| Full Kernel integration | 🔄 In Progress |
| Voice module implementation | 🔄 In Progress |
| Vision module implementation | 🔄 In Progress |

---

## Requirements

- **Julia**: 1.10+
- **Neural Engine**: Flux.jl 0.14-0.16
- **HTTP Client**: HTTP.jl 1.9-1.11
- **Serialization**: JSON.jl 0.21-0.24
- **Audio I/O**: PortAudio.jl 0.1, WAV.jl 1.0-1.3

---

## License

Internal Project - All Rights Reserved
