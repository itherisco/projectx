# cognition/metabolic/MetabolicController.jl - Simulated Metabolism System
# Component 9 (implemented): Energy management for cognitive processes
#
# Every inference costs energy
# State variables: ENERGY, DEATH_ENERGY, RECOVERY_RATE
# If energy low: trigger planning, self-optimization, dreaming mode

module MetabolicController

using Dates
using Statistics

# ============================================================================
# CONSTANTS
# ============================================================================

# Energy thresholds
const ENERGY_MAX = 1.0f0
const ENERGY_DEATH = 0.05f0       # Death threshold - system shutdown
const ENERGY_CRITICAL = 0.15f0    # Critical - emergency mode
const ENERGY_LOW = 0.30f0         # Low - recovery mode
const ENERGY_SUSTAINED = 0.50f0   # Normal operation
const ENERGY_RECOVERY = 0.70f0    # Recovery - can do heavy processing
const ENERGY_FULL = 0.90f0        # Full capacity

# Energy costs per operation type
const COST_PERCEPTION = 0.001f0       # Cost per perception cycle
const COST_BRAIN_INFERENCE = 0.005f0  # Cost per brain inference
const COST_LEARNING = 0.008f0         # Cost per learning update
const COST_PLANNING = 0.010f0         # Cost per planning cycle
const COST_DREAMING = 0.0005f0        # Low cost dreaming mode

# Metabolic clock - 136.1 Hz heartbeat for survival-driven cognition
const METABOLIC_FREQUENCY_HZ = 136.1f0
const METABOLIC_PERIOD_NS = UInt64(round(1e9 / METABOLIC_FREQUENCY_HZ))
const METABOLIC_TICKS_PER_SECOND = Float32(METABOLIC_FREQUENCY_HZ)

# Survival thresholds
const DEATH_ENERGY = 0.05f0  # Death threshold per Phase 2 spec

# Recovery rates
const RECOVERY_RATE_IDLE = 0.002f0     # Recovery while idle
const RECOVERY_RATE_ACTIVE = 0.001f0   # Recovery while active
const RECOVERY_RATE_DREAMING = 0.003f0 # Recovery during dreaming

# Cognitive modes based on energy
@enum CognitiveMode begin
    MODE_DEATH = 0      # System dead - below death threshold
    MODE_CRITICAL = 1   # Emergency - minimal function
    MODE_RECOVERY = 2   # Recovery - limited function
    MODE_IDLE = 3       # Idle - baseline function
    MODE_ACTIVE = 4     # Active - full function
    MODE_DREAMING = 5   # Dreaming - offline consolidation
end

# ============================================================================
# METABOLIC STATE
# ============================================================================

"""
    MetabolicState - State for simulated metabolism

# Fields
- `energy::Float32`: Current energy level (0.0-1.0)
- `max_energy::Float32`: Maximum energy capacity
- `recovery_rate::Float32`: Energy recovery per cycle
- `consumption_rate::Float32`: Energy consumption per cycle
- `mode::CognitiveMode`: Current cognitive mode
- `time_since_last_meal::Float32`: Time since last energy boost
- `consecutive_low_cycles::Int`: Consecutive cycles at low energy
- `dream_accumulation::Float32`: Dream need accumulation
- `metabolic_history::Vector{Tuple{DateTime, Float32}}`: Energy history
"""
mutable struct MetabolicState
    # Core energy state
    energy::Float32
    max_energy::Float32
    recovery_rate::Float32
    consumption_rate::Float32
    
    # Mode
    mode::CognitiveMode
    
    # Tracking
    time_since_last_meal::Float32
    consecutive_low_cycles::Int
    consecutive_high_cycles::Int
    dream_accumulation::Float32
    total_cycles::Int64
    
    # History for monitoring
    metabolic_history::Vector{Tuple{DateTime, Float32}}
    
    # Thresholds
    death_threshold::Float32
    critical_threshold::Float32
    low_threshold::Float32
    recovery_threshold::Float32
    
    function MetabolicState()
        new(
            ENERGY_MAX,          # energy
            ENERGY_MAX,          # max_energy
            RECOVERY_RATE_IDLE,  # recovery_rate
            0.0f0,               # consumption_rate
            MODE_ACTIVE,         # mode
            0.0f0,               # time_since_last_meal
            0,                   # consecutive_low_cycles
            0,                   # consecutive_high_cycles
            0.0f0,               # dream_accumulation
            0,                   # total_cycles
            Tuple{DateTime, Float32}[],  # metabolic_history
            ENERGY_DEATH,        # death_threshold
            ENERGY_CRITICAL,     # critical_threshold
            ENERGY_LOW,          # low_threshold
            ENERGY_RECOVERY      # recovery_threshold
        )
    end
