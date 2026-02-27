# cognition/types.jl - Type definitions for Sovereign Cognition system

module CognitionTypes

using Dates
using UUIDs
using Statistics

export 
    # Agent types
    CognitiveAgent,
    ExecutorAgent,
    StrategistAgent,
    AuditorAgent,
    EvolutionEngineAgent,
    ProposedChange,
    Perception,  # Typed perception for run_sovereign_cycle
    
    # Agent state
    AgentState,
    AgentMetrics,
    
    # Memory types
    DoctrineMemory,
    TacticalMemory,
    AdversaryModels,
    MemoryEntry,
    MemoryVeto,
    MemoryVetoReason,
    check_doctrine_veto,
    check_tactical_veto,
    
    # Feedback types
    PainFeedback,
    RewardSignal,
    AgentPerformance,
    
    # Reality ingestion
    RealitySignal,
    RealitySource,
    
    # Power metrics
    PowerMetric,
    OptionalityTracker

# ============================================================================
# PERCEPTION TYPE - Typed perception (replaces Dict{String, Any})
# ============================================================================

"""
    Perception - Typed perception input for cognition cycle
    Replaces Dict{String, Any} for type stability
"""
struct Perception
    system_state::Dict{String, Float32}  # cpu, memory, etc.
    threat_level::Float32
    active_goals::Vector{String}
    recent_outcomes::Vector{Bool}
    energy_level::Float32
    confidence::Float32
    
    Perception() = new(
        Dict{String, Float32}(),
        0.0f0,
        String[],
        Bool[],
        1.0f0,
        0.8f0
    )
end

# ============================================================================
# AGENT TYPES
# ============================================================================

"""
    CognitiveAgent - Base type for all cognitive agents
"""
abstract type CognitiveAgent end

"""
    ExecutorAgent - Converts approved decisions into Kernel-compliant actions
"""
struct ExecutorAgent <: CognitiveAgent
    id::String
    name::String
    capabilities::Vector{String}
    state::AgentState
    historical_accuracy::Float64
    
    ExecutorAgent(id::String = "executor_001") = new(
        id, "Executor", 
        ["execute_action", "validate_action", "monitor_execution"],
        AgentState(:idle), 0.75
    )
end

"""
    StrategistAgent - Long-horizon planning, identifies leverage and asymmetries
"""
struct StrategistAgent <: CognitiveAgent
    id::String
    name::String
    planning_horizon::Int
    state::AgentState
    historical_accuracy::Float64
    identified_leverage::Vector{String}
    
    StrategistAgent(id::String = "strategist_001") = new(
        id, "Strategist",
        10,  # 10-step planning horizon
        AgentState(:idle), 0.65,
        String[]
    )
end

"""
    AuditorAgent - Adversarial thinker, detects risks and blind spots
"""
struct AuditorAgent <: CognitiveAgent
    id::String
    name::String
    risk_threshold::Float64
    state::AgentState
    historical_accuracy::Float64
    detected_risks::Vector{String}
    veto_count::Int
    
    AuditorAgent(id::String = "auditor_001") = new(
        id, "Auditor",
        0.5,  # 50% risk threshold triggers veto
        AgentState(:idle), 0.70,
        String[], 0
    )
end

"""
    ProposedChange - Typed change proposal for evolution engine (replaces Dict{String, Any})
"""
struct ProposedChange
    id::UUID
    change_type::String  # "prompt", "heuristic", "scoring"
    target::String       # Which component to modify
    description::String
    expected_impact::Float32
    proposed_at::DateTime
    
    ProposedChange(change_type::String, target::String, description::String, impact::Float32) = 
        new(uuid4(), change_type, target, description, impact, now())
end

"""
    EvolutionEngineAgent - Mutates prompts, heuristics, scoring functions
"""
struct EvolutionEngineAgent <: CognitiveAgent
    id::String
    name::String
    mutation_rate::Float64
    state::AgentState
    proposed_changes::Vector{ProposedChange}  # Typed instead of Dict{String, Any}
    accepted_changes::Int
    
    EvolutionEngineAgent(id::String = "evolution_001") = new(
        id, "EvolutionEngine",
        0.1,  # 10% mutation rate
        AgentState(:idle),
        ProposedChange[], 0
    )
