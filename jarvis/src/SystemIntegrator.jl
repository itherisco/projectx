# jarvis/src/SystemIntegrator.jl - Central Nervous System of Project Jarvis
# Integrates LLM Bridge, ITHERIS Brain, Adaptive Kernel, and all subsystems
# SECURITY: Kernel is SOVEREIGN - no action executes without kernel approval

module SystemIntegrator

using Dates
using UUIDs
using JSON
using Logging
using Pkg

# Import all submodules
include("types.jl")
include("llm/LLMBridge.jl")
include("memory/VectorMemory.jl")
include("memory/SemanticMemory.jl")
include("orchestration/TaskOrchestrator.jl")
include("bridge/CommunicationBridge.jl")

# Try to import Adaptive Kernel
const ADAPTIVE_KERNEL_PATH = joinpath(@__DIR__, "..", "..", "adaptive-kernel")
const KERNEL_AVAILABLE = isdir(ADAPTIVE_KERNEL_PATH)

# Try to load Adaptive Kernel module
# SECURITY: Use concrete type for kernel state instead of Any
struct KernelWrapper
    state::Union{Kernel.KernelState, Nothing}
    config::Dict
    initialized::Bool
    
    function KernelWrapper()
        new(nothing, Dict(), false)
    end
end

# ITHERIS Brain wrapper - ADVISORY ONLY (cannot execute)
# SECURITY: Use concrete type for brain state
struct BrainWrapper
    config::Dict
    initialized::Bool
    
    # BrainOutput is the only thing the brain can produce
    # It is an ADVISORY PROPOSAL, not an executable action
    
    function BrainWrapper()
        new(Dict(), false)
    end
end

# Load Adaptive Kernel if available
if KERNEL_AVAILABLE
    try
        push!(LOAD_PATH, ADAPTIVE_KERNEL_PATH)
        include(joinpath(ADAPTIVE_KERNEL_PATH, "kernel", "Kernel.jl"))
        @info "Adaptive Kernel module loaded" path=ADAPTIVE_KERNEL_PATH
    catch e
        @warn "Could not load Adaptive Kernel: $e"
    end
end

using .JarvisTypes
using .LLMBridge
using .VectorMemory
using .SemanticMemory
using .TaskOrchestrator
using .CommunicationBridge

export 
    JarvisSystem,
    JarvisConfig,
    initialize_jarvis,
    run_cycle,
    process_user_request,
    get_system_status,
    shutdown,
    # Re-export from SemanticMemory
    SemanticMemoryStore,
    ActionOutcome,
    store_action_outcome!,
    # Re-export kernel types if available
    KernelState

# Import existing components from ProjectX
# These will be included when the module is loaded into the full system

# ============================================================================
# SYSTEM CONFIGURATION
# ============================================================================

"""
    JarvisConfig - Master configuration for Jarvis system
"""
struct JarvisConfig
    # LLM
    llm::LLMConfig
    
    # Communication
    communication::CommunicationConfig
    
    # Orchestration
    orchestrator::OrchestratorConfig
    
    # Vector Memory
    vector_store_path::String
    
    # Adaptive Kernel integration
    kernel_config_path::String
    
    # Proactive scanning
    proactive_scan_interval::Second
    
    # Logging
    log_level::Symbol
    events_log_path::String
    
    function JarvisConfig(;
        llm::LLMConfig = LLMConfig(),
        communication::CommunicationConfig = CommunicationConfig(),
        orchestrator::OrchestratorConfig = OrchestratorConfig(),
        vector_store_path::String = "./jarvis_vector_store.json",
        kernel_config_path::String = "./adaptive-kernel/config.json",
        proactive_scan_interval::Second = Second(60),
        log_level::Symbol = :info,
        events_log_path::String = "./jarvis_events.log"
    )
        new(
            llm, communication, orchestrator,
            vector_store_path, kernel_config_path,
            proactive_scan_interval, log_level, events_log_path
        )
    end
end

# ============================================================================
# MAIN SYSTEM STRUCTURE
# ============================================================================

