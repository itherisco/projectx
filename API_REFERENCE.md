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

## 7. UI Layer - Web Dashboard

**Module:** `Interfaces.Web`

### Dashboard API

#### `serve_dashboard(;host::String="127.0.0.1", port::Int=8080)`

Start the web dashboard server.

```julia
using Interfaces.Web
serve_dashboard(host="0.0.0.0", port=8080)
```

**Parameters:**
- `host::String` - Host to bind to (default: "127.0.0.1")
- `port::Int` - Port to listen on (default: 8080)

---

#### `get_live_status()::Dict`

Get current live system status.

```julia
status = get_live_status()
println(status["system"]["brain_health"])
```

**Returns:**
- `Dict` with system, metabolic, telemetry, and action status

---

#### `get_telemetry_history()::Dict`

Get historical telemetry data.

```julia
history = get_telemetry_history()
```

**Returns:**
- `Dict` with energy_history, attention_variance_history, policy_entropy_history

---

#### `get_sanity_status()::Dict`

Get cognitive sanity check status.

```julia
sanity = get_sanity_status()
```

**Returns:**
- `Dict` with attention_variance, policy_entropy, cognitive_load, is_sane

---

#### `refresh_dashboard!()`

Manually refresh dashboard data.

```julia
refresh_dashboard!()
```

---

## 8. UI Layer - Mobile API

**Module:** `Interfaces.MobileAPI`

### Authentication

#### `create_access_token(user_id::String; roles::Vector{String}=["user"])`

Create JWT access token for mobile client.

```julia
token = create_access_token("user123", roles=["user", "admin"])
```

**Parameters:**
- `user_id::String` - User identifier
- `roles::Vector{String}` - User roles (default: ["user"])

**Returns:**
- `String` - JWT access token

---

#### `validate_token(token::String)::Union{MobileClaims, Nothing}`

Validate JWT token.

```julia
claims = validate_token(token)
if claims !== nothing
    println(claims.user_id)
end
```

**Returns:**
- `Union{MobileClaims, Nothing}` - Claims if valid, nothing otherwise

---

### Sovereign Approval

#### `approve_action(request::ApprovalRequest; timeout_seconds::Int64=30)`

Request sovereign approval for an action.

```julia
request = ApprovalRequest(
    proposal_id="prop-123",
    capability_id="safe_shell",
    params=Dict("command" => "ls"),
    priority=0.8,
    risk=0.3,
    reward=0.7
)
response = approve_action(request)
```

**Parameters:**
- `request::ApprovalRequest` - Approval request details
- `timeout_seconds::Int64` - Timeout for approval (default: 30)

**Returns:**
- `ApprovalResponse` - Approval decision

---

### Notifications

#### `send_sovereign_notification(user_id::String; title::String, body::String)`

Send sovereign approval notification.

```julia
send_sovereign_notification("user123"; title="Action Approved", body="Your request was approved")
```

---

#### `api_status()::Dict`

Get mobile API status.

```julia
status = api_status()
```

**Returns:**
- `Dict` with version, status, services, security

---

## 9. UI Layer - Desktop System Tray

**Module:** `Interfaces.SystemTray`

### Status Monitoring

#### `get_health()::SystemHealth`

Get current system health.

```julia
health = get_health()
println(health.brain_health)
```

**Returns:**
- `SystemHealth` - Current system health metrics

---

#### `get_status_summary()::Dict{String, Any}`

Get status summary for tray display.

```julia
summary = get_status_summary()
```

**Returns:**
- `Dict` with status_icon, status_text, health, warden_status

---

#### `determine_status_icon(health::SystemHealth)::String`

Determine status icon based on health.

```julia
icon = determine_status_icon(health)  # Returns 🟢🟡🔴🛑
```

**Returns:**
- `String` - Status emoji icon

---

### Controls

#### `set_poll_interval(interval::Float64)`

Set tray poll interval in seconds.

```julia
set_poll_interval(2.0)  # Poll every 2 seconds
```

---

#### `enable_notifications(enabled::Bool)`

Enable or disable desktop notifications.

```julia
enable_notifications(true)
```

---

#### `show_notification(message::String; priority::Symbol=:normal)`

Show desktop notification.

```julia
show_notification("System health changed!"; priority=:critical)
```

---

## 10. Security - Rate Limiter

**Module:** `AdaptiveKernel.RateLimiter`

### Rate Limiting

#### `check_rate_limit(client_key::String; requests_per_window::Int=60, window_seconds::Float64=60.0, burst_allowance::Int=10)::RateLimitResult`

Check if request is within rate limit (fail-closed).

```julia
result = check_rate_limit("client123")
if result.status == ALLOWED
    # Process request
end
```

**Parameters:**
- `client_key::String` - Client identifier
- `requests_per_window::Int` - Max requests per window (default: 60)
- `window_seconds::Float64` - Window duration (default: 60.0)
- `burst_allowance::Int` - Burst requests allowed (default: 10)

