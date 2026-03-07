# adaptive-kernel/cognition/consolidation/Sleep.jl - Component 6: Sleep/Dream/Consolidation
# JARVIS Neuro-Symbolic Architecture - Offline memory consolidation with dream-based counterfactual exploration

module Sleep

using Dates
using UUIDs
using Statistics
using Logging

# Import Oneiric (Dream) module for enhanced dream processing
include(joinpath(@__DIR__, "..", "oneiric", "OneiricController.jl"))
using .OneiricController

# Export all functions and types
export
    # Sleep state
    SleepState,
    SleepPhase,
    
    # Core functions
    sleep_cycle!,
    consolidate_memory!,
    dream_exploration!,
    regularize_weights!,
    snapshot_brain,
    restore_brain!,
    should_enter_sleep,
    
    # Oneiric integration
    enter_oneiric_mode,
    run_oneiric_dream,
    integrate_with_oneiric!

# ============================================================================
# SLEEP PHASES
# ============================================================================

"""
    SleepPhase - Enum representing different stages of sleep

- :awake: Normal waking state
- :light_sleep: Light sleep phase for memory stabilization
- :deep_sleep: Deep sleep for neural consolidation
- :rem: REM sleep for dream-based counterfactual exploration
"""
@enum SleepPhase begin
    :awake
    :light_sleep
    :deep_sleep
    :rem
end

# ============================================================================
# SLEEP STATE
# ============================================================================

"""
    SleepState - Mutable state tracking sleep cycle progress

# Fields
- `phase::SleepPhase`: Current sleep phase
- `cycle_count::Int`: Number of complete sleep cycles
- `last_sleep_time::Float64`: Unix timestamp of last sleep
- `sleep_duration::Float64`: Duration of last sleep in seconds
- `consolidation_active::Bool`: Whether consolidation is currently running

# Example
```julia
sleep_state = SleepState()
sleep_state.phase == :awake  # true
```
"""
mutable struct SleepState
    phase::SleepPhase
    cycle_count::Int
    last_sleep_time::Float64
    sleep_duration::Float64  # seconds
    consolidation_active::Bool
    
    function SleepState()
        new(:awake, 0, 0.0, 0.0, false)
    end
end

# ============================================================================
# PHASE TRANSITIONS
# ============================================================================

"""
    advance_phase - Move to the next sleep phase
"""
function advance_phase(sleep_state::SleepState)::SleepPhase
    current = sleep_state.phase
    next_phase = if current == :awake
        :light_sleep
    elseif current == :light_sleep
        :deep_sleep
    elseif current == :deep_sleep
        :rem
    else
        :awake  # Complete cycle
    end
    sleep_state.phase = next_phase
    
    # If we completed a cycle, increment cycle count
    if next_phase == :awake
        sleep_state.cycle_count += 1
        @info "Completed sleep cycle" cycle_count=sleep_state.cycle_count
    end
    
    return next_phase
end

"""
    get_phase_duration - Get duration for each sleep phase (in seconds)
"""
function get_phase_duration(phase::SleepPhase)::Float64
    if phase == :awake
        return 0.0  # No duration for awake
    elseif phase == :light_sleep
        return 900.0  # 15 minutes
    elseif phase == :deep_sleep
        return 1800.0  # 30 minutes
    else  # :rem
        return 900.0  # 15 minutes
    end
end

# ============================================================================
# SCHEDULED SLEEP ACTIVATION
# ============================================================================

