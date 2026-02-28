# JARVIS Production Implementation Blueprint
## Executable Architecture Specification

**Generated:** 2026-02-26  
**Status:** EXECUTABLE IMPLEMENTATION SPECIFICATION  
**Classification:** SOVEREIGN AI INFRASTRUCTURE  

---

# TABLE OF CONTENTS

1. [Executive Summary](#1-executive-summary)
2. [Phase Specifications](#2-phase-specifications)
   - [Phase 1: Kernel Sovereignty Enforcement](#phase-1-kernel-sovereignty-enforcement)
   - [Phase 2: ITHERIS Brain Full Integration](#phase-2-itheris-brain-full-integration)
   - [Phase 3: Real System Observation](#phase-3-real-system-observation)
   - [Phase 4: Voice Pipeline (STT/TTS)](#phase-4-voice-pipeline-stttts)
   - [Phase 5: Vision Pipeline (VLM)](#phase-5-vision-pipeline-vlm)
   - [Phase 6: Tool Registry & Execution Sandbox](#phase-6-tool-registry--execution-sandbox)
   - [Phase 7: Persistence & Checkpointing](#phase-7-persistence--checkpointing)
   - [Phase 8: Secrets & Configuration](#phase-8-secrets--configuration)
   - [Phase 9: Trust & Confirmation](#phase-9-trust--confirmation)
   - [Phase 10: Error Handling & Recovery](#phase-10-error-handling--recovery)
3. [Integration Flows](#3-integration-flows)
4. [Error & Failure Models](#4-error--failure-models)
5. [Security Models](#5-security-models)
6. [Test Strategies](#6-test-strategies)
7. [Deployment Plans](#7-deployment-plans)
8. [Final Output](#8-final-output)

---

# 1. EXECUTIVE SUMMARY

## Current State Assessment

| Component | Status | Location |
|-----------|--------|----------|
| **Adaptive Kernel** | Production Ready | [`adaptive-kernel/kernel/Kernel.jl`](adaptive-kernel/kernel/Kernel.jl:1) |
| **ITHERIS Brain** | Partial Integration | [`itheris.jl`](itheris.jl:1) |
| **LLMBridge** | Production Ready | [`jarvis/src/llm/LLMBridge.jl`](jarvis/src/llm/LLMBridge.jl:1) |
| **Vector Memory** | Production Ready | [`jarvis/src/memory/VectorMemory.jl`](jarvis/src/memory/VectorMemory.jl:1) |
| **SystemIntegrator** | Integration Layer | [`jarvis/src/SystemIntegrator.jl`](jarvis/src/SystemIntegrator.jl:1) |
| **Kernel.approve()** | Implemented | [`adaptive-kernel/kernel/Kernel.jl:272`](adaptive-kernel/kernel/Kernel.jl:272) |

## Critical Gaps Requiring Implementation

1. **Kernel → Execution wiring not complete** - `approve()` exists but not enforced in execution path
2. **Brain uses fallback heuristics** - Neural inference not fully wired
3. **No real system telemetry** - Mock observations used
4. **No voice pipeline** - STT/TTS not implemented
5. **No vision pipeline** - VLM not integrated
6. **No persistence** - Checkpointing not implemented
7. **No secrets management** - API keys in config.toml

---

# 2. PHASE SPECIFICATIONS

## PHASE 1: Kernel Sovereignty Enforcement

### 1.1 Architectural Role
The Kernel is the SOVEREIGN authority. All execution flows through `Kernel.approve()`. The kernel state **MUST NEVER BE `nothing`**.

### 1.2 Module Specifications

#### File: `adaptive-kernel/kernel/StateValidator.jl` (NEW)

```julia
"""
    StateValidator - Validates kernel state integrity
"""
struct StateValidator
    validation_interval::Float64
    last_validation::DateTime
    
    function StateValidator(interval::Float64=1.0)
        new(interval, now())
    end
end

"""
    validate_kernel_state(state::KernelState)::Bool
Ensures kernel state is valid for operation.
"""
function validate_kernel_state(state::KernelState)::Bool
    state === nothing && return false
    state.self_metrics === nothing && return false
    state.world === nothing && return false
    return true
end

"""
    ensure_kernel_ready(state::KernelState)::KernelState
Auto-initializes kernel if in invalid state (fail-closed).
"""
function ensure_kernel_ready(state::Union{KernelState, Nothing})::KernelState
    if state === nothing
        @error "Kernel state is nothing - initializing with defaults"
        return init_kernel(Dict())
    end
    return state
end
```

### 1.3 Required Changes to Existing Files

#### File: `jarvis/src/SystemIntegrator.jl`

Add sovereignty enforcement in `_execute_action()`:

```julia
function _execute_action(system::JarvisSystem, proposal::ActionProposal)::ActionResult
    # CRITICAL: Verify kernel approval before execution
    if system.kernel.state === nothing
        @error "Kernel state is nothing - refusing execution"
        return ActionResult(success=false, error="Kernel not ready")
    end
    
    if system.kernel.state.last_decision != APPROVED
        @warn "Action not approved by kernel" decision=system.kernel.state.last_decision
        return ActionResult(success=false, error="Kernel approval required")
    end
    
    # Proceed with execution...
end
```

### 1.4 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`jarvis/src/SystemIntegrator.jl:800`](jarvis/src/SystemIntegrator.jl:800) | `_execute_action()` | Verify kernel approval |
| [`adaptive-kernel/kernel/Kernel.jl:272`](adaptive-kernel/kernel/Kernel.jl:272) | `approve()` | Sovereign decision |
| [`adaptive-kernel/kernel/Kernel.jl:386`](adaptive-kernel/kernel/Kernel.jl:386) | `reflect!()` | Self-model update |

### 1.5 Test Strategy

- **Unit Tests:**
  - `test_kernel_never_nothing`: Verify state never nothing after init
  - `test_approve_always_returns`: Verify approve() always returns decision
  - `test_fail_closed`: Verify system fails closed on errors

- **Integration Tests:**
  - `test_brain_kernel_boundary`: Verify brain cannot bypass kernel
  - `test_approval_audit_trail`: Verify all approvals logged

---

## PHASE 2: ITHERIS Brain Full Integration

### 2.1 Architectural Role
The Brain is ADVISORY ONLY. It proposes actions but NEVER executes. All brain outputs pass through `Kernel.approve()`.

### 2.2 Module Specifications

#### File: `adaptive-kernel/brain/NeuralBrain.jl` (NEW)

```julia
"""
    NeuralBrainCore - Full neural network brain implementation
"""
mutable struct NeuralBrainCore
    encoder::Chain          # Encoder network
    policy_network::Chain  # Policy network (action selection)
    value_network::Chain   # Value network (reward estimation)
    latent_dim::Int
    
    # Training state
    experience_buffer::Vector{Experience}
    optimizer::Any
    target_network::Chain
    
    # Uncertainty estimation
    dropout_layers::Vector{Dropout}
    ensemble_models::Vector{Chain}
end

"""
    BrainInferenceResult - Result from brain inference
"""
struct BrainInferenceResult
    proposed_actions::Vector{String}
    confidence::Float32
    value_estimate::Float32
    uncertainty::Float32
    reasoning::String
    latent_features::Vector{Float32}
end
```

### 2.3 Function Signatures

```julia
"""
    infer(brain::JarvisBrain, input::BrainInput)::BrainOutput
INVARIANT: Brain output is ALWAYS advisory. Kernel approval required for execution.
"""
function infer(brain::JarvisBrain, input::BrainInput)::BrainOutput

"""
    learn!(brain::JarvisBrain, experience::Experience)::LearningResult
Update brain based on experience tuple.
"""
function learn!(brain::JarvisBrain, experience::Experience)::LearningResult

"""
    evaluate_value(brain::NeuralBrainCore, perception::Vector{Float32})::Float32
Evaluate expected cumulative reward for given perception.
"""
function evaluate_value(brain::NeuralBrainCore, perception::Vector{Float32})::Float32
```

### 2.4 Required Changes to Existing Files

#### File: `jarvis/src/SystemIntegrator.jl`

Replace `_brain_infer()` fallback:

```julia
function _brain_infer(system::JarvisSystem, perception::PerceptionVector)
    # Use neural brain if available
    if system.brain.brain_core !== nothing
        input = BrainInput(perception.vector)
        return infer(system.brain, input)
    end
    
    # Fallback: return nothing, let kernel handle
    @warn "Brain not available, returning nothing"
    return nothing
end
```

### 2.5 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`jarvis/src/SystemIntegrator.jl:595`](jarvis/src/SystemIntegrator.jl:595) | `_brain_infer()` | Neural inference entry |
| [`jarvis/src/brain/BrainTrainer.jl`](jarvis/src/brain/BrainTrainer.jl:1) | `train_brain!()` | Training loop |
| [`adaptive-kernel/integration/Conversions.jl`](adaptive-kernel/integration/Conversions.jl:1) | `brain_to_proposal()` | Type conversion |

---

## PHASE 3: Real System Observation

### 3.1 Module Specifications

#### File: `adaptive-kernel/kernel/observability/SystemObserver.jl` (NEW)

```julia
"""
    SystemObserver - Real-time system telemetry aggregation
"""
mutable struct SystemObserver
    observation_interval::Float64  # seconds
    last_observation::Union{Observation, Nothing}
    observation_history::CircularBuffer{Observation}
    
    function SystemObserver(interval::Float64=1.0)
        new(interval, nothing, CircularBuffer{Observation}(100))
    end
end

"""
    collect_real_observation()::Observation
Collect real system metrics from /proc (Linux) or WMI (Windows)
"""
function collect_real_observation()::Observation
    cpu = _read_cpu_load()
    mem = _read_memory_usage()
    disk = _read_disk_io()
    net = _read_network_latency()
    files = _count_filesystem_objects()
    procs = _count_processes()
    
    return Observation(cpu, mem, disk, net, files, procs)
end
```

### 3.2 Platform-Specific Implementation

```julia
function _read_cpu_load()::Float32
    if isfile("/proc/loadavg")
        load = parse(Float64, split(readlines("/proc/loadavg")[1])[1])
        return Float32(clamp(load / Sys.CPU_THREADS, 0.0, 1.0))
    elseif Sys.iswindows()
        return _windows_cpu_usage()
    else
        return 0.1f0  # Safe default
    end
end

function _read_memory_usage()::Float32
    if isfile("/proc/meminfo")
        data = _parse_meminfo()
        total = get(data, "MemTotal", 0) / 1024 / 1024  # GB
        avail = get(data, "MemAvailable", 0) / 1024 / 1024
        used = total - avail
        return Float32(used / total)
    elseif Sys.iswindows()
        return _windows_memory_usage()
    else
        return 0.5f0
    end
end
```

### 3.3 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`adaptive-kernel/kernel/Kernel.jl:94`](adaptive-kernel/kernel/Kernel.jl:94) | `init_kernel()` | Initialize observer |
| [`adaptive-kernel/kernel/Kernel.jl:184`](adaptive-kernel/kernel/Kernel.jl:184) | `evaluate_world()` | Use real observations |

---

## PHASE 4: Voice Pipeline (STT/TTS)

### 4.1 Module Specifications

#### File: `jarvis/src/voice/WhisperSTT.jl` (NEW)

```julia
"""
    WhisperSTT - OpenAI Whisper integration for Speech-to-Text
"""
struct WhisperSTT
    api_key::String
    model::String  # "whisper-1" 
    language::Union{String, Nothing}
    client::HTTP.Client
    
    function WhisperSTT(;api_key::String=get(ENV, "JARVIS_WHISPER_API_KEY", ""),
                        model::String="whisper-1",
                        language::Union{String, Nothing}=nothing)
        isempty(api_key) && error("Whisper API key required")
        new(api_key, model, language, HTTP.Client())
    end
end

"""
    transcribe(audio_data::Vector{UInt8}, stt::WhisperSTT)::String
Transcribe audio bytes to text using Whisper API
"""
function transcribe(audio_data::Vector{UInt8}, stt::WhisperSTT)::String
    # Implementation with rate limiting, retry, circuit breaker
end
```

#### File: `jarvis/src/voice/ElevenLabsTTS.jl` (NEW)

```julia
"""
    ElevenLabsTTS - ElevenLabs integration for Text-to-Speech
"""
struct ElevenLabsTTS
    api_key::String
    voice_id::String
    model::String
    stability::Float32
    similarity_boost::Float32
    
    function ElevenLabsTTS(;api_key::String=get(ENV, "JARVIS_ELEVENLABS_API_KEY", ""),
                          voice_id::String="21m00Tcm4TlvDq8ikWAM",
                          model::String="eleven_monolingual_v1",
                          stability::Float32=0.5f0,
                          similarity_boost::Float32=0.75f0)
        isempty(api_key) && error("ElevenLabs API key required")
        new(api_key, voice_id, model, stability, similarity_boost)
    end
end

"""
    speak(text::String, tts::ElevenLabsTTS)::Vector{UInt8}
Convert text to speech audio bytes
"""
function speak(text::String, tts::ElevenLabsTTS)::Vector{UInt8}
    # Implementation with rate limiting, retry, circuit breaker
end
```

#### File: `jarvis/src/voice/VoicePipeline.jl` (NEW)

```julia
"""
    VoicePipeline - Coordinates STT → Cognition → TTS flow
"""
@enum VoiceMode STREAMING BATCH

mutable struct VoicePipeline
    stt::WhisperSTT
    tts::ElevenLabsTTS
    mode::VoiceMode
    audio_buffer::Vector{UInt8}
    sample_rate::Int
    
    function VoicePipeline(;mode::VoiceMode=STREAMING)
        stt = WhisperSTT()
        tts = ElevenLabsTTS()
        new(stt, tts, mode, Vector{UInt8}(), 16000)
    end
end
```

### 4.2 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`jarvis/src/SystemIntegrator.jl`](jarvis/src/SystemIntegrator.jl:1) | `SystemIntegrator` | Wire voice pipeline |
| [`config.toml`](config.toml:1) | `stt_provider`, `tts_provider` | Configuration |

---

## PHASE 5: Vision Pipeline (VLM)

### 5.1 Module Specifications

#### File: `jarvis/src/vision/VisionLanguageModel.jl` (NEW)

```julia
"""
    VLMClient - Vision Language Model abstraction
Supports: GPT-4V, Claude Vision, LLaVA
"""
abstract type VLMClient end

struct GPT4VClient <: VLMClient
    api_key::String
    model::String
    max_tokens::Int
    
    function GPT4VClient(;api_key::String=get(ENV, "JARVIS_OPENAI_API_KEY", ""),
                         model::String="gpt-4-vision-preview")
        new(api_key, model, 2048)
    end
end

struct ClaudeVisionClient <: VLMClient
    api_key::String
    model::String
    
    function ClaudeVisionClient(;api_key::String=get(ENV, "JARVIS_ANTHROPIC_API_KEY", ""),
                               model::String="claude-3-opus-20240229")
        new(api_key, model)
    end
end

"""
    VisionResult - Structured result from VLM analysis
"""
struct VisionResult
    description::String
    objects::Vector{String}
    text_detected::String
    confidence::Float32
end

"""
    analyze_image(client::VLMClient, image_data::Vector{UInt8}, prompt::String)::VisionResult
Send image to VLM and get structured analysis
"""
function analyze_image(client::VLMClient, image_data::Vector{UInt8}, prompt::String)::VisionResult
    # Implementation with rate limiting, retry, circuit breaker
end
```

#### File: `jarvis/src/vision/ImagePipeline.jl` (NEW)

```julia
"""
    ImagePipeline - From camera/file to VLM analysis
"""
struct ImagePipeline
    vlm::VLMClient
    preprocessor::ImagePreprocessor
    risk_filter::VisionRiskFilter
    
    ImagePipeline(;vlm::VLMClient) = new(vlm, ImagePreprocessor(), VisionRiskFilter())
end

"""
    VisionRiskFilter - Block sensitive content before VLM
"""
struct VisionRiskFilter
    blocked_patterns::Vector{Regex}
    
    function VisionRiskFilter()
        new([
            r"credit_card",
            r"ssn|social.security",
            r"password",
        ])
    end
end
```

### 5.2 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`jarvis/src/SystemIntegrator.jl`](jarvis/src/SystemIntegrator.jl:1) | `SystemIntegrator` | Wire vision pipeline |
| [`jarvis/src/memory/VectorMemory.jl`](jarvis/src/memory/VectorMemory.jl:1) | `store()` | Vision embeddings |

---

## PHASE 6: Tool Registry & Execution Sandbox

### 6.1 Module Specifications

#### File: `adaptive-kernel/registry/ToolRegistry.jl` (NEW)

```julia
"""
    ToolRegistry - Central registry for all executable tools
Binds OpenClaw tools + native capabilities
"""
mutable struct ToolRegistry
    openclaw_endpoint::String
    native_capabilities::Dict{String, Capability}
    tool_metadata::Dict{String, ToolMetadata}
    
    function ToolRegistry(endpoint::String="http://localhost:3000")
        new(endpoint, Dict{String, Capability}(), Dict{String, ToolMetadata}())
    end
end

"""
    ToolMetadata - Metadata for tool registration
"""
struct ToolMetadata
    id::String
    name::String
    source::Symbol  # :native or :openclaw
    risk_level::RiskLevel
    execution_mode::Symbol  # :julia or :docker
    endpoint::Union{String, Nothing}
end
```

#### File: `adaptive-kernel/sandbox/ExecutionSandbox.jl` (NEW)

```julia
"""
    ExecutionSandbox - Isolated tool execution environment
"""
abstract type SandboxMode end
struct DockerSandbox <: SandboxMode end
struct ProcessSandbox <: SandboxMode end

"""
    execute_in_sandbox(tool_id::String, params::Dict, mode::SandboxMode, registry::ToolRegistry)::ExecutionResult
"""
function execute_in_sandbox(
    tool_id::String,
    params::Dict,
    mode::DockerSandbox,
    registry::ToolRegistry
)::ExecutionResult
    # Validate tool exists
    !haskey(registry.tool_metadata, tool_id) && 
        return ExecutionResult(success=false, error="Tool not found")
    
    # Execute via OpenClaw API with timeout, memory limit, cpu limit
    # Implement circuit breaker, retry logic
end
```

#### File: `adaptive-kernel/registry/RiskClassifier.jl` (NEW)

```julia
"""
    RiskClassifier - Classify tool risk levels
"""
@enum RiskLevel READ_ONLY LOW MEDIUM HIGH CRITICAL

"""
    classify_tool_risk(tool_id::String, params::Dict)::RiskLevel
"""
function classify_tool_risk(tool_id::String, params::Dict)::RiskLevel
    registry_entry = get_capability_registry(tool_id)
    base_risk = registry_entry.risk
    param_risk = _assess_parameter_risk(tool_id, params)
    context_risk = _assess_context_risk()
    return max(base_risk, param_risk, context_risk)
end
```

### 6.2 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`jarvis/src/bridge/OpenClawBridge.jl`](jarvis/src/bridge/OpenClawBridge.jl:1) | `OpenClawBridge` | Align with registry |
| [`adaptive-kernel/kernel/Kernel.jl:272`](adaptive-kernel/kernel/Kernel.jl:272) | `approve()` | Risk classification |

---

## PHASE 7: Persistence & Checkpointing

### 7.1 Module Specifications

#### File: `adaptive-kernel/persistence/Checkpointer.jl` (NEW)

```julia
"""
    CheckpointManager - Durable state snapshots
"""
struct CheckpointManager
    checkpoint_dir::String
    max_checkpoints::Int
    checkpoint_interval::Int  # seconds
    
    function CheckpointManager(dir::String="./checkpoints"; 
                               max_checkpoints::Int=10,
                               interval::Int=300)
        mkpath(dir)
        new(dir, max_checkpoints, interval)
    end
end

"""
    save_checkpoint(manager::CheckpointManager, state::KernelState)
Serialize kernel state to durable storage
"""
function save_checkpoint(manager::CheckpointManager, state::KernelState)
    checkpoint = Dict(
        "version" => KERNEL_VERSION,
        "timestamp" => string(now()),
        "cycle" => state.cycle[],
        "goals" => [goal_to_dict(g) for g in state.goals],
        "goal_states" => goalstate_to_dict.(values(state.goal_states)),
        "episodic_memory" => [event_to_dict(e) for e in state.episodic_memory],
        "self_metrics" => state.self_metrics
    )
    
    # write_to_file atomically via temp file
end
```

#### File: `jarvis/src/memory/VectorStore.jl` (NEW)

```julia
"""
    VectorStore - Persistent vector embeddings using SQLite
"""
struct VectorStore
    db_path::String
    index_path::String
    embeddings::Vector{Matrix{Float32}}
    
    function VectorStore(path::String="./vector_store")
        mkpath(path)
        db_path = joinpath(path, "vectors.db")
        index_path = joinpath(path, "index.bin")
        
        # Initialize SQLite schema
        DBInterface.connect(SQLite.DB(db_path)) do db
            SQLite.execute(db, """
                CREATE TABLE IF NOT EXISTS embeddings (
                    id TEXT PRIMARY KEY,
                    content TEXT,
                    embedding BLOB,
                    timestamp TEXT,
                    source TEXT
                )
            """)
        end
        
        new(db_path, index_path, Vector{Matrix{Float32}}())
    end
end
```

### 7.2 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`adaptive-kernel/persistence/Persistence.jl`](adaptive-kernel/persistence/Persistence.jl:1) | `Persistence` | Extend with checkpointing |
| [`jarvis/src/memory/VectorMemory.jl`](jarvis/src/memory/VectorMemory.jl:1) | `VectorMemory` | Persist embeddings |

---

## PHASE 8: Secrets & Configuration

### 8.1 Module Specifications

#### File: `jarvis/src/config/SecretsManager.jl` (NEW)

```julia
"""
    SecretsManager - Secure secrets loading from Vault or ENV
"""
struct SecretsManager
    vault_addr::Union{String, Nothing}
    vault_token::Union{String, Nothing}
    cache::Dict{String, String}
    
    function SecretsManager()
        vault_addr = get(ENV, "JARVIS_VAULT_ADDR", nothing)
        vault_token = get(ENV, "JARVIS_VAULT_TOKEN", nothing)
        new(vault_addr, vault_token, Dict{String, String}())
    end
end

"""
    get_secret(manager::SecretsManager, key::String)::String
Load secret from Vault or fall back to ENV
"""
function get_secret(manager::SecretsManager, key::String)::String
    # Check cache first
    haskey(manager.cache, key) && return manager.cache[key]
    
    # Try Vault first
    if manager.vault_addr !== nothing
        secret = _load_from_vault(manager, key)
        secret !== nothing && (manager.cache[key] = secret; return secret)
    end
    
    # Fall back to environment variable
    env_key = "JARVIS_$(uppercase(key))"
    secret = get(ENV, env_key, "")
    
    isempty(secret) && error("Secret $key not found in Vault or ENV")
    
    manager.cache[key] = secret
    return secret
end
```

#### File: `jarvis/src/config/ConfigLoader.jl` (NEW)

```julia
"""
    ConfigLoader - Environment-aware configuration
"""
function load_config(env::String="development")::Config
    # Load base config
    base = TOML.parsefile("config/base.toml")
    
    # Load environment overrides
    env_file = "config/environments/$(env).toml"
    if isfile(env_file)
        overrides = TOML.parsefile(env_file)
        merge!(base, overrides)
    end
    
    # Validate required secrets
    _validate_secrets(base)
    
    return Config(base)
end
```

### 8.2 Environment Variable Schema

```yaml
# config/env_schema.yaml
environment_variables:
  JARVIS_LLM_API_KEY:
    required: true
    description: "OpenAI or Anthropic API key for LLM"
    pattern: "^sk-[a-zA-Z0-9]+$"
  
  JARVIS_WHISPER_API_KEY:
    required: false
    description: "OpenAI API key for Whisper STT"
  
  JARVIS_ELEVENLABS_API_KEY:
    required: false
    description: "ElevenLabs API key for TTS"
  
  JARVIS_OPENCLAW_ENDPOINT:
    required: false
    default: "http://localhost:3000"
```

### 8.3 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`jarvis/src/llm/LLMBridge.jl`](jarvis/src/llm/LLMBridge.jl:1) | `LLMBridge` | Load API keys |
| [`jarvis/src/voice/WhisperSTT.jl`](jarvis/src/voice/WhisperSTT.jl:1) | `WhisperSTT` | Load API keys |

---

## PHASE 9: Trust & Confirmation

### 9.1 Module Specifications

#### File: `adaptive-kernel/kernel/trust/RiskClassifier.jl` (NEW)

```julia
"""
    TrustClassifier - Dynamic risk classification for actions
"""
struct TrustClassifier
    risk_thresholds::Dict{RiskLevel, TrustLevel}
    history::CircularBuffer{TrustEvent}
    
    TrustClassifier() = new(
        Dict(
            READ_ONLY => TRUST_RESTRICTED,
            LOW => TRUST_LIMITED,
            MEDIUM => TRUST_STANDARD,
            HIGH => TRUST_FULL,
            CRITICAL => TRUST_FULL
        ),
        CircularBuffer{TrustEvent}(1000)
    )
end

"""
    classify_action_risk(proposal::ActionProposal, context::ActionContext)::RiskLevel
"""
function classify_action_risk(
    proposal::ActionProposal,
    context::ActionContext,
    classifier::TrustClassifier
)::RiskLevel
    # Base risk from capability registry
    base_risk = get_capability_risk(proposal.capability_id)
    
    # Context modifiers
    modifier = _assess_parameter_risk(proposal.params)
    modifier += _assess_context_risk()
    
    return RiskLevel(min(Int(base_risk) + modifier, Int(CRITICAL)))
end
```

#### File: `adaptive-kernel/kernel/trust/ConfirmationGate.jl` (NEW)

```julia
"""
    ConfirmationGate - User confirmation for high-risk actions
"""
struct ConfirmationGate
    pending_confirmations::Dict{UUID, PendingAction}
    timeout::Int  # seconds
    
    function ConfirmationGate(timeout::Int=30)
        new(Dict{UUID, PendingAction}(), timeout)
    end
end

"""
    require_confirmation(gate::ConfirmationGate, proposal::ActionProposal)::UUID
Queue action for user confirmation, return confirmation ID
"""
function require_confirmation(gate::ConfirmationGate, proposal::ActionProposal)::UUID
    confirmation_id = uuid4()
    
    pending = PendingAction(
        id=confirmation_id,
        proposal=proposal,
        requested_at=now(),
        timeout=gate.timeout
    )
    
    gate.pending_confirmations[confirmation_id] = pending
    emit_confirmation_request(pending)
    
    return confirmation_id
end
```

### 9.2 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`adaptive-kernel/kernel/Kernel.jl:272`](adaptive-kernel/kernel/Kernel.jl:272) | `approve()` | Risk classification |
| [`adaptive-kernel/kernel/Kernel.jl:316`](adaptive-kernel/kernel/Kernel.jl:316) | `approve()` | Confirmation gate |

---

## PHASE 10: Error Handling & Recovery

### 10.1 Module Specifications

#### File: `adaptive-kernel/resilience/CircuitBreaker.jl` (NEW)

```julia
"""
    CircuitBreaker - Prevent cascading failures
"""
mutable struct CircuitBreaker
    name::String
    state::CircuitState  # :closed, :open, :half_open
    failure_count::Int
    success_count::Int
    last_failure_time::DateTime
    threshold::Int  # failures before opening
    timeout::Int  # seconds before half-open
    
    function CircuitBreaker(name::String; threshold::Int=5, timeout::Int=60)
        new(name, :closed, 0, 0, now(), threshold, timeout)
    end
end

@enum CircuitState CLOSED OPEN HALF_OPEN

"""
    call(breaker::CircuitBreaker, func::Function, args...; kwargs...)
Execute function through circuit breaker
"""
function call(breaker::CircuitBreaker, func::Function, args...; kwargs...)
    if breaker.state == OPEN
        # Check if timeout elapsed
        if (now() - breaker.last_failure_time).value / 1000 > breaker.timeout
            breaker.state = HALF_OPEN
        else
            throw(CircuitBreakerOpenError(breaker.name))
        end
    end
    
    try
        result = func(args...; kwargs...)
        on_success(breaker)
        return result
    catch e
        on_failure(breaker)
        rethrow(e)
    end
end
```

#### File: `adaptive-kernel/resilience/HealthMonitor.jl` (NEW)

```julia
"""
    HealthMonitor - Component health tracking
"""
mutable struct HealthMonitor
    components::Dict{String, ComponentHealth}
    last_check::DateTime
    
    function HealthMonitor()
        new(Dict{String, ComponentHealth}(), now())
    end
end

struct ComponentHealth
    name::String
    status::HealthStatus
    last_success::DateTime
    last_failure::DateTime
    failure_count::Int
end

@enum HealthStatus HEALTHY DEGRADED UNHEALTHY UNKNOWN

"""
    check_health(monitor::HealthMonitor, component::String)::HealthStatus
"""
function check_health(monitor::HealthMonitor, component::String)::HealthStatus
    health = get(monitor.components, component, nothing)
    health === nothing && return UNKNOWN
    
    # Unhealthy if recent failures
    if (now() - health.last_failure).value / 1000 < 60
        return health.failure_count > 3 ? UNHEALTHY : DEGRADED
    end
    
    return HEALTHY
end
```

### 10.2 Integration Call Sites

| Location | Function | Purpose |
|----------|----------|---------|
| [`jarvis/src/llm/LLMBridge.jl`](jarvis/src/llm/LLMBridge.jl:1) | `LLMBridge` | API circuit breaker |
| [`jarvis/src/voice/WhisperSTT.jl`](jarvis/src/voice/WhisperSTT.jl:1) | `WhisperSTT` | STT circuit breaker |
| [`jarvis/src/bridge/OpenClawBridge.jl`](jarvis/src/bridge/OpenClawBridge.jl:1) | `OpenClawBridge` | Tool circuit breaker |

---

# 3. INTEGRATION FLOWS

## 3.1 Complete Cognitive Loop

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     COMPLETE COGNITIVE LOOP                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│     ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                │
│     │ PERCEPTION  │ ───► │  COGNITION  │ ───► │ EXECUTION   │                │
│     └─────────────┘      └─────────────┘      └─────────────┘                │
│           │                    │                    │                          │
│           ▼                    ▼                    ▼                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ 1. Input        │  │ 4. Brain        │  │ 7. Kernel       │             │
│  │    Normalization│  │    Inference    │  │    Approval     │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│           │                    │                    │                          │
│           ▼                    ▼                    ▼                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ 2. Entity       │  │ 5. Proposal     │  │ 8. Capability   │             │
│  │    Extraction   │  │    Generation   │  │    Selection    │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│           │                    │                    │                          │
│           ▼                    ▼                    ▼                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ 3. Perception   │  │ 6. BrainOutput  │  │ 9. Tool         │             │
│  │    Vector Build │  │    (Advisory)  │  │    Execution    │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│                                                                  │              │
│                                                                  ▼              │
│              ┌─────────────────────────────────┐                               │
│              │  Kernel.reflect!()              │ ◄── Self-model update        │
│              │  (Self-Model Update)            │    Memory Storage           │
│              └─────────────────────────────────┘                               │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Kernel Sovereignty Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              SOVEREIGNTY ENFORCEMENT PATH                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. PROPOSAL SUBMISSION                                          │
│     BrainOutput → Kernel.request_approval(proposal)             │
│                                                                  │
│  2. RISK CLASSIFICATION                                          │
│     ├─ capability_id lookup                                      │
│     ├─ risk_level (low/medium/high/critical)                    │
│     └─ reversibility assessment                                   │
│                                                                  │
│  3. WORLD STATE VALIDATION                                       │
│     ├─ current_system_health check                              │
│     ├─ goal_alignment verification                              │
│     └─ resource_availability                                    │
│                                                                  │
│  4. TRUST CALIBRATION                                            │
│     ├─ user_trust_level retrieval                               │
│     ├─ action_risk vs trust_threshold comparison                │
│     └─ confirmation_gate evaluation                             │
│                                                                  │
│  5. DECISION (ATOMIC)                                            │
│     APPROVE  → proceed to execution                              │
│     DENY    → log denial, return to cognition                   │
│     STOP    → halt system if critical anomaly                   │
│                                                                  │
│  6. AUDIT TRAIL (NON-NEGOTIABLE)                                 │
│     ├─ timestamp (UTC ISO 8601)                                  │
│     ├─ proposal_hash                                             │
│     ├─ decision + reasoning                                      │
│     └─ trust_level_at_decision                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

# 4. ERROR & FAILURE MODELS

## 4.1 Failure Types

| Category | Failure Mode | Detection | Recovery |
|----------|--------------|-----------|----------|
| **Kernel** | State is nothing | StateValidator | Auto-init with defaults |
| **Kernel** | Approval timeout | Timeout watchdog | Fail-closed: DENY |
| **Brain** | Inference fails | Exception catch | Fallback: DENY all |
| **Brain** | Network unavailable | Health check | Switch to heuristic |
| **Observation** | Invalid metrics | NaN detection | Use last valid |
| **Voice** | STT API fails | HTTP error | Retry with backoff |
| **Vision** | VLM API fails | HTTP error | Retry with backoff |
| **Execution** | Tool timeout | Timeout | Circuit breaker opens |
| **Persistence** | Checkpoint fails | IOError | Log and continue |

## 4.2 Retry Strategy

```julia
"""
    RetryConfig - Configuration for retry behavior
"""
struct RetryConfig
    max_retries::Int
    initial_backoff::Float64  # seconds
    max_backoff::Float64  # seconds
    backoff_multiplier::Float64
    
    RetryConfig(;max_retries::Int=3, initial_backoff::Float64=1.0, 
               max_backoff::Float64=30.0, backoff_multiplier::Float64=2.0) = 
        new(max_retries, initial_backoff, max_backoff, backoff_multiplier)
end

"""
    with_retry(config::RetryConfig, func::Function)
Execute function with exponential backoff retry
"""
function with_retry(config::RetryConfig, func::Function)
    backoff = config.initial_backoff
    
    for attempt in 1:config.max_retries
        try
            return func()
        catch e
            if attempt == config.max_retries
                rethrow(e)
            end
            
            @warn "Attempt $attempt failed, retrying in $backoff seconds" error=string(e)
            sleep(backoff)
            backoff = min(backoff * config.backoff_multiplier, config.max_backoff)
        end
    end
end
```

## 4.3 Circuit Breaker Logic

```julia
function on_success(breaker::CircuitBreaker)
    breaker.failure_count = 0
    breaker.success_count += 1
    
    if breaker.state == HALF_OPEN && breaker.success_count >= 3
        breaker.state = CLOSED
        @info "Circuit breaker closed" name=breaker.name
    end
end

function on_failure(breaker::CircuitBreaker)
    breaker.failure_count += 1
    breaker.success_count = 0
    breaker.last_failure_time = now()
    
    if breaker.failure_count >= breaker.threshold
        breaker.state = OPEN
        @warn "Circuit breaker opened" name=breaker.name
    end
end
```

---

# 5. SECURITY MODELS

## 5.1 Auth Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        AUTH FLOW                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. SYSTEM STARTUP                                               │
│     ├─ Load config (non-secrets from TOML)                      │
│     ├─ Validate environment variables (secrets)                 │
│     └─ Initialize SecretsManager                                 │
│                                                                  │
│  2. API KEY LOADING                                              │
│     ├─ Check Vault (if configured)                             │
│     ├─ Fall back to ENV variables                               │
│     └─ Error if not found                                       │
│                                                                  │
│  3. SESSION ISOLATION                                            │
│     ├─ Per-session memory isolation                             │
│     ├─ No cross-session state mutation                          │
│     └─ User-scoped vector store                                 │
│                                                                  │
│  4. EXECUTION SANDBOX                                            │
│     ├─ Docker isolation for external tools                     │
│     ├─ Process isolation for native capabilities                │
│     └─ Resource limits (memory, CPU, timeout)                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 5.2 Token Handling

- **API Keys**: Loaded from environment variables, never stored in config files
- **Session Tokens**: Generated per-session, stored in memory only
- **Vault Integration**: Optional HashiCorp Vault for production secrets

## 5.3 Permission Boundaries

| Component | Permission Level | Boundary |
|-----------|-----------------|----------|
| **Brain** | Advisory only | Cannot access kernel state |
| **Kernel** | Sovereign | All execution passes through |
| **Capabilities** | Sandboxed | Resource limits enforced |
| **Memory** | Session-scoped | No cross-session access |
| **Observability** | Read-only | Cannot modify system |

---

# 6. TEST STRATEGIES

## 6.1 Unit Tests Required

| Phase | Test | Success Criteria |
|-------|------|-----------------|
| 1 | `test_kernel_never_nothing` | State never nothing after init |
| 1 | `test_approve_always_returns` | Always returns decision |
| 1 | `test_fail_closed` | Fails closed on errors |
| 2 | `test_brain_inference` | Produces valid BrainOutput |
| 2 | `test_confidence_bounds` | Confidence in [0,1] |
| 2 | `test_uncertainty_bounds` | Uncertainty in [0,1] |
| 3 | `test_observation_accuracy` | Matches system tools |
| 4 | `test_stt_transcription` | Accurate transcription |
| 4 | `test_tts_synthesis` | Valid audio output |
| 5 | `test_vlm_analysis` | Valid VisionResult |
| 6 | `test_tool_registration` | Tools registered correctly |
| 7 | `test_checkpoint_save` | State persisted correctly |
| 8 | `test_secrets_loading` | Secrets loaded from ENV |
| 9 | `test_risk_classification` | Correct risk levels |
| 10 | `test_circuit_breaker` | Opens after threshold |

## 6.2 Integration Tests Required

| Test | Purpose |
|------|---------|
| `test_brain_kernel_boundary` | Brain cannot bypass kernel |
| `test_approval_audit_trail` | All approvals logged |
| `test_full_cognitive_loop` | End-to-end perception→execution |
| `test_voice_pipeline` | STT→Cognition→TTS |
| `test_vision_pipeline` | Image→VLM→Memory |
| `test_persistence_recovery` | Restore from checkpoint |

## 6.3 Failure Simulation Cases

| Scenario | Simulation | Expected Behavior |
|----------|------------|-------------------|
| Brain unavailable | Set brain_core=nothing | Kernel uses fallback |
| API rate limit | Mock 429 response | Retry with backoff |
| Tool timeout | Mock timeout | Circuit breaker opens |
| Invalid observation | Inject NaN | Use last valid state |
| Checkpoint corruption | Corrupt file | Recovery fails gracefully |

---

# 7. DEPLOYMENT PLANS

## 7.1 Local Development Mode

```bash
# Environment variables for local development
export JARVIS_ENV=development
export JARVIS_LLM_API_KEY="sk-test-key"
export JARVIS_OPENCLAW_ENDPOINT="http://localhost:3000"

# Run with debug logging
julia --project=. -e 'using Jarvis; Jarvis.run(debug=true)'
```

## 7.2 Production Mode

```bash
# Environment variables for production
export JARVIS_ENV=production
export JARVIS_LLM_API_KEY="sk-prod-key"
export JARVIS_VAULT_ADDR="https://vault.example.com"
export JARVIS_VAULT_TOKEN="vault-token"

# Run as background daemon
julia --project=. -e 'using Jarvis; Jarvis.run_daemon()'
```

## 7.3 Required Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `JARVIS_ENV` | Yes | Environment: development/staging/production |
| `JARVIS_LLM_API_KEY` | Yes | LLM API key |
| `JARVIS_WHISPER_API_KEY` | No | Whisper STT API key |
| `JARVIS_ELEVENLABS_API_KEY` | No | ElevenLabs TTS API key |
| `JARVIS_OPENCLAW_ENDPOINT` | No | OpenClaw server URL |
| `JARVIS_VAULT_ADDR` | No | HashiCorp Vault address |
| `JARVIS_VAULT_TOKEN` | No | Vault authentication token |

## 7.4 Service Orchestration Model

```
┌─────────────────────────────────────────────────────────────────┐
│                    SERVICE ORCHESTRATION                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   Jarvis    │───▶│  OpenClaw   │───▶│   Vector    │         │
│  │   (Julia)   │    │   (Docker)  │    │   Store     │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│        │                                       │                 │
│        ▼                                       ▼                 │
│  ┌─────────────┐                       ┌─────────────┐         │
│  │   Kernel    │                       │  SQLite DB  │         │
│  │   (Julia)   │                       │  (Persistence)        │
│  └─────────────┘                       └─────────────┘         │
│                                                                  │
│  External Services:                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  OpenAI API │  │ElevenLabs  │  │   Vault     │            │
│  │  (STT/VLM)  │  │   (TTS)    │  │  (Secrets)  │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

# 8. FINAL OUTPUT

## 8.1 Master Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           MASTER DEPENDENCY GRAPH                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  PHASE 1: KERNEL SOVEREIGNTY                                                        │
│  ┌─────────────────┐                                                                │
│  │ StateValidator │ ──▶ Kernel.approve() ──▶ Execution                             │
│  └─────────────────┘                                                                │
│        │                                                                             │
│        ▼                                                                             │
│  PHASE 2: BRAIN INTEGRATION                                                         │
│  ┌─────────────────┐     ┌─────────────────┐                                     │
│  │ NeuralBrain.jl  │ ──▶ │ BrainTrainer.jl │ ──▶ ExperienceBuffer                  │
│  └─────────────────┘     └─────────────────┘                                     │
│        │                                                                             │
│        ▼                                                                             │
│  PHASE 3: OBSERVATION                                                               │
│  ┌─────────────────┐     ┌─────────────────┐                                     │
│  │SystemObserver   │ ──▶ │ Kernel.evaluate  │                                     │
│  └─────────────────┘     └─────────────────┘                                     │
│        │                                                                             │
│        ▼                                                                             │
│  PHASE 4-5: INPUT PIPELINES                                                         │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                                    │
│  │ WhisperSTT │  │ElevenLabs  │  │  VLMClient │ ──▶ PerceptionVector               │
│  └────────────┘  └────────────┘  └────────────┘                                    │
│        │                │                │                                           │
│        └────────────────┼────────────────┘                                           │
│                         ▼                                                            │
│  PHASE 6: EXECUTION                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  ToolRegistry   │  │ExecutionSandbox │  │RiskClassifier  │ ──▶ Kernel.approve  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                   │
│        │                                                                             │
│        ▼                                                                             │
│  PHASE 7: PERSISTENCE                                                               │
│  ┌─────────────────┐  ┌─────────────────┐                                          │
│  │  Checkpointer   │  │  VectorStore    │ ──▶ Memory                                │
│  └─────────────────┘  └─────────────────┘                                          │
│        │                                                                             │
│        ▼                                                                             │
│  PHASE 8: CONFIGURATION                                                             │
│  ┌─────────────────┐  ┌─────────────────┐                                          │
│  │ SecretsManager  │  │  ConfigLoader   │ ──▶ All Components                        │
│  └─────────────────┘  └─────────────────┘                                          │
│        │                                                                             │
│        ▼                                                                             │
│  PHASE 9: TRUST                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐                                          │
│  │RiskClassifier   │  │ConfirmationGate│ ──▶ Kernel.approve                         │
│  └─────────────────┘  └─────────────────┘                                          │
│        │                                                                             │
│        ▼                                                                             │
│  PHASE 10: RESILIENCE                                                               │
│  ┌─────────────────┐  ┌─────────────────┐                                          │
│  │CircuitBreaker   │  │ HealthMonitor   │ ──▶ All External APIs                     │
│  └─────────────────┘  └─────────────────┘                                          │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## 8.2 Critical Path Timeline

| Phase | Dependency | Estimated Effort | Priority |
|-------|------------|------------------|----------|
| 1 | None | 1 day | P0 |
| 2 | 1 | 3 days | P0 |
| 3 | 1 | 2 days | P1 |
| 4 | 2 | 3 days | P1 |
| 5 | 2 | 3 days | P1 |
| 6 | 1 | 2 days | P1 |
| 7 | 1 | 2 days | P2 |
| 8 | None | 1 day | P1 |
| 9 | 1 | 2 days | P2 |
| 10 | 4,5,6 | 2 days | P2 |

**Total Estimated Effort: 21 days**

## 8.3 Parallelizable Components

| Components | Can Run In Parallel |
|------------|---------------------|
| Phase 4 (Voice) + Phase 5 (Vision) | Yes |
| Phase 6 (Tool Registry) + Phase 7 (Persistence) | Yes |
| Phase 8 (Config) + Phase 10 (Resilience) | Yes |

## 8.4 Risk-Ranked Module List

| Rank | Module | Risk | Mitigation |
|------|--------|------|------------|
| 1 | Kernel.approve() | CRITICAL | Fail-closed, audit trail |
| 2 | ExecutionSandbox | HIGH | Resource limits, isolation |
| 3 | SecretsManager | HIGH | Vault integration, ENV fallback |
| 4 | CircuitBreaker | MEDIUM | Thorough testing |
| 5 | VoicePipeline | MEDIUM | Graceful degradation |
| 6 | VisionPipeline | MEDIUM | Content filtering |
| 7 | Checkpointer | LOW | Verify on restore |

## 8.5 Definition of "Production Ready"

A module is **Production Ready** when:

1. **All unit tests pass** - 100% pass rate on unit tests
2. **Integration tests pass** - Full cognitive loop functional
3. **Failure modes handled** - All identified failure modes have recovery
4. **Security review passed** - No critical security issues
5. **Documentation complete** - All public APIs documented
6. **Performance acceptable** - Meets latency targets:
   - Cognitive cycle: <100ms (excluding external APIs)
   - Kernel approval: <5ms
   - Tool execution: <30s (configurable timeout)
7. **Observability in place** - Logging, metrics, health checks

---

**END OF IMPLEMENTATION BLUEPRINT**
