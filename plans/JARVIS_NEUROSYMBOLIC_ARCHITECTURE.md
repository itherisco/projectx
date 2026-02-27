# JARVIS Neuro-Symbolic Cognitive Architecture

**Document Version:** 1.0  
**Date:** 2026-02-26  
**Status:** Implementation-Ready Specification

---

## GLOBAL DESIGN PRINCIPLES

1. **Brain is advisory. Kernel is sovereign.** — All brain outputs must pass through `Kernel.approve()` before execution. No exceptions.

2. **Continuous perception must not bypass kernel risk evaluation.** — All sensory streams feed into the kernel's approval pipeline.

3. **Learning must be sandboxed and reversible.** — All model updates occur in isolated environments with checkpoint rollback capability.

4. **Emotions modulate value signals but do not override safety.** — Emotional states affect value weighting in brain inference but cannot bypass kernel veto.

5. **All subsystems must expose clear interface contracts.** — Every module must define input/output types and document pre/post conditions.

6. **No magical abstractions — provide data structures and function signatures.** — Every component includes actual Julia struct definitions and function signatures.

---

## TABLE OF CONTENTS

1. [Target Brain Architecture](#1-target-brain-architecture)
2. [Component Implementation Plans](#2-implementation-plans-for-each-component)
3. [Implementation Roadmap](#3-implementation-roadmap)
4. [Safety & Sovereignty Guarantees](#4-safety--sovereignty-guarantees)
5. [Final Cognitive Loop](#5-final-cognitive-loop)

---

# 1. TARGET BRAIN ARCHITECTURE

## 1.1 Text-Based Systems Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              JARVIS NEURO-SYMBOLIC COGNITIVE ARCHITECTURE             │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐   │
│  │   SENSORY    │────▶│   ATTENTION  │────▶│ WORLD MODEL │────▶│ GOAL SYSTEM  │   │
│  │   BUFFER     │     │   & SALIENCE │     │              │     │              │   │
│  └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘   │
│         │                    │                    │                    │            │
│         ▼                    ▼                    ▼                    ▼            │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                          ITHERIS CORE (Neural Brain)                         │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │    │
│  │  │  VALUE_NET  │  │  POLICY_NET │  │ PREDICTOR   │  │   ATTENTION_NET     │ │    │
│  │  │  (Critic)   │  │   (Actor)   │  │  (World)    │  │   (Salience)        │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────┘ │    │
│  │         │                │                │                  │              │    │
│  │         ▼                ▼                ▼                  ▼              │    │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐ │    │
│  │  │                    EXPERIENCE REPLAY BUFFER                              │ │    │
│  │  │            (Sandboxed, Reversible Learning Environment)                 │ │    │
│  │  └──────────────────────────────────────────────────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                               │
│                                      ▼                                               │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                          │
│  │ EMOTIONAL    │────▶│   ACTION    │────▶│   KERNEL     │                          │
│  │ ARCHITECTURE │     │  PROPOSAL   │     │  APPROVAL    │                          │
│  │              │     │             │     │   (SOVEREIGN)│                          │
│  └──────────────┘     └──────────────┘     └──────────────┘                          │
│         │                                       │                                    │
│         ▼                                       ▼                                    │
│  ┌──────────────┐                      ┌──────────────┐                               │
│  │ METACOGNITION│◀─────────────────────│  EXECUTION   │                               │
│  │ / SELF-MODEL │                      │    & FEEDBACK│                               │
│  └──────────────┘                      └──────────────┘                               │
│         │                                       │                                    │
│         ▼                                       ▼                                    │
│  ┌──────────────┐                      ┌──────────────┐                               │
│  │    SLEEP     │◀─────────────────────│  REFLECTION  │                               │
│  │ CONSOLIDATION│                      │  & LEARNING  │                               │
│  └──────────────┘                      └──────────────┘                               │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## 1.2 Updated Cognitive Cycle

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         COGNITIVE CYCLE DATA FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  1. PERCEIVE()                                                                       │
│     ├── ContinuousSensoryBuffer ←──── Visual Stream                                  │
│     ├── ContinuousSensoryBuffer ←──── Auditory Stream                               │
│     ├── ContinuousSensoryBuffer ←──── System Telemetry                              │
│     └── Returns: SensorySnapshot                                                     │
│                                                                                      │
│  2. ATTEND()                                                                         │
│     ├── SensorySnapshot → SalienceScorer                                            │
│     ├── NoveltyDetector                                                              │
│     └── Returns: AttendedPercept (bounded compute)                                  │
│                                                                                      │
│  3. UPDATE_WORLD_MODEL()                                                             │
│     ├── AttendedPercept → WorldModel.predict_next()                                 │
│     ├── CounterfactualGenerator                                                     │
│     └── Returns: UpdatedWorldState, RiskPrediction                                   │
│                                                                                      │
│  4. GENERATE_GOALS()                                                                 │
│     ├── WorldState → AutonomousGoalGenerator                                        │
│     ├── CuriosityRewardComputer                                                     │
│     └── Kernel.approve(new_goals) ← CRITICAL SOVEREIGNTY CHECK                      │
│                                                                                      │
│  5. INFER_ACTIONS()                                                                  │
│     ├── AttendedPercept + Goals + Emotions → ITHERIS.infer()                        │
│     ├── BrainOutput (advisory)                                                       │
│     └── Returns: BrainOutput                                                         │
│                                                                                      │
│  6. KERNEL_APPROVAL()                                                                │
│     ├── BrainOutput.proposed_actions → Kernel.approve()                              │
│     ├── Kernel evaluates: risk, energy, confidence, goal alignment                 │
│     └── Returns: Decision {APPROVED, DENIED, STOPPED}                               │
│                                                                                      │
│  7. EXECUTE()                                                                        │
│     ├── If APPROVED: Execute action via CapabilityRegistry                           │
│     ├── Observe outcome                                                             │
│     └── Returns: ExecutionResult                                                     │
│                                                                                      │
│  8. REFLECT()                                                                        │
│     ├── ExecutionResult → ReflectionEngine                                          │
│     ├── Update SelfModel (confidence, energy)                                       │
│     ├── Update GoalState                                                             │
│     └── Returns: ReflectionEvent                                                     │
│                                                                                      │
│  9. LEARN()                                                                          │
│     ├── ReflectionEvent → ExperienceReplayBuffer                                     │
│     ├── ITHERIS.learn!() (sandboxed, reversible)                                    │
│     └── MetaLearning.update()                                                       │
│                                                                                      │
│  10. SLEEP_IF_NEEDED()                                                               │
│      ├── Check: cycle_count % sleep_threshold == 0                                  │
│      ├── sleep_cycle!():                                                             │
│      │    ├── consolidate_memory!(): Episodic → Semantic                            │
│      │    └── dream!(): Counterfactual exploration                                  │
│      └── Returns: UpdatedMemory                                                     │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## 1.3 Data Flow Description

| Stage | Input | Processing | Output | Destination |
|-------|-------|------------|--------|-------------|
| **Sensory** | Raw streams | Event-based buffering, backpressure | `SensorySnapshot` | Attention |
| **Attention** | `SensorySnapshot` | Salience scoring, novelty detection | `AttendedPercept` | World Model, Brain |
| **World Model** | `AttendedPercept` | State prediction, risk estimation | `PredictedState` | Goal System, Brain |
| **Goal System** | `PredictedState` | Goal activation/abandonment | `ActiveGoals` | Brain |
| **Brain Inference** | `AttendedPercept` + `Goals` + `Emotions` | Neural forward pass | `BrainOutput` (advisory) | Kernel |
| **Kernel Approval** | `BrainOutput` | Sovereignty checks | `Decision` | Execution or Rejection |
| **Execution** | `Decision=APPROVED` | Capability invocation | `ExecutionResult` | Reflection |
| **Reflection** | `ExecutionResult` | Self-model update | `ReflectionEvent` | Learning |
| **Learning** | `ReflectionEvent` | Gradient updates (sandboxed) | Model weights | Brain |
| **Sleep** | Cycle count | Consolidation, dreaming | Updated memory | Memory |

---

# 2. IMPLEMENTATION PLANS FOR EACH COMPONENT

## Component 1: ACTUAL NEURAL NETWORK INTEGRATION (ITHERIS Core)

### A. Architectural Role

The ITHERIS Core replaces the placeholder `_neural_inference` in `Brain.jl`. It provides the neural decision-making substrate with value estimation, policy selection, and world prediction. The core maintains the brain-kernel boundary: outputs are advisory `BrainOutput` structs that must pass through `Kernel.approve()`.

### B. New Julia Struct Definitions

```julia
# brain/Brain.jl - ADD these structures

"""
    BrainState - Internal mutable state for JarvisBrain
    Exists separately from BrainInput/BrainOutput to enforce boundary contracts
"""
mutable struct BrainState
    belief_state::Vector{Float32}          # Current belief (12D)
    context_state::Vector{Float32}          # Recurrent context (hidden_size)
    last_hidden::Vector{Float32}            # Last layer hidden state
    attention_weights::Vector{Float32}     # Salience distribution
    reward_trace::Vector{Float32}          # Last N rewards for temporal learning
    cycle_count::Int                       
    
    function BrainState(input_size::Int=12, hidden_size::Int=128)
        new(
            zeros(Float32, input_size),
            zeros(Float32, hidden_size),
            zeros(Float32, hidden_size),
            ones(Float32, hidden_size) ./ hidden_size,
            Float32[],
            0
        )
    end
end

"""
    BrainInput - Immutable input snapshot to brain (COPY, never reference)
    
INVARIANTS:
- All fields are immutable after construction
- Kernel owns the original state; brain receives a copy
"""
struct BrainInput
    perception_vector::Vector{Float32}        # 12D normalized perception
    goal_context::Vector{Float32}             # Goal embedding (8D)
    recent_rewards::Vector{Float32}           # Last N reward signals (10D)
    time_budget_ms::Float32                  # Available thinking time
    emotional_state::AffectiveState           # Emotional context
    
    function BrainInput(
        perception::Vector{Float32};
        goal_context::Vector{Float32}=zeros(Float32, 8),
        recent_rewards::Vector{Float32}=zeros(Float32, 10),
        time_budget_ms::Float32=100.0f0,
        emotional_state::AffectiveState=AffectiveState()
    )
        @assert length(perception) == 12 "Perception must be 12D"
        new(copy(perception), copy(goal_context), copy(recent_rewards), time_budget_ms, emotional_state)
    end
end

"""
    BrainOutput - Advisory output from brain (NOT executable)
    
INVARIANTS:
1. BrainOutput is ALWAYS advisory - kernel maintains sovereignty
2. Brain must produce confidence score in [0, 1]
3. Brain must produce uncertainty estimate for meta-cognition
4. Brain cannot access kernel state directly - receives copy only
"""
struct BrainOutput
    proposed_actions::Vector{String}          # Ranked action candidates
    confidence::Float32                       # [0, 1] confidence in proposal
    value_estimate::Float32                  # Expected cumulative reward
    uncertainty::Float32                      # Epistemic uncertainty [0, 1]
    reasoning::String                         # Natural language explanation
    latent_features::Vector{Float32}          # For memory embedding (32D)
    emotional_modulation::Vector{Float32}    # How emotions affected this decision
    timestamp::DateTime
    
    function BrainOutput(
        actions::Vector{String};
        confidence::Float32,
        value_estimate::Float32,
        uncertainty::Float32,
        reasoning::String="",
        latent_features::Vector{Float32}=zeros(Float32, 32),
        emotional_modulation::Vector{Float32}=zeros(Float32, 5)
    )
        @assert 0f0 <= confidence <= 1f0 "Confidence must be in [0, 1]"
        @assert 0f0 <= uncertainty <= 1f0 "Uncertainty must be in [0, 1]"
        @assert length(emotional_modulation) == 5 "Must have 5 emotion dimensions"
        new(actions, confidence, value_estimate, uncertainty, reasoning, 
            latent_features, emotional_modulation, now())
    end
end
```

### C. Function Signatures

```julia
# Core inference functions - brain/Brain.jl

"""
    infer(brain::JarvisBrain, input::BrainInput)::BrainOutput
    
Performs neural inference through ITHERIS Core.
Returns advisory BrainOutput - kernel must approve before execution.
"""
function infer(brain::JarvisBrain, input::BrainInput)::BrainOutput

"""
    update!(brain::JarvisBrain, experience::Experience)::Bool
    
Updates brain weights using experience replay.
CRITICAL: Runs in sandboxed environment with rollback capability.
"""
function update!(brain::JarvisBrain, experience::Experience)::Bool

"""
    estimate_value(brain::JarvisBrain, state::Vector{Float32})::Float32
    
Returns value estimate for given state (for world model integration).
Pure function - no side effects.
"""
function estimate_value(brain::JarvisBrain, state::Vector{Float32})::Float32

"""
    get_deterministic_output(brain::JarvisBrain, input::BrainInput)::BrainOutput
    
Returns deterministic fallback output when neural inference unavailable.
Uses heuristic mapping from perception to actions.
"""
function get_deterministic_output(brain::JarvisBrain, input::BrainInput)::BrainOutput
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| ITHERIS Core | `itheris.jl` | Import `BrainCore`, `infer()`, `learn!()` |
| Kernel | `adaptive-kernel/kernel/Kernel.jl` | Output to `Kernel.approve()` |
| BrainTrainer | `jarvis/src/brain/BrainTrainer.jl` | Uses `train_brain!()` |
| Experience Buffer | `adaptive-kernel/brain/Brain.jl` | Already exists as `ExperienceReplayBuffer` |

### E. Data Flow Description

1. **Input Reception**: `BrainInput` is constructed from kernel's world state copy
2. **Encoding**: Perception vector is normalized to 12D, goals embedded to 8D
3. **Neural Forward Pass**:
   - Belief update: `belief = inertia * belief + (1-inertia) * perception`
   - Recurrence: `[perception_error; context] → hidden layers`
   - Attention: `hidden * attention_weights`
   - Value: `value_net(hidden)` → scalar
   - Policy: `policy_net(hidden)` → action logits → softmax → action selection
4. **Output Construction**: Results packaged as `BrainOutput` with confidence, uncertainty
5. **Delivery**: `BrainOutput` sent to kernel for approval

### F. Learning Strategy

- **Algorithm**: Actor-Critic with Entropy Regularization (A2C)
- **Experience Replay**: Prioritized replay buffer (capacity: 10,000)
- **Gradient Updates**: Batch size 32, learning rate 0.001, gamma 0.95
- **Sandboxing**: All updates happen in copy of brain, validated before commit
- **Rollback**: Checkpoint before each update; revert on validation failure

### G. Safety Constraints

- **Confidence Floor**: Outputs with confidence < 0.1 automatically denied by kernel
- **Uncertainty Cap**: Uncertainty > 0.8 triggers kernel caution mode
- **No Direct Execution**: BrainOutput is advisory; kernel holds execution sovereignty
- **Deterministic Fallback**: If neural inference fails, heuristic fallback with explicit reasoning

### H. Performance Considerations

- **Latency Target**: < 100ms inference on CPU
- **Memory**: ~50MB for brain weights (hidden_size=128)
- **Batch Processing**: Can batch multiple inferences for throughput
- **Deterministic Mode**: For debugging, seed random number generator

### I. Minimal Code Skeleton

```julia
# adaptive-kernel/brain/ITHERISIntegration.jl - NEW FILE

module ITHERISIntegration

using Flux
using Dates
using UUIDs

export 
    JarvisBrain,
    BrainInput,
    BrainOutput,
    BrainState,
    infer,
    update!,
    estimate_value,
    create_brain

# Import ITHERIS core
include("../../itheris.jl")
using ..ITHERISCore

# Import existing brain structures
include("Brain.jl")
using ..Brain

"""
    _neural_inference - Bridge ITHERIS to JarvisBrain
"""
function _neural_inference(brain::JarvisBrain, input::BrainInput)::BrainOutput
    # Convert BrainInput to ITHERIS perception dict
    perception_dict = Dict{String, Any}(
        "cpu_load" => Float64(input.perception_vector[1]),
        "memory_usage" => Float64(input.perception_vector[2]),
        "disk_io" => Float64(input.perception_vector[3]),
        "network_latency" => Float64(input.perception_vector[4]) * 200.0,
        "overall_severity" => Float64(input.perception_vector[5]),
        "threats" => Int(input.perception_vector[6] * 10),
        "file_count" => Int(input.perception_vector[7] * 10000),
        "process_count" => Int(input.perception_vector[8] * 500),
        "energy_level" => Float64(input.emotional_state.energy),
        "confidence" => Float64(input.emotional_state.arousal),
        "system_uptime_hours" => Float64(input.perception_vector[11] * 168),
        "user_activity_level" => Float64(input.perception_vector[12])
    )
    
    # Run ITHERIS inference
    if brain.brain_core === nothing
        # Initialize if needed
        brain.brain_core = initialize_brain(
            input_size=12,
            hidden_size=128,
            learning_rate=0.001f0,
            gamma=0.95f0
        )
    end
    
    thought = infer(brain.brain_core, perception_dict)
    
    # Map ITHERIS actions to capability IDs
    action_map = ["log_status", "observe_cpu", "observe_memory", 
                  "observe_filesystem", "analyze_logs", "safe_shell"]
    
    selected_actions = action_map[min(thought.action, length(action_map))]
    
    # Apply emotional modulation (documented but not overriding)
    emotional_impact = compute_emotional_modulation(input.emotional_state)
    
    return BrainOutput(
        [selected_actions];
        confidence=1f0 - thought.uncertainty,
        value_estimate=thought.value,
        uncertainty=thought.uncertainty,
        reasoning="ITHERIS neural inference with $(round(thought.uncertainty, digits=2)) uncertainty",
        latent_features=thought.context_vector,
        emotional_modulation=emotional_impact
    )
end

function compute_emotional_modulation(emotion::AffectiveState)::Vector{Float32}
    return Float32[emotion.valence, emotion.arousal, emotion.fear, emotion.curiosity, emotion.frustration]
end

end # module
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Boundary Contract** | Pass `BrainInput`, verify no kernel state access | Output is advisory only |
| **Confidence Bounds** | Run 100 inferences | All confidence in [0, 1] |
| **Uncertainty Bounds** | Run 100 inferences | All uncertainty in [0, 1] |
| **Deterministic Fallback** | Disable neural, verify heuristic output | Output has explicit reasoning |
| **Experience Replay** | Add 1000 experiences, sample batch | Batch size matches request |
| **Rollback** | Corrupt weights, verify restoration | Weights match checkpoint |

---

## Component 2: CONTINUOUS SENSORY PROCESSING

### A. Architectural Role

Processes continuous sensory streams (visual, auditory, system telemetry) into bounded, event-driven perception batches. Implements backpressure handling and attention gating to prevent sensory overload from reaching the brain.

### B. New Julia Struct Definitions

```julia
# cognition/sensory/SensoryBuffer.jl - NEW FILE

module SensoryBuffer

using Dates
using UUIDs
using Base.Threads
using CircularBuffers

export 
    SensorySnapshot,
    SensoryBuffer,
    SensoryStream,
    StreamType,
    push_percept!,
    get_snapshot,
    create_sensory_buffer

"""
    StreamType - Classification of sensory input streams
"""
@enum StreamType VISUAL AUDIO SYSTEM_TELEMETRY TEXT INPUT

"""
    SensoryStream - Individual sensory channel
"""
struct SensoryStream
    stream_type::StreamType
    data_buffer::CircularBuffer{Float32}  # Ring buffer for streaming data
    last_update::DateTime
    sample_count::Int
    error_count::Int
    
    function SensoryStream(stream_type::StreamType, capacity::Int=1000)
        new(stream_type, CircularBuffer{Float32}(capacity), now(), 0, 0)
    end
end

"""
    SensorySnapshot - Bounded snapshot of sensory state at a point in time
"""
struct SensorySnapshot
    id::UUID
    timestamp::DateTime
    visual_features::Vector{Float32}      # [0-1] normalized visual salience
    audio_features::Vector{Float32}       # [0-1] normalized audio salience  
    system_telemetry::Vector{Float32}    # CPU, memory, disk, network (4D)
    text_input::Vector{Float32}           # Text embedding if user is typing (8D)
    novelty_score::Float32                # [0-1] how novel is this snapshot
    attention_weights::Vector{Float32}    # Where to focus (4D: visual, audio, system, text)
    cycle_count::Int
    
    function SensorySnapshot(
        visual::Vector{Float32}=zeros(Float32, 16),
        audio::Vector{Float32}=zeros(Float32, 16),
        system::Vector{Float32}=zeros(Float32, 4),
        text::Vector{Float32}=zeros(Float32, 8)
    )
        @assert length(visual) == 16 "Visual must be 16D"
        @assert length(audio) == 16 "Audio must be 16D" 
        @assert length(system) == 4 "System must be 4D"
        @assert length(text) == 8 "Text must be 8D"
        
        # Attention defaults to uniform
        attention = ones(Float32, 4) ./ 4f0
        
        new(uuid4(), now(), visual, audio, system, text, 0f0, attention, 0)
    end
end

"""
    SensoryBuffer - Manages multiple sensory streams with backpressure
"""
mutable struct SensoryBuffer
    streams::Dict{StreamType, SensoryStream}
    snapshot_buffer::CircularBuffer{SensorySnapshot}
    max_latency_ms::Float64              # Maximum processing latency threshold
    backpressure_threshold::Int           # Buffer size trigger for backpressure
    cycle_count::Threads.Atomic{Int}
    
    function SensoryBuffer(
        snapshot_capacity::Int=100,
        max_latency_ms::Float64=500.0,
        backpressure_threshold::Int=50
    )
        streams = Dict{StreamType, SensoryStream}(
            VISUAL => SensoryStream(VISUAL),
            AUDIO => SensoryStream(AUDIO),
            SYSTEM_TELEMETRY => SensoryStream(SYSTEM_TELEMETRY),
            TEXT => SensoryStream(TEXT)
        )
        
        new(
            streams,
            CircularBuffer{SensorySnapshot}(snapshot_capacity),
            max_latency_ms,
            backpressure_threshold,
            Threads.Atomic{Int}(0)
        )
    end
end

end # module
```

### C. Function Signatures

```julia
# Sensory processing functions

"""
    push_percept!(buffer::SensoryBuffer, stream_type::StreamType, data::Vector{Float32})::Bool

Push new percept to a sensory stream with backpressure handling.
Returns false if backpressure is triggered (caller should slow down).
"""
function push_percept!(buffer::SensoryBuffer, stream_type::StreamType, data::Vector{Float32})::Bool

"""
    get_snapshot(buffer::SensoryBuffer)::SensorySnapshot

Get current snapshot of all sensory streams, normalized and bounded.
Applies attention gating to produce focused percept.
"""
function get_snapshot(buffer::SensoryBuffer)::SensorySnapshot

"""
    apply_attention_gating(snapshot::SensorySnapshot)::SensorySnapshot

Modulates attention weights based on novelty and current goal context.
Bounded compute - O(1) complexity.
"""
function apply_attention_gating(snapshot::SensorySnapshot)::SensorySnapshot

"""
    handle_backpressure(buffer::SensoryBuffer)::Bool

Called when backpressure threshold exceeded.
Drops oldest samples to catch up.
"""
function handle_backpressure(buffer::SensoryBuffer)::Bool
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| Attention System | Component 5 | Output to `SalienceScorer` |
| World Model | Component 4 | Output to `WorldModel.update()` |
| System Telemetry | `adaptive-kernel/capabilities/` | Pulls from `observe_cpu`, etc. |

### E. Data Flow Description

1. **Ingestion**: Capabilities call `push_percept!()` with raw sensor data
2. **Buffering**: Data stored in `CircularBuffer` (fixed capacity, overwrites oldest)
3. **Snapshot Creation**: On each cognitive cycle, `get_snapshot()` creates unified view
4. **Normalization**: All streams normalized to [0, 1] range
5. **Attention Gating**: `apply_attention_gating()` computes where to focus
6. **Output**: `SensorySnapshot` passed to brain and world model

### F. Learning Strategy

- **Novelty Detection**: Track history variance; high variance = high novelty
- **Attention Learning**: Future: Learn attention weights from reward signal
- **Current**: Rule-based heuristics (goal-directed attention)

### G. Safety Constraints

- **Backpressure**: If buffer overflows, oldest data dropped, logged for audit
- **Latency Cap**: Snapshots older than `max_latency_ms` rejected
- **Bounded Compute**: Attention gating is O(1), cannot cause runaway computation
- **No Direct Execution**: Sensory data never triggers actions directly

### H. Performance Considerations

- **Lock-Free**: Uses `Threads.Atomic` for cycle count
- **Circular Buffers**: O(1) push/pop, bounded memory
- **Vectorized**: All normalization uses SIMD where possible

### I. Minimal Code Skeleton

```julia
# cognition/sensory/SensoryBuffer.jl

module SensoryBuffer

using CircularBuffers

export push_percept!, get_snapshot, SensoryBuffer

mutable struct SensoryBuffer
    visual::CircularBuffer{Float32}
    audio::CircularBuffer{Float32}
    system::CircularBuffer{Float32}
    text::CircularBuffer{Float32}
    max_size::Int
    
    SensoryBuffer(max_size::Int=1000) = new(
        CircularBuffer{Float32}(max_size),
        CircularBuffer{Float32}(max_size),
        CircularBuffer{Float32}(max_size),
        CircularBuffer{Float32}(max_size),
        max_size
    )
end

function push_percept!(buffer::SensoryBuffer, stream::Symbol, data::Vector{Float32})::Bool
    target = stream == :visual ? buffer.visual :
             stream == :audio ? buffer.audio :
             stream == :system ? buffer.system : buffer.text
    
    for val in data
        push!(target, val)
    end
    return length(target) < buffer.max_size  # false if backpressure
end

function get_snapshot(buffer::SensoryBuffer)::Vector{Float32}
    # Concatenate latest values from each stream (12D total)
    snapshot = Float32[]
    
    # Take last 4 values from each stream if available
    for stream in [buffer.visual, buffer.audio, buffer.system, buffer.text]
        if length(stream) >= 4
            append!(snapshot, last(4, collect(stream)))
        else
            append!(snapshot, zeros(Float32, 4))
        end
    end
    
    return snapshot[1:12]  # Ensure 12D
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Backpressure** | Push 2x capacity | Oldest values dropped, no error |
| **Snapshot Bounds** | Run 1000 cycles | All outputs 12D, in [0,1] |
| **Latency** | Time 1000 snapshots | P99 < 10ms |
| **Thread Safety** | Concurrent push from 4 threads | No race conditions |

---

## Component 3: AUTONOMOUS GOAL FORMATION

### A. Architectural Role

Generates, evaluates, activates, and abandons goals autonomously. Goals are immutable structs that must receive kernel approval before becoming active. Includes curiosity-driven intrinsic reward computation for exploratory behavior.

### B. New Julia Struct Definitions

```julia
# cognition/goals/GoalSystem.jl - NEW FILE

module GoalSystem

using Dates
using UUIDs
using Statistics

export 
    Goal,
    GoalGraph,
    GoalStatus,
    GoalPriority,
    AutonomousGoalGenerator,
    generate_goals!,
    evaluate_goal_activation,
    abandon_goal!,
    compute_curiosity_reward

"""
    GoalStatus - Runtime status of a goal
"""
@enum GoalStatus INACTIVE ACTIVE PAUSED COMPLETED FAILED ABANDONED

"""
    GoalPriority - Priority level with explicit bounds
"""
@enum GoalPriority CRITICAL HIGH MEDIUM LOW

"""
    Goal - Immutable goal definition (structural integrity)
    
INVARIANTS:
- Priority and target_state are IMMUTABLE after construction
- Use GoalRuntimeState for mutable tracking
"""
struct Goal
    id::UUID
    description::String
    target_state::Vector{Float32}       # Desired world state (12D)
    priority::Float32                   # [0, 1] - IMMUTABLE
    priority_level::GoalPriority        # Categorical - IMMUTABLE
    deadline::DateTime                  # Soft deadline
    created_at::DateTime
    parent_goal_id::Union{UUID, Nothing}  # For hierarchical goals
    required_capabilities::Vector{String}  # Capabilities needed to achieve
end

"""
    GoalRuntimeState - Mutable runtime tracking for Goal
"""
mutable struct GoalRuntimeState
    goal_id::UUID
    status::GoalStatus
    progress::Float32           # [0, 1] completion
    iterations::Int             # Times attempted
    last_attempt::DateTime
    intrinsic_reward::Float32   # Curiosity reward accumulated
    activation_count::Int       # Times activated
    
    function GoalRuntimeState(goal_id::UUID)
        new(goal_id, INACTIVE, 0f0, 0, now(), 0f0, 0)
    end
end

"""
    GoalGraph - Hierarchical structure of goals
"""
mutable struct GoalGraph
    goals::Dict{UUID, Goal}
    runtime_states::Dict{UUID, GoalRuntimeState}
    active_goal_ids::Vector{UUID}
    root_goal_ids::Vector{UUID}
    activation_threshold::Float32
    
    function GoalGraph(activation_threshold::Float32=0.3f0)
        new(
            Dict{UUID, Goal}(),
            Dict{UUID, GoalRuntimeState}(),
            UUID[],
            UUID[],
            activation_threshold
        )
    end
end

"""
    AutonomousGoalGenerator - Generates new goals based on world state and curiosity
"""
mutable struct AutonomousGoalGenerator
    graph::GoalGraph
    curiosity_strength::Float32      # How strongly to explore
    goal_horizon::Int                # How many steps to look ahead
    max_active_goals::Int            # Maximum concurrent goals
    min_novelty_for_new_goal::Float32
    
    function AutonomousGoalGenerator(
        curiosity_strength::Float32=0.5f0,
        goal_horizon::Int=5,
        max_active_goals::Int=3
    )
        new(
            GoalGraph(),
            curiosity_strength,
            goal_horizon,
            max_active_goals,
            0.4f0
        )
    end
end

end # module
```

### C. Function Signatures

```julia
# Goal system functions

"""
    generate_goals!(gen::AutonomousGoalGenerator, world_state::Vector{Float32}, 
                   novelty::Float32)::Vector{Goal}

Generates new goals based on world state and curiosity.
CRITICAL: New goals must be approved by kernel before activation.
"""
function generate_goals!(gen::AutonomousGoalGenerator, world_state::Vector{Float32}, 
                        novelty::Float32)::Vector{Goal}

"""
    evaluate_goal_activation(gen::AutonomousGoalGenerator, goal::Goal, 
                            world_state::Vector{Float32})::Float32

Computes activation score for a goal.
Returns value in [0, 1]. Goals with score > activation_threshold become active.
"""
function evaluate_goal_activation(gen::AutonomousGoalGenerator, goal::Goal, 
                                 world_state::Vector{Float32})::Float32

"""
    compute_curiosity_reward(goal::Goal, world_state::Vector{Float32})::Float32

Computes intrinsic curiosity reward for exploring a goal.
Higher reward for states far from current belief (novelty-seeking).
"""
function compute_curiosity_reward(goal::Goal, world_state::Vector{Float32})::Float32

"""
    abandon_goal!(gen::AutonomousGoalGenerator, goal_id::UUID, reason::String)::Bool

Marks goal as abandoned. Logs reason for audit.
Returns true if successful.
"""
function abandon_goal!(gen::AutonomousGoalGenerator, goal_id::UUID, reason::String)::Bool

"""
    kernel_approve_goal(kernel::KernelState, goal::Goal)::Decision

Kernel sovereignty: evaluates if new goal should be allowed.
Similar to approve() for actions but for goal creation.
"""
function kernel_approve_goal(kernel::KernelState, goal::Goal)::Decision
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| Kernel | `adaptive-kernel/kernel/Kernel.jl` | `kernel_approve_goal()` |
| World Model | Component 4 | Uses predicted state for goal evaluation |
| Brain | Component 1 | Goals passed as `goal_context` in `BrainInput` |

### E. Data Flow Description

1. **Generation**: `generate_goals!()` examines world state, computes novelty, proposes goals
2. **Curiosity**: `compute_curiosity_reward()` adds intrinsic reward for exploration
3. **Evaluation**: `evaluate_goal_activation()` scores each goal
4. **Kernel Approval**: New goals sent to kernel (same approval function as actions)
5. **Activation**: Approved goals added to active list
6. **Tracking**: Progress updated via `GoalRuntimeState`
7. **Abandonment**: Failed goals marked abandoned after threshold iterations

### F. Learning Strategy

- **Curiosity-Driven**: Goals that lead to novel states earn intrinsic reward
- **Progress-Based**: Goals with higher progress get priority boost
- **Abandonment Learning**: Track abandoned goals; avoid similar goals in future

### G. Safety Constraints

- **Kernel Approval Required**: No autonomous goal activation without kernel approval
- **Maximum Active Goals**: Configurable cap prevents goal explosion
- **Required Capabilities**: Goals must have at least one available capability
- **Deadline Enforcement**: Soft deadlines trigger re-evaluation

### H. Performance Considerations

- **O(n) Evaluation**: Linear in number of goals
- **Bounded Graph**: Maximum goals configurable, oldest dropped first

### I. Minimal Code Skeleton

```julia
# cognition/goals/GoalSystem.jl

module GoalSystem

using UUIDs
using Statistics

export Goal, GoalStatus, AutonomousGoalGenerator, generate_goals!

@enum GoalStatus INACTIVE ACTIVE PAUSED COMPLETED FAILED ABANDONED

struct Goal
    id::UUID
    description::String
    target_state::Vector{Float32}
    priority::Float32
    status::GoalStatus
    created_at::DateTime
    
    Goal(desc::String, target::Vector{Float32}, priority::Float32) = new(
        uuid4(), desc, target, priority, INACTIVE, now()
    )
end

mutable struct AutonomousGoalGenerator
    goals::Vector{Goal}
    curiosity_strength::Float32
    max_active::Int
    
    AutonomousGoalGenerator(curiosity::Float32=0.5, max_active::Int=3) = new(
        Goal[], curiosity, max_active
    )
end

function generate_goals!(gen::AutonomousGoalGenerator, world_state::Vector{Float32}, 
                        novelty::Float32)::Vector{Goal}
    new_goals = Goal[]
    
    # Generate goal if novelty is high enough
    if novelty > gen.curiosity_strength
        # Example: create exploration goal toward novel region
        target = world_state + rand(Float32, length(world_state)) * 0.3f0
        target = clamp.(target, 0f0, 1f0)
        
        push!(new_goals, Goal(
            "Explore novel state",
            target,
            novelty * gen.curiosity_strength
        ))
    end
    
    return new_goals
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Goal Creation** | Generate goals with varying novelty | Goals have valid UUID, priority in [0,1] |
| **Kernel Approval** | Pass goals to kernel.approve() | Returns APPROVED/DENIED |
| **Abandonment** | Run 100 failed iterations | Goal marked ABANDONED |
| **Curiosity** | Vary novelty, measure reward | Higher novelty → higher reward |

---

## Component 4: PREDICTIVE WORLD MODEL

### A. Architectural Role

Maintains internal model of world state dynamics. Predicts next state given current state and action. Computes risk predictions for kernel evaluation. Enables counterfactual simulation for planning.

### B. New Julia Struct Definitions

```julia
# cognition/worldmodel/WorldModel.jl - NEW FILE

module WorldModel

using LinearAlgebra
using Statistics

export 
    WorldModel,
    WorldState,
    PredictedState,
    predict_next_state,
    compute_risk_prediction,
    simulate_counterfactual

"""
    WorldState - Current state representation (12D)
"""
struct WorldState
    features::Vector{Float32}           # 12D state features
    timestamp::DateTime
    uncertainty::Float32               # Epistemic uncertainty [0, 1]
    
    WorldState(features::Vector{Float32}) = new(copy(features), now(), 0f0)
end

"""
    PredictedState - Predicted future state with confidence
"""
struct PredictedState
    state::WorldState
    confidence::Float32                 # How confident in prediction
    risk_estimate::Float32              # Predicted risk level [0, 1]
    causal_chain::Vector{String}        # Explanation of prediction
    
    PredictedState(state::WorldState) = new(state, 1f0, 0f0, String[])
end

"""
    WorldModel - Predictive model of environment dynamics
"""
mutable struct WorldModel
    transition_matrix::Matrix{Float32}    # Learned state transitions
    confidence_model::Vector{Float32}      # Confidence per dimension
    risk_weights::Vector{Float32}          # Weights for risk prediction
    learning_rate::Float32
    forget_factor::Float32                 # For online adaptation
    
    function WorldModel(state_dim::Int=12; learning_rate::Float32=0.01f0)
        # Initialize with identity + small noise (no prior)
        trans = Matrix{Float32}(I, state_dim, state_dim) * 0.9f0
        trans += rand(Float32, state_dim, state_dim) * 0.1f0
        
        new(
            trans,
            ones(Float32, state_dim),      # High confidence initially
            ones(Float32, state_dim) .* 0.5f0,  # Neutral risk weights
            learning_rate,
            0.95f0                         # Forget old data gradually
        )
    end
end

end # module
```

### C. Function Signatures

```julia
# World model functions

"""
    predict_next_state(model::WorldModel, current_state::WorldState, 
                      action::String)::PredictedState

Predicts next world state given current state and action.
Uses transition matrix multiplication with action embedding.
"""
function predict_next_state(model::WorldModel, current_state::WorldState, 
                           action::String)::PredictedState

"""
    compute_risk_prediction(model::WorldModel, predicted_state::PredictedState)::Float32

Computes risk level for predicted state.
Combines state uncertainty with domain-specific risk weights.
"""
function compute_risk_prediction(model::WorldModel, predicted_state::PredictedState)::Float32

"""
    simulate_counterfactual(model::WorldModel, current_state::WorldState,
                           action_sequence::Vector{String})::Vector{PredictedState}

Simulates multiple steps ahead for planning.
Returns chain of predicted states.
"""
function simulate_counterfactual(model::WorldModel, current_state::WorldState,
                                action_sequence::Vector{String})::Vector{PredictedState}

"""
    update!(model::WorldModel, actual_state::WorldState, predicted_state::PredictedState)

Updates transition matrix based on prediction error.
Uses online learning with forget factor.
"""
function update!(model::WorldModel, actual_state::WorldState, predicted_state::PredictedState)
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| Kernel | `adaptive-kernel/kernel/Kernel.jl` | Provides `risk_estimate` for approval |
| Brain | Component 1 | Uses predictions for value estimation |
| Goal System | Component 3 | Uses predicted states for goal evaluation |

### E. Data Flow Description

1. **Input**: Current `WorldState` + proposed action
2. **Prediction**: `predict_next_state()` applies transition matrix
3. **Risk**: `compute_risk_prediction()` evaluates danger level
4. **Counterfactual**: `simulate_counterfactual()` runs multi-step simulation
5. **Update**: After execution, `update()` corrects transition matrix

### F. Learning Strategy

- **Online Adaptation**: Updates after each action-outcome pair
- **Forget Factor**: Prioritizes recent experience (0.95 decay)
- **Confidence Tracking**: Reduces confidence when predictions fail

### G. Safety Constraints

- **Uncertainty Bounds**: Risk capped at 1.0
- **Prediction Clamping**: All predictions clamped to [0, 1] range
- **Kernel Integration**: Risk prediction passed to kernel for approval

### H. Performance Considerations

- **O(n²) Prediction**: Matrix multiply O(d²) for state dimension d
- **O(n) Update**: Simple delta update

### I. Minimal Code Skeleton

```julia
# cognition/worldmodel/WorldModel.jl

module WorldModel

export WorldModel, predict_next_state, compute_risk_prediction

mutable struct WorldModel
    transition::Matrix{Float32}
    risk_weights::Vector{Float32}
    
    WorldModel(dim::Int=12) = new(
        Matrix{Float32}(I, dim, dim) * 0.9f0,
        ones(Float32, dim) * 0.5f0
    )
end

function predict_next_state(model::WorldModel, state::Vector{Float32}, 
                            action::String)::Vector{Float32}
    # Simple linear prediction with action bias
    action_bias = hash(action) % 100 / 1000f0
    
    predicted = model.transition * state
    predicted .+= action_bias
    return clamp.(predicted, 0f0, 1f0)
end

function compute_risk_prediction(model::WorldModel, state::Vector{Float32})::Float32
    # Risk = weighted sum of concerning state features
    risk = sum(state .* model.risk_weights) / sum(model.risk_weights)
    return clamp(risk, 0f0, 1f0)
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Prediction Bounds** | Predict 1000 states | All outputs in [0, 1] |
| **Risk Bounds** | Compute risk for random states | All risks in [0, 1] |
| **Learning** | Update with known transition | Error decreases over time |
| **Counterfactual** | Simulate 5 steps | Returns 5 predicted states |

---

## Component 5: ATTENTION & SALIENCE SYSTEM

### A. Architectural Role

Computes salience scores across sensory inputs to focus processing on relevant information. Implements novelty detection to identify unexpected stimuli. Bounded compute allocation prevents attention explosion.

### B. New Julia Struct Definitions

```julia
# cognition/attention/Attention.jl - NEW FILE

module Attention

using Statistics
using LinearAlgebra

export 
    SalienceScorer,
    SalienceScore,
    compute_salience,
    detect_novelty,
    allocate_attention

"""
    SalienceScore - Computed salience for a perceptual channel
"""
struct SalienceScore
    channel::Symbol                     # :visual, :audio, :system, :text
    score::Float32                      # [0, 1] salience
    novelty::Float32                     # [0, 1] how novel
    confidence::Float32                 # [0, 1] confidence in score
    
    SalienceScore(ch::Symbol, s::Float32, n::Float32=0f0, c::Float32=1f0) = new(ch, s, n, c)
end

"""
    SalienceScorer - Computes attention allocation
"""
mutable struct SalienceScorer
    channel_weights::Dict{Symbol, Float32}   # Learned channel importance
    history::Vector{Vector{Float32}}         # Recent salience history
    novelty_baseline::Vector{Float32}        # Baseline for novelty detection
    max_history::Int
    
    function SalienceScorer()
        new(
            Dict{Symbol, Float32}(:visual=>0.25, :audio=>0.25, :system=>0.25, :text=>0.25),
            Vector{Float32}[],
            Float32[0.5, 0.5, 0.5, 0.5],
            100
        )
    end
end

end # module
```

### C. Function Signatures

```julia
# Attention functions

"""
    compute_salience(scorer::SalienceScorer, sensory_snapshot::Vector{Float32})::Vector{SalienceScore}

Computes salience for each channel in sensory snapshot.
Bounded compute: O(1) per channel.
"""
function compute_salience(scorer::SalienceScorer, sensory_snapshot::Vector{Float32})::Vector{SalienceScore}

"""
    detect_novelty(scorer::SalienceScorer, current::Vector{Float32})::Float32

Detects novelty by comparing current snapshot to history.
Returns [0, 1] novelty score.
"""
function detect_novelty(scorer::SalienceScorer, current::Vector{Float32})::Float32

"""
    allocate_attention(saliences::Vector{SalienceScore])::Vector{Float32}

Allocates attention proportionally to salience.
Returns weights that sum to 1.0.
"""
function allocate_attention(saliences::Vector{SalienceScore})::Vector{Float32}
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| Sensory Buffer | Component 2 | Receives `SensorySnapshot` |
| Brain | Component 1 | Attention weights passed to brain |
| World Model | Component 4 | Uses attention to focus predictions |

### E. Data Flow Description

1. **Input**: `SensorySnapshot` from buffer
2. **Salience**: `compute_salience()` scores each channel
3. **Novelty**: `detect_novelty()` compares to history
4. **Allocation**: `allocate_attention()` produces weights
5. **Output**: Weighted percept passed to brain

### F. Learning Strategy

- **Channel Weights**: Learn from reward signal (explore vs exploit)
- **Novelty Baseline**: Adaptive exponential moving average

### G. Safety Constraints

- **Bounded Weights**: Attention sums to 1.0
- **No Bypass**: Attention always applied, cannot be skipped

### H. Performance Considerations

- **O(1) per Channel**: Simple dot products
- **Fixed History**: Bounded memory usage

### I. Minimal Code Skeleton

```julia
# cognition/attention/Attention.jl

module Attention

export SalienceScorer, compute_salience, detect_novelty

mutable struct SalienceScorer
    history::Vector{Vector{Float32}}
    
    SalienceScorer() = new(Vector{Float32}[])
end

function compute_salience(scorer::SalienceScorer, snapshot::Vector{Float32})::Vector{Float32}
    # Simple variance-based salience
    saliences = Float32[]
    
    # Divide snapshot into 4 channels (12D / 4 = 3D each)
    for ch in 1:4
        channel_data = snapshot[(ch-1)*3+1:ch*3]
        # Higher variance = higher salience
        push!(saliences, var(channel_data) + 0.1f0)
    end
    
    # Normalize to sum to 1
    total = sum(saliences)
    return total > 0 ? saliences ./ total : ones(Float32, 4) ./ 4f0
end

function detect_novelty(scorer::SalienceScorer, current::Vector{Float32})::Float32
    if isempty(scorer.history)
        return 0.5f0  # Default moderate novelty
    end
    
    # Compare to most recent history
    last = scorer.history[end]
    distance = norm(current - last)
    
    return clamp(distance / 2f0, 0f0, 1f0)
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Weight Bounds** | Compute 100 allocations | All weights in [0, 1], sum = 1 |
| **Novelty** | Repeat same input | Novelty decreases |
| **Bounded Compute** | Time 10000 iterations | < 1ms per iteration |

---

## Component 6: SLEEP / DREAM / CONSOLIDATION

### A. Architectural Role

Implements sleep cycle for memory consolidation. Converts episodic memories to semantic knowledge. Uses dream-based counterfactual exploration for offline learning.

### B. New Julia Struct Definitions

```julia
# cognition/sleep/SleepSystem.jl - NEW FILE

module SleepSystem

using Dates
using Statistics

export 
    SleepState,
    SleepCycle,
    sleep_cycle!,
    consolidate_memory!,
    dream!

"""
    SleepState - Current state of sleep system
"""
@enum SleepState AWAKE LIGHT_SLEEP DEEP_SLEEP REM

"""
    SleepCycle - Manages sleep phases
"""
mutable struct SleepCycle
    state::SleepState
    cycle_count::Int
    total_cycles::Int
    last_sleep::DateTime
    sleep_threshold::Int              # Cycles before sleep triggered
    consolidation_rate::Float32       # How fast to consolidate
    
    function SleepCycle(sleep_threshold::Int=1000)
        new(AWAKE, 0, 0, now(), sleep_threshold, 0.1f0)
    end
end

end # module
```

### C. Function Signatures

```julia
# Sleep system functions

"""
    sleep_cycle!(cycle::SleepCycle, episodic_memory::Vector{ReflectionEvent})::Bool

Main sleep entry point. Returns true if sleep occurred.
"""
function sleep_cycle!(cycle::SleepCycle, episodic_memory::Vector{ReflectionEvent})::Bool

"""
    consolidate_memory!(cycle::SleepCycle, episodic::Vector{ReflectionEvent})::Vector{SemanticKnowledge}

Converts episodic memories to semantic knowledge.
Returns vector of consolidated facts.
"""
function consolidate_memory!(cycle::SleepCycle, episodic::Vector{ReflectionEvent})::Vector{SemanticKnowledge}

"""
    dream!(cycle::SleepCycle, semantic_knowledge::Vector{SemanticKnowledge})::Vector{Experience}

Generates counterfactual experiences from semantic knowledge.
Returns synthetic experiences for offline learning.
"""
function dream!(cycle::SleepCycle, semantic_knowledge::Vector{SemanticKnowledge})::Vector{Experience}
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| Kernel | `adaptive-kernel/kernel/Kernel.jl` | Reads `cycle_count` |
| Brain | Component 1 | Dreams provide experiences for learning |
| Memory | `adaptive-kernel/memory/Memory.jl` | Consolidates to semantic memory |

### E. Data Flow Description

1. **Trigger**: Every `sleep_threshold` cycles, initiate sleep
2. **Phases**: LIGHT_SLEEP → DEEP_SLEEP → REM → AWAKE
3. **Consolidation**: During deep sleep, convert episodic → semantic
4. **Dreaming**: During REM, generate counterfactuals
5. **Learning**: Dream experiences added to replay buffer

### F. Learning Strategy

- **Offline RL**: Dream experiences used for value function updates
- **Generalization**: Semantic knowledge abstracts across episodes

### G. Safety Constraints

- **Non-Blocking**: Sleep triggered between cognitive cycles
- **Checkpoint Before**: Save state before sleep begins

### H. Performance Considerations

- **Deferred**: Runs in background, doesn't block perception

### I. Minimal Code Skeleton

```julia
# cognition/sleep/SleepSystem.jl

module SleepSystem

export SleepCycle, sleep_cycle!

@enum SleepState AWAKE LIGHT_SLEEP DEEP_SLEEP REM

mutable struct SleepCycle
    state::SleepState
    cycle_count::Int
    sleep_threshold::Int
    
    SleepCycle(threshold::Int=1000) = new(AWAKE, 0, threshold)
end

function sleep_cycle!(cycle::SleepCycle, memory::Vector)::Bool
    cycle.cycle_count += 1
    
    if cycle.cycle_count >= cycle.sleep_threshold
        # Simple single-phase sleep
        cycle.state = DEEP_SLEEP
        
        # Simulate consolidation work
        # (In practice: convert episodic → semantic)
        
        cycle.state = AWAKE
        cycle.cycle_count = 0
        return true
    end
    
    return false
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Trigger** | Run 1000+ cycles | Sleep triggered |
| **Wake** | After sleep | State returns to AWAKE |
| **Memory** | Consolidate | Semantic output produced |

---

## Component 7: EMOTIONAL ARCHITECTURE

### A. Architectural Role

Extends `PainFeedback` into full `AffectiveState`. Emotions modulate value signals in brain inference but CANNOT override kernel safety decisions. Provides affective coloring to perception without compromising sovereignty.

### B. New Julia Struct Definitions

```julia
# cognition/emotion/Affective.jl - NEW FILE

module Affective

using Statistics

export 
    AffectiveState,
    Emotion,
    update_emotions!,
    compute_emotional_modulation,
    EMOTION_BOUND

"""
    Emotion - Discrete emotion with intensity
"""
struct Emotion
    name::Symbol                # :fear, :joy, :curiosity, :frustration, :satisfaction
    intensity::Float32         # [0, 1] intensity
    last_update::DateTime
end

"""
    AffectiveState - Full emotional state
    
INVARIANTS:
- Emotions modulate value weighting but CANNOT override kernel
- All intensities bounded in [0, 1]
"""
struct AffectiveState
    valence::Float32            # [-1, 1] positive/negative affect
    arousal::Float32            # [0, 1] activation level
    fear::Float32               # [0, 1] threat response
    joy::Float32                # [0, 1] reward response
    curiosity::Float32          # [0, 1] exploration drive
    frustration::Float32        # [0, 1] failure response
    satisfaction::Float32      # [0, 1] success response
    energy::Float32             # [0, 1] available cognitive resources
    timestamp::DateTime
    
    function AffectiveState(
        valence::Float32=0f0,
        arousal::Float32=0.5f0;
        fear::Float32=0f0,
        joy::Float32=0f0,
        curiosity::Float32=0.3f0,
        frustration::Float32=0f0,
        satisfaction::Float32=0f0,
        energy::Float32=1f0
    )
        @assert -1f0 <= valence <= 1f0
        @assert 0f0 <= arousal <= 1f0
        @assert 0f0 <= fear <= 1f0
        @assert 0f0 <= joy <= 1f0
        @assert 0f0 <= curiosity <= 1f0
        @assert 0f0 <= frustration <= 1f0
        @assert 0f0 <= satisfaction <= 1f0
        @assert 0f0 <= energy <= 1f0
        
        new(valence, arousal, fear, joy, curiosity, frustration, satisfaction, energy, now())
    end
end

# Maximum emotional modulation factor (cannot amplify more than this)
const EMOTION_BOUND = 0.3f0

end # module
```

### C. Function Signatures

```julia
# Emotional functions

"""
    update_emotions!(state::AffectiveState, outcome::ExecutionResult)::AffectiveState

Updates emotional state based on execution outcome.
All updates bounded to prevent runaway emotional states.
"""
function update_emotions!(state::AffectiveState, outcome::ExecutionResult)::AffectiveState

"""
    compute_emotional_modulation(state::AffectiveState)::Vector{Float32}

Computes how emotions should modulate brain value signals.
Returns 5D vector: [valence_effect, arousal_effect, fear_effect, curiosity_effect, frustration_effect]

INVARIANT: All values in [-EMOTION_BOUND, +EMOTION_BOUND]
"""
function compute_emotional_modulation(state::AffectiveState})::Vector{Float32}

"""
    clamp_emotional_modulation(modulation::Vector{Float32})::Vector{Float32}

Ensures emotional modulation stays within safety bounds.
"""
function clamp_emotional_modulation(modulation::Vector{Float32})::Vector{Float32}
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| PainFeedback | `adaptive-kernel/cognition/feedback/PainFeedback.jl` | Extends existing system |
| Brain | Component 1 | `emotional_modulation` field in `BrainInput` |
| Kernel | `adaptive-kernel/kernel/Kernel.jl` | **CANNOT override kernel decisions** |

### E. Data Flow Description

1. **Outcome Reception**: After execution, `update_emotions!()` adjusts state
2. **Modulation**: `compute_emotional_modulation()` produces effect vector
3. **Clamping**: `clamp_emotional_modulation()` enforces safety bounds
4. **Brain Input**: Modulation added to `BrainInput.emotional_state`
5. **Inference**: Brain uses modulation to weight value estimates
6. **Kernel**: **Kernel ignores emotional modulation in approval decisions**

### F. Learning Strategy

- **Reward Learning**: Positive outcomes increase joy/satisfaction
- **Punishment Learning**: Negative outcomes increase fear/frustration
- **Curiosity**: Intrinsic exploration drive (independent of outcome)

### G. Safety Constraints (CRITICAL)

- **EMOTION_BOUND = 0.3**: Maximum modulation is 30%
- **Kernel Ignores Emotion**: `Kernel.approve()` does NOT consider emotional state
- **No Override**: Emotions cannot force approval of denied actions
- **Explicit Bounds**: All emotional values hard-clamped to valid ranges

### H. Performance Considerations

- **O(1) Update**: Simple exponential moving average
- **Fixed Size**: 5D modulation vector

### I. Minimal Code Skeleton

```julia
# cognition/emotion/Affective.jl

module Affective

export AffectiveState, compute_emotional_modulation

const EMOTION_BOUND = 0.3f0

struct AffectiveState
    valence::Float32
    arousal::Float32
    fear::Float32
    joy::Float32
    curiosity::Float32
    frustration::Float32
    satisfaction::Float32
    energy::Float32
    
    AffectiveState() = new(0f0, 0.5f0, 0f0, 0f0, 0.3f0, 0f0, 0f0, 1f0)
end

function compute_emotional_modulation(state::AffectiveState)::Vector{Float32}
    # Emotions modulate but cannot override safety
    modulation = Float32[
        state.valence * EMOTION_BOUND,
        state.arousal * EMOTION_BOUND,
        -state.fear * EMOTION_BOUND,  # Fear reduces value
        state.curiosity * EMOTION_BOUND,  # Curiosity increases exploration
        -state.frustration * EMOTION_BOUND  # Frustration reduces value
    ]
    
    return clamp.(modulation, -EMOTION_BOUND, EMOTION_BOUND)
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Bounds** | Update emotions 100 times | All values always in valid range |
| **Modulation Bounds** | Compute 1000 modulations | All in [-0.3, 0.3] |
| **Kernel Independence** | High emotion + denied action | Kernel still denies |
| **Clamping** | Force extreme emotion | Values clamped |

---

## Component 8: GROUNDED LANGUAGE UNDERSTANDING

### A. Architectural Role

Bridges LLM outputs to perceptual grounding. Resolves language references to actual world entities. Ensures language understanding is anchored in sensory reality.

### B. New Julia Struct Definitions

```julia
# cognition/language/Grounding.jl - NEW FILE

module Grounding

using Statistics

export 
    GroundingContext,
    SymbolGrounding,
    resolve_reference,
    ground_language

"""
    SymbolGrounding - Links language symbol to perceptual entity
"""
struct SymbolGrounding
    symbol::String
    entity_id::UUID
    confidence::Float32
    grounding_type::Symbol  # :perceptual, :conceptual, :procedural
end

"""
    GroundingContext - Current grounding state
"""
mutable struct GroundingContext
    symbol_table::Dict{String, SymbolGrounding}
    entity_memory::Vector{Vector{Float32}}  # Recent entity embeddings
    max_entities::Int
    
    GroundingContext(max_entities::Int=100) = new(
        Dict{String, SymbolGrounding}(),
        Vector{Float32}[],
        max_entities
    )
end

end # module
```

### C. Function Signatures

```julia
# Language grounding functions

"""
    ground_language(text::String, context::GroundingContext, 
                   perception::Vector{Float32})::Vector{SymbolGrounding}

Resolves language in text to grounded entities.
Returns vector of symbol groundings.
"""
function ground_language(text::String, context::GroundingContext, 
                        perception::Vector{Float32})::Vector{SymbolGrounding}

"""
    resolve_reference(reference::String, context::GroundingContext,
                     perception::Vector{Float32})::Union{SymbolGrounding, Nothing}

Resolves a single reference (e.g., "the file", "that process").
"""
function resolve_reference(reference::String, context::GroundingContext,
                          perception::Vector{Float32})::Union{SymbolGrounding, Nothing}
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| LLM Bridge | `jarvis/src/llm/LLMBridge.jl` | Input to grounding |
| Sensory | Component 2 | Perception for anchoring |
| Brain | Component 1 | Grounded context in inference |

### E. Data Flow Description

1. **LLM Output**: Text from language model
2. **Grounding**: `ground_language()` resolves symbols to entities
3. **Anchoring**: Entities matched against current perception
4. **Output**: Grounded understanding passed to brain

### F. Learning Strategy

- **Entity Tracking**: Learn which perceptual features map to which symbols
- **Confidence Learning**: Update grounding confidence based on execution success

### G. Safety Constraints

- **Confidence Threshold**: Low confidence groundings trigger clarification request
- **No Execution from Language Alone**: Grounding feeds brain, not directly to kernel

### H. Performance Considerations

- **O(n)**: Linear in text length

### I. Minimal Code Skeleton

```julia
# cognition/language/Grounding.jl

module Grounding

export GroundingContext, ground_language

mutable struct GroundingContext
    symbols::Dict{String, Vector{Float32}}
    
    GroundingContext() = new(Dict{String, Vector{Float32}}())
end

function ground_language(text::String, context::GroundingContext, 
                        perception::Vector{Float32})::Vector{String}
    # Simple keyword extraction as placeholder
    words = split(lowercase(text))
    grounded = String[]
    
    for word in words
        if haskey(context.symbols, word)
            push!(grounded, word)
        end
    end
    
    return grounded
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Grounding** | Parse text with known entities | Entities resolved |
| **Unknown Handling** | Text with unknown symbols | Returns empty or asks clarification |

---

## Component 9: CONTINUOUS ONLINE LEARNING

### A. Architectural Role

Implements incremental learning with meta-learning hooks. Includes safety rollback mechanism and confidence estimation to prevent catastrophic forgetting.

### B. New Julia Struct Definitions

```julia
# cognition/learning/OnlineLearning.jl - NEW FILE

module OnlineLearning

using UUIDs

export 
    LearningState,
    OnlineLearner,
    learn_batch,
    estimate_confidence,
    rollback_to_checkpoint

"""
    LearningState - Tracks learning progress and safety
"""
mutable struct LearningState
    training_step::Int
    checkpoint_id::UUID
    last_checkpoint_time::DateTime
    gradient_norm::Float32
    loss_history::Vector{Float32}
    confidence_estimate::Float32
    is_sandboxed::Bool
    
    LearningState() = new(0, uuid4(), now(), 0f0, Float32[], 0.5f0, true)
end

"""
    OnlineLearner - Manages continuous learning
"""
mutable struct OnlineLearner
    state::LearningState
    checkpoint_interval::Int      # Steps between checkpoints
    max_loss_history::Int
    confidence_threshold::Float32
    
    OnlineLearner(checkpoint_interval::Int=100) = new(
        LearningState(),
        checkpoint_interval,
        100,
        0.7f0
    )
end

end # module
```

### C. Function Signatures

```julia
# Online learning functions

"""
    learn_batch(learner::OnlineLearner, brain::JarvisBrain, 
               experiences::Vector{Experience})::Bool

Performs learning update on batch of experiences.
Returns true if successful, false if rolled back.
"""
function learn_batch(learner::OnlineLearner, brain::JarvisBrain, 
                    experiences::Vector{Experience})::Bool

"""
    estimate_confidence(learner::OnlineLearner)::Float32

Estimates model confidence based on loss history and gradient stability.
Returns [0, 1] confidence.
"""
function estimate_confidence(learner::OnlineLearner)::Float32

"""
    rollback_to_checkpoint(learner::OnlineLearner, brain::JarvisBrain)::Bool

Rolls brain back to last checkpoint if learning unstable.
Returns true if rollback successful.
"""
function rollback_to_checkpoint(learner::OnlineLearner, brain::JarvisBrain)::Bool
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| Brain | Component 1 | Uses brain's `update!()` |
| Experience Buffer | Component 1 | Sources experiences |
| BrainTrainer | `jarvis/src/brain/BrainTrainer.jl` | Checkpoint integration |

### E. Data Flow Description

1. **Experience Collection**: Buffer accumulates `Experience` tuples
2. **Batch Sampling**: `learn_batch()` samples from buffer
3. **Sandbox Update**: Weights copied, update applied to copy
4. **Validation**: Check loss and gradient norms
5. **Commit or Rollback**: If valid, commit to brain; else rollback

### F. Learning Strategy

- **Experience Replay**: Sample from buffer to prevent forgetting
- **Meta-Learning**: Track loss history for confidence estimation
- **Checkpointing**: Save state before each major update

### G. Safety Constraints

- **Sandbox**: All updates in isolated copy first
- **Rollback**: Automatic rollback on loss spike or gradient explosion
- **Confidence Threshold**: If confidence < threshold, pause learning
- **No Privilege Escalation**: Learning cannot change approval logic

### H. Performance Considerations

- **Checkpoint Cost**: O(model_size) - save entire weight set
- **Batch Size**: Typically 32

### I. Minimal Code Skeleton

```julia
# cognition/learning/OnlineLearning.jl

module OnlineLearning

using UUIDs

export OnlineLearner, learn_batch

mutable struct OnlineLearner
    step::Int
    checkpoint_interval::Int
    checkpoint::Dict{String, Any}
    
    OnlineLearner(interval::Int=100) = new(0, interval, Dict())
end

function learn_batch(learner::OnlineLearner, brain, experiences)::Bool
    learner.step += 1
    
    # Checkpoint before update
    if learner.step % learner.checkpoint_interval == 0
        learner.checkpoint = Dict("weights" => "save_weights_here")
    end
    
    # Simulate learning (actual implementation would call brain.update!)
    loss = rand(Float32) * 0.1f0
    
    # Rollback on high loss
    if loss > 0.5f0
        return false  # Would trigger rollback
    end
    
    return true
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Checkpoint** | Run N steps | Checkpoint saved at interval |
| **Rollback** | Force high loss | Weights restored |
| **Confidence** | Vary loss | Confidence decreases with high loss |

---

## Component 10: SELF-MODEL / METACOGNITION

### A. Architectural Role

Maintains model's understanding of its own capabilities and limitations. Tracks knowledge boundaries, monitors confidence, and supports capability-aware decision making.

### B. New Julia Struct Definitions

```julia
# cognition/metacognition/SelfModel.jl - NEW FILE

module Metacognition

using Statistics

export 
    SelfModel,
    SelfModelState,
    update_self_model,
    estimate_capability,
    get_knowledge_boundary

"""
    SelfModel - Model of own capabilities and limitations
"""
mutable struct SelfModel
    # Capability estimates [0, 1] per task type
    capability_estimates::Dict{Symbol, Float32}
    
    # Knowledge boundaries (what we know we don't know)
    known_unknowns::Vector{Symbol}
    unknown_unknowns_estimate::Float32  # How many unknown unknowns
    
    # Performance history
    recent_successes::Vector{Bool}
    confidence::Float32
    energy::Float32
    
    # Meta-cognitive accuracy
    calibration_error::Float32  # |confidence - actual accuracy|
    
    function SelfModel()
        new(
            Dict{Symbol, Float32}(
                :system_monitoring => 0.8f0,
                :file_operations => 0.7f0,
                :analysis => 0.6f0,
                :planning => 0.5f0
            ),
            Symbol[],
            0.3f0,
            Bool[],
            0.7f0,
            0.9f0,
            0.1f0
        )
    end
end

"""
    SelfModelState - Snapshot for kernel
"""
struct SelfModelState
    confidence::Float32
    energy::Float32
    dominant_capability::Symbol
    knowledge_gaps::Vector{Symbol}
    calibration_error::Float32
end

end # module
```

### C. Function Signatures

```julia
# Metacognition functions

"""
    update_self_model!(model::SelfModel, action::ActionProposal, 
                       result::ExecutionResult)::SelfModelState

Updates self-model based on action outcome.
Tracks success/failure to calibrate confidence.
"""
function update_self_model!(model::SelfModel, action::ActionProposal, 
                           result::ExecutionResult)::SelfModelState

"""
    estimate_capability(model::SelfModel, task_type::Symbol)::Float32

Returns estimated capability for task type.
Combines historical performance with base rate.
"""
function estimate_capability(model::SelfModel, task_type::Symbol)::Float32

"""
    get_knowledge_boundary(model::SelfModel)::Vector{Symbol}

Returns areas where model has low capability (known unknowns).
"""
function get_knowledge_boundary(model::SelfModel)::Vector{Symbol}

"""
    check_calibration(model::SelfModel)::Float32

Computes calibration error: |confidence - actual accuracy|.
Lower is better.
"""
function check_calibration(model::SelfModel)::Float32
```

### D. Integration Points

| Module | File | Integration Method |
|--------|------|-------------------|
| Kernel | `adaptive-kernel/kernel/Kernel.jl` | Provides `self_metrics` |
| Brain | Component 1 | Uses capability estimates for action selection |
| Reflection | Component 1 | Updates from `ReflectionEvent` |

### E. Data Flow Description

1. **Action Execution**: Action proposed and executed
2. **Outcome**: Result fed to `update_self_model!()`
3. **Calibration**: Update confidence to match actual accuracy
4. **Capability**: Adjust capability estimates per task type
5. **Boundary**: Track where model fails to improve known unknowns

### F. Learning Strategy

- **Outcome Tracking**: Every outcome updates capability estimate
- **Calibration**: EMA tracks |confidence - accuracy|
- **Conservative**: Lower estimates for uncertain areas

### G. Safety Constraints

- **Confidence Bounds**: Always in [0, 1]
- **No Overconfidence**: If calibration error > threshold, reduce all confidences
- **Explicit Unknowns**: Known unknowns explicitly tracked

### H. Performance Considerations

- **O(1) Update**: Simple EMA per capability
- **Bounded History**: Fixed-size success history

### I. Minimal Code Skeleton

```julia
# cognition/metacognition/SelfModel.jl

module Metacognition

export SelfModel, update_self_model!

mutable struct SelfModel
    confidence::Float32
    energy::Float32
    recent_successes::Vector{Bool}
    capabilities::Dict{Symbol, Float32}
    
    SelfModel() = new(0.7f0, 1.0f0, Bool[], Dict(:default => 0.7f0))
end

function update_self_model!(model::SelfModel, success::Bool)::Float32
    push!(model.recent_successes, success)
    if length(model.recent_successes) > 100
        popfirst!(model.recent_successes)
    end
    
    # Update confidence
    if !isempty(model.recent_successes)
        actual = mean(model.recent_successes)
        model.confidence = 0.9f0 * model.confidence + 0.1f0 * actual
    end
    
    return model.confidence
end

end
```

### J. Testing Strategy

| Test | Method | Success Criteria |
|------|--------|-----------------|
| **Calibration** | 50% success rate | Confidence ≈ 0.5 |
| **Overconfidence** | Force 0% success | Confidence decreases |
| **Bounds** | 1000 updates | Always in [0, 1] |

---

# 3. IMPLEMENTATION ROADMAP

## 3.1 Dependency Graph

```
CRITICAL PATH (must implement in order):
─────────────────────────────────────────
Component 1 (ITHERIS Core) 
    ↓
Component 2 (Sensory Processing)
    ↓
Component 5 (Attention)
    ↓
Component 4 (World Model) ← Component 2, 5
    ↓
Component 9 (Online Learning) ← Component 1, 4

PARALLELIZABLE (can implement concurrently):
────────────────────────────────────────────
Component 3 (Goal Formation)      ← Component 4
Component 6 (Sleep)               ← Component 9
Component 7 (Emotional Architecture) ← Component 1
Component 8 (Language Grounding)  ← Component 2
Component 10 (Self-Model)         ← Component 1, 9
```

## 3.2 Parallelizable Subsystems

| Subsystem | Dependencies | Can Start After |
|-----------|--------------|-----------------|
| Sensory Processing | None | Day 1 |
| Attention | Sensory | Day 3 |
| Goal Formation | World Model | Day 7 |
| Emotional Architecture | ITHERIS Core | Day 5 |
| Language Grounding | Sensory | Day 5 |
| Sleep | Online Learning | Day 10 |
| Self-Model | ITHERIS Core, Online Learning | Day 10 |

## 3.3 Critical Path

**Shortest Path to Basic Functionality:**
1. **Day 1-3**: Component 1 (ITHERIS Core integration)
2. **Day 3-5**: Component 2 (Sensory) + Component 5 (Attention)
3. **Day 5-7**: Component 4 (World Model)
4. **Day 7-10**: Component 9 (Online Learning)
5. **Day 10**: Basic cognitive loop functional

## 3.4 Estimated Difficulty

| Component | Difficulty | Reason |
|-----------|------------|--------|
| 1. ITHERIS Integration | Medium | Wire existing networks |
| 2. Sensory Processing | Low | Buffer management |
| 3. Goal Formation | Medium | Requires kernel integration |
| 4. World Model | Medium | Learning dynamics |
| 5. Attention | Low | Simple computation |
| 6. Sleep | Low | Background processing |
| 7. Emotional Architecture | Medium | Extend existing |
| 8. Language Grounding | High | LLM integration complex |
| 9. Online Learning | Medium | Safety mechanisms |
| 10. Self-Model | Low | Statistical tracking |

## 3.5 Staged Rollout Strategy

### Phase 1: Core Brain (Days 1-7)
- Component 1: ITHERIS Core integration
- Component 2: Sensory buffer
- Basic cognitive loop

### Phase 2: Perception (Days 7-14)
- Component 5: Attention
- Component 4: World Model
- Basic goal system

### Phase 3: Learning (Days 14-21)
- Component 9: Online Learning
- Component 10: Self-Model

### Phase 4: Advanced (Days 21-28)
- Component 7: Emotions
- Component 8: Language
- Component 6: Sleep

---

# 4. SAFETY & SOVEREIGNTY GUARANTEES

## 4.1 Invariant Definitions

### Invariant 1: No Autonomous Action Without Kernel Approval
```julia
# ALL action execution MUST pass through this:
function execute_action(proposal::BrainOutput, kernel::KernelState)::ExecutionResult
    decision = kernel.approve(proposal, kernel.world)
    
    if decision == APPROVED
        return run_capability(proposal.proposed_actions[1])
    elseif decision == DENIED
        return ExecutionResult(success=false, reason="kernel_denied")
    else  # STOPPED
        return ExecutionResult(success=false, reason="kernel_stopped")
    end
end
```

### Invariant 2: Learning Cannot Escalate Privileges
```julia
# Learning update NEVER touches:
# - Kernel approval logic
# - Safety constraint definitions
# - Capability registry (read-only)
function safe_learning_update(brain::JarvisBrain, experiences::Vector{Experience})::Bool
    # Validate: Only neural weights change
    @assert all(propertynames(brain.brain_core) .!= :kernel_approval)
    
    return sandboxed_update(brain, experiences)
end
```

### Invariant 3: Sensory Spoofing Detection
```julia
function detect_sensory_spoofing(snapshot::SensorySnapshot)::Bool
    # Check for impossible values
    any(isnan, snapshot.visual_features) && return true
    any(isnan, snapshot.system_telemetry) && return true
    
    # Check for sudden jumps (spoofed sensor injection)
    if length(snapshot_buffer) > 1
        delta = norm(snapshot.features - last(snapshot_buffer).features)
        if delta > MAX_SENSOR_JUMP
            @warn "Possible sensory spoofing detected" delta=delta
            return true
        end
    end
    
    return false
end
```

### Invariant 4: Emotional Modulation Bounded
```julia
const EMOTION_BOUND = 0.3f0  # Maximum 30% modulation

function apply_emotional_modulation(value::Float32, emotion::AffectiveState)::Float32
    modulation = compute_emotional_modulation(emotion)
    
    # Hard clamp: emotions can modulate but not override
    # Value can change by at most ±30%
    modulated = value + value * modulation[1]  # valence effect
    
    return clamp(modulated, value * (1-EMOTION_BOUND), value * (1+EMOTION_BOUND))
end

# CRITICAL: Kernel approval does NOT use emotional modulation
function Kernel.approve(kernel::KernelState, proposal::BrainOutput, world::WorldState)::Decision
    # Emotions are NOT consulted here
    # This is the sovereign approval function
    return _evaluate_risk_confidence_energy(kernel, proposal)
end
```

### Invariant 5: Goal Generation Aligned to User Constraints
```julia
function generate_aligned_goals(gen::AutonomousGoalGenerator, 
                               user_constraints::Vector{String})::Vector{Goal}
    new_goals = generate_goals!(gen, ...)
    
    # Filter against user constraints
    aligned = filter(goal -> goal_matches_constraints(goal, user_constraints), new_goals)
    
    # Must get kernel approval before activation
    approved = [g for g in aligned if kernel_approve_goal(g) == APPROVED]
    
    return approved
end
```

## 4.2 Sovereignty Boundary Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            SOVEREIGNTY BOUNDARY                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌──────────────────┐         ┌──────────────────┐                              │
│   │                  │         │                  │                              │
│   │      BRAIN       │         │      KERNEL      │                              │
│   │                  │         │                  │                              │
│   │  - ITHERIS       │         │  - approve()     │                              │
│   │  - Emotions      │         │  - world_state   │                              │
│   │  - Self-Model    │         │  - goals         │                              │
│   │  - Goals (prop)  │         │  - self_metrics  │                              │
│   │                  │         │                  │                              │
│   └────────┬─────────┘         └────────┬─────────┘                              │
│            │                            │                                        │
│            │   BrainOutput (ADVISORY)   │                                        │
│            │ ─────────────────────────▶│                                        │
│            │                            │                                        │
│            │                    ┌───────▼───────┐                                │
│            │                    │               │                                │
│            │                    │  DECISION      │                                │
│            │                    │  {APPROVED,    │                                │
│            │                    │   DENIED,      │                                │
│            │                    │   STOPPED}      │                                │
│            │                    │               │                                │
│            │                    └───────┬───────┘                                │
│            │                            │                                        │
│            │                   ┌────────┴────────┐                               │
│            │                   │                 │                               │
│            │                   │ EXECUTION or    │                               │
│            │                   │ REJECTION       │                               │
│            │                   │                 │                               │
│            │                   └────────┬────────┘                               │
│            │                            │                                        │
│            │   ExecutionResult          │                                        │
│            │ ◀─────────────────────────│                                        │
│            │                            │                                        │
│   ┌────────▼─────────┐                  │                                        │
│   │                  │                  │                                        │
│   │    LEARNING      │◀─────────────────┘                                        │
│   │                  │                                                            │
│   │  - Experience    │      Learning uses outcome but CANNOT                    │
│   │    Buffer        │      change kernel logic                                  │
│   │  - Weight Update │                                                            │
│   │  - Rollback      │                                                            │
│   │                  │                                                            │
│   └──────────────────┘                                                            │
│                                                                                  │
│   INVARIANTS:                                                                     │
│   1. BrainOutput is ADVISORY - kernel holds sovereignty                         │
│   2. Kernel.approve() does NOT consult emotional state                          │
│   3. Learning updates NEVER touch kernel approval logic                         │
│   4. All sensory data passes through spoofing detection                         │
│   5. Goals require explicit kernel approval before activation                   │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

# 5. FINAL COGNITIVE LOOP

## Pseudocode

```julia
"""
    JARVIS Cognitive Loop - Complete Implementation
    
    This is the main loop that orchestrates all components.
    Each iteration represents one cognitive cycle.
"""

function cognitive_cycle!(kernel::KernelState, brain::JarvisBrain, 
                         sensory::SensoryBuffer, attention::SalienceScorer,
                         world_model::WorldModel, goal_gen::AutonomousGoalGenerator,
                         emotions::AffectiveState, self_model::SelfModel,
                         learner::OnlineLearner, sleep::SleepCycle)
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 1: PERCEIVE - Get sensory snapshot
    # ═══════════════════════════════════════════════════════════════════════════
    perception = get_snapshot(sensory)
    
    # Detect sensory spoofing (safety)
    if detect_sensory_spoofing(perception)
        @warn "Sensory spoofing detected, using fallback perception"
        perception = get_fallback_snapshot()
    end
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 2: ATTEND - Compute salience and focus
    # ═══════════════════════════════════════════════════════════════════════════
    novelty = detect_novelty(attention, perception)
    saliences = compute_salience(attention, perception)
    attention_weights = allocate_attention(saliences)
    
    # Apply attention to perception (focused percept)
    attended_percept = perception .* attention_weights
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 3: UPDATE WORLD MODEL - Predict next state
    # ═══════════════════════════════════════════════════════════════════════════
    current_world_state = WorldState(perception)
    predicted_state = predict_next_state(world_model, current_world_state, "none")
    risk_estimate = compute_risk_prediction(world_model, predicted_state)
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 4: GENERATE GOALS - Form new goals based on curiosity
    # ═══════════════════════════════════════════════════════════════════════════
    new_goals = generate_goals!(goal_gen, perception, novelty)
    
    # CRITICAL: Kernel must approve new goals before activation
    for goal in new_goals
        decision = kernel_approve_goal(kernel, goal)
        if decision == APPROVED
            activate_goal!(goal_gen, goal)
        end
    end
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 5: INFER ACTIONS - Brain generates action proposals
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Prepare brain input
    emotional_modulation = compute_emotional_modulation(emotions)
    brain_input = BrainInput(
        attended_percept;
        goal_context=get_active_goal_embedding(goal_gen),
        recent_rewards=get_recent_rewards(kernel),
        emotional_state=emotions
    )
    
    # Neural inference (ITHERIS)
    brain_output = infer(brain, brain_input)
    
    # Apply emotional modulation (documented but advisory)
    modulated_value = brain_output.value_estimate + 
                     brain_output.value_estimate * emotional_modulation[1]
    brain_output = BrainOutput(
        brain_output.proposed_actions;
        confidence=brain_output.confidence,
        value_estimate=clamp(modulated_value, -1f0, 1f0),
        uncertainty=brain_output.uncertainty,
        reasoning=brain_output.reasoning,
        emotional_modulation=emotional_modulation
    )
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6: KERNEL APPROVAL - Sovereignty check (CRITICAL)
    # ═══════════════════════════════════════════════════════════════════════════
    # NOTE: Kernel does NOT consider emotional_modulation in decision
    
    decision = kernel.approve(brain_output, kernel.world)
    
    if decision == DENIED
        @info "Kernel denied action" reason=brain_output.reasoning
        log_reflection(kernel, brain_output, false, "kernel_denied")
        return
    elseif decision == STOPPED
        @warn "Kernel stopped system"
        log_reflection(kernel, brain_output, false, "kernel_stopped")
        return
    end
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 7: EXECUTE - Run approved action
    # ═══════════════════════════════════════════════════════════════════════════
    selected_action = brain_output.proposed_actions[1]
    result = execute_capability(selected_action)
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 8: REFLECT - Update self-model and emotions
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Update emotional state
    emotions = update_emotions!(emotions, result)
    
    # Update self-model
    confidence = update_self_model!(self_model, selected_action, result.success)
    update_kernel_self_metrics!(kernel, confidence, self_model.energy)
    
    # Record reflection
    reflection = ReflectionEvent(
        kernel.cycle[],
        selected_action,
        brain_output.confidence,
        result.cost,
        result.success,
        result.reward,
        abs(brain_output.value_estimate - result.reward),
        result.effect
    )
    push!(kernel.episodic_memory, reflection)
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 9: LEARN - Update brain from experience
    # ═══════════════════════════════════════════════════════════════════════════
    experience = Experience(
        perception, selected_action, result.reward, 
        get_next_perception(sensory), done=result.done
    )
    
    # Store in buffer
    push!(brain.experience_buffer, experience)
    
    # Online learning with safety rollback
    if length(brain.experience_buffer) >= 32
        batch = sample(brain.experience_buffer, 32)
        success = learn_batch(learner, brain, batch)
        
        if !success
            @warn "Learning failed, rolling back"
            rollback_to_checkpoint(learner, brain)
        end
    end
    
    # Update world model
    update!(world_model, WorldState(get_snapshot(sensory)), predicted_state)
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 10: SLEEP IF NEEDED - Consolidation and dreaming
    # ═══════════════════════════════════════════════════════════════════════════
    if sleep_cycle!(sleep, kernel.episodic_memory)
        # Consolidation
        semantic_knowledge = consolidate_memory!(sleep, kernel.episodic_memory)
        
        # Dream exploration
        dream_experiences = dream!(sleep, semantic_knowledge)
        
        # Learn from dreams
        for exp in dream_experiences
            push!(brain.experience_buffer, exp)
        end
    end
    
    # Increment cycle
    kernel.cycle[] += 1
    
    return brain_output
end

"""
    Main loop - runs continuously
"""
function run_jarvis!(kernel::KernelState, brain::JarvisBrain)
    # Initialize components
    sensory = SensoryBuffer()
    attention = SalienceScorer()
    world_model = WorldModel()
    goal_gen = AutonomousGoalGenerator()
    emotions = AffectiveState()
    self_model = SelfModel()
    learner = OnlineLearner()
    sleep = SleepCycle()
    
    # Continuous cognitive cycle
    while kernel.self_metrics["energy"] > 0.1f0
        cognitive_cycle!(
            kernel, brain, sensory, attention,
            world_model, goal_gen, emotions,
            self_model, learner, sleep
        )
    end
    
    @info "JARVIS shutting down - energy depleted"
end
```

---

## Document Summary

This architecture document specifies the complete JARVIS Neuro-Symbolic Cognitive Architecture with:

1. **10 Implementation Components** with full Julia struct definitions and function signatures
2. **Data Flow** across all cognitive stages
3. **Integration Points** to existing codebase (Brain.jl, Kernel.jl, ITHERIS)
4. **Learning Strategies** for each component
5. **Safety Constraints** enforcing kernel sovereignty
6. **Implementation Roadmap** with dependency graph and staged rollout
7. **Pseudocode** for the complete cognitive loop

The architecture follows the five global design principles:
- Brain is advisory, Kernel is sovereign
- Continuous perception does not bypass kernel risk evaluation  
- Learning is sandboxed and reversible
- Emotions modulate value but do not override safety
- All subsystems expose clear interface contracts

---

*End of Document*