end

# ============================================================================
# AGENT STATE & METRICS
# ============================================================================

@enum AgentStatus begin
    AGENT_IDLE
    AGENT_THINKING
    AGENT_PROPOSING
    AGENT_WAITING
    AGENT_ERROR
end

"""
    AgentState - Runtime state of an agent
"""
mutable struct AgentState
    status::AgentStatus
    current_task::Union{String, Nothing}
    processing_since::Union{DateTime, Nothing}
    error_message::Union{String, Nothing}
    
    AgentState(status::AgentStatus = AGENT_IDLE) = new(status, nothing, nothing, nothing)
end

"""
    AgentMetrics - Performance metrics for an agent
"""
mutable struct AgentMetrics
    agent_id::String
    total_cycles::Int
    successful_predictions::Int
    failed_predictions::Int
    warnings_issued::Int
    warnings_heeded::Int
    overconfidence_score::Float64      # [0, 1] - how often agent is overconfident
    prediction_error_history::Vector{Float64}
    risk_detections::Int
    missed_risks::Int
    
    function AgentMetrics(agent_id::String)
        new(agent_id, 0, 0, 0, 0, 0, 0.0, Float64[], 0, 0)
    end
end

function update_accuracy!(metrics::AgentMetrics, prediction_correct::Bool)
    metrics.total_cycles += 1
    if prediction_correct
        metrics.successful_predictions += 1
    else
        metrics.failed_predictions += 1
    end
end

function get_accuracy(metrics::AgentMetrics)::Float64
    return metrics.total_cycles > 0 ? 
        metrics.successful_predictions / metrics.total_cycles : 0.0
end

# ============================================================================
# MEMORY TYPES - THREE TIERS
# ============================================================================

"""
    MemoryEntry - Base memory entry
"""
struct MemoryEntry
    id::UUID
    content::String
    importance::Float64          # [0, 1]
    timestamp::DateTime
    source_agent::String
    verified::Bool
    tags::Vector{String}
end

"""
    DoctrineMemory - Core laws, principles, invariants (Tier 1)
    Updated rarely, requires Auditor + Strategist agreement
"""
struct DoctrineMemory
    entries::Vector{MemoryEntry}
    invariants::Vector{String}              # Inviolable rules
    core_principles::Vector{String}         # Core operating principles
    last_update::DateTime
    update_count::Int
    
    DoctrineMemory() = new(
        MemoryEntry[],
        String[],
        String[],
        now(),
        0
    )
end

function add_doctrine_entry!(
    doctrine::DoctrineMemory, 
    entry::MemoryEntry,
    auditor_approved::Bool,
    strategist_approved::Bool
)
    # Requires both Auditor and Strategist agreement
    if auditor_approved && strategist_approved
        push!(doctrine.entries, entry)
        doctrine.last_update = now()
        doctrine.update_count += 1
    end
end

"""
    TacticalMemory - Short-to-mid term patterns, outcomes, failures (Tier 2)
    Aggressively pruned
"""
struct TacticalMemory
    entries::Vector{MemoryEntry}
    recent_outcomes::Vector{Dict{String, Any}}  # Recent decision outcomes
    failure_patterns::Vector{String}
    max_entries::Int
    pruning_threshold::Int
    
    TacticalMemory(max_entries::Int = 1000) = new(
        MemoryEntry[],
        Dict{String, Any}[],
        String[],
        max_entries,
        Int(floor(max_entries * 0.8))  # Prune at 80%
    )
end

function add_tactical_entry!(tactical::TacticalMemory, entry::MemoryEntry)
    push!(tactical.entries, entry)
    
    # Aggressive pruning if over threshold
    if length(tactical.entries) > tactical.pruning_threshold
        # Remove oldest entries
        sort!(tactical.entries, by=e => e.timestamp)
        tactical.entries = tactical.entries[end-tactical.pruning_threshold+1:end]
    end
