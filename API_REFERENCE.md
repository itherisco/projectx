# API Reference Documentation

**Version:** 1.0.0  
**Last Updated:** 2026-02-28  

---

## Table of Contents

1. [System Integrator](#1-system-integrator)
2. [Kernel API](#2-kernel-api)
3. [Cognition API](#3-cognition-api)
4. [Memory API](#4-memory-api)
5. [Security API](#5-security-api)
6. [Trust API](#6-trust-api)
7. [Type Definitions](#7-type-definitions)

---

## 1. System Integrator

**Module:** `Jarvis.SystemIntegrator`

### Initialization

#### `initialize_jarvis(config::Dict = Dict())::JarvisSystem`

Initialize the complete Jarvis system with optional configuration.

```julia
system = initialize_jarvis(Dict(
    "llm" => Dict("provider" => "openai"),
    "proactive_scan_interval" => 30
))
```

**Parameters:**
- `config::Dict` - Configuration dictionary

**Returns:**
- `JarvisSystem` - Initialized system instance

**Throws:**
- `SystemError` if initialization fails

---

### Main Cycle

#### `run_cycle(system::JarvisSystem)::Dict`

Execute one complete cognitive cycle.

```julia
result = run_cycle(system)
```

**Returns:**
- `Dict` with keys: `cycle`, `action`, `result`, `success`

---

### Request Processing

#### `process_user_request(system::JarvisSystem, text::String)::Dict`

Process a natural language user request.

```julia
response = process_user_request(system, "Check the CPU usage")
println(response["response"])
```

**Parameters:**
- `system::JarvisSystem` - Jarvis system instance
- `text::String` - Natural language request

**Returns:**
- `Dict` with keys: `response`, `action`, `success`, `confidence`

---

### Status and Control

#### `get_system_status(system::JarvisSystem)::Dict`

Get current system status.

```julia
status = get_system_status(system)
println("Cycle: ", status["current_cycle"])
```

**Returns:**
- `Dict` with keys: `status`, `current_cycle`, `trust_level`, `memory_usage`

#### `shutdown(system::JarvisSystem)::Bool`

Graceful shutdown of the system.

```julia
shutdown(system)
```

**Returns:**
- `Bool` - Success status

---

## 2. Kernel API

**Module:** `AdaptiveKernel.Kernel`

### Initialization

#### `init_kernel(config::Dict)::KernelState`

Initialize the kernel with configuration.

```julia
kernel = init_kernel(Dict(
    "goals" => [
        Dict("id" => "test_goal", "description" => "Test", "priority" => 0.8)
    ]
))
```

**Parameters:**
- `config::Dict` - Kernel configuration

**Returns:**
- `KernelState` - Initialized kernel state

---

### Core Cycle

#### `step_once(kernel::KernelState, ...)::KernelState`

Execute one kernel cycle.

```julia
kernel = step_once(kernel, candidates, executor, permission_handler)
```

**Parameters:**
- `kernel::KernelState` - Current kernel state
- `candidates::Vector{ActionProposal}` - Available actions
- `executor::Function` - Capability executor function
- `permission_handler::Function` - Permission check function

**Returns:**
- `KernelState` - Updated kernel state

---

### Decision Making

#### `evaluate_world(kernel::KernelState)::Vector{Float32}`

Compute priority scores for all goals.

```julia
scores = evaluate_world(kernel)
```

**Returns:**
- `Vector{Float32}` - Priority scores for each goal

#### `request_action(kernel::KernelState, action::ActionProposal)::Decision`

Request kernel approval for an action.

```julia
proposal = ActionProposal("observe_cpu", 0.9f0, 0.1f0, 0.8f0, 0.2f0, "Check CPU")
decision = request_action(kernel, proposal)
```

**Parameters:**
- `kernel::KernelState` - Current kernel state
- `action::ActionProposal` - Proposed action

**Returns:**
- `Decision` - One of: `APPROVED`, `DENIED`, `STOPPED`

---

### Reflection

#### `reflect!(kernel::KernelState, event::ReflectionEvent)::Nothing`

Update kernel state based on action outcome.

```julia
event = ReflectionEvent(
    kernel.cycle, "observe_cpu", 0.9f0, 0.1f0, 
    true, 0.8f0, 0.1f0, "Success"
)
reflect!(kernel, event)
```

**Parameters:**
- `kernel::KernelState` - Current kernel state
- `event::ReflectionEvent` - Outcome event

**Returns:**
- `Nothing`

---

## 3. Cognition API

**Module:** `AdaptiveKernel.Cognition`

### Cognitive Engine

#### `CognitiveEngine(config::SpineConfig = SpineConfig())`

Create a new cognitive engine.

```julia
engine = CognitiveEngine()
```

**Parameters:**
- `config::SpineConfig` - Optional configuration

**Returns:**
- `CognitiveEngine` - New cognitive engine instance

---

#### `run_sovereign_cycle(engine::CognitiveEngine, perception::Perception)`

Run a complete sovereign cognition cycle.

```julia
perception = Perception()
cycle_number = run_sovereign_cycle(engine, perception)
```

**Parameters:**
- `engine::CognitiveEngine` - Cognitive engine
- ` Perception` - Typed perception input

**Returns:**
- `Int` - Cycle number

---

### Goal System

**Module:** `AdaptiveKernel.Cognition.GoalSystem`

#### `generate_goals(engine::CognitiveEngine, perception::Perception)::Vector{Goal}`

Generate goals from perception.

```julia
goals = generate_goals(engine, perception)
```

**Returns:**
- `Vector{Goal}` - Generated goals

---

#### `should_activate_goal(goal::Goal, current_goals::Vector{GoalState})::Bool`

Determine if goal should be activated.

```julia
should_activate = should_activate_goal(goal, active_goals)
```

**Parameters:**
- `goal::Goal` - Goal to evaluate
- `current_goals::Vector{GoalState}` - Currently active goals

**Returns:**
- `Bool` - Whether to activate

---

#### `should_abandon_goal(goal_state::GoalState)::Bool`

Determine if goal should be abandoned.

```julia
should_abandon = should_abandon_goal(goal_state)
```

**Returns:**
- `Bool` - Whether to abandon

---

### World Model

**Module:** `AdaptiveKernel.Cognition.WorldModel`

#### `predict_next_state(model::WorldModel, state::Dict, action::String)::Dict`

Predict next system state.

```julia
next_state = predict_next_state(model, current_state, "observe_cpu")
```

**Returns:**
- `Dict` - Predicted state

---

#### `predict_reward(model::WorldModel, state::Dict, action::String)::Float32`

Predict expected reward.

```julia
reward = predict_reward(model, state, "observe_cpu")
```

**Returns:**
- `Float32` - Expected reward [0, 1]

---

#### `predict_risk(model::WorldModel, state::Dict, action::String)::Float32`

Predict action risk.

```julia
risk = predict_risk(model, state, "safe_shell")
```

**Returns:**
- `Float32` - Risk estimate [0, 1]

---

## 4. Memory API

**Module:** `Jarvis.VectorMemory`

### Storage Operations

#### `store_conversation!(store::VectorStore, entry::Dict)::Bool`

Store a conversation entry.

```julia
entry = Dict(
    "user" => "user123",
    "message" => "Check CPU",
    "response" => "CPU is at 45%"
)
store_conversation!(store, entry)
```

**Returns:**
- `Bool` - Success status

---

#### `search(store::VectorStore, query::String, top_k::Int = 5)::Vector{Dict}`

Semantic similarity search.

```julia
results = search(store, "system performance", top_k=10)
```

**Parameters:**
- `store::VectorStore` - Vector store instance
- `query::String` - Search query
- `top_k::Int` - Number of results (default: 5)

**Returns:**
- `Vector{Dict}` - Search results with scores

---

#### `rag_retrieve(store::VectorStore, query::String, context_window::Int = 3)::String`

Retrieve RAG context for query.

```julia
context = rag_retrieve(store, "user preferences")
```

**Returns:**
- `String` - Retrieved context

---

**Module:** `Jarvis.SemanticMemory`

### Action Outcomes

#### `store_action_outcome!(memory::SemanticMemoryStore, outcome::Dict)::Bool`

Store action execution result.

```julia
outcome = Dict(
    "action" => "observe_cpu",
    "success" => true,
    "reward" => 0.8,
    "error" => 0.1
)
store_action_outcome!(memory, outcome)
```

**Returns:**
- `Bool` - Success status

---

#### `recall_similar_outcomes(memory::SemanticMemoryStore, action::String)::Vector{Dict}`

Query similar past outcomes.

```julia
similar = recall_similar_outcomes(memory, "observe_cpu")
```

**Returns:**
- `Vector{Dict}` - Similar outcomes

---

## 5. Security API

**Module:** `AdaptiveKernel.InputSanitizer`

### Input Sanitization

#### `sanitize_input(input::String)::SanitizationResult`

Sanitize user input.

```julia
result = sanitize_input("Check the CPU please")
if result.level == CLEAN
    # Process input
elseif result.level == MALICIOUS
    # Block input
end
```

**Parameters:**
- `input::String` - Raw user input

**Returns:**
- `SanitizationResult` with fields:
  - `original::String` - Original input
  - `sanitized::Union{Nothing, String}` - Sanitized version
  - `level::SanitizationLevel` - `CLEAN`, `SUSPICIOUS`, or `MALICIOUS`
  - `errors::Vector{SanitizationError}` - Detected issues

---

#### `is_clean(result::SanitizationResult)::Bool`

Check if input is clean.

```julia
is_clean(result)  # true if no issues detected
```

---

#### `is_malicious(result::SanitizationResult)::Bool`

Check if input is malicious.

```julia
is_malicious(result)  # true if blocked
```

---

## 6. Trust API

**Module:** `AdaptiveKernel.Trust`

### Risk Classification

#### `classify_action_risk(action::String, context::Dict = Dict())::RiskLevel`

Classify action risk level.

```julia
risk = classify_action_risk("safe_shell")
# Returns: RISK_LOW, RISK_MEDIUM, or RISK_HIGH
```

**Returns:**
- `RiskLevel` - Risk classification

---

#### `get_required_trust(action::String)::TrustLevel`

Get required trust level for action.

```julia
required = get_required_trust("safe_shell")
# Returns: TRUST_BLOCKED through TRUST_FULL
```

---

### Confirmation Gate

#### `require_confirmation(action::ActionProposal)::Bool`

Check if action requires confirmation.

```julia
needs_confirmation = require_confirmation(proposal)
```

---

#### `confirm_action(action_id::UUID, token::String)::Bool`

Confirm a pending action.

```julia
confirmed = confirm_action(action_id, "user_token")
```

---

#### `deny_action(action_id::UUID)::Bool`

Deny a pending action.

```julia
denied = deny_action(action_id)
```

---

## 7. Type Definitions

### Trust Levels

```julia
@enum TrustLevel begin
    TRUST_BLOCKED = 0
    TRUST_RESTRICTED = 1
    TRUST_LIMITED = 2
    TRUST_STANDARD = 3
    TRUST_FULL = 4
end
```

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
    ACTION_READ
    ACTION_WRITE
    ACTION_EXECUTE
    ACTION_IOT
    ACTION_SYSTEM
end
```

### Decision Types

```julia
@enum Decision begin
    APPROVED
    DENIED
    STOPPED
end
```

### Sanitization Levels

```julia
@enum SanitizationLevel begin
    CLEAN
    SUSPICIOUS
    MALICIOUS
end
```

### Goal Status

```julia
@enum GoalStatus begin
    :active
    :completed
    :failed
    :paused
end
```

---

## File Locations

| Module | File |
|--------|------|
| SystemIntegrator | [`jarvis/src/SystemIntegrator.jl`](jarvis/src/SystemIntegrator.jl) |
| Kernel | [`adaptive-kernel/kernel/Kernel.jl`](adaptive-kernel/kernel/Kernel.jl) |
| Cognition | [`adaptive-kernel/cognition/Cognition.jl`](adaptive-kernel/cognition/Cognition.jl) |
| GoalSystem | [`adaptive-kernel/cognition/goals/GoalSystem.jl`](adaptive-kernel/cognition/goals/GoalSystem.jl) |
| WorldModel | [`adaptive-kernel/cognition/worldmodel/WorldModel.jl`](adaptive-kernel/cognition/worldmodel/WorldModel.jl) |
| VectorMemory | [`jarvis/src/memory/VectorMemory.jl`](jarvis/src/memory/VectorMemory.jl) |
| InputSanitizer | [`adaptive-kernel/cognition/security/InputSanitizer.jl`](adaptive-kernel/cognition/security/InputSanitizer.jl) |
| Trust | [`adaptive-kernel/kernel/trust/Trust.jl`](adaptive-kernel/kernel/trust/Trust.jl) |

---

*Last Updated: 2026-02-28*
