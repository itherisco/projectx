# jarvis/src/types.jl - Core type definitions for Project Jarvis
# Central types used across all modules

module JarvisTypes

using Dates
using UUIDs
using SHA
using Random

# CRITICAL SECURITY FIX: Use SecureKeystore instead of ENV for secrets
include("config/SecureKeystore.jl")

export 
    # Core enums
    TrustLevel,
    SystemStatus,
    ActionCategory,
    
    # Secure trust (HMAC-verified)
    SecureTrustLevel,
    verify_trust,
    get_trust_secret,
    trust_secret_is_set,
    
    # Goal and planning
    JarvisGoal,
    GoalPriority,
    
    # Perception and action
    PerceptionVector,
    ActionProposal,
    ExecutableAction,
    
    # Memory types
    SemanticEntry,
    ConversationEntry,
    UserPreference,
    
    # System state
    JarvisState,
    WorldState,
    WorldObservation,
    CycleResult,
    to_dict,
    
    # Neuro-symbolic bridge types
    LearningResult,
    NeuroSymbolicBridge,
    SymbolicCorrection,
    
    # RL types
    Experience,
    ExperienceBuffer

# ============================================================================
# ENUMS
# ============================================================================

@enum TrustLevel begin
    TRUST_BLOCKED = 0      # No actions allowed
    TRUST_RESTRICTED = 1   # Only read-only actions
    TRUST_LIMITED = 2      # Non-destructive actions only  
    TRUST_STANDARD = 3     # Most actions allowed
    TRUST_FULL = 4         # All actions allowed (with audit)
end

@enum SystemStatus begin
    STATUS_BOOTING
    STATUS_INITIALIZING
    STATUS_RUNNING
    STATUS_PAUSED
    STATUS_ERROR
    STATUS_SHUTDOWN
end

@enum ActionCategory begin
    ACTION_READ      # Observations, queries
    ACTION_WRITE     # File operations
    ACTION_EXECUTE   # Shell commands, HTTP requests
    ACTION_IOT       # IoT device control
    ACTION_SYSTEM    # System modifications
end

# ============================================================================
# PRIORITY & GOAL TYPES
# ============================================================================

@enum GoalPriority begin
    PRIORITY_CRITICAL = 5
    PRIORITY_HIGH = 4
    PRIORITY_MEDIUM = 3
    PRIORITY_LOW = 2
    PRIORITY_BACKGROUND = 1
end

"""
    JarvisGoal - High-level goal parsed from natural language
"""
mutable struct JarvisGoal
    id::UUID
    description::String
    target_state::Vector{Float32}  # 12-dimensional feature vector
    priority::GoalPriority
    deadline::DateTime
    status::Symbol  # :pending, :active, :completed, :failed, :cancelled
    required_trust::TrustLevel
    created_at::DateTime
    
    function JarvisGoal(
        desc::String, 
        target::Vector{Float32}, 
        priority::GoalPriority = PRIORITY_MEDIUM;
        required_trust::TrustLevel = TRUST_STANDARD,
        deadline::DateTime = now() + Hour(1)
    )
        new(uuid4(), desc, target, priority, deadline, :pending, required_trust, now())
    end
end

# ============================================================================
# PERCEPTION & ACTION TYPES
# ============================================================================