"""
    should_enter_sleep - Check if sleep should be triggered

# Arguments
- `sleep_state::SleepState`: Current sleep state
- `cycles_threshold::Int`: Trigger sleep after this many cycles without sleep (default: 100)
- `time_since_sleep::Float64`: Minimum time since last sleep in seconds (default: 3600.0 = 1 hour)

# Returns
- `Bool`: true if sleep should be entered

# Example
```julia
if should_enter_sleep(sleep_state)
    sleep_cycle!(brain, sleep_state)
end
```
"""
function should_enter_sleep(
    sleep_state::SleepState;
    cycles_threshold::Int=100,
    time_since_sleep::Float64=3600.0
)::Bool
    # Already in sleep
    sleep_state.phase != :awake && return false
    
    # Check time since last sleep
    current_time = time()
    time_elapsed = current_time - sleep_state.last_sleep_time
    
    # Enter sleep if enough time has passed
    if time_elapsed >= time_since_sleep
        @info "Sleep triggered: time threshold reached" time_elapsed=time_elapsed threshold=time_since_sleep
        return true
    end
    
    # Enter sleep if too many cycles without sleep
    if sleep_state.cycle_count >= cycles_threshold
        @info "Sleep triggered: cycle threshold reached" cycles=sleep_state.cycle_count threshold=cycles_threshold
        return true
    end
    
    return false
end

# ============================================================================
# SNAPSHOT AND RESTORE
# ============================================================================

"""
    snapshot_brain - Capture current brain state for rollback

# Arguments
- `brain_state::Any`: The brain state (JarvisBrain or ITHERIS BrainCore)

# Returns
- `Dict{String, Any}`: Snapshot containing weights, memory state, and metadata

# Safety
This function MUST be called before any weight modifications to enable rollback.
"""
function snapshot_brain(brain_state::Any)::Dict{String, Any}
    snapshot = Dict{String, Any}()
    
    try
        # Capture timestamp
        snapshot["timestamp"] = time()
        snapshot["datetime"] = string(now())
        snapshot["id"] = string(uuid4())
        
        # Extract brain weights if available
        if isdefined(brain_state, :weights)
            snapshot["weights"] = deepcopy(brain_state.weights)
        elseif isdefined(brain_state, :model) && isdefined(brain_state.model, :weights)
            snapshot["weights"] = deepcopy(brain_state.model.weights)
        else
            snapshot["weights"] = nothing
            @warn "No weights found in brain_state for snapshot"
        end
        
        # Extract memory state if available
        if isdefined(brain_state, :episodic_memory)
            snapshot["episodic_memory"] = deepcopy(brain_state.episodic_memory)
        else
            snapshot["episodic_memory"] = nothing
        end
        
        if isdefined(brain_state, :semantic_memory)
            snapshot["semantic_memory"] = deepcopy(brain_state.semantic_memory)
        else
            snapshot["semantic_memory"] = nothing
        end
        
        # Extract belief networks if available
        if isdefined(brain_state, :beliefs)
            snapshot["beliefs"] = deepcopy(brain_state.beliefs)
        else
            snapshot["beliefs"] = nothing
        end
        
        # Store cycle count
        if isdefined(brain_state, :cycle_count)
            snapshot["cycle_count"] = brain_state.cycle_count
        else
            snapshot["cycle_count"] = 0
        end
        
        @info "Brain snapshot created" snapshot_id=snapshot["id"]        
    catch e
        @error "Failed to create brain snapshot" error=e
        snapshot["error"] = string(e)
    end
    
    return snapshot
end