end

function record_outcome!(tactical::TacticalMemory, outcome::Dict{String, Any})
    push!(tactical.recent_outcomes, outcome)
    # Keep only last 100 outcomes
    if length(tactical.recent_outcomes) > 100
        tactical.recent_outcomes = tactical.recent_outcomes[end-99:end]
    end
end

"""
    AdversaryModels - Models of markets, competitors, user archetypes, past self (Tier 3)
    Continuously updated
"""
struct AdversaryModels
    models::Dict{String, Dict{String, Any}}  # model_name => model_data
    update_frequency::Int  # Cycles between full updates
    
    AdversaryModels() = new(Dict{String, Dict{String, Any}}(), 10)
end

function update_adversary_model!(
    models::AdversaryModels,
    model_name::String,
    new_data::Dict{String, Any}
)
    if haskey(models.models, model_name)
        # Merge new data with existing
        merge!(models.models[model_name], new_data)
    else
        models.models[model_name] = new_data
    end
end

# ============================================================================
# MEMORY RESISTANCE - VETO HOOKS (Phase 3)
# ============================================================================

@enum MemoryVetoReason begin
    VETO_INVARIANT_VIOLATION      # Violates doctrine invariant
    VETO_FAILURE_PATTERN_MATCH     # Similar to past failure
    VETO_KERNEL_OVERRIDE          # Kernel explicitly overriding
end

"""
    MemoryVeto - Veto from institutional memory
"""
struct MemoryVeto
    reason::MemoryVetoReason
    description::String
    blocked_action::String
    similar_failures::Vector{String}  # IDs of similar failed actions
    requires_kernel_override::Bool
    timestamp::DateTime
end

function MemoryVeto(
    reason::MemoryVetoReason,
    description::String,
    blocked_action::String
)::MemoryVeto
    return MemoryVeto(
        reason,
        description,
        blocked_action,
        String[],
        reason != VETO_KERNEL_OVERRIDE,  # Most vetos require kernel override
        now()
    )
end

"""
    check_doctrine_veto - Check if action violates doctrine invariants
    Returns nothing if no veto, MemoryVeto if blocked
"""
function check_doctrine_veto(
    doctrine::DoctrineMemory,
    action::String,
    context::Dict{String, Any}
)::Union{MemoryVeto, Nothing}
    
    # Check each invariant
    for invariant in doctrine.invariants
        if violates_invariant(action, context, invariant)
            return MemoryVeto(
                VETO_INVARIANT_VIOLATION,
                "Action violates doctrine invariant: $invariant",
                action
            )
        end
    end
    
    return nothing
end

"""
    violates_invariant - Check if action violates an invariant
"""
function violates_invariant(
    action::String,
    context::Dict{String, Any},
    invariant::String
)::Bool
    # Simplified check - in production would parse invariant
    # For now, check if action contains forbidden terms
    forbidden = ["delete_all", "drop_database", "rm -rf"]
    return any(f -> occursin(f, action), forbidden)
end

"""
    check_tactical_veto - Check if action matches past failure patterns
    Returns nothing if no veto, MemoryVeto if blocked
"""
function check_tactical_veto(
    tactical::TacticalMemory,
    action::String,
    context::Dict{String, Any}
)::Union{MemoryVeto, Nothing}
    
    # Check against failure patterns
    similar_failures = String[]
    
    for outcome in tactical.recent_outcomes
        if get(outcome, "result", false) == false  # Failed outcome
            failed_action = get(outcome, "decision", "")
            if is_similar_action(action, failed_action)
                push!(similar_failures, get(outcome, "decision", "unknown"))
            end
        end
    end
    
    # If too many similar failures, veto
    if length(similar_failures) >= 3
        return MemoryVeto(
            VETO_FAILURE_PATTERN_MATCH,
            "Action matches $(length(similar_failures)) past failures",
            action
        )
    end
    
    return nothing
end

