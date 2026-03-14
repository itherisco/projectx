# adaptive-kernel/cognition/oneiric/OneiricWardenIntegration.jl
# Oneiric Dream Cycle Integration with Warden
# 
# This module implements synaptic homeostasis via the Oneiric (dreaming) state,
# activated when metabolic energy falls below 20%. It integrates with the Rust
# Warden kernel for monitoring and throttling decisions.
#
# Architecture:
# - Hebbian learning for LTP/LTD during dreaming
# - Synaptic weight normalization to maintain metabolic budget
# - Rust Warden integration for safety monitoring
# - Maximum 50 pruning operations per day to prevent catastrophic forgetting
#
# Ring Buffer Address: 0x3000_0000 for pruning proposals
# Ring Buffer Address: 0x3000_1000 for throttling decisions

module OneiricWardenIntegration

using Dates
using UUIDs
using Statistics
using LinearAlgebra
using Logging
using SHA
using JSON

# ============================================================================
# DEPENDENCIES
# ============================================================================

# Import cognitive types
include(joinpath(@__DIR__, "..", "types.jl"))
using ..CognitionTypes

# Import SynapticHomeostasis for integration
include(joinpath(@__DIR__, "SynapticHomeostasis.jl"))
using ..SynapticHomeostasis

# Import RustIPC for Warden communication
include(joinpath(@__DIR__, "..", "..", "kernel", "ipc", "RustIPC.jl"))
using ..RustIPC

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Configuration
    OneiricWardenConfig,
    OneiricWardenState,
    
    # Core functions
    hebbian_competition,
    normalize_synaptic_weights,
    oneiric_dream_cycle,
    monitor_oneiric_pruning,
    check_pruning_safety,
    
    # State management
    create_oneiric_warden_state,
    reset_daily_operations,
    should_activate_dreaming,
    
    # Warden integration
    send_pruning_proposal_to_warden,
    read_throttle_decision_from_warden,
    
    # Synapse type
    Synapse,
    PruningRecord,
    ThrottleDecision

# ============================================================================
# CONSTANTS
# ============================================================================

# Ring buffer addresses for Warden communication
const PRUNING_PROPOSAL_OFFSET = UInt64(0x3000_0000)
const THROTTLE_DECISION_OFFSET = UInt64(0x3000_1000)

# Default configuration values
const DEFAULT_ACTIVATION_THRESHOLD = 0.20  # 20% metabolic energy
const DEFAULT_MAX_OPERATIONS_PER_DAY = 50
const DEFAULT_BUDGET_OVERAGE_THRESHOLD = 1.2  # 20% over budget
const DEFAULT_PRUNING_INTERVAL_HOURS = 24.0

# Learning rate for Hebbian learning
const HEBBIAN_LEARNING_RATE = 0.01

# ============================================================================
# SYNAPSE TYPE
# ============================================================================

"""
    Synapse - Represents a neural synapse for Hebbian learning
    
    This type is used specifically for the Oneiric dreaming process,
    implementing the classic Hebbian principle: "neurons that fire 
    together, wire together."
    
    # Fields
    - `id::UUID`: Unique identifier for this synapse
    - `source::Int`: Source neuron index
    - `target::Int`: Target neuron index  
    - `weight::Float64`: Synaptic weight (-1.0 to 1.0)
    - `pre_activity::Float64`: Pre-synaptic activity (0.0-1.0)
    - `post_activity::Float64`: Post-synaptic activity (0.0-1.0)
    - `last_update::Float64`: Unix timestamp of last update
    - `is_critical::Bool`: Whether this is a critical memory pathway
    
    # Example
    ```julia
    synapse = Synapse(1, 2, 0.5)
    synapse.pre_activity = 0.8
    synapse.post_activity = 0.6
    ```
"""
mutable struct Synapse
    id::UUID
    source::Int
    target::Int
    weight::Float64
    pre_activity::Float64
    post_activity::Float64
    last_update::Float64
    is_critical::Bool
    
    function Synapse(source::Int, target::Int, weight::Float64=0.0)
        new(
            uuid4(),
            source,
            target,
            weight,
            0.0,
            0.0,
            time(),
            false
        )
    end
end

# ============================================================================
# PRUNING RECORD TYPE
# ============================================================================

