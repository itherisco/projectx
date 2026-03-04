# Jarvis System Implementation Roadmap

> **⚠️ System Status: PROTOTYPE / EXPERIMENTAL**
> This document outlines a design specification for a future production system.
> The current implementation is an experimental prototype with significant security gaps.

## Comprehensive Autonomous AI Assistant (Design Specification)

**Generated:** 2026-02-26  
**Status:** ARCHITECTURE SPECIFICATION  
**Classification:** PRODUCTION SYSTEM DESIGN (Target - Not Yet Achieved)

---

## 1. SYSTEM COMPLETION BLUEPRINT

### 1.1 High-Level Final Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        JARVIS PRODUCTION ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    PERCEPTION LAYER (Input)                         │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │    │
│  │  │  Voice       │  │  Vision      │  │  Text/JSON   │              │    │
│  │  │  (Whisper)   │  │  (GPT-4V)    │  │  (REST API)  │              │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │    │
│  │         │                  │                  │                      │    │
│  │         └──────────────────┼──────────────────┘                      │    │
│  │                            ▼                                           │    │
│  │                   ┌─────────────────┐                                 │    │
│  │                   │ PerceptionVector │ ◄── Unified input format     │    │
│  │                   └────────┬────────┘                                 │    │
│  └─────────────────────────────┼──────────────────────────────────────────┘    │
│                                ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    COGNITION LAYER (Brain)                          │    │
│  │  ┌────────────────────────────────────────────────────────────┐     │    │
│  │  │                    ITHERIS BRAIN                           │     │    │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐            │     │    │
│  │  │  │ Encoder   │  │  Policy    │  │  Value     │            │     │    │
│  │  │  │  Network  │──│  Network  │──│  Network   │            │     │    │
│  │  │  └────────────┘  └────────────┘  └────────────┘            │     │    │
│  │  │        │                                     │              │     │    │
│  │  │        └──────────────┬──────────────────────┘              │     │    │
│  │  │                       ▼                                       │     │    │
│  │  │              ┌─────────────────┐                              │     │    │
│  │  │              │  BrainOutput    │ ◄── ADVISORY PROPOSAL       │     │    │
│  │  │              │  (Thought)      │    (confidence, value,      │     │    │
│  │  │              └─────────────────┘     uncertainty)            │     │    │
│  │  └────────────────────────────────────────────────────────────┘     │    │
│  │                              │                                      │    │
│  │                              ▼ ADVISORY ONLY                       │    │
│  └──────────────────────────────┼──────────────────────────────────────┘    │
│                                 ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    SOVEREIGNTY LAYER (Kernel)                      │    │
│  │  ┌────────────────────────────────────────────────────────────┐     │    │
│  │  │                   ADAPTIVE KERNEL                          │     │    │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐            │     │    │
│  │  │  │ WorldState │  │  Goal      │  │ Reflection │            │     │    │
│  │  │  │ Observer   │  │  Manager   │  │  Engine    │            │     │    │
│  │  │  └─────┬──────┘  └──────┬─────┘  └──────┬─────┘            │     │    │
│  │  │        │                │                │                   │     │    │
│  │  │        └────────────────┼────────────────┘                   │     │    │
│  │  │                         ▼                                    │     │    │
│  │  │              ┌─────────────────────┐                         │     │    │
│  │  │              │  Kernel.approve()   │ ◄── SOVEREIGN DECISION │     │    │
│  │  │              │  (APPROVE/DENY/STOP)│    NO EXCEPTION        │     │    │
│  │  │              └──────────┬──────────┘                         │     │    │
│  │  └─────────────────────────┼────────────────────────────────────┘     │    │
│  │                            │ APPROVED                                │    │
│  │                            ▼                                         │    │
│  └────────────────────────────┼────────────────────────────────────────┘    │
│                               ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    EXECUTION LAYER (Action)                         │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │    │
│  │  │  OpenClaw   │  │  Capability  │  │  System     │              │    │
│  │  │  Tools      │  │  Registry    │  │  Commands   │              │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │    │
│  │         │                  │                  │                      │    │
│  │         └──────────────────┼──────────────────┘                      │    │
│  │                            ▼                                           │    │
│  │                   ┌─────────────────┐                                 │    │
│  │                   │  ActionResult   │ ◄── Execution outcome          │    │
│  │                   └────────┬────────┘                                 │    │
│  └─────────────────────────────┼──────────────────────────────────────────┘    │
│                                ▼                                              │
│                               FEEDBACK                                         │
│                                │                                               │
│                                ▼                                               │
│              ┌─────────────────────────────────┐                            │
│              │  Kernel.reflect!(proposal,result)│ ◄── Self-model update    │
│              └─────────────────────────────────┘                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                       SUPPORTING INFRASTRUCTURE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │   Vector     │  │  Semantic   │  │  Config     │  │   Trust     │    │
│  │   Store      │  │  Memory     │  │  Manager    │  │   Manager   │    │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘    │
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │   Error      │  │   Recovery  │  │   Secrets   │  │  Observability│   │
│  │   Handler   │  │   Manager   │  │   Vault     │  │   (Logging)  │    │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Updated Data Flow Diagram (Text-Based)

```
User Input → [Perception] → PerceptionVector
                                │
                                ▼
                    ┌───────────────────────┐
                    │    ITHERIS Brain     │
                    │   (Neural Inference) │
                    │  Output: BrainOutput │
                    │  (action, value,      │
                    │   uncertainty)       │
                    └───────────┬───────────┘
                                │
                                ▼ ADVISORY PROPOSAL
                    ┌───────────────────────┐
                    │  Convert to           │
                    │  Integration types    │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │   Adaptive Kernel    │
                    │  Kernel.approve()    │
                    │  Output: APPROVED    │
                    │         / DENIED     │
                    │         / STOPPED    │
                    └───────────┬───────────┘
                                │
                    ┌───────────┴───────────┐
                    │                        │
                    ▼                        ▼
              [APPROVED]               [DENIED/STOPPED]
                    │                        │
                    ▼                        ▼
                    ┌───────────────────────┐
                    │   Execute Action       │
                    │   via Capability      │
                    │   Registry            │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │   ActionResult        │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  Kernel.reflect!()    │
                    │  (Self-model update)  │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  Update Memory/        │
                    │  Vector Store         │
                    └───────────────────────┘
```

### 1.3 Revised Sovereignty Enforcement Path

**INVARIANT:** `No action executes without kernel.approve() returning APPROVED`

**Enforcement Points:**

1. **Entry Point:** `SystemIntegrator.run_cycle()` at line ~455
   - Current: Calls `_brain_infer()` → gets proposal
   - Required: Must call `Kernel.approve(proposal, world_state)`

2. **Execution Gate:** `SystemIntegrator._execute_action()` at line ~800
   - Current: May execute without kernel check
   - Required: MUST verify `kernel.state.last_decision == APPROVED`

3. **Reflection Callback:** After execution
   - Current: Has `Kernel.reflect!()` call at line ~844
   - Required: Must pass complete `ActionResult` with all metrics

**Code Pattern:**
```julia
# CORRECT SOVEREIGNTY ENFORCEMENT
function run_cycle(system::JarvisSystem)
    perception = _collect_perception(system)
    proposal = _brain_infer(system, perception)  # ADVISORY ONLY
    
    # CRITICAL: Kernel sovereignty enforcement
    world_state = _build_world_state(system)
    decision = Kernel.approve(system.kernel.state, proposal, world_state)
    
    if decision == APPROVED
        result = _execute_action(system, proposal)
        Kernel.reflect!(system.kernel.state, proposal, result)
    else
        @warn "Kernel denied proposal" decision=decision
    end
end
```

### 1.4 Final Perception → Cognition → Execution Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                     COGNITIVE CYCLE (Fixed)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  T=0    ┌──────────────┐                                        │
│         │  Collect     │                                        │
│         │  Perception  │ ◄── Real system metrics, user input  │
│         └──────┬───────┘                                        │
│                │                                                │
│                ▼                                                │
│  T=1    ┌──────────────┐                                        │
│         │  ITHERIS     │                                        │
│         │  Brain       │ ◄── Neural inference (ADVISORY)       │
│         │  Infer()     │    Returns: action, value, uncertainty │
│         └──────┬───────┘                                        │
│                │                                                │
│                ▼ PROPOSAL                                       │
│  T=2    ┌──────────────┐                                        │
│         │  Convert     │ ◄── To IntegrationActionProposal      │
│         │  Types       │                                        │
│         └──────┬───────┘                                        │
│                │                                                │
│                ▼ PROPOSAL                                       │
│  T=3    ┌──────────────┐                                        │
│         │  Kernel      │ ◄── SOVEREIGN APPROVAL                │
│         │  approve()   │    Returns: APPROVED/DENIED/STOPPED    │
│         └──────┬───────┘                                        │
│                │                                                │
│        ┌───────┴───────┐                                        │
│        │               │                                        │
│        ▼               ▼                                        │
│   [APPROVED]       [DENIED]                                      │
│        │               │                                        │
│        ▼               ▼                                         │
│  T=4    ┌───────────┐  ┌───────────┐                           │
│         │  Execute   │  │  Log &    │                           │
│         │  Action    │  │  Continue │                           │
│         └─────┬─────┘  └───────────┘                           │
│               │                                                 │
│               ▼ RESULT                                          │
│  T=5    ┌──────────────┐                                        │
│         │  Kernel       │ ◄── Self-model update                 │
│         │  reflect!()   │    Updates: confidence, energy,       │
│         └──────┬───────┘     prediction_error, goal_progress   │
│                │                                                 │
│                ▼                                                 │
│  T=6    ┌──────────────┐                                        │
│         │  Update       │ ◄── Vector store, semantic memory    │
│         │  Memory       │                                        │
│         └───────────────┘                                        │
│                                                                  │
│  CYCLE TIME TARGET: <100ms (excluding external API calls)       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. CRITICAL GAP IMPLEMENTATION PLANS