end

# ============================================================================
# CORE METABOLIC FUNCTIONS
# ============================================================================

"""
    initialize_metabolism()::MetabolicState

Create and initialize metabolic state
"""
function initialize_metabolism()::MetabolicState
    state = MetabolicState()
    record_energy!(state)
    return state
end

"""
    update_metabolism!(state::MetabolicState, operations::Dict{Symbol, Bool})::CognitiveMode

Update metabolic state based on operations performed.
Returns the appropriate cognitive mode for this energy level.

# Arguments
- `state::MetabolicState`: Current metabolic state
- `operations::Dict{Symbol, Bool}`: Which operations were performed
"""
function update_metabolism!(state::MetabolicState, operations::Dict{Symbol, Bool})::CognitiveMode
    state.total_cycles += 1
    state.time_since_last_meal += CYCLE_DURATION_MS / 1000.0
    
    # Calculate energy consumption based on operations
    consumption = calculate_consumption(operations)
    state.consumption_rate = consumption
    
    # Calculate energy recovery based on mode
    recovery = calculate_recovery(state)
    state.recovery_rate = recovery
    
    # Update energy
    state.energy = clamp(state.energy - consumption + recovery, 0.0f0, state.max_energy)
    
    # Update mode based on energy level
    state.mode = determine_mode(state)
    
    # Update tracking variables
    update_tracking!(state)
    
    # Record history
    if state.total_cycles % 100 == 0
        record_energy!(state)
    end
    
    # Check for death
    if state.energy <= state.death_threshold
        return MODE_DEATH
    end
    
    return state.mode
end

"""
    calculate_consumption - Calculate energy consumption for operations
"""
function calculate_consumption(operations::Dict{Symbol, Bool})::Float32
    consumption = 0.0f0
    
    if get(operations, :perception, false)
        consumption += COST_PERCEPTION
    end
    
    if get(operations, :brain_inference, false)
        consumption += COST_BRAIN_INFERENCE
    end
    
    if get(operations, :learning, false)
        consumption += COST_LEARNING
    end
    
    if get(operations, :planning, false)
        consumption += COST_PLANNING
    end
    
    if get(operations, :dreaming, false)
        consumption += COST_DREAMING
    end
    
    # Base metabolism cost
    consumption += 0.0002f0
    
    return consumption
end

"""
    calculate_recovery - Calculate energy recovery based on current mode
"""
function calculate_recovery(state::MetabolicState)::Float32
    if state.mode == MODE_DREAMING
        return RECOVERY_RATE_DREAMING
    elseif state.mode == MODE_IDLE
        return RECOVERY_RATE_IDLE
    elseif state.mode == MODE_ACTIVE
        return RECOVERY_RATE_ACTIVE
    else
        # Low or critical mode - minimal recovery
        return 0.0f0
    end
end

"""
    determine_mode - Determine cognitive mode based on energy level
"""
function determine_mode(state::MetabolicState)::CognitiveMode
    if state.energy <= state.death_threshold
        return MODE_DEATH
    elseif state.energy <= state.critical_threshold
        return MODE_CRITICAL
    elseif state.energy <= state.low_threshold
        return MODE_RECOVERY
    elseif state.energy <= state.recovery_threshold
        return MODE_IDLE
    elseif state.dream_accumulation > 0.8f0
        # Dreaming needed
        return MODE_DREAMING
    else
        return MODE_ACTIVE
    end