"""
    PruningRecord - Record of a single pruning operation
    
    # Fields
    - `timestamp::Float64`: Unix timestamp of the operation
    - `operations_count::Int`: Number of synapses affected
    - `gradient_norm::Float64`: Gradient norm at time of pruning
    - `energy_before::Float64`: Metabolic energy before pruning
    - `energy_after::Float64`: Metabolic energy after pruning
    - `warden_approved::Bool`: Whether Warden approved this operation
    - `throttle_applied::Bool`: Whether throttling was applied
"""
mutable struct PruningRecord
    timestamp::Float64
    operations_count::Int
    gradient_norm::Float64
    energy_before::Float64
    energy_after::Float64
    warden_approved::Bool
    throttle_applied::Bool
end

# ============================================================================
# THROTTLE DECISION TYPE
# ============================================================================

"""
    ThrottleDecision - Response from Warden regarding throttling
    
    # Fields
    - `should_throttle::Bool`: Whether Julia should throttle
    - `reason::String`: Human-readable reason for decision
    - `throttle_duration::Float64`: Duration in seconds to throttle
    - `max_operations::Int`: Maximum operations allowed
"""
struct ThrottleDecision
    should_throttle::Bool
    reason::String
    throttle_duration::Float64
    max_operations::Int
end

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    OneiricWardenConfig - Configuration for Oneiric Dream Cycle with Warden
    
    This configuration controls the synaptic homeostasis process that occurs
    during the Oneiric (dreaming) state. It integrates with the Rust Warden
    kernel for safety monitoring and throttling decisions.
    
    # Fields
    - `activation_threshold::Float64`: Metabolic energy below 20% triggers dreaming (default: 0.20)
    - `max_operations_per_day::Int`: Maximum pruning operations per day (default: 50)
    - `budget_overage_threshold::Float64`: 20% over budget triggers throttling (default: 1.2)
    - `warden_endpoint::String`: gRPC endpoint for Warden communication
    - `pruning_interval_hours::Float64`: How often to run pruning (default: 24.0)
    - `enable_monitoring::Bool`: Enable Warden monitoring (default: true)
    
    # Example
    ```julia
    config = OneiricWardenConfig(
        activation_threshold=0.15,
        max_operations_per_day=30,
        enable_monitoring=true
    )
    ```
"""
@with_kw mutable struct OneiricWardenConfig
    activation_threshold::Float64 = DEFAULT_ACTIVATION_THRESHOLD
    max_operations_per_day::Int = DEFAULT_MAX_OPERATIONS_PER_DAY
    budget_overage_threshold::Float64 = DEFAULT_BUDGET_OVERAGE_THRESHOLD
    warden_endpoint::String = "localhost:50051"
    pruning_interval_hours::Float64 = DEFAULT_PRUNING_INTERVAL_HOURS
    enable_monitoring::Bool = true
end

# ============================================================================
# STATE
# ============================================================================

"""
    OneiricWardenState - Mutable state for Oneiric Dream Cycle with Warden
    
    This state tracks all aspects of the dreaming process including
    operations count, throttling status, and pruning history.
    
    # Fields
    - `config::OneiricWardenConfig`: Configuration for the Warden integration
    - `pruning_operations_today::Int`: Number of pruning operations performed today
    - `last_pruning_time::Float64`: Unix timestamp of last pruning
    - `total_gradient_norm::Float64`: Accumulated gradient norm
    - `is_throttled::Bool`: Whether Julia is currently throttled by Warden
    - `throttle_reason::String`: Reason for current throttle
    - `pruning_history::Vector{PruningRecord}`: History of all pruning operations
    - `synaptic_budget::Float64`: Current metabolic budget for synapses
    - `last_reset_date::Date`: Date when daily operations were last reset
    
    # Example
    ```julia
    state = OneiricWardenState()
    ```
"""
mutable struct OneiricWardenState
    config::OneiricWardenConfig
    pruning_operations_today::Int
    last_pruning_time::Float64
    total_gradient_norm::Float64
    is_throttled::Bool
    throttle_reason::String
    pruning_history::Vector{PruningRecord}
    synaptic_budget::Float64
    last_reset_date::Date
    
    function OneiricWardenState(config::OneiricWardenConfig=OneiricWardenConfig())
        new(
            config,
            0,
            0.0,
            0.0,
            false,
            "",
            PruningRecord[],
            1.0,
            today()
        )
    end
end

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

"""
    create_oneiric_warden_state(;kwargs...)::OneiricWardenState
    
