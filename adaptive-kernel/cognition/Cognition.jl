# cognition/Cognition.jl - Main Sovereign Cognition Module
# Phase 2: Self-directing, multi-agent intelligence engine

module Cognition

using Dates
using UUIDs
using Statistics

# Export all components
export
    # Types
    CognitionTypes,
    
    # Spine
    DecisionSpine,
    DecisionCycle,
    CommittedDecision,
    SpineConfig,
    
    # Agents
    Agents,
    ExecutorAgent,
    StrategistAgent,
    AuditorAgent,
    EvolutionEngineAgent,
    
    # Memory
    WeaponizedMemory,
    DoctrineMemory,
    TacticalMemory,
    AdversaryModels,
    
    # Feedback
    PainFeedback,
    AgentPerformance,
    
    # Reality
    RealityIngestion,
    RealitySignal,
    
    # Power
    PowerMetric,
    OptionalityTracker,
    measure_power,
    
    # Main orchestration
    CognitiveEngine,
    run_sovereign_cycle

# Submodules
include("types.jl")
using .CognitionTypes

include("spine/DecisionSpine.jl")
using .DecisionSpine

include("agents/Agents.jl")
using .Agents

include("feedback/PainFeedback.jl")
using .PainFeedback

include("reality/RealityIngestion.jl")
using .RealityIngestion

# ============================================================================
# MAIN COGNITIVE ENGINE
# ============================================================================

"""
    CognitiveEngine - Main engine for sovereign cognition
"""
mutable struct CognitiveEngine
    # Configuration
    config::SpineConfig
    
    # Agents
    executor::ExecutorAgent
    strategist::StrategistAgent
    auditor::AuditorAgent
    evolution_engine::EvolutionEngineAgent
    
    # Memory
    doctrine::DoctrineMemory
    tactical::TacticalMemory
    adversary::AdversaryModels
    
    # Feedback
    executor_performance::AgentPerformance
    strategist_performance::AgentPerformance
    auditor_performance::AgentPerformance
    evolution_performance::AgentPerformance
    
    # Power tracking
    optionality::OptionalityTracker
    power_metric::PowerMetric
    
    # State
    cycle_count::Int
    last_cycle_timestamp::DateTime
    
    function CognitiveEngine(config::SpineConfig = SpineConfig())
        new(
            config,
            ExecutorAgent("executor_001"),
            StrategistAgent("strategist_001"),
            AuditorAgent("auditor_001"),
            EvolutionEngineAgent("evolution_001"),
            DoctrineMemory(),
            TacticalMemory(1000),
            AgentPerformance("executor_001", :executor),
            AgentPerformance("strategist_001", :strategist),
            AgentPerformance("auditor_001", :auditor),
            AgentPerformance("evolution_001", :evolution),
            OptionalityTracker(),
            PowerMetric(now()),
            0,
            now()
        )
    end
end