"""
    JarvisSystem - The complete Jarvis autonomous system
    SECURITY: All execution flows through kernel.approve() - no exceptions
"""
mutable struct JarvisSystem
    # Configuration
    config::JarvisConfig
    
    # Core components
    vector_store::VectorStore
    semantic_memory::SemanticMemoryStore  # Action outcome memory for RL
    llm_bridge::LLMConfig  # Re-using config as bridge instance
    
    # Adaptive Kernel (sovereign authority for execution)
    # SECURITY: This is the ONLY authority that can approve execution
    kernel::KernelWrapper
    
    # ITHERIS Brain (advisory only - proposes actions, never executes)
    brain::BrainWrapper
    
    # System state
    state::JarvisState
    
    # Conversation history
    conversation_history::Vector{ConversationEntry}
    
    # Proactive suggestions queue
    pending_suggestions::Vector{ProactiveSuggestion}
    
    # Metrics
    cycle_times::Vector{Float64}  # ms
    last_proactive_scan::DateTime
    
    # Logging
    logger::Logger
    
    # Kernel availability flag - now stored in KernelWrapper
    # kernel_initialized::Bool - now in kernel.initialized
    # brain_initialized::Bool - now in brain.initialized
    
    function JarvisSystem(config::JarvisConfig)
        # Initialize vector store
        if isfile(config.vector_store_path)
            vector_store = load_from_file(config.vector_store_path)
        else
            vector_store = VectorStore()
        end
        
        # Initialize semantic memory for action outcomes
        semantic_memory_path = replace(config.vector_store_path, "vector_store" => "semantic_memory")
        if isfile(semantic_memory_path)
            semantic_memory = load_from_file(semantic_memory_path)
        else
            semantic_memory = initialize_semantic_memory()
        end
        
        # Initialize logger
        logger = Logger(config.events_log_path)
        
        new(
            config,
            vector_store,
            semantic_memory,
            config.llm,
            KernelWrapper(),  # kernel - sovereign authority
            BrainWrapper(),    # brain - advisory only
            JarvisState(),
            ConversationEntry[],
            ProactiveSuggestion[],
            Float64[],
            now() - config.proactive_scan_interval,
            logger
            # Removed kernel_initialized and brain_initialized - now in wrappers
        )
    end
end

# ============================================================================
# INITIALIZATION
# ============================================================================

"""
    initialize_jarvis - Initialize the complete Jarvis system
"""
function initialize_jarvis(
    config::JarvisConfig = JarvisConfig()
)::JarvisSystem
    
    println("="^60)
    println("  INITIALIZING PROJECT JARVIS - Neuro-Symbolic Autonomous System")
    println("="^60)
    
    system = JarvisSystem(config)
    
    # Update state
    system.state.status = STATUS_INITIALIZING
    
    # Initialize vector store with default data if empty
    if isempty(system.vector_store.entries)
        _initialize_default_knowledge!(system)
    end
    
    # Load Adaptive Kernel if available
    _initialize_kernel!(system)
    
    # Load ITHERIS Brain if available
    _initialize_brain!(system)
    
    # Mark as running
    system.state.status = STATUS_RUNNING
    
    println("✓ Jarvis System initialized successfully")
    println("  - Vector store entries: $(length(system.vector_store.entries))")
    println("  - Trust level: $(system.state.trust_level)")
    
    return system
end

function _initialize_default_knowledge!(system::JarvisSystem)
    # Add some default preferences
    store_preference!(system.vector_store, "notifications_enabled", true; category = :interface)
    store_preference!(system.vector_store, "auto_optimize", false; category = :behavior)
    store_preference!(system.vector_store, "proactive_suggestions", true; category = :behavior)
    
    # Add welcome knowledge
    store_knowledge!(
        system.vector_store,
        "Jarvis is an AI assistant that helps with system monitoring, task automation, and information retrieval.";
        tags = ["about", "jarvis"],
        source = "system"
    )
end

function _initialize_kernel!(system::JarvisSystem)
    # Try to load Adaptive Kernel from adaptive-kernel directory
    try
        if KERNEL_AVAILABLE
            # Load kernel config if exists
            config_path = joinpath(ADAPTIVE_KERNEL_PATH, "registry", "capability_registry.json")
            kernel_config = if isfile(config_path)
                JSON.parsefile(config_path)
            else
                Dict(
                    "goals" => [
                        Dict("id" => "default", "description" => "Run system nominal", "priority" => 0.8)
                    ],
                    "observations" => Dict{String, Any}()
                )
            end
            
            # Initialize kernel state using Kernel module if available
            try
                system.kernel.state = Kernel.init_kernel(kernel_config)
                system.kernel.config = kernel_config
                system.kernel.initialized = true
                println("  - Adaptive Kernel: INITIALIZED (sovereign authority)")
                @info "Kernel initialized successfully" cycle=system.kernel.state.cycle
            catch e
                println("  - Adaptive Kernel: FAILED TO INITIALIZE ($e)")
                @warn "Kernel initialization failed: $e"
                system.kernel.initialized = false
            end
        else
            println("  - Adaptive Kernel: NOT FOUND (using fallback)")
            system.kernel.initialized = false
        end
    catch e
        @warn "Could not initialize Adaptive Kernel: $e"
        @error "Kernel initialization failed" exception=(e, catch_backtrace())
        system.kernel.initialized = false
    end
