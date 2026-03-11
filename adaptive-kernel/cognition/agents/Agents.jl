# cognition/agents/Agents.jl - Multi-Agent Cognitive Pantheon Module
# Exports all agent implementations

module Agents

using Dates
using UUIDs

# Export all agent types and functions
export 
    # Executor
    ExecutorAgent,
    create_executor,
    generate_proposal,
    
    # Strategist
    StrategistAgent,
    create_strategist,
    
    # Auditor
    AuditorAgent,
    create_auditor,
    detect_risks,
    apply_power_modifier,
    detect_narrowing_decisions,
    calculate_power_confidence,
    update_optionality!,
    recover_optionality!
    
    # Evolution Engine
    EvolutionEngineAgent,
    create_evolution_engine,
    propose_mutation

# Submodules
include("Executor.jl")
include("Strategist.jl")
include("Auditor.jl")
include("EvolutionEngine.jl")

end # module Agents