"""
    run_sovereign_cycle - Run a complete sovereign cognition cycle
"""
function run_sovereign_cycle(
    engine::CognitiveEngine,
    perception::Dict{String, Any}
)::DecisionCycle
    
    engine.cycle_count += 1
    cycle_number = engine.cycle_count
    
    # =========================================================================
    # Step 1: Ingest external reality (if available)
    # =========================================================================
    # In a real system, this would fetch actual signals
    # For now, we use the perception directly
    augmented_perception = perception
    
    # =========================================================================
    # Step 2: Run parallel agent proposals
    # =========================================================================
    proposals = AgentProposal[]
    
    # Executor proposal
    executor_prop = generate_proposal(engine.executor, augmented_perception, engine.tactical)
    executor_prop = AgentProposal(
        executor_prop.agent_id,
        executor_prop.agent_type,
        executor_prop.decision,
        executor_prop.confidence * engine.executor_performance.current_weight,
        reasoning = executor_prop.reasoning,
        weight = engine.executor_performance.current_weight,
        evidence = executor_prop.evidence
    )
    push!(proposals, executor_prop)
    
    # Strategist proposal
    strategist_prop = generate_proposal(
        engine.strategist, 
        augmented_perception, 
        engine.doctrine,
        engine.tactical,
        engine.adversary
    )
    strategist_prop = AgentProposal(
        strategist_prop.agent_id,
        strategist_prop.agent_type,
        strategist_prop.decision,
        strategist_prop.confidence * engine.strategist_performance.current_weight,
        reasoning = strategist_prop.reasoning,
        weight = engine.strategist_performance.current_weight,
        evidence = strategist_prop.evidence
    )
    push!(proposals, strategist_prop)
    
    # Auditor proposal
    auditor_prop = generate_proposal(
        engine.auditor,
        augmented_perception,
        proposals,  # Check other proposals for overconfidence
        engine.doctrine,
        engine.tactical
    )
    auditor_prop = AgentProposal(
        auditor_prop.agent_id,
        auditor_prop.agent_type,
        auditor_prop.decision,
        auditor_prop.confidence * engine.auditor_performance.current_weight,
        reasoning = auditor_prop.reasoning,
        weight = engine.auditor_performance.current_weight,
        evidence = auditor_prop.evidence
    )
    push!(proposals, auditor_prop)
    
    # Evolution proposal
    evolution_prop = generate_proposal(
        engine.evolution_engine,
        augmented_perception,
        Dict("prediction_accuracy" => 0.7),  # Would come from historical data
        engine.doctrine
    )
    evolution_prop = AgentProposal(
        evolution_prop.agent_id,
        evolution_prop.agent_type,
        evolution_prop.decision,
        evolution_prop.confidence * engine.evolution_performance.current_weight,
        reasoning = evolution_prop.reasoning,
        weight = engine.evolution_performance.current_weight,
        evidence = evolution_prop.evidence
    )
    push!(proposals, evolution_prop)
    
    # =========================================================================
    # Step 3: Conflict resolution
    # =========================================================================
    conflict = resolve_conflict(proposals, engine.config)
    
    # =========================================================================
    # Step 4: Commit decision
    # =========================================================================
    decision = CommittedDecision(conflict.winner, proposals, conflict)
    
    # =========================================================================
    # Step 5: Kernel approval (simulated - always approved)
    # =========================================================================
    decision.kernel_approved = true
    decision.kernel_approval_timestamp = now()
    
    # =========================================================================
    # Step 6: Execute and record outcome
    # =========================================================================
    outcome = DecisionOutcome(
        OUTCOME_EXECUTED,
        Dict("decision" => decision.decision, "cycle" => cycle_number),
        Dict(),
        now()
    )
    
    # Record in tactical memory
    record_outcome!(engine.tactical, Dict(
        "decision" => decision.decision,
        "agents" => [p.agent_id for p in proposals],
        "winner" => conflict.winner,
        "outcome" => "success"
    ))
    
    # =========================================================================
    # Step 7: Process feedback
    # =========================================================================
    # Update optionality based on decision
    push!(engine.optionality.viable_actions, decision.decision)
    
    # Create cycle result for feedback
    cycle_result = Dict(
        "expected_outcome" => decision.decision,
        "actual_outcome" => decision.decision,
        "agent_confidence" => mean([p.confidence for p in proposals]),
        "expected_risks" => String[],
        "actual_risks" => String[],
        "warnings_issued" => occursin("veto", auditor_prop.decision) ? 1 : 0
    )
    
    # Process feedback for each agent
    process_cycle_feedback(engine.executor_performance, cycle_result)
    process_cycle_feedback(engine.strategist_performance, cycle_result)
    process_cycle_feedback(engine.auditor_performance, cycle_result)
    process_cycle_feedback(engine.evolution_performance, cycle_result)
    
    engine.last_cycle_timestamp = now()
    
    # Return cycle (simplified - full DecisionCycle would have more fields)
    return cycle_number
end

"""
    measure_power - Calculate current power metric
"""
function measure_power(engine::CognitiveEngine)::Float64
    
    # Update power metric
    engine.power_metric.optionality_end = length(engine.optionality.viable_actions)
    engine.power_metric.optionality_gained = engine.power_metric.optionality_end - engine.power_metric.optionality_start
    
    engine.power_metric.viable_actions_end = length(engine.optionality.viable_actions)
    engine.power_metric.pivot_speed_end = engine.optionality.pivot_speed
    engine.power_metric.reversibility_end = engine.optionality.reversibility
    engine.power_metric.leverage_points_discovered = length(engine.optionality.leverage_points)
    
    return calculate_power(engine.power_metric)
end

end # module Cognition