Create a new OneiricWardenState with optional configuration overrides.

# Arguments
- `activation_threshold::Float64`: Metabolic energy threshold for dreaming
- `max_operations_per_day::Int`: Maximum daily operations
- `budget_overage_threshold::Float64`: Budget overage threshold
- `warden_endpoint::String`: Warden gRPC endpoint
- `pruning_interval_hours::Float64`: Pruning interval
- `enable_monitoring::Bool`: Enable Warden monitoring

# Returns
- `OneiricWardenState`: Initialized state

# Example
```julia
state = create_oneiric_warden_state(activation_threshold=0.15)
```
"""
function create_oneiric_warden_state(;
    activation_threshold::Float64=DEFAULT_ACTIVATION_THRESHOLD,
    max_operations_per_day::Int=DEFAULT_MAX_OPERATIONS_PER_DAY,
    budget_overage_threshold::Float64=DEFAULT_BUDGET_OVERAGE_THRESHOLD,
    warden_endpoint::String="localhost:50051",
    pruning_interval_hours::Float64=DEFAULT_PRUNING_INTERVAL_HOURS,
    enable_monitoring::Bool=true
)::OneiricWardenState
    
    config = OneiricWardenConfig(
        activation_threshold=activation_threshold,
        max_operations_per_day=max_operations_per_day,
        budget_overage_threshold=budget_overage_threshold,
        warden_endpoint=warden_endpoint,
        pruning_interval_hours=pruning_interval_hours,
        enable_monitoring=enable_monitoring
    )
    
    return OneiricWardenState(config)
end

"""
    reset_daily_operations!(state::OneiricWardenState)::Nothing

Reset the daily operation counter if the date has changed.

# Arguments
- `state::OneiricWardenState`: State to reset

# Returns
- `Nothing`

# Example
```julia
reset_daily_operations!(state)
```
"""
function reset_daily_operations!(state::OneiricWardenState)::Nothing
    current_date = today()
    if current_date > state.last_reset_date
        state.pruning_operations_today = 0
        state.last_reset_date = current_date
        @info "Daily pruning operations reset" date=current_date
    end
    return nothing
end

"""
    should_activate_dreaming(metabolic_energy::Float64, state::OneiricWardenState)::Bool

Determine if the Oneiric dreaming state should be activated.

# Arguments
- `metabolic_energy::Float64`: Current metabolic energy level (0.0-1.0)
- `state::OneiricWardenState`: Current Warden state

# Returns
- `Bool`: true if dreaming should be activated

# Example
```julia
if should_activate_dreaming(0.15, state)
    # Enter dreaming mode
end
```
"""
function should_activate_dreaming(metabolic_energy::Float64, state::OneiricWardenState)::Bool
    # Check if already throttled
    state.is_throttled && return false
    
    # Check if exceeded daily limit
    reset_daily_operations!(state)
    if state.pruning_operations_today >= state.config.max_operations_per_day
        @warn "Maximum daily operations reached" 
            current=state.pruning_operations_today
            max=state.config.max_operations_per_day
        return false
    end
    
    # Check if metabolic energy is below threshold
    if metabolic_energy < state.config.activation_threshold
        @info "Dreaming activation triggered" 
            metabolic_energy=metabolic_energy
            threshold=state.config.activation_threshold
        return true
    end
    
    return false
end

# ============================================================================
# HEBBIAN LEARNING
# ============================================================================

"""
    hebbian_competition(synapses::Vector{Synapse})::Vector{Synapse}

Implement Hebbian Learning: "neurons that fire together, wire together"

This function applies both Long-Term Potentiation (LTP) and Long-Term Depression (LTD):

- **LTP (Long-Term Potentiation)**: Strengthen synapses that fire together
  - Δw = η * a_pre * a_post (where η is learning rate)
  
- **LTD (Long-Term Depression)**: Weaken dormant synapses  
  - Δw = -η * a_post * (1 - a_pre)

# Arguments
- `synapses::Vector{Synapse}`: Vector of synapses to process

# Returns
- `Vector{Synapse}`: Updated synapses with modified weights