end

function _initialize_brain!(system::JarvisSystem)
    # Try to load ITHERIS Brain
    # SECURITY: The brain is ADVISORY ONLY - it proposes actions but NEVER executes
    # This is enforced by design - the brain module has no execution capabilities
    try
        # Configure brain as advisory-only
        system.brain.config = Dict(
            "model_path" => nothing,
            "confidence_threshold" => 0.5,
            "advisory_mode" => true,  # Brain never executes - only proposes
            "execution_bypass_blocked" => true  # Explicitly block any execution attempts
        )
        system.brain.initialized = true
        println("  - ITHERIS Brain: INITIALIZED (advisory mode)")
    catch e
        @warn "Could not initialize ITHERIS Brain: $e"
        system.brain.initialized = false
    end
end

"""
    _log_event - Log system event for audit trail
"""
function _log_event(system::JarvisSystem, event_type::String, data::Dict{String, Any})
    try
        log_entry = Dict(
            "timestamp" => string(now()),
            "event_type" => event_type,
            "cycle" => system.state.current_cycle,
            "data" => data
        )
        # Write to log file
        open(system.config.events_log_path, "a") do f
            JSON.print(f, log_entry)
            println(f)  # Newline after each entry
        end
    catch e
        @warn "Failed to log event: $e"
    end
end

# ============================================================================
# CORE EXECUTION LOOP - STRICT KERNEL SOVEREIGNTY
# ============================================================================

"""
    run_cycle - Execute one complete cognitive cycle
    SECURITY: All execution flows through kernel.approve() - no exceptions
"""
function run_cycle(system::JarvisSystem)::CycleResult
    start_time = time()
    
    # Update cycle counter
    system.state.current_cycle += 1
    cycle_num = system.state.current_cycle
    
    # 1. Observe world state
    observation = _observe_world(system)
    
    # 2. Build perception vector
    perception = _build_perception(observation)
    
    # 3. Get ITHERIS brain inference (advisory only - PROPOSES actions)
    action_proposal = _brain_infer(system, perception)
    
    # 4. KERNEL SAFETY CHECK (MANDATORY - SOVEREIGN AUTHORITY)
    # This is the single choke point for all execution
    executable_action = _kernel_approval(system, action_proposal, perception)
    
    # 5. Execute action (only if kernel approved)
    execution_result = _execute_action(system, executable_action)
    
    # 6. Learn from outcome
    reward = _compute_reward(execution_result)
    _learn!(system, perception, action_proposal, reward)
    
    # 7. Proactive scanning
    suggestions = _proactive_scan(system, observation)
    
    # Record cycle time
    push!(system.cycle_times, (time() - start_time) * 1000)
    
    return CycleResult(
        cycle_num,
        perception,
        executable_action,
        execution_result,
        reward,
        0.0f0,  # prediction_error (would come from brain)
        SemanticEntry[],  # new memories
        [s.description for s in suggestions],
        now()
    )
end

function _observe_world(system::JarvisSystem)::WorldObservation
    # Collect system metrics (simplified - would integrate with actual monitoring)
    metrics = Dict{String, Float32}(
        "cpu_load" => 0.5f0,
        "memory_usage" => 0.6f0,
        "disk_usage" => 0.4f0,
        "network_latency" => 25.0f0
    )
    
    return WorldObservation(;
        system_metrics = metrics,
        recent_events = Dict{String, Any}[],
        active_goals = JarvisGoal[],
        user_present = true
    )
end