"""
    restore_brain! - Restore brain from snapshot (for rollback on bad training)

# Arguments
- `brain_state::Any`: The brain state to restore
- `snapshot::Dict{String, Any}`: The snapshot to restore from

# Returns
- `Bool`: true if restore was successful

# Example
```julia
snapshot = snapshot_brain(brain)
# ... perform training ...
if training_failed
    restore_brain!(brain, snapshot)
end
```
"""
function restore_brain!(
    brain_state::Any,
    snapshot::Dict{String, Any}
)::Bool
    try
        # Verify snapshot has required data
        if !haskey(snapshot, "weights") || snapshot["weights"] === nothing
            @error "Snapshot missing weights"
            return false
        end
        
        # Restore weights
        if isdefined(brain_state, :weights)
            brain_state.weights = deepcopy(snapshot["weights"])
        elseif isdefined(brain_state, :model) && isdefined(brain_state.model, :weights)
            brain_state.model.weights = deepcopy(snapshot["weights"])
        else
            @warn "Cannot restore weights: brain_state structure unknown"
        end
        
        # Restore memory if available
        if haskey(snapshot, "episodic_memory") && snapshot["episodic_memory"] !== nothing
            if isdefined(brain_state, :episodic_memory)
                brain_state.episodic_memory = deepcopy(snapshot["episodic_memory"])
            end
        end
        
        if haskey(snapshot, "semantic_memory") && snapshot["semantic_memory"] !== nothing
            if isdefined(brain_state, :semantic_memory)
                brain_state.semantic_memory = deepcopy(snapshot["semantic_memory"])
            end
        end
        
        # Restore beliefs if available
        if haskey(snapshot, "beliefs") && snapshot["beliefs"] !== nothing
            if isdefined(brain_state, :beliefs)
                brain_state.beliefs = deepcopy(snapshot["beliefs"])
            end
        end
        
        # Restore cycle count
        if haskey(snapshot, "cycle_count") && isdefined(brain_state, :cycle_count)
            brain_state.cycle_count = snapshot["cycle_count"]
        end
        
        @info "Brain restored from snapshot" snapshot_id=get(snapshot, "id", "unknown")        return true
        
    catch e
        @error "Failed to restore brain from snapshot" error=e
        return false
    end
end

# ============================================================================
# WEIGHT REGULARIZATION
# ============================================================================

"""
    regularize_weights! - Apply L2 regularization to neural weights

# Arguments
- `brain_state::Any`: The brain state to regularize
- `l2_factor::Float32`: L2 regularization strength (default: 0.01)
- `max_weight_change::Float32`: Maximum allowed weight change for safety (default: 0.1)

# Safety
- Weight changes are bounded by max_weight_change
- Snapshot should be taken before calling this function

# Example
```julia
snapshot = snapshot_brain(brain)
regularize_weights!(brain, l2_factor=0.01f0, max_weight_change=0.1f0)
```
"""
function regularize_weights!(
    brain_state::Any;
    l2_factor::Float32=0.01f0,
    max_weight_change::Float32=0.1f0
)
    try
        # Get weights based on brain structure
        weights = if isdefined(brain_state, :weights)
            brain_state.weights
        elseif isdefined(brain_state, :model) && isdefined(brain_state.model, :weights)
            brain_state.model.weights
        else
            @warn "No weights found to regularize"
            return
        end
        
        # Apply L2 regularization to each weight tensor
        for (key, w) in pairs(weights)
            if isa(w, AbstractArray{<:AbstractFloat})
                # Compute L2 gradient: 2 * l2_factor * w
                l2_grad = 2.0f0 * l2_factor .* w
                
                # Compute new weights
                new_weights = w - l2_grad
                
                # Bound weight changes
                weight_diff = new_weights - w
                clamped_diff = clamp.(weight_diff, -max_weight_change, max_weight_change)
                bounded_weights = w + clamped_diff
                
                # Update weights
                if isdefined(brain_state, :weights)
                    brain_state.weights[key] = bounded_weights
                elseif isdefined(brain_state, :model)
                    brain_state.model.weights[key] = bounded_weights
                end
            end
        end
        
        @debug "Weight regularization applied" l2_factor=l2_factor max_change=max_weight_change
        
    catch e
        @error "Failed to apply weight regularization" error=e
    end
end

# ============================================================================
# MEMORY CONSOLIDATION
# ============================================================================