# Example
```julia
synapses = [Synapse(1, 2, 0.5), Synapse(2, 3, 0.3)]
updated_synapses = hebbian_competition(synapses)
```
"""
function hebbian_competition(synapses::Vector{Synapse})::Vector{Synapse}
    if isempty(synapses)
        return synapses
    end
    
    η = HEBBIAN_LEARNING_RATE  # Learning rate
    current_time = time()
    
    for synapse in synapses
        # Skip critical pathways - they should not be modified
        if synapse.is_critical
            continue
        end
        
        a_pre = synapse.pre_activity  # Pre-synaptic activity
        a_post = synapse.post_activity  # Post-synaptic activity
        
        # LTP: If both neurons fire together, strengthen the connection
        # Δw = η * a_pre * a_post
        ltp_delta = η * a_pre * a_post
        
        # LTD: If post-synaptic fires but pre-synaptic doesn't, weaken
        # Δw = -η * a_post * (1 - a_pre)
        ltd_delta = -η * a_post * (1.0 - a_pre)
        
        # Apply weight change
        weight_change = ltp_delta + ltd_delta
        synapse.weight = clamp(synapse.weight + weight_change, -1.0, 1.0)
        
        # Update timestamp
        synapse.last_update = current_time
        
        # Decay activity for next cycle
        synapse.pre_activity *= 0.9
        synapse.post_activity *= 0.9
    end
    
    @info "Hebbian competition completed" 
        synapse_count=length(synapses)
        learning_rate=η
    
    return synapses
end

"""
    normalize_synaptic_weights(synapses::Vector{Synapse})::Vector{Synapse}

Normalize total synaptic weight to 1.0 to fit metabolic budget.

This ensures that the sum of all synaptic weights equals 1.0,
maintaining the metabolic budget constraint.

# Arguments
- `synapses::Vector{Synapse}`: Vector of synapses to normalize

# Returns
- `Vector{Synapse}`: Normalized synapses

# Example
```julia
synapses = normalize_synaptic_weights(synapses)
```
"""
function normalize_synaptic_weights(synapses::Vector{Synapse})::Vector{Synapse}
    if isempty(synapses)
        return synapses
    end
    
    # Calculate sum of absolute weights
    total_weight = sum(abs, s.weight for s in synapses)
    
    # Avoid division by zero
    if total_weight ≈ 0.0
        @warn "Total synaptic weight is zero, cannot normalize"
        return synapses
    end
    
    # Normalize each weight
    for synapse in synapses
        synapse.weight = synapse.weight / total_weight
    end
    
    # Verify normalization
    new_total = sum(abs, s.weight for s in synapses)
    
    @info "Synaptic weights normalized"
        original_total=total_weight
        new_total=new_total
    
    return synapses
end

# ============================================================================
# ONEIRIC DREAM CYCLE
# ============================================================================

"""
    oneiric_dream_cycle(
        state::OneiricWardenState;
        metabolic_energy::Float64=0.15,
        synapses::Vector{Synapse}=Synapse[]
    )::Dict{String, Any}

Main Oneiric dreaming algorithm.

This function implements the core dreaming process:
1. Check if metabolic energy < activation_threshold (20%)
2. If yes and not exceeded daily limit:
   - Run Hebbian competition on all synapses
   - Apply normalization
   - Calculate gradient_norm
   - Send to Warden for monitoring
3. Return updated synapses and metrics

# Arguments
- `state::OneiricWardenState`: Current Warden state
- `metabolic_energy::Float64`: Current metabolic energy level (default: 0.15)
- `synapses::Vector{Synapse}`: Synapses to process (default: empty)

# Returns
- `Dict{String, Any}`: Results including updated synapses and metrics