### A. Full ITHERIS Neural Brain Activation

**Current State:** `_brain_infer()` exists but falls back to heuristics at line ~595 in `SystemIntegrator.jl`

**Required Changes:**

#### A.1 Complete `_brain_infer()` Implementation

**File:** `jarvis/src/SystemIntegrator.jl`

**Lines:** 524-620 (expand)

**Implementation Steps:**

1. **Replace Heuristic Fallback (lines 595-620)**
   - Current: Returns hardcoded "observe_system" when brain unavailable
   - Required: Return `nothing` when brain unavailable, forcing kernel to handle

2. **Add Neural Confidence Threshold**
   ```julia
   const BRAIN_CONFIDENCE_THRESHOLD = 0.7f0
   
   function _brain_infer(system::JarvisSystem, perception::PerceptionVector)
       # ... existing ITHERIS inference code ...
       
       if thought.uncertainty > (1.0 - BRAIN_CONFIDENCE_THRESHOLD)
           @warn "Brain confidence too low" uncertainty=thought.uncertainty
           return nothing  # Let kernel decide with heuristic
       end
       
       return action_proposal
   end
   ```

3. **Add Brain Learning Feedback**
   ```julia
   function _brain_feedback!(system::JarvisSystem, proposal::ActionProposal, result::ActionResult)
       system.brain.learning_buffer !== nothing || return nothing
       
       # Convert to training sample
       sample = Dict(
           "perception" => system.last_perception,
           "proposal" => proposal,
           "outcome" => result.success ? result.reward : -result.cost,
           "timestamp" => now()
       )
       push!(system.brain.learning_buffer, sample)
       
       # Trigger training if buffer full
       if length(system.brain.learning_buffer) >= BRAIN_BATCH_SIZE
           @async train_brain!(system)
       end
   end
   ```

#### A.2 Connect Training Loop

**New File:** `jarvis/src/brain/BrainTrainer.jl`

```julia
module BrainTrainer

export train_brain!, brain_checkpoint, restore_brain

using ...JarvisTypes
using ...ITHERISCore

const BRAIN_BATCH_SIZE = 32
const CHECKPOINT_INTERVAL = 100  # cycles

"""
    train_brain!(system::JarvisSystem)
Trigger incremental training from accumulated experience buffer.
"""
function train_brain!(system::JarvisSystem)
    buffer = system.brain.learning_buffer
    length(buffer) < BRAIN_BATCH_SIZE && return nothing
    
    # Extract training data
    perceptions = [sample["perception"] for sample in buffer]
    outcomes = [sample["outcome"] for sample in buffer]
    
    # Train (simplified - actual implementation depends on ITHERIS architecture)
    ITHERISCore.train_step!(system.brain.brain_core, perceptions, outcomes)
    
    # Clear buffer
    empty!(buffer)
    
    @info "Brain trained" samples=length(perceptions)
end

"""
    brain_checkpoint(system::JarvisSystem, path::String)
Save brain state for crash recovery.
"""
function brain_checkpoint(system::JarvisSystem, path::String)
    system.brain.brain_core === nothing && return
    ITHERISCore.save_state(system.brain.brain_core, path)
    @info "Brain checkpoint saved" path=path
end

"""
    restore_brain!(system::JarvisSystem, path::String)
Restore brain from checkpoint.
"""
function restore_brain!(system::JarvisSystem, path::String)
    system.brain.brain_core = ITHERISCore.load_state(path)
    system.brain.initialized = true
    @info "Brain restored" path=path
end

end  # module
```

#### A.3 Define Inference Contract

**Brain-Kernel Boundary Invariant:**

```
INVARIANT: BrainOutput → IntegrationActionProposal
- action ∈ [1, 6] (discrete actions)
- value ∈ [0, 1] (expected reward)
- uncertainty ∈ [0, 1] (epistemic uncertainty)

BOUNDARY: Brain never accesses:
- Kernel state
- Execution results
- User confirmation state
- External APIs (except training)
```

#### A.4 Testing Strategy

- **Unit:** Test `_brain_infer()` with mock BrainCore
- **Integration:** Test brain → kernel → execution flow
- **Failure:** Test fallback when brain returns `nothing`

---

### B. Adaptive Kernel Sovereignty Enforcement

**Current State:** `Kernel.approve()` exists in `adaptive-kernel/kernel/Kernel.jl` but NOT wired into `SystemIntegrator`

**Required Changes:**

#### B.1 Complete `Kernel.approve()` Integration

**File:** `jarvis/src/SystemIntegrator.jl`

**Lines:** ~439-530 (expand `run_cycle`)

**Implementation:**

```julia
function run_cycle(system::JarvisSystem)::CycleResult
    # Step 1: Collect real perception
    perception = _collect_perception(system)
    system.last_perception = perception
    
    # Step 2: Get brain proposal (ADVISORY)
    proposal = _brain_infer(system, perception)
    
    # Step 3: Build world state for kernel
    world_state = _build_world_state(system)
    
    # Step 4: CRITICAL - Kernel sovereignty approval
    decision = Kernel.approve(system.kernel.state, proposal, world_state)
    
    # Step 5: Execute based on decision
    if decision == Kernel.APPROVED
        result = _execute_action(system, proposal)
        # Step 6: Reflection for self-model update
        Kernel.reflect!(system.kernel.state, proposal, result)
        return CycleResult(:executed, proposal, result)
    elseif decision == Kernel.STOPPED
        return CycleResult(:stopped, proposal, nothing)
    else
        return CycleResult(:denied, proposal, nothing)
    end
end
```

#### B.2 Wire `reflect!` Feedback Loop

**Existing:** `Kernel.reflect!()` called at line 844 in `SystemIntegrator.jl`

**Required:** Update to pass complete reflection data

```julia
function _kernel_reflect!(kernel::KernelWrapper, proposal::ActionProposal, result::ActionResult)
    kernel.state === nothing && return
    
    # Convert Jarvis result to reflection event
    reflection = ReflectionEvent(
        uuid4(),
        now(),
        proposal.capability_id,
        result.success ? :success : :failure,
        result.reward,
        result.cost,
        result.impact_estimate,
        result.error_message,
        Dict(
            "user_confirmed" => result.user_confirmed,
            "retry_count" => result.retry_count
        )
    )
    
    Kernel.reflect_with_event!(kernel.state, reflection)
end
```

#### B.3 Define Formal Invariant

```
SOVEREIGNTY INVARIANT:
┌─────────────────────────────────────────────────────────────┐
│  ∀ action ∈ Actions:                                        │
│    execute(action) ⇒ kernel.state.last_decision == APPROVED│
└─────────────────────────────────────────────────────────────┘

VIOLATION = SECURITY BREACH = SYSTEM HALT
```

**Implementation:** Add assertion in `_execute_action()`
```julia
function _execute_action(system::JarvisSystem, proposal::ActionProposal)::ActionResult
    # CRITICAL: Verify sovereignty
    if system.kernel.state === nothing
        error("KERNEL NOT INITIALIZED - SOVEREIGNTY VIOLATION")
    end
    
    last_decision = getfield(system.kernel.state, :last_decision)
    if last_decision != Kernel.APPROVED
        error("SOVEREIGNTY VIOLATION: Action executed without kernel approval")
    end
    
    # ... rest of execution ...
end
```

#### B.4 Implement Audit Trail

**New File:** `jarvis/src/security/AuditLog.jl`

```julia
module AuditLog

export audit_event, get_audit_trail, SecurityEvent

using UUIDs
using Dates

@enum SecurityEventType KERNEL_APPROVAL KERNEL_DENIAL ACTION_EXECUTED 
                       ACTION_FAILED SOVEREIGNTY_VIOLATION USER_CONFIRMATION

struct SecurityEvent
    id::UUID
    timestamp::DateTime
    event_type::SecurityEventType
    actor::String  # "brain", "kernel", "executor"
    details::Dict{String, Any}
    decision::Symbol  # :approved, :denied, :stopped
end

const AUDIT_LOG = Vector{SecurityEvent}()
const MAX_AUDIT_SIZE = 10000

function audit_event(event_type::SecurityEventType, actor::String, details::Dict)
    event = SecurityEvent(uuid4(), now(), event_type, actor, details, :pending)
    push!(AUDIT_LOG, event)
    
    # Rotate if too large
    if length(AUDIT_LOG) > MAX_AUDIT_SIZE
        splice!(AUDIT_LOG, 1:length(AUDIT_LOG)-MAX_AUDIT_SIZE)
    end
    
    # Sync to disk for persistence
    _persist_audit()
    
    return event
end

end  # module
```