end

"""
    update_tracking! - Update tracking variables
"""
function update_tracking!(state::MetabolicState)
    # Track consecutive low energy cycles
    if state.energy < state.low_threshold
        state.consecutive_low_cycles += 1
    else
        state.consecutive_low_cycles = 0
    end
    
    # Track consecutive high energy cycles
    if state.energy > state.recovery_threshold
        state.consecutive_high_cycles += 1
    else
        state.consecutive_high_cycles = 0
    end
    
    # Dream accumulation (need for consolidation)
    if state.mode == MODE_ACTIVE
        state.dream_accumulation = min(1.0f0, state.dream_accumulation + 0.001f0)
    elseif state.mode == MODE_DREAMING
        state.dream_accumulation = max(0.0f0, state.dream_accumulation - 0.05f0)
    end
end

"""
    record_energy! - Record current energy in history
"""
function record_energy!(state::MetabolicState)
    push!(state.metabolic_history, (now(), state.energy))
    
    # Keep history bounded
    if length(state.metabolic_history) > 1000
        deleteat!(state.metabolic_history, 1:length(state.metabolic_history) - 1000)
    end
end

# ============================================================================
# ENERGY MANAGEMENT
# ============================================================================

"""
    boost_energy!(state::MetabolicState, amount::Float32)

Boost energy level (e.g., after successful task completion or external input)
"""
function boost_energy!(state::MetabolicState, amount::Float32)
    state.energy = clamp(state.energy + amount, 0.0f0, state.max_energy)
    state.time_since_last_meal = 0.0f0
    
    # Record the boost
    record_energy!(state)
end

"""
    force_mode!(state::MetabolicState, mode::CognitiveMode)

Force a specific cognitive mode (for testing or special circumstances)
"""
function force_mode!(state::MetabolicState, mode::CognitiveMode)
    state.mode = mode
    
    # Adjust dream accumulation based on mode
    if mode == MODE_DREAMING
        state.dream_accumulation = 0.0f0
    end
end

"""
    get_energy_status - Get detailed energy status
"""
function get_energy_status(state::MetabolicState)::Dict
    return Dict(
        "energy" => state.energy,
        "mode" => String(Symbol(state.mode)),
        "recovery_rate" => state.recovery_rate,
        "consumption_rate" => state.consumption_rate,
        "consecutive_low_cycles" => state.consecutive_low_cycles,
        "dream_accumulation" => state.dream_accumulation,
        "total_cycles" => state.total_cycles,
        "time_since_last_meal" => state.time_since_last_meal,
        "is_critical" => state.energy <= state.critical_threshold,
        "needs_dream" => state.dream_accumulation > 0.8f0
    )
end

"""
    should_enter_dreaming - Check if dreaming mode should be entered
"""
function should_enter_dreaming(state::MetabolicState)::Bool
    return (state.dream_accumulation > 0.8f0 && 
            state.energy > state.low_threshold &&
            state.mode != MODE_CRITICAL &&
            state.mode != MODE_DEATH)
end

"""
    should_trigger_planning - Check if self-optimization planning should be triggered
"""
function should_trigger_planning(state::MetabolicState)::Bool
    return (state.consecutive_low_cycles > 10 &&
            state.energy > state.critical_threshold)
end

"""
    get_recommended_operations - Get recommended operations for current energy level
"""
function get_recommended_operations(state::MetabolicState)::Dict{Symbol, Bool}
    operations = Dict{Symbol, Bool}(
        :perception => true,
        :brain_inference => false,
        :learning => false,
        :planning => false,
        :dreaming => false
    )
    
    if state.energy >= state.recovery_threshold
        # Full capacity
        operations[:brain_inference] = true
        operations[:learning] = true
        operations[:planning] = true
    elseif state.energy >= state.low_threshold
        # Normal capacity
        operations[:brain_inference] = true
        operations[:learning] = true
    elseif state.energy >= state.critical_threshold
        # Minimal capacity
        operations[:brain_inference] = true
    else
        # Critical - just perception
        operations[:perception] = true
    end
    
    # Override for dreaming
    if state.mode == MODE_DREAMING
        operations[:dreaming] = true
        operations[:perception] = false
        operations[:brain_inference] = false
    end
    
    return operations