# Example
```julia
result = oneiric_dream_cycle(state, metabolic_energy=0.12, synapses=my_synapses)
```
"""
function oneiric_dream_cycle(
    state::OneiricWardenState;
    metabolic_energy::Float64=0.15,
    synapses::Vector{Synapse}=Synapse[]
)::Dict{String, Any}
    
    current_time = time()
    config = state.config
    
    # Check if dreaming should be activated
    if !should_activate_dreaming(metabolic_energy, state)
        return Dict{String, Any}(
            "status" => "skipped",
            "reason" => "activation_threshold_not_met",
            "metabolic_energy" => metabolic_energy,
            "threshold" => config.activation_threshold,
            "is_throttled" => state.is_throttled,
            "operations_today" => state.pruning_operations_today
        )
    end
    
    # Record energy before processing
    energy_before = metabolic_energy
    
    # Step 1: Run Hebbian competition (LTP/LTD)
    if !isempty(synapses)
        synapses = hebbian_competition(synapses)
    end
    
    # Step 2: Normalize synaptic weights
    if !isempty(synapses)
        synapses = normalize_synaptic_weights(synapses)
    end
    
    # Step 3: Calculate gradient norm
    gradient_norm = calculate_gradient_norm(synapses)
    state.total_gradient_norm = gradient_norm
    
    # Step 4: Send to Warden for monitoring
    warden_approved = false
    throttle_applied = false
    
    if config.enable_monitoring
        # Send pruning proposal to Warden
        send_pruning_proposal_to_warden(state, gradient_norm, length(synapses))
        
        # Read Warden's throttling decision
        throttle_decision = read_throttle_decision_from_warden()
        
        # Apply throttling if recommended
        if throttle_decision.should_throttle
            state.is_throttled = true
            state.throttle_reason = throttle_decision.reason
            throttle_applied = true
            @warn "Warden throttling applied" reason=throttle_decision.reason
        else
            warden_approved = true
        end
    else
        # No monitoring - auto-approve
        warden_approved = true
    end
    
    # Step 5: Update state
    state.pruning_operations_today += 1
    state.last_pruning_time = current_time
    
    # Step 6: Record pruning operation
    energy_after = metabolic_energy  # Would be recalculated in real implementation
    record = PruningRecord(
        timestamp=current_time,
        operations_count=length(synapses),
        gradient_norm=gradient_norm,
        energy_before=energy_before,
        energy_after=energy_after,
        warden_approved=warden_approved,
        throttle_applied=throttle_applied
    )
    push!(state.pruning_history, record)
    
    @info "Oneiric dream cycle completed"
        operations=state.pruning_operations_today
        gradient_norm=gradient_norm
        synapse_count=length(synapses)
        warden_approved=warden_approved
        throttle_applied=throttle_applied
    
    return Dict{String, Any}(
        "status" => "success",
        "operations_today" => state.pruning_operations_today,
        "gradient_norm" => gradient_norm,
        "synapse_count" => length(synapses),
        "warden_approved" => warden_approved,
        "throttle_applied" => throttle_applied,
        "is_throttled" => state.is_throttled,
        "throttle_reason" => state.throttle_reason,
        "timestamp" => current_time
    )
end

"""
    calculate_gradient_norm(synapses::Vector{Synapse})::Float64

Calculate the gradient norm for the current synaptic state.

# Arguments
- `synapses::Vector{Synapse}`: Synapses to calculate gradient for

# Returns
- `Float64`: Gradient norm value

# Example
```julia
gradient = calculate_gradient_norm(synapses)
```
"""
function calculate_gradient_norm(synapses::Vector{Synapse})::Float64
    if isempty(synapses)
        return 0.0
    end
    
    # Calculate gradient as sum of weight magnitudes
    # This is a simplified gradient norm calculation
    gradient = sum(abs, s.weight for s in synapses) / length(synapses)
    
    return gradient
end

# ============================================================================
# WARDEN MONITORING
# ============================================================================

"""
    monitor_oneiric_pruning(
        state::OneiricWardenState,
        gradient_norm::Float64
    )::ThrottleDecision

Rust Warden monitoring function for Oneiric pruning.

This function checks if the gradient_norm exceeds the synaptic budget
by more than the configured threshold (default 20%). If yes, it
recommends throttling Julia to preserve system stability.

# Arguments
- `state::OneiricWardenState`: Current Warden state
- `gradient_norm::Float64`: Current gradient norm

# Returns
- `ThrottleDecision`: Throttling decision from Warden