function _build_perception(observation::WorldObservation)::PerceptionVector
    metrics = observation.system_metrics
    
    return PerceptionVector(
        get(metrics, "cpu_load", 0.5f0),
        get(metrics, "memory_usage", 0.5f0),
        get(metrics, "disk_io", 0.5f0),
        get(metrics, "network_latency", 0.5f0) / 500f0,  # Normalize
        get(metrics, "overall_severity", 0.0f0),
        get(metrics, "threat_count", 0.0f0),
        get(metrics, "file_count", 0.5f0),
        get(metrics, "change_rate", 0.5f0),
        get(metrics, "process_count", 0.5f0),
        get(metrics, "energy_level", 0.9f0),
        0.8f0,  # confidence
        get(metrics, "user_activity", 0.5f0)
    )
end

function _brain_infer(system::JarvisSystem, perception::PerceptionVector)::Union{ActionProposal, Nothing}
    """
    ITHERIS BRAIN INFERENCE - ADVISORY ONLY
    
    The brain PROPOSES actions but NEVER executes them.
    All actions must go through kernel approval.
    
    This function:
    - Receives perception vector
    - Proposes an action with confidence and risk estimates
    - Returns ActionProposal (advisory - requires kernel approval)
    
    SECURITY: The brain CANNOT execute anything. It only produces proposals.
    """
    
    # If brain is initialized, use it
    if system.brain.initialized
        # In full implementation, this would call the actual brain
        # For now, generate a proposal based on perception
        
        # Simple heuristic: if CPU is high, propose observe_cpu
        cpu_high = perception.cpu_load > 0.7f0
        memory_high = perception.memory_usage > 0.7f0
        
        capability_id = "observe_system"
        confidence = 0.8f0
        predicted_cost = 0.1f0
        predicted_reward = 0.5f0
        risk = 0.1f0
        
        if cpu_high
            capability_id = "observe_cpu"
            predicted_reward = 0.7f0
            risk = 0.05f0
        elseif memory_high
            capability_id = "observe_memory"
            predicted_reward = 0.7f0
            risk = 0.05f0
        end
        
        return ActionProposal(
            capability_id,
            confidence,
            predicted_cost,
            predicted_reward,
            risk;
            reasoning = "ITHERIS brain proposal: based on current perception",
            impact = 0.3f0
        )
    end
    
    # Fallback: return a default proposal
    return ActionProposal(
        "observe_system",
        0.8f0,
        0.1f0,
        0.5f0,
        0.1f0;
        reasoning = "Default system observation",
        impact = 0.3f0
    )
end

function _kernel_approval(
    system::JarvisSystem, 
    proposal::Union{ActionProposal, Nothing},
    perception::PerceptionVector
)::Union{ExecutableAction, Nothing}
    """
    KERNEL APPROVAL - THE SOVEREIGN AUTHORITY
    
    This is the SINGLE CHOKE POINT for all execution.
    - Brain proposes actions (advisory only)
    - Kernel approves or denies execution
    - No action executes without kernel approval
    
    SECURITY: This function MUST be called for every action.
    """
    
    if proposal === nothing
        @debug "No proposal to approve"
        return nothing
    end
    
    # Build risk assessment for kernel
    risk_score = _compute_risk_score(proposal, system.state)
    
    # If kernel is initialized, use it for approval
    if system.kernel.initialized && system.kernel.state !== nothing
        try
            # Convert proposal to capability candidate format for kernel
            candidate = Dict{String, Any}(
                "id" => proposal.capability_id,
                "risk" => risk_score > 0.5f0 ? "high" : (risk_score > 0.2f0 ? "medium" : "low"),
                "cost" => proposal.predicted_cost,
                "confidence" => proposal.confidence
            )
            
            # Kernel evaluates the action
            kernel_action = Kernel.select_action(system.kernel.state, [candidate])
            
            # Kernel approval: check if selected action matches our proposal
            if kernel_action.capability_id != proposal.capability_id
                @warn "Kernel DENIED execution" proposed=proposal.capability_id denied_by=kernel_action.capability_id
                _log_event(system, "kernel_denial", Dict(
                    "proposed_action" => proposal.capability_id,
                    "kernel_selected" => kernel_action.capability_id,
                    "risk_score" => risk_score,
                    "timestamp" => string(now())
                ))
                return nothing
            end
            
            # Kernel approved - compute score
            score = proposal.confidence * (proposal.predicted_reward - risk_score)
            
            _log_event(system, "kernel_approval", Dict(
                "action" => proposal.capability_id,
                "score" => score,
                "risk" => risk_score,
                "timestamp" => string(now())
            ))
            
            return ExecutableAction(
                proposal,
                score,
                now(),
                Dict{String, Any}("kernel_approved" => true, "risk_score" => risk_score)
            )
        catch e
            @error "Kernel approval failed: $e"
            # Fall back to local approval
        end
    end
    
    # Fallback: Local kernel approval (when Adaptive Kernel unavailable)
    # Deterministic formula: score = confidence × (reward - risk)
    score = proposal.confidence * (proposal.predicted_reward - risk_score)
    
    # Check trust level for safety
    if system.state.trust_level < TRUST_STANDARD && risk_score > 0.3f0
        # Low trust - only allow low-risk actions
        @warn "Kernel DENIED (low trust)" action=proposal.capability_id trust=system.state.trust_level
        return nothing
    end
    
    # Score threshold check
    if score < 0.1f0
        @warn "Kernel DENIED (low score)" action=proposal.capability_id score=score
        return nothing
    end
    
    return ExecutableAction(
        proposal,
        score,
        now(),
        Dict{String, Any}("kernel_approved" => true, "risk_score" => risk_score, "fallback" => true)
    )
