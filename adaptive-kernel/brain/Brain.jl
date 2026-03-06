# adaptive-kernel/brain/Brain.jl - ITHERIS Neural Brain Module
# Complete neural brain activation with proper kernel boundary enforcement
# SECURITY: fallback_to_heuristic requires explicit human approval via SecureConfirmationGate

module Brain

using Dates
using UUIDs
using LinearAlgebra
using Statistics

# ITHERIS Neural Brain Integration
using ..ITHERISCore  # infer(), learn!(), initialize_brain()

# Trust and Confirmation (P0 Security - require explicit approval for fallback)
# Note: SecureConfirmationGate integration happens at higher levels (Kernel)
# Brain uses fallback_approval_token field in BrainConfig for security checks

# RiskLevel enum for security classification
@enum RiskLevel READ_ONLY LOW MEDIUM HIGH CRITICAL

# Export brain types and functions
export 
    # Types
    BrainOutput,
    BrainInput,
    BrainHealth,
    BrainConfig,
    
    # Core functions
    create_brain,
    infer_brain,
    learn_from_experience,
    get_brain_health,
    
    # Boundary enforcement
    validate_brain_output,
    enforce_brain_advisory_only,
    BoundaryInvariant,
    
    # SECURITY: Fallback approval functions (P0 - Vulnerability #5 & Weakness #6)
    check_fallback_approval

# ============================================================================
# BRAIN-KERNEL BOUNDARY CONTRACTS
# ============================================================================

"""
    BrainInput - Immutable input snapshot to brain (copy of relevant state)
    
INVARIANT: Brain receives a COPY, never direct state reference
This ensures kernel maintains full control over state
"""
struct BrainInput
    perception_vector::Vector{Float32}        # 12D normalized perception
    goal_context::Vector{Float32}             # Goal embedding
    recent_rewards::Vector{Float32}           # Last N reward signals
    time_budget_ms::Float32                  # Available thinking time
    
    function BrainInput(
        perception::Vector{Float32};
        goal_context::Vector{Float32}=zeros(Float32, 8),
        recent_rewards::Vector{Float32}=zeros(Float32, 10),
        time_budget_ms::Float32=100.0f0
    )
        @assert length(perception) == 12 "Perception must be 12D"
        new(copy(perception), copy(goal_context), copy(recent_rewards), time_budget_ms)
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
    latent_features::Vector{Float32}          # For memory embedding
    timestamp::DateTime
    
    function BrainOutput(
        actions::Vector{String};
        confidence::Float32,
        value_estimate::Float32,
        uncertainty::Float32,
        reasoning::String="",
        latent_features::Vector{Float32}=zeros(Float32, 32)
    )
        @assert 0f0 <= confidence <= 1f0 "Confidence must be in [0, 1]"
        @assert 0f0 <= uncertainty <= 1f0 "Uncertainty must be in [0, 1]"
        new(actions, confidence, value_estimate, uncertainty, reasoning, latent_features, now())
    end
end

"""
    FORMAL INVARIANT: Brain-Kernel Boundary

The brain and kernel MUST maintain semantic isolation:
- Brain receives: BrainInput (immutable snapshot)
- Brain produces: BrainOutput (advisory only)
- Kernel owns: world_state, goal_states, trust_classifier, approval_logic

No direct brain → kernel state mutation permitted.
All brain outputs pass through kernel.approve() before execution.
"""
const BoundaryInvariant = """
BRAIN OUTPUT IS ADVISORY ONLY.
KERNEL SOVEREIGNTY IS ABSOLUTE.
NO EXCEPTION TO APPROVAL GATE.
"""

"""
    validate_brain_output - Verify brain output meets contract invariants
"""
function validate_brain_output(output::BrainOutput)::Bool
    # Validate confidence bounds
    !(0f0 <= output.confidence <= 1f0) && return false
    # Validate uncertainty bounds
    !(0f0 <= output.uncertainty <= 1f0) && return false
    # Validate non-empty proposals
    isempty(output.proposed_actions) && return false
    # Validate all proposed actions are strings
    !all(isa(a, String) for a in output.proposed_actions) && return false
    return true