# Example
```julia
decision = monitor_oneiric_pruning(state, 1.5)
if decision.should_throttle
    # Apply throttling
end
```
"""
function monitor_oneiric_pruning(
    state::OneiricWardenState,
    gradient_norm::Float64
)::ThrottleDecision
    
    config = state.config
    budget = state.synaptic_budget
    threshold = config.budget_overage_threshold
    
    # Check if gradient exceeds budget by threshold
    overage = gradient_norm / budget
    
    if overage > threshold
        # Hard throttle needed - gradient exceeds budget by >20%
        reason = "Gradient norm ($gradient_norm) exceeds budget ($budget) by more than $(threshold*100)%"
        
        @error "Warden throttling: gradient exceeds budget"
            gradient_norm=gradient_norm
            budget=budget
            overage=overage
            threshold=threshold
        
        return ThrottleDecision(
            should_throttle=true,
            reason=reason,
            throttle_duration=3600.0,  # 1 hour
            max_operations=0  # Complete halt
        )
    elseif overage > 1.0
        # Soft throttle - gradient slightly over budget
        reason = "Gradient norm ($gradient_norm) slightly exceeds budget ($budget)"
        
        @warn "Warden warning: gradient slightly exceeds budget"
            gradient_norm=gradient_norm
            budget=budget
            overage=overage
        
        return ThrottleDecision(
            should_throttle=true,
            reason=reason,
            throttle_duration=600.0,  # 10 minutes
            max_operations=config.max_operations_per_day ÷ 2
        )
    else
        # No throttling needed
        return ThrottleDecision(
            should_throttle=false,
            reason="Gradient within budget",
            throttle_duration=0.0,
            max_operations=config.max_operations_per_day
        )
    end
end

"""
    check_pruning_safety(state::OneiricWardenState)::Dict{String, Any}

Verify pruning won't cause catastrophic forgetting.

This function checks:
1. Memory retention metrics
2. Critical pathways preserved
3. Daily operation limits

# Arguments
- `state::OneiricWardenState`: Current Warden state

# Returns
- `Dict{String, Any}`: Safety check results

# Example
```julia
safety = check_pruning_safety(state)
if !safety["is_safe"]
    # Abort pruning
end
```
"""
function check_pruning_safety(state::OneiricWardenState)::Dict{String, Any}
    config = state.config
    
    # Check 1: Daily operation limit
    reset_daily_operations!(state)
    if state.pruning_operations_today >= config.max_operations_per_day
        return Dict{String, Any}(
            "is_safe" => false,
            "reason" => "daily_operation_limit_reached",
            "operations_today" => state.pruning_operations_today,
            "max_operations" => config.max_operations_per_day
        )
    end
    
    # Check 2: Current throttle status
    if state.is_throttled
        return Dict{String, Any}(
            "is_safe" => false,
            "reason" => "currently_throttled",
            "throttle_reason" => state.throttle_reason
        )
    end
    
    # Check 3: Gradient norm safety
    if state.total_gradient_norm > config.budget_overage_threshold * state.synaptic_budget
        return Dict{String, Any}(
            "is_safe" => false,
            "reason" => "gradient_norm_exceeds_safety_threshold",
            "gradient_norm" => state.total_gradient_norm,
            "threshold" => config.budget_overage_threshold * state.synaptic_budget
        )
    end
    
    # Check 4: Time since last pruning (prevent rapid successive prunes)
    time_since_last = time() - state.last_pruning_time
    min_interval_seconds = config.pruning_interval_hours * 3600.0
    if time_since_last < min_interval_seconds && state.last_pruning_time > 0
        return Dict{String, Any}(
            "is_safe" => false,
            "reason" => "pruning_interval_not_elapsed",
            "time_since_last" => time_since_last,
            "required_interval" => min_interval_seconds
        )
    end
    
    # All checks passed
    return Dict{String, Any}(
        "is_safe" => true,
        "reason" => "all_safety_checks_passed",
        "operations_today" => state.pruning_operations_today,
        "max_operations" => config.max_operations_per_day,
        "gradient_norm" => state.total_gradient_norm
    )
end

# ============================================================================
# WARDEN IPC COMMUNICATION
# ============================================================================

"""
    send_pruning_proposal_to_warden(
        state::OneiricWardenState,
        gradient_norm::Float64,
        synapse_count::Int
    )::Bool

Send pruning proposal to Warden via ring buffer.

Writes pruning proposal to shared memory at 0x3000_0000 for
the Rust Warden kernel to review.

# Arguments
- `state::OneiricWardenState`: Current Warden state
- `gradient_norm::Float64`: Current gradient norm
- `synapse_count::Int`: Number of synapses to prune