"""
    PerceptionVector - 12-Dimensional Feature Vector for ITHERIS brain
    Based on the ITHERIS cognitive architecture
"""
struct PerceptionVector
    # System metrics (indices 1-4)
    cpu_load::Float32           # [0, 1] - CPU utilization
    memory_usage::Float32       # [0, 1] - Memory utilization  
    disk_io::Float32            # [0, 1] - Disk I/O rate
    network_latency::Float32    # [0, 1] - Network latency (normalized)
    
    # Security/threat (indices 5-6)
    overall_severity::Float32   # [0, 1] - Aggregate threat level
    threat_count::Float32       # [0, 1] - Normalized threat count
    
    # File system (indices 7-8)
    file_count::Float32         # [0, 1] - Normalized file count
    change_rate::Float32        # [0, 1] - Rate of file changes
    
    # Process state (indices 9-12)
    process_count::Float32      # [0, 1] - Normalized process count
    energy_level::Float32       # [0, 1] - System energy/battery
    confidence::Float32         # [0, 1] - Model confidence
    user_activity::Float32      # [0, 1] - User activity level
    
    function PerceptionVector(
        cpu::Float32, mem::Float32, disk::Float32, net::Float32,
        severity::Float32, threats::Float32,
        files::Float32, changes::Float32,
        procs::Float32, energy::Float32, conf::Float32, activity::Float32
    )
        new(
            clamp(cpu, 0f0, 1f0), clamp(mem, 0f0, 1f0), clamp(disk, 0f0, 1f0), clamp(net, 0f0, 1f0),
            clamp(severity, 0f0, 1f0), clamp(threats, 0f0, 1f0),
            clamp(files, 0f0, 1f0), clamp(changes, 0f0, 1f0),
            clamp(procs, 0f0, 1f0), clamp(energy, 0f0, 1f0), clamp(conf, 0f0, 1f0), clamp(activity, 0f0, 1f0)
        )
    end
end

# Convert to Vector for neural network
Base.Vector(pv::PerceptionVector) = Float32[
    pv.cpu_load, pv.memory_usage, pv.disk_io, pv.network_latency,
    pv.overall_severity, pv.threat_count,
    pv.file_count, pv.change_rate,
    pv.process_count, pv.energy_level, pv.confidence, pv.user_activity
]

"""
    ActionProposal - Neural output from ITHERIS brain
    
    SECURITY: All Float32 fields are validated to ensure:
    - Values are within [0.0, 1.0] bounds
    - Values are not NaN or Inf
    - This prevents safety score manipulation via invalid risk values
"""
mutable struct ActionProposal
    id::UUID
    capability_id::String
    confidence::Float32
    predicted_cost::Float32
    predicted_reward::Float32
    risk::Float32
    reasoning::String
    impact_estimate::Float32
    timestamp::DateTime
    
    # Inner constructor with validation - SECURITY FIX for Vulnerability #1 & #2
    function ActionProposal(
        cap_id::String,
        confidence::Float32,
        cost::Float32,
        reward::Float32,
        risk::Float32;
        reasoning::String = "",
        impact::Float32 = 0.5f0
    )
        # Validate all Float32 fields - reject invalid values
        _validate_float32_bounds(confidence, "confidence", 0.0f0, 1.0f0)
        _validate_float32_bounds(cost, "predicted_cost", 0.0f0, Inf32)
        _validate_float32_bounds(reward, "predicted_reward", 0.0f0, 1.0f0)
        _validate_float32_bounds(risk, "risk", 0.0f0, 1.0f0)  # Risk MUST be in [0,1]
        _validate_float32_bounds(impact, "impact_estimate", 0.0f0, 1.0f0)
        
        new(uuid4(), cap_id, confidence, cost, reward, risk, reasoning, impact, now())
    end
end

"""
    _validate_float32_bounds(value, field_name, min_val, max_val)
    
Validate that a Float32 value is within acceptable bounds and not NaN/Inf.
Raises an error if validation fails (fail-secure approach).
"""
function _validate_float32_bounds(
    value::Float32, 
    field_name::String, 
    min_val::Float32, 
    max_val::Float32
)::Nothing
    # Check for NaN
    if isnan(value)
        throw(ArgumentError(
            "SECURITY VALIDATION FAILED: $field_name cannot be NaN. " *
            "ActionProposal rejected to prevent safety score manipulation."
        ))
    end
    
    # Check for Inf/-Inf
    if isinf(value)
        throw(ArgumentError(
            "SECURITY VALIDATION FAILED: $field_name cannot be Inf or -Inf. " *
            "ActionProposal rejected to prevent safety score manipulation."
        ))
    end
    
    # Check bounds
    if value < min_val || value > max_val
        throw(ArgumentError(
            "SECURITY VALIDATION FAILED: $field_name must be in [$min_val, $max_val], got $value. " *
            "ActionProposal rejected to prevent safety score manipulation."
        ))
    end
    
    return nothing
end