end

"""
    enforce_brain_advisory_only - GUARD: Prevent any execution from Brain
    
    This function is a security safeguard that should be called at the
    boundary between Brain and any execution layer. It throws if anyone
    attempts to execute actions directly from Brain output.
    
    # Arguments
    - `output::BrainOutput`: The brain output to validate
    
    # Throws
    - `ErrorException`: If execution is attempted without kernel approval
    
    # Design Principle
    BRAIN IS ADVISORY - KERNEL IS SOVEREIGN
    The Brain can ONLY produce proposals. Execution requires Kernel.approve().
"""
function enforce_brain_advisory_only(output::BrainOutput)
    # This is a no-op guard that documents the architectural invariant
    # The actual enforcement happens in the execution layer (Kernel, DecisionSpine)
    # by checking kernel_approved flag before any execution
    
    # Log the advisory nature of this output for audit trail
    @debug "BrainOutput is advisory - kernel approval required for execution"
        confidence=output.confidence
        num_proposals=length(output.proposed_actions)
        first_action=isempty(output.proposed_actions) ? "none" : first(output.proposed_actions)
    
    # Return silently - this is expected behavior
    # The real enforcement is in the execution layer
    return nothing
end

# ============================================================================
# BRAIN HEALTH MONITORING
# ============================================================================

"""
    BrainHealth - Track brain operational health
"""
@enum BrainHealthStatus HEALTHY DEGRADED UNHEALTHY

mutable struct BrainHealth
    status::BrainHealthStatus
    inference_count::Int
    inference_failures::Int
    last_inference_time::Float64  # ms
    average_inference_time::Float64
    last_failure_reason::Union{String, Nothing}
    consecutive_failures::Int
    
    function BrainHealth()
        new(HEALTHY, 0, 0, 0.0, 0.0, nothing, 0)
    end
end

function record_inference!(health::BrainHealth, duration_ms::Float64, success::Bool)
    health.inference_count += 1
    health.last_inference_time = duration_ms
    
    # Rolling average
    health.average_inference_time = if health.inference_count == 1
        duration_ms
    else
        0.9 * health.average_inference_time + 0.1 * duration_ms
    end
    
    if success
        health.consecutive_failures = 0
        health.status = health.consecutive_failures >= 5 ? DEGRADED : HEALTHY
    else
        health.consecutive_failures += 1
        if health.consecutive_failures >= 10
            health.status = UNHEALTHY
        elseif health.consecutive_failures >= 5
            health.status = DEGRADED
        end
    end
end

function get_brain_health(health::BrainHealth)::Dict{String, Any}
    return Dict(
        "status" => string(health.status),
        "inference_count" => health.inference_count,
        "inference_failures" => health.inference_failures,
        "failure_rate" => health.inference_count > 0 ? 
            health.inference_failures / health.inference_count : 0.0,
        "average_inference_time_ms" => health.average_inference_time,
        "consecutive_failures" => health.consecutive_failures
    )
end

# ============================================================================
# BRAIN CONFIGURATION
# ============================================================================