"""
    is_similar_action - Check if two actions are similar
"""
function is_similar_action(action1::String, action2::String)::Bool
    # Simple similarity check - same action type
    type1 = split(action1, ":")[1]
    type2 = split(action2, ":")[1]
    return type1 == type2
end

"""
    record_doctrine_veto_log - Log a doctrine veto for audit
"""
function record_doctrine_veto_log(
    doctrine::DoctrineMemory,
    veto::MemoryVeto
)
    # In production, would write to immutable audit log
end

"""
    record_tactical_veto_log - Log a tactical veto for audit
"""
function record_tactical_veto_log(
    tactical::TacticalMemory,
    veto::MemoryVeto
)
    # In production, would write to immutable audit log
end

# ============================================================================
# PAIN-DRIVEN FEEDBACK TYPES
# ============================================================================

"""
    PainFeedback - Numerical pain signal for agent performance tracking
"""
struct PainFeedback
    agent_id::String
    cycle_id::UUID
    pain_type::Symbol              # :overconfidence, :prediction_error, :missed_risk
    pain_value::Float64            # [0, 1] - numerical pain
    context::Dict{String, Any}
    timestamp::DateTime
end

"""
    RewardSignal - Numerical reward for agent performance
"""
struct RewardSignal
    agent_id::String
    cycle_id::UUID
    reward_type::Symbol            # :warning_issued, :accurate_prediction, :risk_detected
    reward_value::Float64          # [0, 1] - numerical reward
    context::Dict{String, Any}
    timestamp::DateTime
end

# ============================================================================
# EXTERNAL REALITY INGESTION
# ============================================================================

@enum RealitySourceType begin
    SOURCE_MARKET       # Market signals
    SOURCE_USER        # User behavior
    SOURCE_SYSTEM      # System failures
    SOURCE_ADVERSARIAL # Adversarial inputs
    SOURCE_SIMULATED   # Simulated hostile environment
end

"""
    RealitySignal - Signal from external reality
"""
struct RealitySignal
    id::UUID
    source::RealitySourceType
    content::Dict{String, Any}
    timestamp::DateTime
    contradictions::Vector{String}  # What assumptions this contradicts
    signal_strength::Float64         # [0, 1] - how significant
end

# ============================================================================
# POWER METRIC
# ============================================================================

"""
    OptionalityTracker - Tracks optionality over time
"""
mutable struct OptionalityTracker
    viable_actions::Vector{String}      # Count of viable future actions
    pivot_speed::Float64                # Speed of pivot (0 = cannot pivot, 1 = instant)
    reversibility::Float64              # Reversibility of decisions (0 = irreversible, 1 = fully reversible)
    leverage_points::Vector{String}     # Discovered leverage points
    
    function OptionalityTracker()
        new(String[], 0.5, 0.5, String[])
    end
end

"""
    PowerMetric - Weekly power measurement
    Power = Optionality Gained Over Time
"""
mutable struct PowerMetric
    week_start::DateTime
    optionality_start::Float64
    optionality_end::Float64
    optionality_gained::Float64
    
    # Components
    viable_actions_start::Int
    viable_actions_end::Int
    pivot_speed_start::Float64
    pivot_speed_end::Float64
    reversibility_start::Float64
    reversibility_end::Float64
    leverage_points_discovered::Int
    
    # Growth rate
    power_gain_rate::Float64  # Percentage growth per week
    
    function PowerMetric(week_start::DateTime)
        new(week_start, 0.0, 0.0, 0.0, 0, 0, 0.5, 0.5, 0.5, 0.5, 0, 0.0)
    end
end

function calculate_power(metric::PowerMetric)::Float64
    # Power = optionality_gained + component improvements
    return metric.optionality_gained + 
           0.1 * (metric.viable_actions_end - metric.viable_actions_start) +
           0.2 * (metric.pivot_speed_end - metric.pivot_speed_start) +
           0.2 * (metric.reversibility_end - metric.reversibility_start) +
           0.5 * metric.leverage_points_discovered
end

end # module CognitionTypes