**Returns:**
- `RateLimitResult` with status (ALLOWED/RATE_LIMITED/BLOCKED), remaining, reset_time

---

#### `check_rate_limit!(client_key::String; kwargs...)::Bool`

Check rate limit and return boolean (fail-closed).

```julia
if check_rate_limit!("client123")
    # Process request
end
```

**Returns:**
- `Bool` - true if allowed, false if rate limited (fail-closed)

---

#### `is_rate_limited(client_key::String)::Bool`

Quick check if client is currently rate limited.

```julia
if is_rate_limited("client123")
    println("Too many requests!")
end
```

---

#### `reset_rate_limits()`

Reset all rate limiters (admin/testing).

```julia
reset_rate_limits()
```

---

### Configuration

#### `configure_rate_limit(endpoint::String, config::RateLimitConfig)`

Configure endpoint-specific rate limiting.

```julia
config = RateLimitConfig(requests_per_window=10, window_seconds=60.0, burst_allowance=2)
configure_rate_limit("/api/mobile/approve", config)
```

---

#### `set_global_limit(requests_per_window::Int, window_seconds::Float64)`

Set global rate limit for all clients.

```julia
set_global_limit(100, 60.0)
```

---

### Rate Limit Types

```julia
@enum RateLimitStatus ALLOWED RATE_LIMITED BLOCKED

struct RateLimitConfig
    requests_per_window::Int
    window_seconds::Float64
    burst_allowance::Int
    enabled::Bool
end

struct RateLimitResult
    status::RateLimitStatus
    remaining::Int
    reset_time::Float64
    retry_after::Float64
end
```

---

## 11. Security - Integration

**Module:** `AdaptiveKernel.SecurityIntegration`

### Unified Security Boundary

#### `secure_input(input::String; context_kwargs...)::Tuple{Bool, String, SanitizationResult}`

Apply full security pipeline to input (fail-closed).

```julia
allowed, message, result = secure_input(user_input; client_key="user123", energy_level=0.8)
if !allowed
    println("Blocked: $message")
end
```

**Security Pipeline:**
1. Input Sanitization - detect prompt injection
2. Rate Limiting - check client rate limits
3. Metabolic Protection - block if energy critical

**Returns:**
- `Tuple{Bool, String, SanitizationResult}` - (allowed, message, result)

---

#### `secure_api_request(input::String, context::SecurityContext)::Dict`

Secure API request with full pipeline.

```julia
context = SecurityContext(client_key="api_client", client_ip="192.168.1.1")
result = secure_api_request(request_body, context)
```

**Returns:**
- `Dict` with allowed, sanitized_input, rate_limit_result, security_context

---

#### `secure_capability_call(capability_id::String, params::Dict, context::SecurityContext)::Dict`

Secure capability execution.

```julia
result = secure_capability_call("safe_shell", Dict("command" => "ls"), context)
```

---

#### `get_security_status()::Dict`

Get current security system status.

```julia
status = get_security_status()
println(status["sanitizer"]["threats_blocked"])
```

**Returns:**
- `Dict` with sanitizer, rate_limiter, crypto, metabolic_protection status

---

### Security Context

```julia
mutable struct SecurityContext
    client_key::String
    client_ip::Union{String, Nothing}
    session_token::Union{String, Nothing}
    user_id::Union{String, Nothing}
    energy_level::Float32
    request_id::String
    timestamp::DateTime
end

struct SecureRequest
    original_input::Any
    sanitized_input::Any
    context::SecurityContext
    security_result::SanitizationResult
    rate_limit_result::RateLimitResult
end
```

---

## 12. Type Definitions

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

### Mobile Token Types

```julia
@enum TokenType ACCESS REFRESH

@enum UserRole ADMIN USER READONLY SERVICE

struct MobileClaims
    subject::String
    roles::Vector{UserRole}
    issued_at::Int64
    expires_at::Int64
    jwt_id::String
end

struct ApprovalRequest
    proposal_id::String
    capability_id::String
    params::Dict{String, Any}
    priority::Float64
    risk::Float64
    reward::Float64
end

struct ApprovalResponse
    approved::Bool
    token::Union{String, Nothing}
    veto_score::Float64
    expires_at::Int64
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
| Web Dashboard | [`interfaces/web/Dashboard.jl`](interfaces/web/Dashboard.jl) |
| Mobile API | [`interfaces/mobile/MobileAPI.jl`](interfaces/mobile/MobileAPI.jl) |
| System Tray | [`interfaces/desktop/SystemTray.jl`](interfaces/desktop/SystemTray.jl) |
| Unified Bridge | [`interfaces/UnifiedBridge.jl`](interfaces/UnifiedBridge.jl) |
| RateLimiter | [`adaptive-kernel/kernel/security/RateLimiter.jl`](adaptive-kernel/kernel/security/RateLimiter.jl) |
| SecurityIntegration | [`adaptive-kernel/kernel/security/SecurityIntegration.jl`](adaptive-kernel/kernel/security/SecurityIntegration.jl) |

---

*Last Updated: 2026-03-13*
