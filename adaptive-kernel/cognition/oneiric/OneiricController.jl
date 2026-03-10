# adaptive-kernel/cognition/oneiric/OneiricController.jl - Oneiric (Dream State) Controller
# JARVIS Neuro-Symbolic Architecture - Central controller for dream-based cognitive processing

module OneiricController

using Dates
using UUIDs
using Statistics
using Logging

# Import sleep system for integration
include(joinpath(@__DIR__, "..", "consolidation", "Sleep.jl"))
using .Sleep

# Import memory store
include(joinpath(@__DIR__, "..", "..", "memory", "Memory.jl"))
using ..Memory

# Import cognitive types
include(joinpath(@__DIR__, "..", "types.jl"))
using ..CognitionTypes

# Import oneiric modules
include(joinpath(@__DIR__, "MemoryReplay.jl"))
using .MemoryReplay

include(joinpath(@__DIR__, "HallucinationTrainer.jl"))
using .HallucinationTrainer

include(joinpath(@__DIR__, "SynapticHomeostasis.jl"))
using .SynapticHomeostasis

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Configuration
    OneiricConfig,
    
    # State
    OneiricState,
    OneiricPhase,
    
    # Core functions
    enter_dream_state!,
    process_dream_cycle!,
    exit_dream_state!,
    should_enter_dream,
    run_dream_processing!

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    OneiricConfig - Configuration for Oneiric (dream) mode

# Fields
- `min_energy_for_dream::Float32`: Maximum energy to enter dream state (default: 0.35)
- `dream_duration_min::Float64`: Minimum dream duration in seconds (default: 300.0)
- `dream_duration_max::Float64`: Maximum dream duration in seconds (default: 1800.0)
- `cycle_interval::Float64`: Interval between dream cycles in seconds (default: 60.0)
- `enable_replay::Bool`: Enable memory replay (default: true)
- `enable_hallucination_training::Bool`: Enable hallucination detection (default: true)
- `enable_homeostasis::Bool`: Enable synaptic homeostasis (default: true)
- `idle_threshold::Float64`: Idle time threshold in seconds (default: 300.0)
- `nightly_hour::Int`: Hour of day for nightly dreams (default: 2 = 2 AM)
"""
@with_kw mutable struct OneiricConfig
    min_energy_for_dream::Float32 = 0.35f0
    dream_duration_min::Float64 = 300.0  # 5 minutes
    dream_duration_max::Float64 = 1800.0  # 30 minutes
    cycle_interval::Float64 = 60.0  # 1 minute
    enable_replay::Bool = true
    enable_hallucination_training::Bool = true
    enable_homeostasis::Bool = true
    idle_threshold::Float64 = 300.0  # 5 minutes
    nightly_hour::Int = 2  # 2 AM
end

# ============================================================================
# ONEIRIC PHASES
# ============================================================================

"""
    OneiricPhase - Enum representing different stages of dream processing

- `:idle`: Not in dream state
- `:entering`: Transitioning into dream state
- `:replay`: Memory replay phase
- `:hallucination_training`: Hallucination detection training
- `:homeostasis`: Synaptic homeostasis
- `:exiting`: Transitioning out of dream state
"""
@enum OneiricPhase begin
    :idle
    :entering
    :replay
    :hallucination_training
    :homeostasis
    :exiting
end

# ============================================================================
# STATE
# ============================================================================

"""
    OneiricState - Central state for Oneiric (dream) mode

# Fields
- `config::OneiricConfig`: Oneiric configuration
- `phase::OneiricPhase`: Current dream phase
- `dream_count::Int`: Number of dream sessions completed
- `current_dream_start::Float64`: Unix timestamp of current dream start
- `last_dream_time::Float64`: Unix timestamp of last dream
- `replay_state::ReplayState`: Memory replay subsystem
- `hallucination_state::HallucinationState`: Hallucination detection subsystem
- `homeostasis_state::HomeostasisState`: Synaptic homeostasis subsystem
- `sleep_state::Union{SleepState, Nothing}`: Reference to sleep state
- `memory_store::Union{MemoryStore, Nothing}`: Reference to memory store
- `dream_history::Vector{Dict}`: History of dream sessions
"""
mutable struct OneiricState
    config::OneiricConfig
    phase::OneiricPhase
    dream_count::Int
    current_dream_start::Float64
    last_dream_time::Float64
    
    # Subsystems
    replay_state::ReplayState
    hallucination_state::HallucinationState
    homeostasis_state::HomeostasisState
    
    # External references
    sleep_state::Union{SleepState, Nothing}
    memory_store::Union{MemoryStore, Nothing}
    
    # History
    dream_history::Vector{Dict{String, Any}}
    
    function OneiricState(
        config::OneiricConfig=OneiricConfig();
        sleep_state::Union{SleepState, Nothing}=nothing,
        memory_store::Union{MemoryStore, Nothing}=nothing
    )
        new(
            config,
            :idle,
            0,
            0.0,
            0.0,
            ReplayState(),
            HallucinationState(),
            HomeostasisState(),
            sleep_state,
            memory_store,
            Dict{String, Any}[]
        )
    end
end

# ============================================================================
# TRIGGER CONDITIONS
# ============================================================================

"""
    should_enter_dream(
    energy_level::Float32,
    is_idle::Bool,
    idle_duration::Float64,
    state::OneiricState
)::Bool