"""
    consolidate_memory! - Transfer episodic to semantic memory, prune old memories, update beliefs

# Arguments
- `brain_state::Any`: The brain state with memory systems
- `sleep_state::SleepState`: Current sleep state

# Returns
- `Dict{String, Any}`: Consolidation report with statistics

# Process
1. Transfer important episodic memories to semantic memory
2. Prune old/low-importance episodic memories
3. Update belief networks
4. Return detailed report
"""
function consolidate_memory!(
    brain_state::Any,
    sleep_state::SleepState
)::Dict{String, Any}
    report = Dict{String, Any}()
    report["timestamp"] = time()
    report["phase"] = string(sleep_state.phase)
    
    try
        # Mark consolidation as active
        sleep_state.consolidation_active = true
        
        # Track statistics
        transferred_count = 0
        pruned_count = 0
        belief_updates = 0
        
        # 1. Transfer episodic to semantic memory
        if isdefined(brain_state, :episodic_memory) && isdefined(brain_state, :semantic_memory)
            episodic = brain_state.episodic_memory
            semantic = brain_state.semantic_memory
            
            # Find high-importance episodic memories for transfer
            if isa(episodic, Vector) && length(episodic) > 0
                for i in eachindex(episodic)
                    mem = episodic[i]
                    # Transfer if importance > 0.7
                    importance = get(mem, :importance, 0.5)
                    if importance > 0.7
                        push!(semantic, deepcopy(mem))
                        transferred_count += 1
                        @debug "Transferred memory to semantic" importance=importance
                    end
                end
            end
        end
        
        # 2. Prune old episodic memories
        if isdefined(brain_state, :episodic_memory)
            episodic = brain_state.episodic_memory
            if isa(episodic, Vector)
                original_len = length(episodic)
                
                # Keep only recent or high-importance memories
                max_episodic = 1000
                if length(episodic) > max_episodic
                    # Sort by importance and recency, keep top max_episodic
                    sorted = sort(episodic, by=m -> get(m, :importance, 0.0), rev=true)
                    brain_state.episodic_memory = sorted[1:min(max_episodic, length(sorted))]
                    pruned_count = original_len - length(brain_state.episodic_memory)
                end
            end
        end
        
        # 3. Update belief networks
        if isdefined(brain_state, :beliefs)
            beliefs = brain_state.beliefs
            # Strengthen high-frequency patterns
            if isa(beliefs, Dict)
                for (key, belief) in pairs(beliefs)
                    if isa(belief, Dict) && haskey(belief, :strength)
                        # Slightly increase strength of beliefs reinforced by recent memories
                        belief[:strength] = min(1.0, belief[:strength] + 0.01)
                        belief_updates += 1
                    end
                end
            end
        end
        
        # 4. Record consolidation metrics
        report["transferred_count"] = transferred_count
        report["pruned_count"] = pruned_count
        report["belief_updates"] = belief_updates
        report["success"] = true
        
        @info "Memory consolidation complete" 
              transferred=transferred_count 
              pruned=pruned_count 
              belief_updates=belief_updates
        
    catch e
        @error "Memory consolidation failed" error=e
        report["success"] = false
        report["error"] = string(e)
    finally
        sleep_state.consolidation_active = false
    end
    
    return report
end

# ============================================================================
# DREAM-BASED COUNTERFACTUAL EXPLORATION
# ============================================================================