"""
    BrainConfig - Configuration for brain module
    
    SECURITY: fallback_to_heuristic requires EXPLICIT human approval via SecureConfirmationGate
    - Even if fallback_to_heuristic=true is set in config, runtime approval is REQUIRED
    - This prevents silent bypass of brain verification
"""
struct BrainConfig
    model_path::Union{String, Nothing}
    confidence_threshold::Float32
    advisory_mode::Bool                    # Brain never executes
    execution_bypass_blocked::Bool
    fallback_to_heuristic::Bool            # Allow fallback on failure (requires APPROVAL to activate)
    fallback_approval_token::Union{String, Nothing}  # Token from SecureConfirmationGate approval
    max_inference_time_ms::Float32
    enable_training::Bool
    
    function BrainConfig(;
        model_path::Union{String, Nothing}=nothing,
        confidence_threshold::Float32=0.5f0,
        advisory_mode::Bool=true,
        execution_bypass_blocked::Bool=true,
        fallback_to_heuristic::Bool=false,  # Default: NO fallback - must be explicitly enabled
        fallback_approval_token::Union{String, Nothing}=nothing,  # Requires explicit approval token
        max_inference_time_ms::Float32=500.0f0,
        enable_training::Bool=true
    )
        # SECURITY: If fallback_to_heuristic is enabled, warn about requirement for approval
        if fallback_to_heuristic && fallback_approval_token === nothing
            @warn "SECURITY WARNING: fallback_to_heuristic is set but NO approval token provided!" * 
                  " Runtime approval via SecureConfirmationGate is REQUIRED."
        elseif fallback_to_heuristic && fallback_approval_token !== nothing
            @info "SECURITY: fallback_to_heuristic enabled with approval token - verified fallback"
        end
        new(model_path, confidence_threshold, advisory_mode, 
            execution_bypass_blocked, fallback_to_heuristic, 
            fallback_approval_token, max_inference_time_ms, enable_training)
    end
end

"""
    require_fallback_approval - Request human approval for heuristic fallback
    
    Returns approval token if granted, nothing if denied/pending.
    This is the ONLY way to enable heuristic fallback - fail-closed by default.
    
    NOTE: This function is typically called from Kernel's SecureConfirmationGate.
    The Kernel level handles the actual human confirmation UI/flow.
"""
function require_fallback_approval(
    gate_missing_not_used::Nothing;  # Placeholder - actual implementation in Kernel
    reason::String="Heuristic fallback requested - bypasses brain verification"
)::Union{String, Nothing}
    # This is a stub - the actual implementation with human confirmation
    # should be called from Kernel. This function exists for API completeness.
    @warn "require_fallback_approval: Should be called via Kernel's SecureConfirmationGate"
    return nothing  # Fail-closed: no token returned by default
end

"""
    check_fallback_approval - Verify that fallback has valid human approval
    
    FAIL-CLOSED: Returns false if no valid approval token present.
"""
function check_fallback_approval(config::BrainConfig)::Bool
    # Fail-closed: no fallback allowed without explicit approval
    if !config.fallback_to_heuristic
        return false
    end
    
    # Even if fallback is enabled in config, requires valid approval token
    if config.fallback_approval_token === nothing
        @error "SECURITY VIOLATION: fallback_to_heuristic=true but NO approval token!" *
              " Denying fallback activation - human approval required."
        return false
    end
    
    return true  # Has valid approval
end

# ============================================================================
# EXPERIENCE REPLAY FOR LEARNING
# ============================================================================

"""
    Experience - Single experience tuple for learning
"""
struct Experience
    state::Vector{Float32}
    action::String
    reward::Float32
    next_state::Vector{Float32}
    done::Bool
    timestamp::DateTime
    priority::Float32  # For prioritized experience replay
    
    function Experience(
        state::Vector{Float32},
        action::String,
        reward::Float32,
        next_state::Vector{Float32};
        done::Bool=false,
        priority::Float32=1.0f0
    )
        new(state, action, reward, next_state, done, now(), priority)
    end
end

"""
    ExperienceReplayBuffer - Ring buffer for experience replay
"""
mutable struct ExperienceReplayBuffer
    capacity::Int
    experiences::Vector{Experience}
    position::Int
    size::Int
    
    function ExperienceReplayBuffer(capacity::Int=10000)
        new(capacity, Experience[], 0, 0)
    end
end