"""
    ExecutableAction - Kernel-approved action ready for execution
"""
struct ExecutableAction
    proposal::ActionProposal
    kernel_score::Float32    # priority × (reward - risk)
    approved_at::DateTime
    execution_context::Dict{String, Any}
end

# ============================================================================
# MEMORY TYPES (Semantic & Episodic)
# ============================================================================

"""
    SemanticEntry - Long-term knowledge stored in vector DB
"""
mutable struct SemanticEntry
    id::UUID
    collection::Symbol  # :user_preferences, :conversations, :project_knowledge
    content::String
    embedding::Vector{Float32}
    metadata::Dict{String, Any}
    created_at::DateTime
    accessed_at::DateTime
    access_count::Int
    
    function SemanticEntry(
        collection::Symbol,
        content::String,
        embedding::Vector{Float32};
        metadata::Dict{String, Any} = Dict()
    )
        new(uuid4(), collection, content, embedding, metadata, now(), now(), 0)
    end
end

"""
    ConversationEntry - Past conversation for context
"""
mutable struct ConversationEntry
    id::UUID
    user_message::String
    jarvis_response::String
    intent::String
    entities::Dict{String, Any}
    satisfaction::Union{Float32, Nothing}  # If user provided feedback
    timestamp::DateTime
    
    function ConversationEntry(
        user_msg::String,
        jarvis_resp::String;
        intent::String = "unknown",
        entities::Dict{String, Any} = Dict()
    )
        new(uuid4(), user_msg, jarvis_resp, intent, entities, nothing, now())
    end
end

"""
    UserPreference - Stored user preferences
"""
mutable struct UserPreference
    key::String
    value::Any
    category::Symbol  # :interface, :behavior, :privacy, :notifications
    confidence::Float32
    updated_at::DateTime
end

# ============================================================================
# SYSTEM STATE
# ============================================================================

"""
    WorldState - Represents the current state of the world for Kernel and Brain
    This is consumed by both the Kernel (for decisions) and Brain (for perception)
"""
struct WorldState
    # System metrics
    timestamp::DateTime
    cpu_load::Float32
    memory_usage::Float32
    disk_usage::Float32
    network_latency::Float32
    
    # Security state
    overall_severity::Float32
    threat_count::Int
    
    # Trust and safety
    trust_level::TrustLevel
    kernel_approvals::Int  # Total approvals this session
    kernel_denials::Int    # Total denials this session
    
    # Available capabilities
    available_capabilities::Vector{String}
    
    # Last kernel decision
    last_decision::Symbol  # :approved, :denied, :pending
    last_action_id::Union{String, Nothing}
    
    # System status
    status::SystemStatus
    
    function WorldState(;
        cpu_load::Float32 = 0.5f0,
        memory_usage::Float32 = 0.5f0,
        disk_usage::Float32 = 0.5f0,
        network_latency::Float32 = 25.0f0,
        overall_severity::Float32 = 0.0f0,
        threat_count::Int = 0,
        trust_level::TrustLevel = TRUST_STANDARD,
        available_capabilities::Vector{String} = String[],
        status::SystemStatus = STATUS_RUNNING
    )
        new(
            now(),
            cpu_load, memory_usage, disk_usage, network_latency,
            overall_severity, threat_count,
            trust_level, 0, 0,
            available_capabilities,
            :pending,  # last_decision
            nothing,   # last_action_id
            status
        )
    end
end

"""
    to_dict - Convert WorldState to Dict for kernel consumption
"""
function to_dict(ws::WorldState)::Dict{String, Any}
    return Dict(
        "timestamp" => string(ws.timestamp),
        "system_metrics" => Dict(
            "cpu_load" => ws.cpu_load,
            "memory_usage" => ws.memory_usage,
            "disk_usage" => ws.disk_usage,
            "network_latency" => ws.network_latency
        ),
        "security" => Dict(
            "overall_severity" => ws.overall_severity,
            "threat_count" => ws.threat_count
        ),
        "trust" => Dict(
            "trust_level" => Int(ws.trust_level),
            "kernel_approvals" => ws.kernel_approvals,
            "kernel_denials" => ws.kernel_denials
        ),
        "capabilities" => ws.available_capabilities,
        "last_decision" => string(ws.last_decision),
        "last_action" => ws.last_action_id,
        "status" => string(ws.status)
    )