Determine if the system should enter dream (Oneiric) state.

# Arguments
- `energy_level::Float32`: Current energy level (0.0-1.0)
- `is_idle::Bool`: Whether system is idle
- `idle_duration::Float64`: Duration of idle state in seconds
- `state::OneiricState`: Current Oneiric state

# Returns
- `Bool`: true if should enter dream state

# Triggers
- Nightly at configured hour
- Low energy (< 0.35)
- System idle for threshold duration

# Example
```julia
if should_enter_dream(0.25, true, 600.0, oneiric_state)
    enter_dream_state!(oneiric_state)
end
```
"""
function should_enter_dream(
    energy_level::Float32,
    is_idle::Bool,
    idle_duration::Float64,
    state::OneiricState
)::Bool
    config = state.config
    
    # Already in dream state
    state.phase != :idle && return false
    
    # Check if recently dreamed (prevent rapid re-entry)
    if state.last_dream_time > 0.0
        time_since_dream = time() - state.last_dream_time
        if time_since_dream < config.dream_duration_min
            return false
        end
    end
    
    # Check nightly trigger
    current_hour = Hour(now())
    if current_hour == Hour(config.nightly_hour)
        # During nightly hour, check if enough time since last dream
        if state.last_dream_time > 0.0
            time_since_last = time() - state.last_dream_time
            if time_since_last >= 3600.0  # At least 1 hour since last dream
                @info "Nightly dream trigger"
                return true
            end
        else
            @info "Nightly dream trigger (first)"
            return true
        end
    end
    
    # Check low energy trigger
    if energy_level <= config.min_energy_for_dream
        @info "Low energy dream trigger" energy=energy_level threshold=config.min_energy_for_dream
        return true
    end
    
    # Check idle trigger
    if is_idle && idle_duration >= config.idle_threshold
        @info "Idle dream trigger" idle_duration=idle_duration threshold=config.idle_threshold
        return true
    end
    
    return false
end

"""
    should_enter_dream(state::OneiricState; energy_level::Float32=1.0f0, is_idle::Bool=false, idle_duration::Float64=0.0)::Bool

Convenience wrapper with default parameters.
"""
function should_enter_dream(
    state::OneiricState;
    energy_level::Float32=1.0f0,
    is_idle::Bool=false,
    idle_duration::Float64=0.0
)::Bool
    return should_enter_dream(energy_level, is_idle, idle_duration, state)
end

# ============================================================================
# DREAM STATE MANAGEMENT
# ============================================================================

"""
    enter_dream_state!(state::OneiricState)::Dict{String, Any}

Transition into dream (Oneiric) state.

# Arguments
- `state::OneiricState`: Current Oneiric state

# Returns
- `Dict{String, Any}`: Entry results with configuration

# Example
```julia
results = enter_dream_state!(oneiric_state)
```
"""
function enter_dream_state!(state::OneiricState)::Dict{String, Any}
    current_time = time()
    
    if state.phase != :idle
        return Dict{String, Any}(
            "status" => "already_in_dream",
            "phase" => string(state.phase)
        )
    end
    
    # Transition to entering
    state.phase = :entering
    state.current_dream_start = current_time
    
    # Reset subsystems for new dream
    reset_replay_state!(state.replay_state)
    reset_hallucination_state!(state.hallucination_state)
    reset_homeostasis_state!(state.homeostasis_state)
    
    # Initialize neural connections if needed
    if isempty(state.homeostasis_state.connections)
        initialize_connections!(state.homeostasis_state, 100)  # 100 neurons
    end
    
    @info "Entered dream state"
        dream_count=state.dream_count + 1
    
    return Dict{String, Any}(
        "status" => "success",
        "phase" => "entering",
        "dream_start" => current_time,
        "config" => Dict(
            "enable_replay" => state.config.enable_replay,
            "enable_hallucination_training" => state.config.enable_hallucination_training,
            "enable_homeostasis" => state.config.enable_homeostasis
        )
    )
end

"""
    process_dream_cycle!(state::OneiricState)::Dict{String, Any}