#### B.5 Testing Strategy

- **Unit:** Test `Kernel.approve()` with various proposal/world combinations
- **Integration:** Test full cycle with brain → kernel → executor
- **Security:** Test that bypassing kernel raises sovereignty violation

---

### C. Real System Observation Integration

**Current State:** `observe_cpu.jl` reads real metrics, BUT `SystemIntegrator` uses mock values (0.5, 0.6)

**Required Changes:**

#### C.1 Create SystemMonitor Module

**New File:** `jarvis/src/monitoring/SystemMonitor.jl`

```julia
module SystemMonitor

export get_system_observation, get_cpu_usage, get_memory_usage, 
       get_disk_io, get_network_stats, get_process_count

using Dates

"""
    SystemObservation - Real system metrics
"""
struct SystemObservation
    timestamp::DateTime
    cpu_load::Float32          # [0, 1]
    memory_usage::Float32      # [0, 1] 
    disk_read_bytes::Int64
    disk_write_bytes::Int64
    network_rx_bytes::Int64
    network_tx_bytes::Int64
    process_count::Int
    thread_count::Int
end

"""
    get_system_observation()::SystemObservation
Collect real system metrics using multiple sources.
"""
function get_system_observation()::SystemObservation
    return SystemObservation(
        now(),
        get_cpu_usage(),
        get_memory_usage(),
        get_disk_read(),
        get_disk_write(),
        get_network_rx(),
        get_network_tx(),
        get_process_count(),
        get_thread_count()
    )
end

function get_cpu_usage()::Float32
    try
        # Linux: Read /proc/loadavg
        if isfile("/proc/loadavg")
            load = split(readchomp("/proc/loadavg"))[1]
            load1 = parse(Float64, load)
            # Normalize by CPU count
            return Float32(clamp(load1 / Sys.CPU_THREADS, 0.0, 1.0))
        end
    catch
    end
    return 0.5f0  # Safe default
end

function get_memory_usage()::Float32
    try
        if isfile("/proc/meminfo")
            data = readchomp("/proc/meminfo")
            total = 0.0
            available = 0.0
            
            for line in split(data, '\n')
                m = match(r"^(MemTotal|MemAvailable):\s+(\d+)", line)
                if m !== nothing
                    val = parse(Int64, m.captures[2]) * 1024  # kB to bytes
                    if m.captures[1] == "MemTotal"
                        total = val
                    else
                        available = val
                    end
                end
            end
            
            if total > 0
                return Float32(1.0 - (available / total))
            end
        end
    catch
    end
    return 0.5f0
end

# ... similar for disk and network ...

end  # module
```

#### C.2 Replace Mock Metrics in SystemIntegrator

**File:** `jarvis/src/SystemIntegrator.jl`

**Lines:** ~485-520 (`_collect_perception`)

**Change:**
```julia
# BEFORE (mock):
metrics = Dict{String, Float32}(
    "cpu_load" => 0.5f0,  # MOCK!
    "memory_usage" => 0.6f0,  # MOCK!
    ...
)

# AFTER (real):
function _collect_perception(system::JarvisSystem)::PerceptionVector
    obs = SystemMonitor.get_system_observation()
    
    return PerceptionVector(
        obs.cpu_load,
        obs.memory_usage,
        obs.disk_read_bytes / (obs.disk_read_bytes + obs.disk_write_bytes + 1),
        obs.network_latency,
        0.0f0,  # severity - from trust manager
        0,  # threats - from trust manager
        obs.process_count,
        obs.thread_count,
        system.trust_level,
        0.5f0,  # energy
        0.8f0,  # confidence
        0.5f0   # user_activity
    )
end
```

#### C.3 Implement Capability-Based Observation Layer

**File:** `adaptive-kernel/capabilities/observe_system.jl` (new or expand existing)

```julia
# Unified observation that delegates to SystemMonitor
function observe_system(params::Dict)::Dict
    obs = SystemMonitor.get_system_observation()
    
    return Dict(
        "cpu_load" => obs.cpu_load,
        "memory_usage" => obs.memory_usage,
        "disk_io_rate" => (obs.disk_read_bytes + obs.disk_write_bytes),
        "network_throughput" => (obs.network_rx_bytes + obs.network_tx_bytes),
        "process_count" => obs.process_count,
        "thread_count" => obs.thread_count,
        "timestamp" => string(obs.timestamp)
    )
end
```

#### C.4 Security Considerations

**Prevent Observation Privilege Escalation:**

1. **Rate Limiting:** Max 1 observation per 100ms
2. **Resource Caps:** Max 1MB memory for observation cache
3. **No Sensitive Data Exposure:** Observation data sanitized before storage
4. **Audit:** Log all observation requests

#### C.5 Testing Strategy

- **Unit:** Test each SystemMonitor function with mock /proc files
- **Integration:** Verify real metrics flow through to brain
- **Performance:** Ensure observation collection < 50ms

---

### D. Voice Module (STT/TTS)

**Current State:** Not implemented - CommunicationBridge exists but no STT/TTS

**Required Implementation:**

#### D.1 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      VOICE MODULE                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐  │
│  │  Audio In   │────▶│   Whisper   │────▶│   Text      │  │
│  │  (PortAudio)│     │   (STT)     │     │   Output    │  │
│  └─────────────┘     └─────────────┘     └──────┬──────┘  │
│                                                   │          │
│                                                   ▼          │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐  │
│  │  Text       │────▶│   LLM       │────▶│   Intent    │  │
│  │  Input      │     │   Process   │     │   Parser    │  │
│  └─────────────┘     └─────────────┘     └──────┬──────┘  │
│                                                   │          │
│                                                   ▼          │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐  │
│  │   Intent    │────▶│   Jarvis    │────▶│   Action    │  │
│  │   Response  │     │   Response  │     │   Execute   │  │
│  └─────────────┘     └──────┬──────┘     └─────────────┘  │
│                              │                              │
│                              ▼                              │
│                     ┌─────────────────┐                    │
│                     │  ElevenLabs     │                    │
│                     │  (TTS)          │                    │
│                     └────────┬────────┘                    │
│                              │                              │
│                              ▼                              │
│                     ┌─────────────────┐                    │
│                     │  Audio Out      │                    │
│                     │  (PortAudio)    │                    │
│                     └─────────────────┘                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### D.2 Whisper STT Integration

**New File:** `jarvis/src/voice/WhisperSTT.jl`

```julia
module WhisperSTT

export transcribe, WhisperConfig

using HTTP
using JSON
using Base64

struct WhisperConfig
    api_url::String
    model::String
    language::String
    timeout::Int
    
    WhisperConfig(;
        api_url=getenv("WHISPER_API_URL", "https://api.openai.com/v1/audio/transcriptions"),
        model="whisper-1",
        language="en",
        timeout=30
    ) = new(api_url, model, language, timeout)
end

"""
    transcribe(audio_data::Vector{UInt8}, config::WhisperConfig)::String
Transcribe audio to text using Whisper API.
"""
function transcribe(audio_data::Vector{UInt8}, config::WhisperConfig)::String
    # Convert audio to base64
    audio_b64 = base64encode(audio_data)
    
    # Build multipart request
    body = HTTP.Form(...)
    
    response = HTTP.post(
        config.api_url,
        [
            "Authorization" => "Bearer $(getenv('OPENAI_API_KEY'))",
            "Content-Type" => "multipart/form-data"
        ];
        body=body,
        timeout=config.timeout
    )
    
    result = JSON.parse(String(response.body))
    return result["text"]
end

"""
    Stream transcribe for real-time processing.
"""
function stream_transcribe(audio_stream, config::WhisperConfig, callback::Function)
    buffer = Vector{UInt8}()
    
    while !eof(audio_stream)
        chunk = read(audio_stream, 4096)
        append!(buffer, chunk)
        
        # Process when we have enough audio (~1 second)
        if length(buffer) > 16000 * 2  # 1 second of 16kHz mono
            text = transcribe(buffer, config)
            callback(text)
            empty!(buffer)
        end
    end
end

end  # module
```

#### D.3 ElevenLabs TTS Integration

**New File:** `jarvis/src/voice/ElevenLabsTTS.jl`

```julia
module ElevenLabsTTS

export speak, TTSConfig

using HTTP
using JSON

struct TTSConfig
    api_url::String
    voice_id::String
    model::String
    timeout::Int
    
    TTSConfig(;
        api_url="https://api.elevenlabs.io/v1",
        voice_id=getenv("ELEVENLABS_VOICE_ID", "21m00Tcm4TlvDq8ikWAM"),
        model="eleven_monolingual_v1",
        timeout=30
    ) = new(api_url, voice_id, model, timeout)
end

"""
    speak(text::String, config::TTSConfig)::Vector{UInt8}
Generate speech audio from text.
"""
function speak(text::String, config::TTSConfig)::Vector{UInt8}
    url = "$(config.api_url)/text-to-speech/$(config.voice_id)"
    
    body = JSON.json(Dict(
        "text" => text,
        "model_id" => config.model,
        "voice_settings" => Dict(
            "stability" => 0.5,
            "similarity_boost" => 0.8
        )
    ))
    
    response = HTTP.post(
        url,
        [
            "xi-api-key" => getenv("ELEVENLABS_API_KEY"),
            "Content-Type" => "application/json"
        ];
        body=body,
        timeout=config.timeout
    )
    
    return response.body
end

"""
    stream_speak - Generate and stream audio for low latency.
"""
function stream_speak(text::String, config::TTSConfig, output_io::IO)
    url = "$(config.api_url)/text-to-speech/$(config.voice_id)/stream"
    
    # ... stream implementation ...
end

end  # module
```