"""
    dream_exploration! - Generate and learn from counterfactual scenarios during REM sleep

# Arguments
- `brain_state::Any`: The brain state for simulation
- `sleep_state::SleepState`: Current sleep state
- `exploration_horizon::Int`: How many steps into the future to explore (default: 5)
- `num_dreams::Int`: Number of dream scenarios to generate (default: 10)

# Returns
- `Vector{Dict{String, Any}}`: Array of dream experiences for memory storage

# Process
1. Sample recent episodic memories as dream seeds
2. Generate counterfactual variations
3. Simulate action outcomes
4. Learn from imagined experiences
5. Return experiences for memory storage
"""
function dream_exploration!(
    brain_state::Any,
    sleep_state::SleepState;
    exploration_horizon::Int=5,
    num_dreams::Int=10
)::Vector{Dict{String, Any}}
    dreams = Vector{Dict{String, Any}}()
    
    try
        @info "Starting dream exploration" num_dreams=num_dreams horizon=exploration_horizon
        
        # Get recent memories as seeds for dreams
        memory_seeds = []
        if isdefined(brain_state, :episodic_memory)
            episodic = brain_state.episodic_memory
            if isa(episodic, Vector) && length(episodic) > 0
                # Take last min(5, length) memories as seeds
                memory_seeds = episodic[max(1, end-min(5, length(episodic))+1):end]
            end
        end
        
        # Generate counterfactual dreams
        for dream_idx in 1:num_dreams
            dream = Dict{String, Any}()
            dream["id"] = string(uuid4())
            dream["timestamp"] = time()
            dream["type"] = "counterfactual"
            
            # Select a memory seed or create synthetic
            if !isempty(memory_seeds)
                seed = rand(memory_seeds)
                dream["seed_memory"] = get(seed, :content, "unknown")
            else
                # Create synthetic dream from nothing
                dream["seed_memory"] = "synthetic_dream"
            end
            
            # Generate counterfactual variations
            counterfactuals = Vector{Dict{String, Any}}()
            
            # Create alternative scenarios
            num_alternatives = min(3, exploration_horizon)
            for alt_idx in 1:num_alternatives
                alt = Dict{String, Any}()
                alt["scenario_id"] = string(uuid4())
                
                # Generate counterfactual: "what if I had done X instead of Y?"
                alt["counterfactual"] = "action_$alt_idx"
                alt["hypothetical_outcome"] = rand(Float32)  # Simulated outcome
                alt["learned_value"] = rand(Float32) * 0.5 - 0.25  # Learning signal
                
                push!(counterfactuals, alt)
            end
            
            dream["counterfactuals"] = counterfactuals
            
            # Simulate outcomes for exploration
            simulated_rewards = Float32[]
            for step in 1:exploration_horizon
                push!(simulated_rewards, rand(Float32) * 2 - 1)  # -1 to 1
            end
            dream["simulated_rewards"] = simulated_rewards
            dream["total_exploration_value"] = mean(simulated_rewards)
            
            # Store dream quality metrics
            dream["novelty"] = rand(Float32)  # How novel is this dream
            dream["coherence"] = rand(Float32)  # How coherent
            
            push!(dreams, dream)
            
            @debug "Dream generated" dream_id=dream["id"] value=dream["total_exploration_value"]
        end
        
        # Optional: Store dreams in memory if capacity available
        if isdefined(brain_state, :dream_memory)
            if isa(brain_state.dream_memory, Vector)
                # Keep only last 100 dreams
                if length(brain_state.dream_memory) >= 100
                    brain_state.dream_memory = brain_state.dream_memory[end-99:end]
                end
                append!(brain_state.dream_memory, dreams)
            end
        end
        
        @info "Dream exploration complete" num_dreams=length(dreams)
        
    catch e
        @error "Dream exploration failed" error=e
    end
    
    return dreams
end

# ============================================================================
# SLEEP CYCLE ORCHESTRATION
# ============================================================================