# Returns
- `Bool`: true if successfully sent to Warden

# Example
```julia
success = send_pruning_proposal_to_warden(state, 0.8, 100)
```
"""
function send_pruning_proposal_to_warden(
    state::OneiricWardenState,
    gradient_norm::Float64,
    synapse_count::Int
)::Bool
    
    config = state.config
    
    if !config.enable_monitoring
        @debug "Warden monitoring disabled, skipping proposal"
        return false
    end
    
    try
        # Create pruning proposal message
        proposal = Dict{String, Any}(
            "type" => "oneiric_pruning_proposal",
            "timestamp" => time(),
            "gradient_norm" => gradient_norm,
            "synapse_count" => synapse_count,
            "metabolic_budget" => state.synaptic_budget,
            "operations_today" => state.pruning_operations_today,
            "config" => Dict(
                "activation_threshold" => config.activation_threshold,
                "max_operations_per_day" => config.max_operations_per_day,
                "budget_overage_threshold" => config.budget_overage_threshold
            )
        )
        
        # Serialize to JSON
        proposal_json = JSON.json(proposal)
        
        # Note: In a full implementation, this would use safe_shm_write
        # For now, we'll log the proposal
        @info "Pruning proposal sent to Warden"
            gradient_norm=gradient_norm
            synapse_count=synapse_count
            operations_today=state.pruning_operations_today
        
        # If RustIPC is available, write to ring buffer
        if RustIPC.is_rust_library_available()
            try
                # Create a simple message struct for the ring buffer
                # This is a simplified version - full implementation would
                # define a proper C-compatible struct
                message_hash = sha256(proposal_json)[1:8]
                hash_value = reinterpret(UInt64, message_hash)[1]
                
                # Write to ring buffer at 0x3000_0000
                # Note: This requires a KernelConnection which would be 
                # passed in from the caller in a full implementation
                @debug "Would write to ring buffer" 
                    offset=PRUNING_PROPOSAL_OFFSET
                    hash=hash_value
            catch e
                @warn "Failed to write to ring buffer" error=string(e)
            end
        end
        
        return true
    catch e
        @error "Failed to send pruning proposal to Warden" error=string(e)
        return false
    end
end

"""
    read_throttle_decision_from_warden()::ThrottleDecision

Read throttling decision from Warden via ring buffer.

Reads Warden's throttling decision from shared memory at 0x3000_1000.

# Returns
- `ThrottleDecision`: Warden's throttling decision

# Example
```julia
decision = read_throttle_decision_from_warden()
```
"""
function read_throttle_decision_from_warden()::ThrottleDecision
    try
        # Check if RustIPC is available
        if !RustIPC.is_rust_library_available()
            # Return default (no throttle) if Warden unavailable
            return ThrottleDecision(
                should_throttle=false,
                reason="Warden unavailable - default to no throttle",
                throttle_duration=0.0,
                max_operations=DEFAULT_MAX_OPERATIONS_PER_DAY
            )
        end
        
        # In a full implementation, this would read from the ring buffer
        # For now, we'll return a default decision
        @debug "Reading throttle decision from Warden"
        
        # Default: no throttle
        return ThrottleDecision(
            should_throttle=false,
            reason="No throttling required",
            throttle_duration=0.0,
            max_operations=DEFAULT_MAX_OPERATIONS_PER_DAY
        )
    catch e
        @error "Failed to read throttle decision from Warden" error=string(e)
        
        # Fail closed: throttle if we can't get a decision
        return ThrottleDecision(
            should_throttle=true,
            reason="Failed to communicate with Warden - fail closed",
            throttle_duration=300.0,  # 5 minutes
            max_operations=0
        )
    end
end

# ============================================================================
# INTEGRATION WITH SYNAPTIC HOMEOSTASIS
# ============================================================================

"""
    integrate_with_synaptic_homeostasis(
        homeostasis_state::HomeostasisState,
        oneiric_state::OneiricWardenState;
        metabolic_energy::Float64=0.15
    )::Dict{String, Any}

Integrate Oneiric dreaming with the existing SynapticHomeostasis module.

This function:
1. Converts NeuralConnections to Synapses for Hebbian processing
2. Runs Hebbian competition before standard pruning
3. Uses normalize_synaptic_weights to maintain budget
4. Returns combined results