#### D.4 Voice Activity Detection

**New File:** `jarvis/src/voice/VoiceActivityDetector.jl`

```julia
module VAD

export detect_speech, EnergyVAD

"""
    EnergyVAD - Simple energy-based voice activity detection
"""
mutable struct EnergyVAD
    threshold::Float32
    min_speech_duration::Float32  # seconds
    min_silence_duration::Float32  # seconds
    
    EnergyVAD(;threshold=0.01f0, min_speech=0.3, min_silence=0.5) = 
        new(threshold, min_speech, min_silence)
end

"""
    detect_speech(audio_chunk::Vector{Float32}, vad::EnergyVAD)::Bool
Detect if audio chunk contains speech based on energy level.
"""
function detect_speech(audio_chunk::Vector{Float32}, vad::EnergyVAD)::Bool
    energy = sum(x->x^2, audio_chunk) / length(audio_chunk)
    return energy > vad.threshold
end

end  # module
```

#### D.5 Secure API Key Management

All voice API keys must be loaded from environment:
```bash
# Required environment variables
export WHISPER_API_URL="https://api.openai.com/v1/audio/transcriptions"
export OPENAI_API_KEY="sk-..."
export ELEVENLABS_API_KEY="..."
export ELEVENLABS_VOICE_ID="..."
```

#### D.6 Latency Mitigation

1. **Pre-buffer:** Start TTS generation while executing action
2. **Chunk streaming:** Stream audio in chunks for perceived latency
3. **Wake word:** Use lightweight wake word detection to trigger processing
4. **Target:** End-to-end voice latency < 1 second

#### D.7 Testing Strategy

- **Unit:** Test Whisper/ElevenLabs with mocked API responses
- **Integration:** Test full voice pipeline with real audio
- **Performance:** Target < 500ms STT, < 500ms TTS

---

### E. Vision Module (VLM)

**Current State:** Not implemented

**Required Implementation:**

#### E.1 GPT-4V / Claude Vision Integration

**New File:** `jarvis/src/vision/VisionProcessor.jl`

```julia
module VisionProcessor

export analyze_image, capture_screen, VisionConfig

using HTTP
using JSON
using Base64

struct VisionConfig
    provider::Symbol  # :openai or :anthropic
    model::String
    max_tokens::Int
    timeout::Int
    
    VisionConfig(;provider=:openai, model="gpt-4o", max_tokens=500, timeout=30) = 
        new(provider, model, max_tokens, timeout)
end

"""
    analyze_image(image_data::Vector{UInt8}, prompt::String, config::VisionConfig)::String
Analyze image and return description.
"""
function analyze_image(image_data::Vector{UInt8}, prompt::String, config::VisionConfig)::String
    image_b64 = base64encode(image_data)
    
    if config.provider == :openai
        return _analyze_openai(image_b64, prompt, config)
    else
        return _analyze_anthropic(image_b64, prompt, config)
    end
end

function _analyze_openai(image_b64::String, prompt::String, config::VisionConfig)::String
    body = JSON.json(Dict(
        "model" => config.model,
        "messages" => [
            Dict(
                "role" => "user",
                "content" => [
                    Dict("type" => "text", "text" => prompt),
                    Dict(
                        "type" => "image_url",
                        "image_url" => Dict("url" => "data:image/jpeg;base64,$image_b64")
                    )
                ]
            )
        ],
        "max_tokens" => config.max_tokens
    ))
    
    response = HTTP.post(
        "https://api.openai.com/v1/chat/completions",
        ["Authorization" => "Bearer $(getenv('OPENAI_API_KEY'))",
         "Content-Type" => "application/json"];
        body=body,
        timeout=config.timeout
    )
    
    result = JSON.parse(String(response.body))
    return result["choices"][1]["message"]["content"]
end

"""
    capture_screen()::Vector{UInt8}
Capture screenshot for desktop analysis.
"""
function capture_screen()::Vector{UInt8}
    # Platform-specific implementation
    # Linux: Use import from ImageMagick or maim
    if Sys.islinux()
        # Save to temp file then read
        tmpfile = "/tmp/jarvis_screenshot_$(uuid4()).png"
        run(`import -window root $tmpfile`)
        data = read(tmpfile)
        rm(tmpfile)
        return data
    end
    error("Screenshot not implemented for $(Sys.KERNEL)")
end

end  # module
```

#### E.2 Image Preprocessing Pipeline

```julia
"""
    preprocess_image(image_data::Vector{UInt8})::Vector{UInt8}
Resize and compress image for API efficiency.
"""
function preprocess_image(image_data::Vector{UInt8})::Vector{UInt8}
    # 1. Decode
    img = load_image(image_data)
    
    # 2. Resize to max 1024x1024
    img = resize_image(img, 1024, 1024)
    
    # 3. Compress to JPEG quality 85
    return encode_jpeg(img, 85)
end
```

#### E.3 Visual Context Memory

**File:** `jarvis/src/memory/VisualMemory.jl`

```julia
"""
    VisualMemory - Stores image embeddings for multi-image conversations
"""
mutable struct VisualMemory
    entries::Vector{VisualEntry}
    max_entries::Int
    
    VisualMemory(max=10) = new(Vector{VisualEntry}(), max)
end

struct VisualEntry
    id::UUID
    timestamp::DateTime
    description::String
    embedding::Vector{Float32}  # For similarity search
end

function store_visual!(memory::VisualMemory, description::String, embedding::Vector{Float32})
    entry = VisualEntry(uuid4(), now(), description, embedding)
    push!(memory.entries, entry)
    
    # Rotate if too many
    if length(memory.entries) > memory.max_entries
        popfirst!(memory.entries)
    end
end
```

#### E.4 Risk Filtering Layer

**Security:** All vision input must pass through trust manager before processing
```julia
function analyze_image(image_data, prompt)
    # Pre-check: Is this request allowed?
    TrustManager.check_permission("vision", user_level) || throw(SecurityError())
    
    # Process
    result = VisionProcessor.analyze_image(image_data, prompt)
    
    # Post-check: Sanitize output
    return sanitize_output(result)
end
```

#### E.5 Testing Strategy

- **Unit:** Test with mocked API responses
- **Integration:** Test with real images
- **Performance:** Target < 3s for image analysis

---

### F. OpenClaw Tooling Integration

**Current State:** `jarvis/src/bridge/OpenClawBridge.jl` exists but not wired

**Required Implementation:**

#### F.1 Proper Include and Registration

**File:** `jarvis/src/SystemIntegrator.jl`

**Lines:** 15-25 (module includes)

**Add:**
```julia
include("bridge/OpenClawBridge.jl")
using .OpenClawBridge

# In JarvisConfig:
struct JarvisConfig
    # ... existing fields ...
    openclaw_enabled::Bool
    openclaw_socket_path::String
end
```

#### F.2 Tool Registry Binding

**File:** `jarvis/src/bridge/OpenClawBridge.jl` (expand)

```julia
"""
    ToolRegistry - Discovers and registers OpenClaw tools
"""
mutable struct ToolRegistry
    tools::Dict{String, ToolDefinition}
    capabilities::Vector{String}  # IDs that map to our capabilities
    
    ToolRegistry() = new(Dict(), [
        "log_status", "list_processes", "garbage_collect",
        "optimize_disk", "throttle_cpu", "emergency_shutdown",
        "observe_cpu", "observe_memory", "observe_filesystem",
        "safe_shell", "safe_http_request", "write_file"
    ])
end

function discover_tools(registry::ToolRegistry)::Vector{ToolDefinition}
    # Connect to OpenClaw daemon and request tool list
    socket_path = getenv("OPENCLAW_SOCKET", "/tmp/openclaw.sock")
    
    # Send discovery request
    request = JSON.json(Dict("method" => "tools.list", "params" => Dict()))
    response = openclaw_request(socket_path, request)
    
    tools = ToolDefinition[]
    for tool_json in response["result"]["tools"]
        tool = ToolDefinition(
            tool_json["name"],
            tool_json["description"],
            tool_json["parameters"],
            tool_json["risk_level"]
        )
        registry.tools[tool.name] = tool
        push!(tools, tool)
    end
    
    return tools
end
```

#### F.3 Execution Sandbox

**New File:** `jarvis/src/sandbox/ToolSandbox.jl`