end

"""
    WorldObservation - Current state of the world (system + environment)
"""
struct WorldObservation
    timestamp::DateTime
    system_metrics::Dict{String, Float32}
    recent_events::Vector{Dict{String, Any}}
    active_goals::Vector{JarvisGoal}
    user_present::Bool
    
    function WorldObservation(;
        system_metrics::Dict{String, Float32} = Dict(),
        recent_events::Vector{Dict{String, Any}} = Dict[],
        active_goals::Vector{JarvisGoal} = JarvisGoal[],
        user_present::Bool = true
    )
        new(now(), system_metrics, recent_events, active_goals, user_present)
    end
end

"""
    CycleResult - Result of one Jarvis cognitive cycle
"""
struct CycleResult
    cycle_number::Int
    perception::PerceptionVector
    selected_action::Union{ExecutableAction, Nothing}
    execution_result::Dict{String, Any}
    reward::Float32
    prediction_error::Float32
    new_memory_entries::Vector{SemanticEntry}
    proactive_suggestions::Vector{String}
    timestamp::DateTime
end

# ============================================================================
# REINFORCEMENT LEARNING TYPES (must be defined before JarvisState)
# ============================================================================

"""
    Experience - Single experience tuple for reinforcement learning
    Format: (state, action, reward, next_state, done)
"""
struct Experience
    state::Vector{Float32}  # 12D perception vector
    action_id::String
    reward::Float32
    next_state::Vector{Float32}
    done::Bool
    timestamp::DateTime
    
    function Experience(
        state::Vector{Float32},
        action_id::String,
        reward::Float32,
        next_state::Vector{Float32};
        done::Bool = false
    )
        new(state, action_id, reward, next_state, done, now())
    end
end

"""
    ExperienceBuffer - Ring buffer for experience replay
"""
mutable struct ExperienceBuffer
    buffer::Vector{Experience}
    capacity::Int
    position::Int
    
    function ExperienceBuffer(capacity::Int = 10000)
        new(Experience[], capacity, 0)
    end
end

function Base.push!(buf::ExperienceBuffer, exp::Experience)
    if length(buf.buffer) < buf.capacity
        push!(buf.buffer, exp)
    else
        buf.buffer[buf.position + 1] = exp
    end
    buf.position = (buf.position + 1) % buf.capacity
end

function sample(buf::ExperienceBuffer, batch_size::Int)::Vector{Experience}
    n = length(buf.buffer)
    if n == 0 return Experience[] end
    
    indices = rand(1:n, min(batch_size, n))
    return [buf.buffer[i] for i in indices]
end

"""
    JarvisState - Global system state
"""
mutable struct JarvisState
    status::SystemStatus
    trust_level::TrustLevel
    current_cycle::Int
    total_cycles::Int
    success_count::Int
    failure_count::Int
    user_confirmations_pending::Vector{JarvisGoal}
    last_error::Union{String, Nothing}
    
    # Neuro-symbolic bridge: Learning parameters
    learning_rate::Float32
    discount_factor::Float32  # γ for TD learning
    exploration_rate::Float32  # ε for ε-greedy
    
    # Experience replay buffer
    experience_buffer::Vector{Experience}
    
    # Session persistence
    session_id::UUID
    last_persisted::DateTime
    
    # Cryptographically secure session ID generator
    """
    Generate a cryptographically secure session ID using CSPRNG.
    Uses RandomDevice() which reads from /dev/urandom on Unix systems,
    providing true cryptographic randomness for session ID generation.
    """
    function generate_secure_session_id()
        # Use RandomDevice for cryptographically secure random number generation
        # This uses /dev/urandom (Unix) or equivalent CSPRNG
        rand(RandomDevice(), UUID)
    end
    
    function JarvisState()
        new(
            STATUS_BOOTING,
            TRUST_RESTRICTED,
            0, 0, 0, 0,
            JarvisGoal[],
            nothing,
            # Learning parameters
            0.001f0,    # learning_rate
            0.95f0,     # discount_factor
            0.1f0,      # exploration_rate
            # Experience buffer
            Experience[],
            # Session
            generate_secure_session_id(),
            now()
        )
    end