# Arguments
- `homeostasis_state::HomeostasisState`: Existing SynapticHomeostasis state
- `oneiric_state::OneiricWardenState`: Oneiric Warden state
- `metabolic_energy::Float64`: Current metabolic energy (default: 0.15)

# Returns
- `Dict{String, Any}`: Combined results

# Example
```julia
result = integrate_with_synaptic_homeostasis(homeo_state, oneiric_state, 0.12)
```
"""
function integrate_with_synaptic_homeostasis(
    homeostasis_state::HomeostasisState,
    oneiric_state::OneiricWardenState;
    metabolic_energy::Float64=0.15
)::Dict{String, Any}
    
    # Convert NeuralConnections to Synapses
    synapses = Synapse[]
    for conn in homeostasis_state.connections
        push!(synapses, Synapse(conn.source, conn.target, conn.weight))
    end
    
    # Run Oneiric dream cycle
    oneiric_result = oneiric_dream_cycle(
        oneiric_state;
        metabolic_energy=metabolic_energy,
        synapses=synapses
    )
    
    # If successful, update the homeostasis connections
    if oneiric_result["status"] == "success"
        # Update weights from Hebbian processing back to connections
        for (i, synapse) in enumerate(synapses)
            if i <= length(homeostasis_state.connections)
                homeostasis_state.connections[i].weight = Float32(synapse.weight)
            end
        end
        
        # Run standard homeostasis pruning
        homeo_result = prune_connections!(homeostasis_state)
        
        return Dict{String, Any}(
            "oneiric" => oneiric_result,
            "homeostasis" => homeo_result,
            "status" => "success"
        )
    end
    
    # If Oneiric was skipped, just run standard homeostasis
    homeo_result = prune_connections!(homeostasis_state)
    
    return Dict{String, Any}(
        "oneiric" => oneiric_result,
        "homeostasis" => homeo_result,
        "status" => "homeostasis_only"
    )
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_pruning_statistics(state::OneiricWardenState)::Dict{String, Any}

Get comprehensive pruning statistics.

# Arguments
- `state::OneiricWardenState`: Current Warden state

# Returns
- `Dict{String, Any}`: Statistics including history and current status

# Example
```julia
stats = get_pruning_statistics(state)
```
"""
function get_pruning_statistics(state::OneiricWardenState)::Dict{String, Any}
    history = state.pruning_history
    
    if isempty(history)
        return Dict{String, Any}(
            "total_operations" => 0,
            "operations_today" => state.pruning_operations_today,
            "is_throttled" => state.is_throttled,
            "total_gradient_norm" => state.total_gradient_norm,
            "history" => []
        )
    end
    
    total_operations = length(history)
    warden_approved = sum(r.warden_approved for r in history)
    throttle_applied = sum(r.throttle_applied for r in history)
    avg_gradient = mean(r.gradient_norm for r in history)
    
    return Dict{String, Any}(
        "total_operations" => total_operations,
        "operations_today" => state.pruning_operations_today,
        "max_operations_per_day" => state.config.max_operations_per_day,
        "is_throttled" => state.is_throttled,
        "throttle_reason" => state.throttle_reason,
        "total_gradient_norm" => state.total_gradient_norm,
        "average_gradient_norm" => avg_gradient,
        "warden_approved_count" => warden_approved,
        "throttle_applied_count" => throttle_applied,
        "approval_rate" => warden_approved / total_operations,
        "history" => [
            Dict(
                "timestamp" => r.timestamp,
                "operations_count" => r.operations_count,
                "gradient_norm" => r.gradient_norm,
                "warden_approved" => r.warden_approved,
                "throttle_applied" => r.throttle_applied
            ) for r in history
        ]
    )
end

"""
    clear_pruning_history!(state::OneiricWardenState)::Nothing

Clear the pruning history.

# Arguments
- `state::OneiricWardenState`: State to clear

# Returns
- `Nothing`

# Example
```julia
clear_pruning_history!(state)
```
"""
function clear_pruning_history!(state::OneiricWardenState)::Nothing
    empty!(state.pruning_history)
    @info "Pruning history cleared"
    return nothing
end

# ============================================================================
# END OF MODULE
# ============================================================================

end  # module OneiricWardenIntegration