```julia
module ToolSandbox

export execute_in_sandbox, SandboxConfig, ToolResult

using HTTP
using JSON
using Base64

struct SandboxConfig
    timeout::Int        # Max execution time (seconds)
    memory_limit::Int   # Max memory in MB
    network_allowed::Bool
    shell_allowed::Bool
    
    SandboxConfig(;timeout=30, memory_limit=256, network_allowed=true, shell_allowed=false) =
        new(timeout, memory_limit, network_allowed, shell_allowed)
end

"""
    execute_in_sandbox(tool_name, params, config)::ToolResult
Execute tool in isolated sandbox with timeout and resource limits.
"""
function execute_in_sandbox(tool_name, params, config::SandboxConfig)::ToolResult
    start_time = time()
    
    # Build sandbox request
    request = Dict(
        "method" => "tools.execute",
        "params" => Dict(
            "name" => tool_name,
            "parameters" => params,
            "timeout" => config.timeout,
            "limits" => Dict(
                "memory_mb" => config.memory_limit,
                "network" => config.network_allowed,
                "shell" => config.shell_allowed
            )
        )
    )
    
    # Execute with timeout
    try
        response = openclaw_request(OPENCLAW_SOCKET, JSON.json(request); timeout=config.timeout)
        
        elapsed = time() - start_time
        
        return ToolResult(
            success=true,
            result=response["result"],
            error=nothing,
            execution_time=elapsed,
            resource_usage=response["result"]["resources"]
        )
    catch e
        elapsed = time() - start_time
        return ToolResult(
            success=false,
            result=nothing,
            error=string(e),
            execution_time=elapsed,
            resource_usage=Dict()
        )
    end
end

end  # module
```

#### F.4 Capability Risk Classification

**File:** `jarvis/src/trust/RiskClassifier.jl`

```julia
"""
    Risk levels for tools:
    - LOW: Read-only, no side effects
    - MEDIUM: Limited side effects, reversible
    - HIGH: Significant changes, requires confirmation
    - CRITICAL: System-level changes, requires explicit approval
"""
@enum RiskLevel LOW MEDIUM HIGH CRITICAL

const TOOL_RISK_MAP = Dict{String, RiskLevel}(
    "log_status" => LOW,
    "list_processes" => LOW,
    "observe_cpu" => LOW,
    "observe_memory" => LOW,
    "observe_filesystem" => LOW,
    "safe_http_request" => MEDIUM,
    "safe_shell" => HIGH,
    "write_file" => HIGH,
    "garbage_collect" => MEDIUM,
    "optimize_disk" => HIGH,
    "throttle_cpu" => CRITICAL,
    "emergency_shutdown" => CRITICAL
)

function get_tool_risk(tool_name::String)::RiskLevel
    return get(TOOL_RISK_MAP, tool_name, HIGH)  # Default to HIGH
end
```

#### F.5 Testing Strategy

- **Unit:** Test tool registry with mocked OpenClaw responses
- **Integration:** Test with real OpenClaw daemon
- **Security:** Test sandbox isolation

---

### G. Persistence & Checkpointing

**Current State:** Vector store exists in-memory only (no persistence)

**Required Implementation:**

#### G.1 Vector Store Persistence

**File:** `jarvis/src/memory/VectorMemory.jl` (expand)

```julia
"""
    save_vector_store(store::VectorStore, path::String)
Persist vector store to disk.
"""
function save_vector_store(store::VectorStore, path::String)
    data = Dict(
        "entries" => [to_dict(e) for e in store.entries],
        "collection_indices" => store.collection_indices,
        "ef_construction" => store.ef_construction,
        "m" => store.m
    )
    
    open(path, "w") do f
        JSON.print(f, data)
    end
    
    @info "Vector store saved" path=path entries=length(store.entries)
end

"""
    load_vector_store(path::String)::VectorStore
Load vector store from disk.
"""
function load_vector_store(path::String)::VectorStore
    open(path, "r") do f
        data = JSON.parse(f)
    end
    
    entries = [from_dict(SemanticEntry, e) for e in data["entries"]]
    
    return VectorStore(
        entries=entries,
        collection_indices=data["collection_indices"],
        ef_construction=data["ef_construction"],
        m=data["m"]
    )
end
```

#### G.2 Full System Checkpoint

**New File:** `jarvis/src/persistence/CheckpointManager.jl`

```julia
module CheckpointManager

export checkpoint, restore, AutoSave

using UUIDs
using Dates

"""
    SystemSnapshot - Complete system state for crash recovery
"""
struct SystemSnapshot
    id::UUID
    timestamp::DateTime
    vector_store_path::String
    semantic_memory_path::String
    kernel_state_path::String
    brain_state_path::String
    config_hash::String
end

"""
    checkpoint(system::JarvisSystem, base_path::String)
Create full system snapshot.
"""
function checkpoint(system::JarvisSystem, base_path::String)
    snapshot_id = uuid4()
    timestamp = now()
    
    # Paths for each component
    vs_path = joinpath(base_path, "vector_store_$snapshot_id.json")
    sm_path = joinpath(base_path, "semantic_memory_$snapshot_id.json")
    ks_path = joinpath(base_path, "kernel_state_$snapshot_id.jls")
    br_path = joinpath(base_path, "brain_state_$snapshot_id.bson")
    
    # Save each component
    VectorMemory.save_vector_store(system.vector_store, vs_path)
    SemanticMemory.save(system.semantic_memory, sm_path)
    serialize(ks_path, system.kernel.state)
    BrainTrainer.brain_checkpoint(system.brain, br_path)
    
    # Save metadata
    config_hash = sha256(serialize(system.config))
    snapshot = SystemSnapshot(
        snapshot_id, timestamp, vs_path, sm_path, ks_path, br_path,
        bytes2hex(config_hash)[1:16]
    )
    
    # Save snapshot index
    index_path = joinpath(base_path, "snapshot_index.json")
    _update_index(index_path, snapshot)
    
    @info "Checkpoint created" id=snapshot_id timestamp=timestamp
    
    return snapshot
end

"""
    restore(base_path::String)::JarvisSystem
Restore system from latest checkpoint.
"""
function restore(base_path::String)::JarvisSystem
    index_path = joinpath(base_path, "snapshot_index.json")
    snapshots = JSON.parsefile(index_path)
    
    # Find latest
    latest = sort(snapshots; by=s->s["timestamp"], rev=true)[1]
    
    # Restore components
    vs = VectorMemory.load_vector_store(latest["vector_store_path"])
    sm = SemanticMemory.load(latest["semantic_memory_path"])
    kernel_state = deserialize(latest["kernel_state_path"])
    brain = BrainTrainer.restore_brain(latest["brain_state_path"])
    
    # Reconstruct system (simplified)
    return JarvisSystem(...; 
        vector_store=vs,
        semantic_memory=sm,
        kernel_state=kernel_state,
        brain=brain
    )
end

end  # module
```

#### G.3 Crash Recovery Strategy

1. **Startup:** Check for existing checkpoints
2. **Auto-recovery:** If crash detected, prompt user to restore
3. **Incremental saves:** Every N cycles, save incrementally
4. **Rotation:** Keep last 5 checkpoints

#### G.4 Testing Strategy

- **Unit:** Test serialization/deserialization
- **Integration:** Test checkpoint/restore cycle
- **Recovery:** Simulate crash and verify recovery

---

### H. Configuration & Secrets Management

**Current State:** No proper configuration system

**Required Implementation:**

#### H.1 Environment Variable Schema

**File:** `.env.example`

```bash
# ===========================================
# JARVIS ENVIRONMENT CONFIGURATION
# ===========================================

# LLM Configuration
OPENAI_API_KEY="sk-..."
ANTHROPIC_API_KEY="sk-ant-..."
LLM_MODEL="gpt-4o"
LLM_TEMPERATURE="0.7"
MAX_TOKENS="2000"

# Voice Configuration
WHISPER_API_URL="https://api.openai.com/v1/audio/transcriptions"
ELEVENLABS_API_KEY="..."
ELEVENLABS_VOICE_ID="21m00Tcm4TlvDq8ikWAM"

# Vision Configuration
VISION_PROVIDER="openai"  # or "anthropic"
VISION_MODEL="gpt-4o"

# OpenClaw Configuration
OPENCLAW_SOCKET="/tmp/openclaw.sock"
OPENCLAW_ENABLED="true"

# System Configuration
JARVIS_DATA_DIR="/var/lib/jarvis"
JARVIS_LOG_LEVEL="info"
JARVIS_PORT="8080"

# Security
TRUST_LEVEL_DEFAULT="3"
CONFIRMATION_REQUIRED_LEVEL="high"
AUDIT_LOG_PATH="/var/log/jarvis/audit.log"

# Persistence
CHECKPOINT_INTERVAL="100"
CHECKPOINT_DIR="/var/lib/jarvis/checkpoints"
AUTO_RESTORE="true"
```

#### H.2 Configuration Manager

**New File:** `jarvis/src/config/ConfigManager.jl`