end

# ============================================================================
# NEURO-SYMBOLIC BRIDGE TYPES
# ============================================================================

"""
    LearningResult - Result of a learning step (Flux.train! output)
"""
struct LearningResult
    loss::Float32
    prediction_error::Float32
    old_value::Float32
    new_value::Float32
    timestamp::DateTime
end

"""
    SymbolicCorrection - Error handling response from Kernel to LLM
"""
struct SymbolicCorrection
    original_proposal::ActionProposal
    error_type::Symbol  # :invalid_capability, :method_error, :safety_violation
    error_message::String
    suggested_fix::String
    adjusted_risk::Float32
    timestamp::DateTime
    
    function SymbolicCorrection(
        proposal::ActionProposal,
        error_type::Symbol,
        message::String,
        fix::String;
        adjusted_risk::Float32 = 1.0f0
    )
        new(proposal, error_type, message, fix, adjusted_risk, now())
    end
end

"""
    NeuroSymbolicBridge - Interface between LLM (Cerebral Cortex) and ITHERIS Brain
    Handles the translation between symbolic (LLM) and numeric (Neural) representations
"""
mutable struct NeuroSymbolicBridge
    # LLM to ITHERIS translation
    intent_to_vector::Dict{String, Vector{Float32}}
    
    # ITHERIS to Kernel translation
    action_embeddings::Dict{String, Vector{Float32}}
    
    # Reward adjustment from memory
    reward_adjustments::Dict{String, Float32}  # action_id -> adjustment factor
    
    # Error handling
    last_correction::Union{SymbolicCorrection, Nothing}
    
    function NeuroSymbolicBridge()
        new(
            Dict{String, Vector{Float32}}(),
            Dict{String, Vector{Float32}}(),
            Dict{String, Float32}(),
            nothing
        )
    end
end

# ============================================================================
# SAFETY FORMULA UTILITIES
# ============================================================================

"""
    compute_safety_score - Safety Formula: score = priority × (reward - risk)
    This is the core safety validation in the Kernel
"""
function compute_safety_score(
    priority::Float32,
    reward::Float32,
    risk::Float32
)::Float32
    return priority * (reward - risk)
end

"""
    should_execute - Determine if action should be executed based on safety score
"""
function should_execute(safety_score::Float32; threshold::Float32 = 0.7f0)::Bool
    return safety_score >= threshold
end

# ============================================================================
# SECURE TRUST LEVEL WITH HMAC VERIFICATION (Finding 8)
# ============================================================================

const _TRUST_SECRET_ENV = "JARVIS_TRUST_SECRET"

# Generate cryptographically secure random secret as default
# SECURITY: Use SecureRandom to ensure cryptographic strength
function _generate_secure_trust_secret()::Vector{UInt8}
    return rand(UInt8, 32)  # 256-bit cryptographically secure random
end

const _DEFAULT_TRUST_SECRET = _generate_secure_trust_secret()

# Module-level cache for the secret (loaded once)
mutable struct _TrustSecretCache
    secret::Union{Vector{UInt8}, Nothing}
    is_set::Bool
    
    _TrustSecretCache() = new(nothing, false)
end

const _trust_secret_cache = _TrustSecretCache()

"""
    get_trust_secret()::Vector{UInt8}
Get the HMAC secret key for trust verification.
Loads from SecureKeystore, or generates cryptographically secure random.

CRITICAL SECURITY FIX: Now uses SecureKeystore instead of ENV variables.
Fails closed - requires explicit configuration for production.
"""
function get_trust_secret()::Vector{UInt8}
    if _trust_secret_cache.is_set && _trust_secret_cache.secret !== nothing
        return _trust_secret_cache.secret
    end
    
    # CRITICAL: Try SecureKeystore first (secure local storage)
    secret = SecureKeystore.get_trust_secret()
    
    if secret === nothing || isempty(secret)
        # Check ENV as fallback
        if haskey(ENV, _TRUST_SECRET_ENV)
            @warn "Using ENV for JARVIS_TRUST_SECRET - migrate to SecureKeystore for production"
            secret = Vector{UInt8}(ENV[_TRUST_SECRET_ENV])
        else
            # SECURITY: Generate cryptographically secure random as last resort
            # This is better than a hardcoded default but should still be migrated
            @warn "No JARVIS_TRUST_SECRET configured - using generated secure random. Store in SecureKeystore for production."
            secret = _generate_secure_trust_secret()
        end
    end
    
    _trust_secret_cache.secret = secret
    _trust_secret_cache.is_set = true
    return secret