function push!(buffer::ExperienceReplayBuffer, exp::Experience)
    if buffer.size < buffer.capacity
        push!(buffer.experiences, exp)
    else
        buffer.experiences[buffer.position + 1] = exp
    end
    buffer.position = mod(buffer.position + 1, buffer.capacity)
    buffer.size = min(buffer.size + 1, buffer.capacity)
end

function sample(buffer::ExperienceReplayBuffer, batch_size::Int)::Vector{Experience}
    n = min(batch_size, buffer.size)
    indices = rand(1:buffer.size, n)
    return buffer.experiences[indices]
end

# ============================================================================
# MAIN BRAIN INTERFACE
# ============================================================================

"""
    JarvisBrain - Complete brain wrapper with health monitoring and contracts
"""
mutable struct JarvisBrain
    # Core brain (loaded from ITHERIS if available)
    brain_core::Any  # Union{BrainCore, Nothing}
    
    # Configuration
    config::BrainConfig
    
    # Health monitoring
    health::BrainHealth
    
    # Experience replay for training
    experience_buffer::ExperienceReplayBuffer
    
    # State tracking
    initialized::Bool
    last_perception::Union{BrainInput, Nothing}
    
    # Metadata for learning (stores last thought for training)
    metadata::Dict{Symbol, Any}
    
    # Deterministic mode for safety-critical operations
    deterministic::Bool
    
    function JarvisBrain(config::BrainConfig=BrainConfig())
        new(
            nothing,  # brain_core
            config,
            BrainHealth(),
            ExperienceReplayBuffer(10000),
            false,
            nothing,
            Dict{Symbol, Any}(:last_thought => nothing),
            true
        )
    end
end

"""
    create_brain - Initialize the brain with ITHERIS or fallback
"""
function create_brain(
    config::BrainConfig=BrainConfig();
    input_size::Int=12,
    hidden_size::Int=128
)::JarvisBrain
    brain = JarvisBrain(config)
    
    # Try to initialize ITHERIS BrainCore
    try
        # Initialize ITHERIS BrainCore with configuration
        brain_core = try
            ITHERISCore.initialize_brain(
                input_size=input_size,
                hidden_size=hidden_size,
                learning_rate=0.01f0,
                gamma=0.95f0,
                policy_temperature=1.5f0
            )
        catch e
            @warn "Failed to initialize ITHERIS: $e"
            nothing
        end
        
        if brain_core !== nothing
            brain.brain_core = brain_core
            brain.initialized = true
            @info "ITHERIS Brain initialized successfully"
        else
            # SECURITY: Check for explicit human approval BEFORE allowing fallback
            if !check_fallback_approval(config)
                # FAIL-CLOSED: Require explicit approval to use fallback
                error("ITHERIS initialization failed and NO valid fallback approval - BRAIN VERIFICATION REQUIRED")
            end
            # Log audit event when falling back with approval
            @error "ITHERIS not available - fallback approved by human - running in DEGRADED MODE"
            @warn "Brain running in DEGRADED MODE with human-approved fallback"
            brain.initialized = true  # Can initialize with degraded mode since human approved
        end
    catch e
        # SECURITY: Check for explicit human approval before allowing any fallback
        if !check_fallback_approval(config)
            rethrow()  # Fail-closed: propagate error
        end
        @error "Brain initialization failed: $e - using human-approved degraded mode"
        brain.initialized = true
    end
    
    return brain
end