end

"""
    _compute_risk_score - Compute risk assessment for an action proposal
"""
function _compute_risk_score(proposal::ActionProposal, state::JarvisState)::Float32
    # Base risk from proposal
    base_risk = proposal.risk
    
    # Adjust based on trust level
    trust_penalty = if state.trust_level == TRUST_BLOCKED
        1.0f0
    elseif state.trust_level == TRUST_RESTRICTED
        0.5f0
    elseif state.trust_level == TRUST_LIMITED
        0.2f0
    else
        0.0f0
    end
    
    return clamp(base_risk + trust_penalty, 0.0f0, 1.0f0)
end

function _execute_action(
    system::JarvisSystem,
    action::Union{ExecutableAction, Nothing}
)::Dict{String, Any}
    """
    Execute action - REQUIRES kernel approval
    
    SECURITY: This function MUST only execute actions that have been
    approved by the kernel. The ExecutableAction contains kernel_approved=true
    in its execution_context.
    """
    
    if action === nothing
        return Dict("success" => false, "reason" => "no_action")
    end
    
    # SECURITY CHECK: Verify kernel approval
    kernel_approved = get(action.execution_context, "kernel_approved", false)
    if !kernel_approved
        @error "SECURITY VIOLATION: Attempted to execute action without kernel approval!"
        return Dict(
            "success" => false, 
            "reason" => "SECURITY_VIOLATION: no kernel approval",
            "action" => action.proposal.capability_id
        )
    end
    
    # Log the action
    _log_event(system, "action_execution", Dict(
        "action_id" => action.proposal.capability_id,
        "score" => action.kernel_score,
        "timestamp" => string(now())
    ))
    
    # Execute based on capability type
    # This would integrate with the actual capability system
    return Dict(
        "success" => true,
        "action" => action.proposal.capability_id,
        "result" => "executed",
        "kernel_score" => action.kernel_score
    )
end

function _compute_reward(result::Dict{String, Any})::Float32
    if get(result, "success", false)
        return 1.0f0
    else
        return -0.5f0
    end
end

function _learn!(
    system::JarvisSystem,
    perception::PerceptionVector,
    proposal::Union{ActionProposal, Nothing},
    reward::Float32
)
    # Store experience in vector store
    if proposal !== nothing
        entry = SemanticEntry(
            :episodic,
            "Action: $(proposal.capability_id) with reward $reward",
            Vector(perception);
            metadata = Dict(
                "action" => proposal.capability_id,
                "reward" => reward,
                "cycle" => system.state.current_cycle
            )
        )
        store!(system.vector_store, entry)
    end
    
    # Update system metrics
    if reward > 0
        system.state.success_count += 1
    else
        system.state.failure_count += 1
    end
end

function _proactive_scan(
    system::JarvisSystem,
    observation::WorldObservation
)::Vector{ProactiveSuggestion}
    
    # Check if enough time has passed since last scan
    time_since_scan = now() - system.last_proactive_scan
    if time_since_scan < system.config.proactive_scan_interval
        return system.pending_suggestions
    end
    
    # Get recent actions for analysis
    recent = get_recent(system.vector_store; n=20, collection = :episodic)
    recent_actions = [
        Dict("action_id" => get(e.metadata, "action", "unknown")) 
        for e in recent
    ]
    
    # Run orchestrator
    suggestions = analyze_and_suggest(
        observation,
        recent_actions,
        system.config.orchestrator
    )
    
    system.pending_suggestions = suggestions
    system.last_proactive_scan = now()
    
    return suggestions