```julia
module ConfigManager

export load_config, get_config, validate_config, reload_config!

using YAML
using JSON

"""
    load_config(config_file::String)::JarvisConfig
Load configuration from YAML/TOML file.
"""
function load_config(config_file::String)::JarvisConfig
    if endswith(config_file, ".yaml") || endswith(config_file, ".yml")
        return _load_yaml(config_file)
    elseif endswith(config_file, ".toml")
        return _load_toml(config_file)
    else
        error("Unsupported config format: $config_file")
    end
end

function _load_yaml(path::String)::JarvisConfig
    data = YAML.load_file(path)
    
    # Override with environment variables
    data = _apply_env_overrides(data)
    
    return JarvisConfig(;
        llm=LLMConfig(;
            api_key=get(data, "llm", Dict())["api_key"],
            model=get(data, "llm", Dict())["model"]
        ),
        vector_store_path=get(data, "vector_store_path", "./jarvis_vector_store.json"),
        kernel_config_path=get(data, "kernel_config_path", "./adaptive-kernel/config.json"),
        log_level=Symbol(get(data, "log_level", "info"))
    )
end

function _apply_env_overrides(config::Dict)::Dict
    # Check for JARVIS_* environment variables
    for (key, value) in ENV
        if startswith(key, "JARVIS_")
            config[lowercase(key[8:end])] = value
        end
    end
    return config
end

"""
    validate_config(config::JarvisConfig)::Bool
Validate configuration at startup.
"""
function validate_config(config::JarvisConfig)::Bool
    errors = String[]
    
    # Check required fields
    if config.llm.api_key == ""
        push!(errors, "LLM API key is required")
    end
    
    # Validate paths exist or can be created
    vs_dir = dirname(config.vector_store_path)
    if !isdir(vs_dir) && vs_dir != "."
        push!(errors, "Vector store directory does not exist: $vs_dir")
    end
    
    if !isempty(errors)
        @error "Configuration validation failed" errors=errors
        return false
    end
    
    return true
end

end  # module
```

#### H.3 Secure Secrets Vault

**New File:** `jarvis/src/security/SecretVault.jl`

```julia
module SecretVault

export get_secret, set_secret!, clear_vault

using NaCl.jl
using Base64

"""
    SecretVault - Encrypted storage for sensitive data
"""
mutable struct SecretVault
    path::String
    key::Vector{UInt8}  # 32-byte key
    
    SecretVault(path="/var/lib/jarvis/secrets.enc") = 
        new(path, _derive_key())
end

function _derive_key()::Vector{UInt8}
    # Derive from machine-specific identifier
    machine_id = _get_machine_id()
    return sha256(machine_id)[1:32]
end

function get_secret(vault::SecretVault, key::String)::Union{String, Nothing}
    !isfile(vault.path) && return nothing
    
    encrypted = open(vault.path, "r") do f
        read(f)
    end
    
    decrypted = NaCl.secretbox_open(encrypted[24:end], encrypted[1:24], vault.key)
    secrets = JSON.parse(String(decrypted))
    
    return get(secrets, key, nothing)
end

function set_secret!(vault::SecretVault, key::String, value::String)
    secrets = isfile(vault.path) ? JSON.parsefile(vault.path) : Dict()
    secrets[key] = value
    
    plaintext = JSON.json(secrets)
    nonce = rand(UInt8, 24)
    encrypted = nonce * NaCl.secretbox(plaintext, nonce, vault.key)
    
    open(vault.path, "w") do f
        write(f, encrypted)
    end
end

end  # module
```

#### H.4 Multi-Environment Config

```
jarvis/
├── config/
│   ├── defaults.yaml      # All default values
│   ├── development.yaml    # Dev overrides
│   ├── staging.yaml        # Staging overrides  
│   └── production.yaml     # Production overrides
```

**Loading precedence:** defaults → env-specific → env vars

#### H.5 Testing Strategy

- **Unit:** Test config loading
- **Security:** Test vault encryption
- **Integration:** Test environment-specific configs

---

### I. Trust & Confirmation Model

**Current State:** Basic TrustLevel enum exists in `jarvis/src/types.jl`

**Required Implementation:**

#### I.1 Risk Classification Engine

**File:** `jarvis/src/trust/RiskClassifier.jl` (expand)

```julia
"""
    classify_risk(proposal::ActionProposal)::RiskLevel
Classify action risk based on proposal attributes.
"""
function classify_risk(proposal::ActionProposal)::RiskLevel
    # Check tool risk
    tool_risk = get_tool_risk(proposal.capability_id)
    
    # Check confidence (low confidence = higher effective risk)
    confidence_factor = proposal.confidence < 0.7 ? 1 : 0
    
    # Check impact
    impact_factor = proposal.impact_estimate > 0.7 ? 1 : 0
    
    effective_risk = max(tool_risk, confidence_factor, impact_factor)
    
    return effective_risk
end
```

#### I.2 User Confirmation Gate

**File:** `jarvis/src/trust/ConfirmationGate.jl`

```julia
module ConfirmationGate

export requires_confirmation, request_confirmation, confirm_action

"""
    requires_confirmation(risk_level::RiskLevel, trust_level::Int)::Bool
Determine if action requires user confirmation.
"""
function requires_confirmation(risk_level::RiskLevel, trust_level::Int)::Bool
    # Higher trust = fewer confirmations
    thresholds = Dict(
        0 => [LOW],           # Blocked - no actions
        1 => [LOW, MEDIUM],  # Minimal - confirm medium+
        2 => [LOW, MEDIUM, HIGH],  # Standard - confirm high+
        3 => [LOW, MEDIUM],  # Elevated - confirm medium (reduced high)
        4 => [LOW]           # Full - only confirm low
    )
    
    threshold_set = get(thresholds, trust_level, [LOW])
    return risk_level ∉ threshold_set
end

"""
    ConfirmationRequest - Suspends execution pending user response
"""
mutable struct ConfirmationRequest
    id::UUID
    proposal::ActionProposal
    risk_level::RiskLevel
    prompt::String
    timeout::Int  # seconds
    channel::Symbol  # :console, :api, :voice
end

# Global pending confirmations
const PENDING_CONFIRMATIONS = Dict{UUID, ConfirmationRequest}()

function request_confirmation(proposal::ActionProposal, risk_level::RiskLevel)::UUID
    request = ConfirmationRequest(
        uuid4(),
        proposal,
        risk_level,
        _generate_prompt(proposal, risk_level),
        30,
        :console
    )
    
    PENDING_CONFIRMATIONS[request.id] = request
    
    # Notify via configured channel
    _notify_user(request)
    
    return request.id
end

function confirm_action(request_id::UUID, confirmed::Bool)::Bool
    request = get(PENDING_CONFIRMATIONS, request_id, nothing)
    request === nothing && return false
    
    delete!(PENDING_CONFIRMATIONS, request_id)
    
    return confirmed
end

end  # module
```

#### I.3 Real-Time Trust Recalibration

**File:** `jarvis/src/trust/TrustManager.jl`

```julia
"""
    recalculate_trust!(system::JarvisSystem)
Adjust trust score based on recent action outcomes.
"""
function recalculate_trust!(system::JarvisSystem)
    recent_outcomes = get_recent_outcomes(system.semantic_memory, last(100))
    
    success_rate = mean(o.success for o in recent_outcomes)
    avg_confidence = mean(o.predicted_confidence for o in recent_outcomes)
    
    # Calculate new trust level
    new_trust = _calculate_trust_score(success_rate, avg_confidence)
    
    if new_trust != system.trust_level
        @info "Trust level adjusted" old=system.trust_level new=new_trust
        system.trust_level = new_trust
    end
end

function _calculate_trust_score(success_rate, avg_confidence)::Int
    # Weighted score: 60% success rate, 40% prediction accuracy
    score = (success_rate * 0.6 + avg_confidence * 0.4)
    
    # Map to trust levels 0-4
    if score < 0.2 return 0
    elseif score < 0.4 return 1
    elseif score < 0.6 return 2
    elseif score < 0.8 return 3
    else return 4
    end
end
```

#### I.4 Policy Overlays

**File:** `jarvis/src/trust/PolicyOverlay.jl`

```julia
"""
    PolicyOverlay - Runtime security policies
"""
@enum PolicyMode PERMISSIVE AUDIT STRICT PARANOID

mutable struct PolicyOverlay
    mode::PolicyMode
    blocked_tools::Set{String}
    required_confirmations::Set{String}
    rate_limits::Dict{String, Int}  # tool -> max per minute
end

function check_policy(overlay::PolicyOverlay, proposal::ActionProposal)::Bool
    # Blocked tools
    if proposal.capability_id in overlay.blocked_tools
        return false
    end
    
    # Rate limiting
    limit = get(overlay.rate_limits, proposal.capability_id, Inf)
    if _get_recent_count(proposal.capability_id) >= limit
        return false
    end
    
    return true
end
```

#### I.5 Testing Strategy

- **Unit:** Test risk classification
- **Integration:** Test confirmation flow
- **Security:** Test trust manipulation

---

### J. Error Handling & Recovery Architecture

**Current State:** Minimal error handling

**Required Implementation:**

#### J.1 Circuit Breaker Design

**New File:** `jarvis/src/error/CircuitBreaker.jl`