end

# ============================================================================
# METABOLIC INTEGRATION WITH COGNITIVE LOOP
# ============================================================================

"""
    apply_metabolic_constraints - Apply metabolic constraints to cognitive operations

This function is called at the start of each cognitive cycle to determine
what operations can be performed based on current energy state.
"""
function apply_metabolic_constraints(state::MetabolicState)::Dict{Symbol, Bool}
    # Get recommended operations based on energy
    operations = get_recommended_operations(state)
    
    # Check for special conditions
    
    # 1. Critical energy - reduce all operations
    if state.energy <= state.critical_threshold
        operations[:brain_inference] = false
        operations[:learning] = false
        operations[:planning] = false
    end
    
    # 2. Check for death
    if state.energy <= state.death_threshold
        # System should be in shutdown
        return Dict{Symbol, Bool}()
    end
    
    # 3. Dreaming mode
    if should_enter_dreaming(state)
        operations[:dreaming] = true
    end
    
    return operations
end

"""
    process_metabolic_feedback - Process outcomes and adjust energy

Called after cognitive cycle with outcome information.
"""
function process_metabolic_feedback!(
    state::MetabolicState,
    outcome_success::Bool,
    reward::Float32
)
    if outcome_success
        # Successful outcomes provide energy boost
        boost = reward * 0.01f0
        boost_energy!(state, boost)
    else
        # Failures cost extra energy (frustration)
        state.energy = max(0.0f0, state.energy - 0.002f0)
    end
end

# ============================================================================
# DIAGNOSTICS
# ============================================================================

"""
    get_metabolic_summary - Get summary of metabolic state
"""
function get_metabolic_summary(state::MetabolicState)::Dict
    recent_history = length(state.metabolic_history) > 10 ?
                     last(state.metabolic_history, 10) : state.metabolic_history
    
    avg_energy = isempty(recent_history) ? 0.0f0 :
                 mean([e[2] for e in recent_history])
    
    return Dict(
        "current_energy" => state.energy,
        "mode" => String(Symbol(state.mode)),
        "avg_energy_recent" => avg_energy,
        "total_cycles" => state.total_cycles,
        "consecutive_low_cycles" => state.consecutive_low_cycles,
        "dream_need" => state.dream_accumulation,
        "is_healthy" => state.energy > state.low_threshold,
        "needs_intervention" => state.energy <= state.critical_threshold
    )
end

"""
    export_metabolic_history - Export metabolic history for analysis
"""
function export_metabolic_history(state::MetabolicState)::Vector{Dict}
    return [
        Dict("timestamp" => string(t), "energy" => e)
        for (t, e) in state.metabolic_history
    ]
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    MetabolicState,
    CognitiveMode,
    MODE_DEATH,
    MODE_CRITICAL,
    MODE_RECOVERY,
    MODE_IDLE,
    MODE_ACTIVE,
    MODE_DREAMING,
    initialize_metabolism,
    update_metabolism!,
    boost_energy!,
    force_mode!,
    get_energy_status,
    should_enter_dreaming,
    should_trigger_planning,
    get_recommended_operations,
    apply_metabolic_constraints,
    process_metabolic_feedback!,
    get_metabolic_summary,
    export_metabolic_history,
    ENERGY_DEATH,
    ENERGY_CRITICAL,
    ENERGY_LOW,
    ENERGY_RECOVERY

# Cycle duration constant (imported from CognitiveLoop)
const CYCLE_DURATION_MS = 7.35f0

end # module