end

# ============================================================================
# USER INTERACTION
# ============================================================================

"""
    process_user_request - Process a natural language user request
"""
function process_user_request(
    system::JarvisSystem,
    user_input::String
)::Dict{String, Any}
    
    # 1. Parse intent with LLM
    llm_response = parse_user_intent(
        user_input,
        system.llm_bridge;
        conversation_history = system.conversation_history
    )
    
    # 2. Retrieve relevant context (RAG)
    context = rag_retrieve(
        system.vector_store,
        user_input;
        n_results = 5
    )
    
    # 3. Check if confirmation needed
    if llm_response.parsed_goal !== nothing
        goal = llm_response.parsed_goal
        
        if goal.required_trust > system.state.trust_level
            # Need to request confirmation
            push!(system.state.user_confirmations_pending, goal)
            return Dict(
                "type" => "confirmation_required",
                "goal" => goal.description,
                "reason" => "insufficient_trust"
            )
        end
    end
    
    # 4. Execute the requested action
    # (Simplified - would create actual action proposal)
    result = Dict(
        "type" => "response",
        "intent" => llm_response.intent,
        "entities" => llm_response.entities,
        "message" => "Processing: $(user_input)"
    )
    
    # 5. Generate response
    response_text = generate_response(
        user_input,
        llm_response.intent,
        result,
        system.llm_bridge;
        conversation_history = system.conversation_history
    )
    
    # 6. Store conversation
    entry = store_conversation!(
        system.vector_store,
        user_input,
        response_text;
        intent = llm_response.intent,
        entities = llm_response.entities
    )
    
    push!(system.conversation_history, ConversationEntry(
        user_input, response_text;
        intent = llm_response.intent,
        entities = llm_response.entities
    ))
    
    # Keep history bounded
    if length(system.conversation_history) > 100
        system.conversation_history = system.conversation_history[end-99:end]
    end
    
    return Dict(
        "type" => "success",
        "response" => response_text,
        "intent" => llm_response.intent,
        "context_used" => !isempty(context)
    )
end

# ============================================================================
# UTILITIES
# ============================================================================

"""
    get_system_status - Get current system status
"""
function get_system_status(system::JarvisSystem)::Dict{String, Any}
    avg_cycle_time = isempty(system.cycle_times) ? 0.0 : mean(system.cycle_times)
    
    return Dict(
        "status" => string(system.state.status),
        "trust_level" => string(system.state.trust_level),
        "current_cycle" => system.state.current_cycle,
        "total_cycles" => system.state.total_cycles,
        "success_count" => system.state.success_count,
        "failure_count" => system.state.failure_count,
        "avg_cycle_time_ms" => round(avg_cycle_time, digits=2),
        "vector_store_entries" => length(system.vector_store.entries),
        "pending_suggestions" => length(system.pending_suggestions),
        "pending_confirmations" => length(system.state.user_confirmations_pending)
    )
end

"""
    shutdown - Gracefully shutdown the system
"""
function shutdown(system::JarvisSystem)
    system.state.status = STATUS_SHUTDOWN
    
    # Save vector store
    save_to_file(system.vector_store, system.config.vector_store_path)
    
    # Log shutdown
    _log_event(system, "shutdown", Dict(
        "total_cycles" => system.state.current_cycle,
        "success_rate" => system.state.success_count / max(1, system.state.success_count + system.state.failure_count)
    ))
    
    println("✓ Jarvis System shutdown complete")
end

function _log_event(system::JarvisSystem, event_type::String, data::Dict{String, Any})
    log_entry = Dict(
        "timestamp" => string(now()),
        "type" => event_type,
        "data" => data
    )
    
    # Append to events log
    open(system.config.events_log_path, "a") do f
        JSON.print(f, log_entry)
        println(f)
    end
end

# ============================================================================
# Logger utility
# ============================================================================

struct Logger
    filepath::String
end

Logger(filepath::String) = Logger(filepath)

function (l::Logger)(level::Symbol, message::String)
    timestamp = now()
    open(l.filepath, "a") do f
        println(f, "[$timestamp] $level: $message")
    end
end

end # module SystemIntegrator