```julia
module CircuitBreaker

export CircuitBreaker, circuit_open, circuit_half_open, record_success!, record_failure!

using Dates

@enum CircuitState CLOSED OPEN HALF_OPEN

mutable struct CircuitBreaker
    name::String
    state::CircuitState
    failure_count::Int
    success_count::Int
    last_failure_time::DateTime
    threshold::Int        # Failures before opening
    timeout::Int          # Seconds before half-open
    half_open_successes::Int  # Successes needed to close
    
    CircuitBreaker(name; threshold=5, timeout=60) = 
        new(name, CLOSED, 0, 0, now(), threshold, timeout, 2)
end

"""
    circuit_open(breaker::CircuitBreaker)::Bool
Returns true if circuit is open (calls will fail fast).
"""
function circuit_open(breaker::CircuitBreaker)::Bool
    if breaker.state == CLOSED
        return false
    elseif breaker.state == OPEN
        # Check if timeout expired
        if (now() - breaker.last_failure_time).value > breaker.timeout * 1000
            breaker.state = HALF_OPEN
            breaker.success_count = 0
            return false
        end
        return true
    else  # HALF_OPEN
        return false
    end
end

function record_success!(breaker::CircuitBreaker)
    if breaker.state == HALF_OPEN
        breaker.success_count += 1
        if breaker.success_count >= breaker.half_open_successes
            breaker.state = CLOSED
            breaker.failure_count = 0
        end
    else
        breaker.failure_count = 0
    end
end

function record_failure!(breaker::CircuitBreaker)
    breaker.failure_count += 1
    breaker.last_failure_time = now()
    
    if breaker.failure_count >= breaker.threshold
        breaker.state = OPEN
    end
end

# Circuit breakers for each external dependency
const CIRCUITS = Dict{String, CircuitBreaker}()

function get_circuit(name::String)::CircuitBreaker
    return get!(CIRCUITS, name, CircuitBreaker(name))
end

end  # module
```

#### J.2 Component Health Monitoring

**New File:** `jarvis/src/monitoring/HealthMonitor.jl`

```julia
module HealthMonitor

export HealthStatus, ComponentHealth, get_health_status

@enum HealthState HEALTHY DEGRADED UNHEALTHY UNKNOWN

struct ComponentHealth
    name::String
    state::HealthState
    last_check::DateTime
    latency_ms::Float64
    error_message::Union{String, Nothing}
end

"""
    get_health_status()::Dict{String, ComponentHealth}
Check health of all system components.
"""
function get_health_status()::Dict{String, ComponentHealth}
    return Dict(
        "brain" => _check_brain_health(),
        "kernel" => _check_kernel_health(),
        "llm" => _check_llm_health(),
        "memory" => _check_memory_health(),
        "persistence" => _check_persistence_health()
    )
end

function _check_kernel_health()::ComponentHealth
    start = time()
    try
        # Simple kernel health check
        # In reality, check state, goals, etc.
        latency = (time() - start) * 1000
        
        if latency < 100
            return ComponentHealth("kernel", HEALTHY, now(), latency, nothing)
        elseif latency < 500
            return ComponentHealth("kernel", DEGRADED, now(), latency, "High latency")
        else
            return ComponentHealth("kernel", UNHEALTHY, now(), latency, "Very high latency")
        end
    catch e
        return ComponentHealth("kernel", UNHEALTHY, now(), 0, string(e))
    end
end

end  # module
```

#### J.3 Graceful Degradation Modes

**File:** `jarvis/src/error/Degradation.jl`

```julia
"""
    DegradationMode - System operating levels
"""
@enum DegradationMode FULL OPERATIONAL DEGRADED EMERGENCY

mutable struct DegradationManager
    current_mode::DegradationMode
    available_components::Set{String}
    fallback_strategies::Dict{String, Function}
    
    DegradationManager() = new(
        FULL,
        Set(["brain", "kernel", "llm", "memory", "voice", "vision"]),
        Dict()
    )
end

"""
    degrade_to!(manager::DegradationManager, mode::DegradationMode)
Transition to lower operational mode.
"""
function degrade_to!(manager::DegradationManager, mode::DegradationMode)
    manager.current_mode = mode
    
    if mode == DEGRADED
        # Disable non-essential features
        delete!(manager.available_components, "voice")
        delete!(manager.available_components, "vision")
    elseif mode == EMERGENCY
        # Only core cognition
        manager.available_components = Set(["kernel"])
    end
    
    @warn "System degraded" mode=mode
end

"""
    execute_with_fallback(manager::DegradationManager, component::String, 
                          primary::Function, fallback::Function)
Try primary, fall back if component unavailable.
"""
function execute_with_fallback(manager::DegradationManager, component::String,
                                primary::Function, fallback::Function)
    if component in manager.available_components
        try
            return primary()
        catch e
            if component == "brain"
                # Brain failure - use kernel heuristics
                return fallback()
            end
            rethrow()
        end
    else
        return fallback()
    end
end
```

#### J.4 Autonomous Self-Healing

```julia
"""
    SelfHealing - Automatic recovery behaviors
"""
function attempt_recovery(system::JarvisSystem, component::String)
    if component == "brain"
        _recover_brain(system)
    elseif component == "kernel"
        _recover_kernel(system)
    elseif component == "memory"
        _recover_memory(system)
    end
end

function _recover_brain(system::JarvisSystem)
    # Try to restore from checkpoint
    checkpoint_path = find_latest_checkpoint(CHECKPOINT_DIR)
    if checkpoint_path !== nothing
        BrainTrainer.restore_brain!(system.brain, checkpoint_path)
        @info "Brain recovered from checkpoint"
    else
        # Reinitialize brain
        system.brain.initialized = false
        system.brain.brain_core = ITHERISCore.init()
    end
end
```

#### J.5 Testing Strategy

- **Unit:** Test circuit breaker state transitions
- **Integration:** Test degradation modes
- **Chaos:** Simulate component failures

---

## 3. INTEGRATION SEQUENCING ROADMAP

### 3.1 Phased Implementation Order

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         IMPLEMENTATION SEQUENCE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PHASE 1: CORE INFRASTRUCTURE (Weeks 1-4)                                   │
│  ├─ 1.1  Fix Kernel Initialization ← CRITICAL                               │
│  ├─ 1.2  Wire Brain → Kernel → Executor flow                               │
│  ├─ 1.3  Real System Observations (SystemMonitor)                          │
│  └─ 1.4  Basic Audit Logging                                                │
│                                                                              │
│  PHASE 2: PERCEPTION MODULES (Weeks 5-8)                                    │
│  ├─ 2.1  Voice Module (Whisper STT)                                         │
│  ├─ 2.2  Voice Module (ElevenLabs TTS)                                      │
│  ├─ 2.3  Vision Module (GPT-4V)                                             │
│  └─ 2.4  OpenClaw Integration                                               │
│                                                                              │
│  PHASE 3: INFRASTRUCTURE (Weeks 9-12)                                       │
│  ├─ 3.1  Persistence & Checkpointing                                        │
│  ├─ 3.2  Configuration Manager                                              │
│  ├─ 3.3  Secret Vault                                                       │
│  ├─ 3.4  Trust & Confirmation                                               │
│  └─ 3.5  Error Handling & Recovery                                          │
│                                                                              │
│  PHASE 4: PRODUCTION HARDENING (Weeks 13-16)                                │
│  ├─ 4.1  Observability Stack                                                │
│  ├─ 4.2  CI/CD Pipeline                                                     │
│  ├─ 4.3  Security Audit                                                     │
│  └─ 4.4  Load Testing                                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DEPENDENCY GRAPH                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐                                                           │
│   │ Kernel       │ ◄── FOUNDATION (ALL other components depend on it)       │
│   │ Init         │                                                            │
│   └──────┬───────┘                                                            │
│          │                                                                    │
│   ┌──────┴───────┐    ┌──────────────┐                                      │
│   │              │    │ Brain →      │                                      │
│   │ Brain        │────│ Kernel       │ ◄── Requires Kernel                  │
│   │ Integration  │    │ Integration  │                                        │
│   └──────┬───────┘    └──────┬───────┘                                      │
│          │                   │                                                │
│          │            ┌──────┴───────┐                                        │
│          │            │              │                                        │
│   ┌──────┴───────┐   │ Executor     │                                        │
│   │              │   │ Integration  │                                        │
│   │ System       │   │ (OpenClaw)   │                                        │
│   │ Monitor      │   └──────────────┘                                        │
│   └──────┬───────┘                                                           │
│          │                                                                    │
│   ┌──────┴───────┐    ┌──────────────┐                                      │
│   │              │    │              │                                        │
│   │ Memory       │────│ Persistence  │                                        │
│   │ (Vector)     │    │              │                                        │
│   └──────────────┘    └──────────────┘                                        │
│                                                                              │
│   ┌──────────────────────────────────────────┐                              │
│   │                                          │                              │
│   │         Trust & Confirmation             │ ◄── Depends on everything  │
│   │                                          │                              │
│   └──────────────────────────────────────────┘                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Parallelizable Workstreams

| Workstream | Dependencies | Can Start |
|------------|--------------|-----------|
| Voice Module (STT) | None | Week 1 |
| Vision Module | None | Week 1 |
| Config Manager | None | Week 1 |
| Secret Vault | None | Week 1 |
| Persistence | None | Week 1 |
| Kernel Init | None | **Week 1** |
| Brain Integration | Kernel Init | Week 2 |
| System Monitor | Kernel Init | Week 2 |
| OpenClaw | Kernel Init | Week 2 |
| Trust Model | Kernel Init | Week 3 |
| Error Handling | All components | Week 5 |
| Observability | All components | Week 9 |