Process a single dream cycle with all subsystems.

# Arguments
- `state::OneiricState`: Current Oneiric state

# Returns
- `Dict{String, Any}`: Cycle results with subsystem outputs

# Example
```julia
results = process_dream_cycle!(oneiric_state)
```
"""
function process_dream_cycle!(state::OneiricState)::Dict{String, Any}
    config = state.config
    current_time = time()
    
    if state.phase == :idle
        return Dict{String, Any}(
            "status" => "not_in_dream",
            "phase" => "idle"
        )
    end
    
    # Check if dream should end
    dream_duration = current_time - state.current_dream_start
    if dream_duration >= config.dream_duration_max
        return exit_dream_state!(state)
    end
    
    results = Dict{String, Any}(
        "timestamp" => current_time,
        "dream_duration" => dream_duration,
        "phases" => Dict{String, Any}()
    )
    
    # Phase 1: Memory Replay
    if config.enable_replay && state.phase in [:entering, :replay]
        state.phase = :replay
        
        if state.memory_store !== nothing
            replay_result = replay_experiences!(state.memory_store, state.replay_state)
            results["phases"]["replay"] = replay_result
            
            # Compress to embeddings if replay successful
            if replay_result["status"] == "success"
                embeddings = compress_to_embeddings!(state.replay_state)
                results["phases"]["embeddings"] = Dict(
                    "dim" => size(embeddings, 1),
                    "count" => size(embeddings, 2)
                )
            end
        else
            results["phases"]["replay"] = Dict("status" => "no_memory_store")
        end
    end
    
    # Phase 2: Hallucination Training
    if config.enable_hallucination_training && state.phase in [:replay, :hallucination_training]
        state.phase = :hallucination_training
        
        # Get embeddings from replay if available
        embeddings = state.replay_state.embeddings_cache
        
        if embeddings !== nothing
            # Use embeddings as training data
            real_features = [embeddings[:, i] for i in axes(embeddings, 2)]
            synthetic = generate_synthetic_examples(state.hallucination_state, real_features)
            
            if !isempty(real_features) && !isempty(synthetic)
                training_result = train_discriminator!(
                    state.hallucination_state,
                    real_features,
                    synthetic
                )
                results["phases"]["hallucination_training"] = training_result
            else
                results["phases"]["hallucination_training"] = Dict("status" => "insufficient_data")
            end
        else
            # Run without embeddings
            halluc_result = Dict{String, Any}(
                "status" => "no_embeddings",
                "waiting_for_replay" => state.config.enable_replay
            )
            results["phases"]["hallucination_training"] = halluc_result
        end
    end
    
    # Phase 3: Synaptic Homeostasis
    if config.enable_homeostasis && state.phase in [:hallucination_training, :homeostasis]
        state.phase = :homeostasis
        
        # Get priorities from replay
        priorities = state.replay_state.priorities
        
        if !isempty(priorities)
            # Consolidate memories
            consolidation_result = consolidate_memories!(state.homeostasis_state, priorities)
            results["phases"]["consolidation"] = consolidation_result
        end
        
        # Maintain energy budget
        energy_result = maintain_energy_budget!(state.homeostasis_state)
        results["phases"]["energy"] = energy_result
        
        # Optimize weights
        optimization_result = optimize_weights!(state.homeostasis_state)
        results["phases"]["optimization"] = optimization_result
    end
    
    results["status"] = "cycle_complete"
    results["current_phase"] = string(state.phase)
    
    return results
end

"""
    exit_dream_state!(state::OneiricState)::Dict{String, Any}

Transition out of dream (Oneiric) state.

# Arguments
- `state::OneiricState`: Current Oneiric state

# Returns
- `Dict{String, Any}`: Exit results with dream statistics

