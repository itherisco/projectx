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
    
    # Evolution Engine
    EvolutionEngineAgent,
    create_evolution_engine,
    propose_mutation,
    
    # Policy Validator (for security invariant checking)
    PolicyValidator,
    validate_mutation,
    validate_proposed_changes,

    # Web Search Agent
    WebSearchAgent,
    create_websearch_agent,

    # Code Agent
    CodeAgent,
    create_code_agent,

    # MindMap Agent (knowledge graph for logical coherence)
    MindMapAgent,
    create_mindmap_agent,
    add_reasoning_node,
    add_reasoning_edge,
    query_knowledge_graph,
    detect_coherence_breaks,
    validate_chain_consistency,
    check_hallucination,
    get_chain_confidence,
    backtrack_to_state

# Submodules
include("Executor.jl")
include("Strategist.jl")
include("Auditor.jl")
include("EvolutionEngine.jl")
include("PolicyValidator.jl")
include("WebSearchAgent.jl")
include("CodeAgent.jl")
include("MindMapAgent.jl")

end # module Agents