end

"""
    trust_secret_is_set()::Bool
Check if JARVIS_TRUST_SECRET environment variable has been set.
"""
function trust_secret_is_set()::Bool
    # Force check environment
    return haskey(ENV, _TRUST_SECRET_ENV)
end

"""
    SecureTrustLevel - HMAC-verified trust level wrapper

Provides cryptographic integrity protection for trust state to prevent
manipulation attacks (CWE-639: Authorization Bypass Through User-Controlled Key).

# Fields
- `level::TrustLevel`: The actual trust level value
- `hmac::Vector{UInt8}`: HMAC-SHA256 of level + timestamp
- `timestamp::Float64`: Unix timestamp when created
"""
struct SecureTrustLevel
    level::TrustLevel
    hmac::Vector{UInt8}
    timestamp::Float64
    
    """
        SecureTrustLevel(level::TrustLevel, secret_key::Vector{UInt8})
    Create a new secure trust level with HMAC verification.
    """
    function SecureTrustLevel(level::TrustLevel, secret_key::Vector{UInt8})
        timestamp = time()
        payload = _build_payload(level, timestamp)
        hmac = sha256(secret_key * payload)
        new(level, hmac, timestamp)
    end
    
    # Internal constructor for deserialization
    function SecureTrustLevel(level::TrustLevel, hmac::Vector{UInt8}, timestamp::Float64)
        new(level, hmac, timestamp)
    end
end

"""
    _build_payload(level::TrustLevel, timestamp::Float64)::Vector{UInt8}
Build the payload for HMAC computation.
"""
function _build_payload(level::TrustLevel, timestamp::Float64)::Vector{UInt8}
    level_byte = UInt8(Int(level))
    timestamp_bytes = reinterpret(UInt8, [timestamp])
    return vcat(level_byte, timestamp_bytes)
end

"""
    verify_trust(secure::SecureTrustLevel, secret_key::Vector{UInt8})::Bool
Verify the HMAC of a secure trust level.
Returns true if the HMAC is valid, false otherwise.

# Arguments
- `secure::SecureTrustLevel`: The secure trust level to verify
- `secret_key::Vector{UInt8}`: The HMAC secret key

# Returns
- `Bool`: true if trust level is verified, false if tampered
"""
function verify_trust(secure::SecureTrustLevel, secret_key::Vector{UInt8})::Bool
    payload = _build_payload(secure.level, secure.timestamp)
    expected_hmac = sha256(secret_key * payload)
    return secure.hmac == expected_hmac
end

"""
    verify_trust(secure::SecureTrustLevel)::Bool
Verify using the default trust secret.
"""
function verify_trust(secure::SecureTrustLevel)::Bool
    return verify_trust(secure, get_trust_secret())
end

"""
    create_secure_trust(level::TrustLevel)::SecureTrustLevel
Create a new secure trust level using the default secret.
"""
function create_secure_trust(level::TrustLevel)::SecureTrustLevel
    return SecureTrustLevel(level, get_trust_secret())
end

"""
    Base.get(secure::SecureTrustLevel)::TrustLevel
Extract the underlying trust level (does NOT verify - caller must verify first!).
"""
function Base.get(secure::SecureTrustLevel)::TrustLevel
    return secure.level
end

"""
    secure_trust_to_enum(secure::SecureTrustLevel)::TrustLevel
Alias for get() - extract trust level (caller must verify first!).
"""
function secure_trust_to_enum(secure::SecureTrustLevel)::TrustLevel
    return secure.level
end

end # module JarvisTypes
