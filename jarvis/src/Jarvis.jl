# jarvis/src/Jarvis.jl - Main entry point for Project Jarvis

module Jarvis

using Dates
using UUIDs
using JSON
using Logging

# Version
const VERSION = v"1.0.0"

# Export main components
export 
    # Core
    SystemIntegrator,
    JarvisTypes,
    NLPGateway,
    
    # Submodules
    LLMBridge,
    VectorMemory,
    TaskOrchestrator,
    CommunicationBridge,
    
    # Types
    JarvisTypes.JarvisSystem,
    JarvisTypes.JarvisConfig,
    JarvisTypes.JarvisState,
    JarvisTypes.JarvisGoal,
    JarvisTypes.PerceptionVector,
    JarvisTypes.ActionProposal,
    JarvisTypes.ExecutableAction,
    JarvisTypes.TrustLevel,
    JarvisTypes.SystemStatus,
    
    # NLP Gateway exports
    NLPGateway.generate_feature_vector,
    NLPGateway.construct_goal,
    NLPGateway.FeatureVector,
    NLPGateway.GoalContext,
    NLPGateway.DoctrineConstraint,
    NLPGateway.extract_keywords,
    NLPGateway.detect_urgency,
    NLPGateway.classify_intent,
    
    # Functions
    SystemIntegrator.initialize_jarvis,
    SystemIntegrator.run_cycle,
    SystemIntegrator.process_user_request,
    SystemIntegrator.get_system_status,
    SystemIntegrator.shutdown,

    # Configuration
    JarvisTypes.LLMConfig,
    JarvisTypes.CommunicationConfig,
    JarvisTypes.OrchestratorConfig,

    # Vector Memory
    VectorMemory.VectorStore,
    VectorMemory.store!,
    VectorMemory.search,
    VectorMemory.rag_retrieve

# Import all modules
include("types.jl")
using .JarvisTypes

# NLP Gateway - must be after JarvisTypes
include("nlp/NLPGateway.jl")
using .NLPGateway

include("llm/LLMBridge.jl")
using .LLMBridge

include("memory/VectorMemory.jl")
using .VectorMemory

include("orchestration/TaskOrchestrator.jl")
using .TaskOrchestrator

include("bridge/CommunicationBridge.jl")
using .CommunicationBridge

include("SystemIntegrator.jl")
using .SystemIntegrator

# ============================================================================
# AUTO-START FUNCTION
# ============================================================================

"""
    start(config::JarvisConfig) -> JarvisSystem
    
Automatically initialize and start the Jarvis system with the given configuration.
"""
function start(config::JarvisConfig = JarvisConfig())
    return initialize_jarvis(config)
end

"""
    repl_start() -> JarvisSystem

Start Jarvis in REPL mode with default configuration.
"""
function repl_start()
    config = JarvisConfig()
    return initialize_jarvis(config)
end

# ============================================================================
# DEFAULT CONFIGURATION
# ============================================================================

function Base.show(io::IO, ::MIME"text/plain", config::JarvisConfig)
    print(io, "JarvisConfig(")
    print(io, "llm=$(config.llm.model), ")
    print(io, "trust=$(config.communication.require_confirmation_threshold), ")
    print(io, "scan_interval=$(config.proactive_scan_interval))")
end

function Base.show(io::IO, ::MIME"text/plain", system::JarvisSystem)
    status = get_system_status(system)
    print(io, "JarvisSystem(")
    print(io, "status=$(status["status"]), ")
    print(io, "cycle=$(status["current_cycle"]), ")
    print(io, "trust=$(status["trust_level"]))")
end

end # module Jarvis