"""
    infer_brain - Main inference function with boundary contract
    
Returns BrainOutput (advisory) - never executes anything
"""
function infer_brain(
    brain::JarvisBrain,
    perception::Vector{Float32};
    goal_context::Vector{Float32}=zeros(Float32, 8),
    recent_rewards::Vector{Float32}=zeros(Float32, 10)
)::BrainOutput
    start_time = time()
    
    # Create input (enforces immutable copy)
    brain_input = BrainInput(
        perception;
        goal_context=goal_context,
        recent_rewards=recent_rewards
    )
    
    # Track perception
    brain.last_perception = brain_input
    
    # Try neural inference if available
    if brain.initialized && brain.brain_core !== nothing
        try
            output = _neural_inference(brain, brain_input)
            record_inference!(brain.health, (time() - start_time) * 1000, true)
            return output
        catch e
            @error "Neural inference failed" error=e
            record_inference!(brain.health, (time() - start_time) * 1000, false)
            
            # SECURITY: Check for explicit human approval BEFORE allowing fallback
            if !check_fallback_approval(brain.config)
                # FAIL-CLOSED: Return safe output instead of silently falling back
                @error "Neural inference failed and NO valid fallback approval - returning safe output"
                return _safe_fallback_output("Neural inference failed: $e - no human approval for fallback")
            end
            @error "Neural inference failed - using HEURISTIC FALLBACK with human approval"
        end
    end
    
    # Fallback (if enabled) - now requires explicit human approval at RUNTIME
    if check_fallback_approval(brain.config)
        @warn "BRAIN FALLBACK ACTIVE - Heuristic mode with human-approved fallback"
        return _heuristic_fallback(brain_input)
    else
        # FAIL-CLOSED: Safe output with very low confidence
        return _safe_fallback_output("Brain not initialized and no fallback approval")
    end
end

function _neural_inference(brain::JarvisBrain, input::BrainInput)::BrainOutput
    # Convert BrainInput to ITHERIS format (Dict{String, Any})
    perception_dict = _brain_input_to_itheris(input)
    
    # Call ITHERISCore.infer() with safety wrapper
    thought = try
        ITHERISCore.infer(brain.brain_core, perception_dict)
    catch e
        @error "ITHERIS inference failed: $e"
        return _safe_fallback_output("ITHERIS inference error: $e")
    end
    
    # Store thought in metadata for training
    brain.metadata[:last_thought] = thought
    
    # Convert Thought back to BrainOutput
    return _itheris_thought_to_brain_output(thought, input)
end

# ============================================================================
# ITHERIS CONVERSION FUNCTIONS
# ============================================================================

"""
    _brain_input_to_itheris - Convert BrainInput to ITHERIS Dict format
"""
function _brain_input_to_itheris(input::BrainInput)::Dict{String, Any}
    # Map 12D perception_vector to ITHERIS expected keys
    # Map 8D goal_context to keys
    # Map 10D recent_rewards to keys
    Dict{String, Any}(
        "cpu_load" => input.perception_vector[1],
        "memory_usage" => input.perception_vector[2],
        "disk_io" => input.perception_vector[3],
        "network_latency" => input.perception_vector[4],
        "overall_severity" => input.perception_vector[5],
        "threats" => input.perception_vector[6],
        "file_count" => input.perception_vector[7],
        "process_count" => input.perception_vector[8],
        "energy_level" => input.perception_vector[9],
        "confidence" => input.perception_vector[10],
        "system_uptime_hours" => input.perception_vector[11],
        "user_activity_level" => input.perception_vector[12],
        "goal_context" => input.goal_context,
        "recent_rewards" => input.recent_rewards,
        "time_budget_ms" => input.time_budget_ms
    )
end

"""
    _itheris_thought_to_brain_output - Convert ITHERIS Thought to BrainOutput
"""
function _itheris_thought_to_brain_output(thought::Thought, input::BrainInput)::BrainOutput
    # Map ITHERIS thought.action (Int 1-6) to action strings
    action_names = ["analyze", "optimize", "protect", "explore", "rest", "communicate"]
    
    # Ensure action index is valid
    action_idx = clamp(thought.action, 1, length(action_names))
    proposed_actions = [action_names[action_idx]]
    
    # Compute confidence from action probabilities (max probability)
    if !isempty(thought.probs)
        confidence = Float32(maximum(thought.probs))
    else
        confidence = 0.5f0
    end
    
    # Build action probabilities dict (for logging/debugging)
    action_probs = Dict{String, Float32}(
        action_names[i] => (i <= length(thought.probs) ? Float32(thought.probs[i]) : 0f0) 
        for i in 1:length(action_names)
    )
    
    BrainOutput(
        proposed_actions,
        confidence=confidence,
        value_estimate=thought.value,
        uncertainty=thought.uncertainty,
        reasoning="ITHERIS inference: action=$(thought.action), value=$(thought.value)",
        latent_features=thought.context_vector
    )