### 3.4 Risk Ranking

| Priority | Component | Risk | Rationale |
|----------|-----------|------|-----------|
| CRITICAL | Kernel Init Fix | HIGH | Blocks all execution |
| CRITICAL | Brain → Kernel Flow | HIGH | Security vulnerability if missed |
| HIGH | System Monitor | MEDIUM | Wrong metrics = wrong decisions |
| HIGH | Trust Model | HIGH | Safety critical |
| MEDIUM | Voice Module | MEDIUM | External API dependency |
| MEDIUM | Vision Module | MEDIUM | External API dependency |
| MEDIUM | Persistence | MEDIUM | Data loss risk |
| LOW | Config Manager | LOW | Can use defaults initially |
| LOW | Secret Vault | LOW | Can use env vars initially |

---

## 4. PRODUCTION HARDENING REQUIREMENTS

### 4.1 Observability Stack

**Metrics to Collect:**
- Cognitive cycle latency (target: <100ms p99)
- Action execution latency (per capability)
- Brain inference latency
- Kernel approval latency
- Memory usage (vector store entries)
- API call success/failure rates
- Trust level changes
- System resource usage

**Implementation:**
```julia
# jarvis/src/monitoring/Metrics.jl
module Metrics

export record_metric!, get_metrics, MetricsCollector

using StatsBase

mutable struct MetricsCollector
    counters::Dict{Symbol, Int}
    histograms::Dict{Symbol, Vector{Float64}}
    gauges::Dict{Symbol, Float64}
    
    MetricsCollector() = new(Dict(), Dict(), Dict())
end

function record_metric!(mc::MetricsCollector, name::Symbol, value::Float64)
    get!(mc.histograms, name, Float64[])
    push!(mc.histograms[name], value)
    
    # Keep only last 1000 values
    if length(mc.histograms[name]) > 1000
        popfirst!(mc.histograms[name])
    end
end

function get_metrics(mc::MetricsCollector, name::Symbol)::Dict
    histogram = get(mc.histograms, name, Float64[])
    return Dict(
        "count" => length(histogram),
        "mean" => mean(histogram),
        "p50" => median(histogram),
        "p95" => percentile(histogram, 95),
        "p99" => percentile(histogram, 99)
    )
end

end  # module
```

### 4.2 Structured Logging Standard

```
# Log Format (JSON)
{
  "timestamp": "2026-02-26T03:27:00.000Z",
  "level": "INFO",
  "component": "kernel",
  "event": "approval",
  "message": "Action approved",
  "data": {
    "proposal_id": "uuid",
    "capability": "observe_cpu",
    "confidence": 0.9,
    "risk": "low"
  },
  "trace_id": "uuid"
}
```

### 4.3 Metrics Dashboard Model

**Key Dashboards:**

1. **System Health**
   - Uptime
   - Component health status
   - Error rates

2. **Cognitive Performance**
   - Cycle latency
   - Brain confidence distribution
   - Kernel approval rate

3. **Resource Usage**
   - Memory (heap)
   - Vector store size
   - API rate limits

4. **Trust & Safety**
   - Trust level over time
   - Confirmation requests
   - Blocked actions

### 4.4 Chaos Testing Plan

**Scenarios:**

1. **Brain Failure:** Kill brain process, verify kernel fallback
2. **Kernel Failure:** Nullify kernel state, verify sovereignty violation
3. **Memory Exhaustion:** Fill vector store, verify graceful degradation
4. **API Failures:** Mock API timeouts, verify circuit breakers
5. **Trust Manipulation:** Inject false outcomes, verify trust recalibration

### 4.5 Load Testing Targets

| Metric | Target | Threshold |
|--------|--------|-----------|
| Cycle throughput | 10 cycles/sec | 5 cycles/sec |
| Cycle latency (p99) | <100ms | <500ms |
| Memory (steady state) | <500MB | <1GB |
| API latency (p99) | <2s | <5s |
| Error rate | <0.1% | <1% |

### 4.6 Security Audit Checklist

- [ ] All API keys in vault, not code
- [ ] Sovereignty invariant verified
- [ ] Audit log immutable
- [ ] Input sanitization
- [ ] Rate limiting enforced
- [ ] Sandboxing verified
- [ ] No privilege escalation paths

### 4.7 Secrets Rotation Plan

1. **API Keys:** Rotate every 90 days
2. **Encryption Keys:** Rotate every 180 days
3. **Certificates:** Rotate annually

### 4.8 CI/CD Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          CI/CD PIPELINE                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐             │
│   │  Commit  │───▶│   Build  │───▶│   Test   │───▶│  Deploy  │             │
│   │          │    │          │    │          │    │          │             │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘             │
│                       │               │                │                     │
│                       ▼               ▼                ▼                     │
│                  ┌──────────┐   ┌──────────┐    ┌──────────┐               │
│                  │  Lint    │   │  Unit    │    │  Staging │               │
│                  │  Format  │   │  Tests   │    │  Deploy  │               │
│                  └──────────┘   └──────────┘    └──────────┘               │
│                                         │                │                   │
│                                         ▼                ▼                   │
│                                    ┌──────────┐    ┌──────────┐              │
│                                    │Integration│    │ Production│             │
│                                    │  Tests   │    │  Deploy  │              │
│                                    └──────────┘    └──────────┘              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.9 Deployment Topology

**Development:** Local Julia process + OpenClaw socket

**Staging:**
- Jarvis: Single instance on VM
- OpenClaw: Local socket
- Monitoring: Local Prometheus

**Production:**
- Jarvis: Containerized (Docker)
- OpenClaw: Networked service
- Monitoring: Prometheus + Grafana stack
- Persistence: Persistent volume + S3 backup

---

## 5. FINAL STATE DEFINITION

### 5.1 "Production Ready" Qualifiers

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Functional completeness | All 10 gaps implemented | 10/10 |
| Test coverage | Lines covered by tests | >80% |
| Documentation | API docs + guides | Complete |
| Configuration | Environment-specific | Dev/Staging/Prod |
| Monitoring | Metrics exposed | All key metrics |
| Security | Audit passed | No critical findings |

### 5.2 "Sovereign Safe" Qualifiers

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Kernel always consulted | Audit log verification | 100% of actions |
| No bypass paths | Code review | Zero bypasses |
| Audit trail complete | Events logged | Every decision |
| Trust model functional | Trust level adjustable | Dynamic |
| Confirmation gate works | High-risk paused | Manual override |

### 5.3 "Cognitively Integrated" Qualifiers

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Brain processes all inputs | Neural inference usage | >95% |
| Reflection updates model | Self-model changes | Every cycle |
| Memory persists | Checkpoint exists | Recoverable |
| Real observations | No mock data | 100% real |
| Learning functional | Training triggered | On batch full |

### 5.4 "Operationally Resilient" Qualifiers

| Criterion | Measurement | Target |
|-----------|-------------|--------|
| Uptime | System availability | >99.9% |
| Recovery time | MTTR from failure | <5 minutes |
| Degradation graceful | Lower modes work | All modes |
| Error containment | Cascading failures | Zero |
| Circuit breakers | Fast failures | <100ms |

---

## APPENDIX: File Modification Summary

### Existing Files to Modify

| File | Changes |
|------|---------|
| `jarvis/src/SystemIntegrator.jl` | Wire kernel init, brain → kernel flow, real metrics |
| `adaptive-kernel/kernel/Kernel.jl` | Ensure `approve()` exported and functional |
| `adaptive-kernel/types.jl` | Integration types already exist |

### New Files to Create

| File | Purpose |
|------|---------|
| `jarvis/src/brain/BrainTrainer.jl` | Training loop |
| `jarvis/src/monitoring/SystemMonitor.jl` | Real metrics |
| `jarvis/src/voice/WhisperSTT.jl` | Speech to text |
| `jarvis/src/voice/ElevenLabsTTS.jl` | Text to speech |
| `jarvis/src/voice/VoiceActivityDetector.jl` | VAD |
| `jarvis/src/vision/VisionProcessor.jl` | Image analysis |
| `jarvis/src/memory/VisualMemory.jl` | Image memory |
| `jarvis/src/sandbox/ToolSandbox.jl` | Tool sandbox |
| `jarvis/src/persistence/CheckpointManager.jl` | Checkpointing |
| `jarvis/src/config/ConfigManager.jl` | Config loading |
| `jarvis/src/security/SecretVault.jl` | Encrypted storage |
| `jarvis/src/security/AuditLog.jl` | Security events |
| `jarvis/src/trust/RiskClassifier.jl` | Risk levels |
| `jarvis/src/trust/ConfirmationGate.jl` | User confirmations |
| `jarvis/src/trust/TrustManager.jl` | Trust scoring |
| `jarvis/src/trust/PolicyOverlay.jl` | Runtime policies |
| `jarvis/src/error/CircuitBreaker.jl` | Failure isolation |
| `jarvis/src/monitoring/HealthMonitor.jl` | Health checks |
| `jarvis/src/error/Degradation.jl` | Graceful degradation |
| `jarvis/src/monitoring/Metrics.jl` | Performance metrics |

---

*Document Version: 1.0*  
*Next Review: After Phase 1 completion*