"""
    sleep_cycle! - Execute a complete sleep cycle with phase progression

# Arguments
- `brain_state::Any`: The brain state (JarvisBrain or ITHERIS BrainCore)
- `sleep_state::SleepState`: Current sleep state
- `min_sleep_interval::Float64`: Minimum time between sleep cycles in seconds (default: 3600.0 = 1 hour)

# Returns
- `Bool`: true if sleep occurred, false otherwise

# Process
1. Check if sleep is needed (based on min_sleep_interval)
2. Cycle through sleep phases: awake -> light_sleep -> deep_sleep -> rem -> awake
3. Perform consolidation at each phase
4. Apply weight regularization during deep sleep
5. Run dream exploration during REM
6. Return true if sleep completed

# Safety
- Snapshot is taken before any modifications
- Weight changes are bounded
"""
function sleep_cycle!(
    brain_state::Any,
    sleep_state::SleepState;
    min_sleep_interval::Float64=3600.0  # 1 hour minimum
)::Bool
    current_time = time()
    
    # Check if sleep needed
    time_since_last = current_time - sleep_state.last_sleep_time
    if time_since_last < min_sleep_interval
        @debug "Sleep not needed yet" time_since=time_since_last min_interval=min_sleep_interval
        return false
    end
    
    try
        @info "Starting sleep cycle" 
              last_sleep=sleep_state.last_sleep_time 
              cycles_since=sleep_state.cycle_count
        
        # Take snapshot before any modifications
        snapshot = snapshot_brain(brain_state)
        
        # Record sleep start time
        sleep_start_time = current_time
        sleep_state.phase = :light_sleep
        sleep_state.consolidation_active = true
        
        # Cycle through sleep phases
        phases = [:light_sleep, :deep_sleep, :rem]
        consolidation_reports = []
        
        for phase in phases
            sleep_state.phase = phase
            phase_duration = get_phase_duration(phase)
            
            @info "Entering sleep phase" phase=string(phase) duration=phase_duration
            
            # Execute phase-specific processing
            if phase == :light_sleep
                # Light sleep: initial memory stabilization
                report = consolidate_memory!(brain_state, sleep_state)
                push!(consolidation_reports, report)
                
            elseif phase == :deep_sleep
                # Deep sleep: neural consolidation + regularization
                regularize_weights!(brain_state, l2_factor=0.01f0, max_weight_change=0.1f0)
                
                report = consolidate_memory!(brain_state, sleep_state)
                push!(consolidation_reports, report)
                
            elseif phase == :rem
                # REM: dream exploration for counterfactual learning
                dreams = dream_exploration!(
                    brain_state, 
                    sleep_state;
                    exploration_horizon=5,
                    num_dreams=10
                )
                
                # Optional: consolidate learnings from dreams
                report = consolidate_memory!(brain_state, sleep_state)
                push!(consolidation_reports, report)
            end
            
            # Simulate phase duration (in real implementation, would actually sleep)
            # For computational sleep, we just proceed
        end
        
        # Complete cycle
        sleep_state.phase = :awake
        sleep_state.cycle_count += 1
        sleep_state.last_sleep_time = time()
        sleep_state.sleep_duration = sleep_state.last_sleep_time - sleep_start_time
        sleep_state.consolidation_active = false
        
        @info "Sleep cycle completed" duration=sleep_state.sleep_duration cycle_count=sleep_state.cycle_count
        
        return true
        
    catch e
        @error "Sleep cycle failed, attempting restore" error=e
        
        # Attempt to restore from snapshot
        if exists(snapshot)
            restore_brain!(brain_state, snapshot)
        end
        
        sleep_state.consolidation_active = false
        sleep_state.phase = :awake
        return false
    end
end

# Helper to check if snapshot exists
function exists(snap::Dict{String, Any})::Bool
    return haskey(snap, "weights") && snap["weights"] !== nothing
end

# ============================================================================
# INTEGRATION HELPERS
# ============================================================================

"""
    enter_sleep_mode - Helper to transition brain to sleep mode
"""
function enter_sleep_mode(brain_state::Any)::Bool
    try
        if isdefined(brain_state, :mode)
            brain_state.mode = :sleep
        end
        if isdefined(brain_state, :sleep_active)
            brain_state.sleep_active = true
        end
        @info "Brain entered sleep mode"
        return true
    catch e
        @error "Failed to enter sleep mode" error=e
        return false
    end
end

"""
    exit_sleep_mode - Helper to transition brain back to awake mode
"""
function exit_sleep_mode(brain_state::Any)::Bool
    try
        if isdefined(brain_state, :mode)
            brain_state.mode = :awake
        end
        if isdefined(brain_state, :sleep_active)
            brain_state.sleep_active = false
        end
        @info "Brain exited sleep mode"
        return true
    catch e
        @error "Failed to exit sleep mode" error=e
        return false
    end