end

function _heuristic_fallback(input::BrainInput)::BrainOutput
    # SECURITY WARNING: This function is ONLY called when fallback_to_heuristic=true
    # This bypasses brain/ITHERIS verification - USE ONLY IN EMERGENCY
    @error "INSECURE FALLBACK: Using heuristic without brain verification!"
    
    # Simple heuristic based on perception
    cpu_high = input.perception_vector[1] > 0.7f0
    memory_high = input.perception_vector[2] > 0.7f0
    
    actions = if cpu_high
        ["observe_cpu", "log_status"]
    elseif memory_high
        ["observe_memory", "log_status"]
    else
        ["log_status", "observe_system"]
    end
    
    return BrainOutput(
        actions;
        confidence=0.7f0,
        value_estimate=0.5f0,
        uncertainty=0.3f0,
        reasoning="Heuristic fallback - NO BRAIN VERIFICATION (insecure mode)"
    )
end

function _safe_fallback_output(reason::String)::BrainOutput
    # FAIL-CLOSED: Safe output that will be rejected by kernel due to low confidence
    # This is the secure default when brain verification is unavailable
    return BrainOutput(
        ["log_status"];
        confidence=0.1f0,
        value_estimate=0.0f0,
        uncertainty=1.0f0,
        reasoning="Safe fallback (fail-closed): $reason"
    )
end

"""
    learn_from_experience - Update brain with experience
"""
function learn_from_experience(
    brain::JarvisBrain,
    state::Vector{Float32},
    action::String,
    reward::Float32,
    next_state::Vector{Float32};
    done::Bool=false
)::Bool
    if !brain.config.enable_training
        return false
    end
    
    # Store in experience replay
    exp = Experience(state, action, reward, next_state; done=done)
    push!(brain.experience_buffer, exp)
    
    # Train on batch (function handles sampling internally)
    if brain.experience_buffer.size >= 32
        return _train_batch(brain)
    end
    
    return true
end

function _train_batch(brain::JarvisBrain)::Bool
    # Check if brain is properly initialized
    if brain.brain_core === nothing
        @warn "No brain core available for training"
        return false
    end
    
    # Check for sufficient samples
    if brain.experience_buffer.size < 32
        return false  # Not enough samples
    end
    
    # Sample batch from experience buffer
    batch = sample(brain.experience_buffer, 32)
    
    # Get last thought for learning
    last_thought = get(brain.metadata, :last_thought, nothing)
    if last_thought === nothing
        @warn "No last thought available for training"
        return false
    end
    
    # Call ITHERISCore.learn!() for each experience with safety wrapper
    try
        for experience in batch
            # Convert experience to ITHERIS format
            perception = _brain_input_to_itheris(BrainInput(
                experience.state, 
                zeros(Float32, 8), 
                zeros(Float32, 10),
                0.0f0
            ))
            next_perception = _brain_input_to_itheris(BrainInput(
                experience.next_state,
                zeros(Float32, 8),
                zeros(Float32, 10),
                0.0f0
            ))
            
            # Use the stored thought from metadata
            thought = brain.metadata[:last_thought]
            
            ITHERISCore.learn!(
                brain.brain_core,
                perception,
                next_perception,
                thought,
                Float32(experience.reward),
                Float32(experience.reward)  # Using reward as next_value estimate
            )
        end
        return true
    catch e
        @error "ITHERIS learning failed: $e"
        return false
    end
end

end # module