# Example
```julia
results = exit_dream_state!(oneiric_state)
```
"""
function exit_dream_state!(state::OneiricState)::Dict{String, Any}
    current_time = time()
    
    if state.phase == :idle
        return Dict{String, Any}(
            "status" => "not_in_dream"
        )
    end
    
    # Transition to exiting
    state.phase = :exiting
    
    # Calculate dream duration
    dream_duration = current_time - state.current_dream_start
    
    # Gather final statistics
    replay_stats = get_replay_statistics(state.replay_state)
    hallucination_stats = get_hallucination_statistics(state.hallucination_state)
    homeostasis_stats = get_homeostasis_statistics(state.homeostasis_state)
    
    # Record in history
    dream_record = Dict{String, Any}(
        "dream_id" => string(uuid4()),
        "start_time" => state.current_dream_start,
        "end_time" => current_time,
        "duration" => dream_duration,
        "replay" => replay_stats,
        "hallucination" => hallucination_stats,
        "homeostasis" => homeostasis_stats
    )
    push!(state.dream_history, dream_record)
    
    # Update counters
    state.dream_count += 1
    state.last_dream_time = current_time
    
    # Transition to idle
    state.phase = :idle
    
    @info "Exited dream state"
        dream_count=state.dream_count
        duration=dream_duration
    
    return Dict{String, Any}(
        "status" => "success",
        "phase" => "idle",
        "dream_count" => state.dream_count,
        "dream_duration" => dream_duration,
        "statistics" => Dict(
            "replay" => replay_stats,
            "hallucination" => hallucination_stats,
            "homeostasis" => homeostasis_stats
        )
    )
end

# ============================================================================
# DREAM PROCESSING RUNNER
# ============================================================================

"""
    run_dream_processing!(
    state::OneiricState;
    max_cycles::Int=10
)::Dict{String, Any}

Run complete dream processing session.

# Arguments
- `state::OneiricState`: Current Oneiric state
- `max_cycles::Int`: Maximum number of dream cycles (default: 10)

# Returns
- `Dict{String, Any}`: Complete dream session results

# Example
```julia
results = run_dream_processing!(oneiric_state)
```
"""
function run_dream_processing!(
    state::OneiricState;
    max_cycles::Int=10
)::Dict{String, Any}
    # Enter dream state
    entry_result = enter_dream_state!(state)
    
    if entry_result["status"] != "success" && entry_result["status"] != "already_in_dream"
        return entry_result
    end
    
    # Process cycles
    cycle_results = Dict{String, Any}[]
    
    for cycle in 1:max_cycles
        cycle_result = process_dream_cycle!(state)
        push!(cycle_results, cycle_result)
        
        # Check if exited
        if state.phase == :idle
            break
        end
        
        # Small delay between cycles
        sleep(0.1)
    end
    
    # If still in dream after max cycles, force exit
    if state.phase != :idle
        exit_result = exit_dream_state!(state)
        return merge(exit_result, Dict("cycles" => cycle_results))
    end
    
    # Get final results
    final_results = exit_dream_state!(state)
    final_results["cycles"] = cycle_results
    
    return final_results
end

# ============================================================================
# INTEGRATION WITH SLEEP
# ============================================================================

"""
    integrate_with_sleep(state::OneiricState, sleep_state::SleepState)

Integrate Oneiric controller with sleep system.

# Arguments
- `state::OneiricState`: Oneiric state to integrate
- `sleep_state::SleepState`: Sleep state to reference
"""
function integrate_with_sleep(state::OneiricState, sleep_state::SleepState)
    state.sleep_state = sleep_state
end

"""
    integrate_with_memory(state::OneiricState, memory_store::MemoryStore)

Integrate Oneiric controller with memory store.

# Arguments
- `state::OneiricState`: Oneiric state to integrate
- `memory_store::MemoryStore`: Memory store to reference
"""
function integrate_with_memory(state::OneiricState, memory_store::MemoryStore)
    state.memory_store = memory_store
end

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

"""
    get_oneiric_statistics(state::OneiricState)::Dict{String, Any}

Get comprehensive statistics about the Oneiric system.

# Arguments
- `state::OneiricState`: Current state

# Returns
- `Dict{String, Any}`: Statistics dictionary
"""
function get_oneiric_statistics(state::OneiricState)::Dict{String, Any}
    return Dict{String, Any}(
        "current_phase" => string(state.phase),
        "dream_count" => state.dream_count,
        "last_dream_time" => state.last_dream_time,
        "current_dream_duration" => state.current_dream_start > 0 ? 
            time() - state.current_dream_start : 0.0,
        "replay" => get_replay_statistics(state.replay_state),
        "hallucination" => get_hallucination_statistics(state.hallucination_state),
        "homeostasis" => get_homeostasis_statistics(state.homeostasis_state),
        "config" => Dict(
            "min_energy_for_dream" => state.config.min_energy_for_dream,
            "dream_duration_max" => state.config.dream_duration_max,
            "enable_replay" => state.config.enable_replay,
            "enable_hallucination_training" => state.config.enable_hallucination_training,
            "enable_homeostasis" => state.config.enable_homeostasis
        ),
        "history_length" => length(state.dream_history)
    )
end

end # module OneiricController