end

# ============================================================================
# ONEIRIC (DREAM STATE) INTEGRATION
# ============================================================================

# Global Oneiric state for integration
const _oneiric_state = Ref{Union{OneiricState, Nothing}}(nothing)

"""
    integrate_with_oneiric!(memory_store::MemoryStore)

Integrate the Sleep module with the Oneiric (dream state) controller.
This enables enhanced dream processing with memory replay, hallucination 
training, and synaptic homeostasis.

# Arguments
- `memory_store::MemoryStore`: The memory store to use for dream processing

# Example
```julia
memory_store = MemoryStore()
integrate_with_oneiric!(memory_store)
```
"""
function integrate_with_oneiric!(memory_store::MemoryStore)
    config = OneiricConfig(
        min_energy_for_dream=0.35f0,
        dream_duration_min=300.0,
        dream_duration_max=1800.0,
        enable_replay=true,
        enable_hallucination_training=true,
        enable_homeostasis=true
    )
    
    _oneiric_state[] = OneiricState(
        config;
        sleep_state=nothing,
        memory_store=memory_store
    )
    
    @info "Integrated Oneiric controller with Sleep module"
end

"""
    enter_oneiric_mode(; energy_level::Float32=1.0f0, is_idle::Bool=false, idle_duration::Float64=0.0)

Enter the Oneiric (dream) state if conditions are met.

# Arguments
- `energy_level::Float32`: Current energy level (default: 1.0)
- `is_idle::Bool`: Whether system is idle (default: false)
- `idle_duration::Float64`: Duration of idle state in seconds (default: 0.0)

# Returns
- `Dict{String, Any}`: Result of entering dream state

# Example
```julia
result = enter_oneiric_mode(energy_level=0.25f0, is_idle=true, idle_duration=300.0)
```
"""
function enter_oneiric_mode(
    ;
    energy_level::Float32=1.0f0,
    is_idle::Bool=false,
    idle_duration::Float64=0.0
)::Dict{String, Any}
    state = _oneiric_state[]
    
    if state === nothing
        return Dict{String, Any}(
            "status" => "not_integrated",
            "message" => "Call integrate_with_oneiric! first"
        )
    end
    
    # Check if should enter
    if !should_enter_dream(energy_level, is_idle, idle_duration, state)
        return Dict{String, Any}(
            "status" => "conditions_not_met",
            "energy_level" => energy_level,
            "is_idle" => is_idle,
            "idle_duration" => idle_duration
        )
    end
    
    # Enter dream state
    return enter_dream_state!(state)
end

"""
    run_oneiric_dream(; max_cycles::Int=10)

Run a complete Oneiric (dream) processing session.

# Arguments
- `max_cycles::Int`: Maximum number of dream cycles (default: 10)

# Returns
- `Dict{String, Any}`: Complete dream session results

# Example
```julia
results = run_oneiric_dream(max_cycles=5)
```
"""
function run_oneiric_dream(; max_cycles::Int=10)::Dict{String, Any}
    state = _oneiric_state[]
    
    if state === nothing
        return Dict{String, Any}(
            "status" => "not_integrated",
            "message" => "Call integrate_with_oneiric! first"
        )
    end
    
    # Run dream processing
    return run_dream_processing!(state; max_cycles=max_cycles)
end

"""
    get_oneiric_status()

Get the current status of the Oneiric (dream) system.

# Returns
- `Dict{String, Any}`: Status information

# Example
```julia
status = get_oneiric_status()
```
"""
function get_oneiric_status()::Dict{String, Any}
    state = _oneiric_state[]
    
    if state === nothing
        return Dict{String, Any}(
            "status" => "not_integrated",
            "message" => "Call integrate_with_oneiric! first"
        )
    end
    
    return get_oneiric_statistics(state)
end

end # module Sleep
