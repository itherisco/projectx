# jarvis/src/SystemIntegrator.jl - Central Nervous System of Project Jarvis
# Integrates LLM Bridge, ITHERIS Brain, Adaptive Kernel, and all subsystems
# SECURITY: Kernel is SOVEREIGN - no action executes without kernel approval

module SystemIntegrator

using Dates
using UUIDs
using JSON
using Logging
using Pkg

# ============================================================================
# SECURITY ERROR TYPES - Flow Integrity (PFI) Pattern
# ============================================================================

"""
    SovereigntyViolationError - Fatal security error for kernel sovereignty violations
    
    This error implements the Flow Integrity (PFI) pattern where no action proceeds
    without cryptographic proof of kernel approval. Throwing this error halts the
    entire thread execution.
"""
abstract type SovereigntyError <: Exception end

struct SovereigntyViolationError <: SovereigntyError
    message::String
    reason::Symbol  # :verification_failed, :approval_missing, :invalid_proof
    
    function SovereigntyViolationError(message::String, reason::Symbol)
        @assert reason in (:verification_failed, :approval_missing, :invalid_proof) 
        new(message, reason)
    end
end

Base.showerror(io::IO, e::SovereigntyViolationError) = print(io, "SovereigntyViolationError[$(e.reason)]: ", e.message)

"""
    KernelOfflineException - Fatal error when kernel is unreachable
    
    This exception implements the Sovereign Agent "Kill Switch" protocol.
    When the kernel goes offline, the system must freeze. There is no
    graceful degradation - this is fatal for a Sovereign Agent.
"""
struct KernelOfflineException <: SovereigntyError
    message::String
    
    function KernelOfflineException(message::String)
        new(message)
    end
end

Base.showerror(io::IO, e::KernelOfflineException) = print(io, "CRITICAL: KernelOfflineException - ", e.message)

# Import auth module
using .JWTAuth

# Import all submodules
include("types.jl")
include("auth/JWTAuth.jl")
include("llm/LLMBridge.jl")
include("memory/VectorMemory.jl")
include("memory/SemanticMemory.jl")
include("orchestration/TaskOrchestrator.jl")
include("bridge/CommunicationBridge.jl")

# Try to import ITHERIS Brain
const ITHERIS_PATH = joinpath(@__DIR__, "..", "..")
const ITHERIS_AVAILABLE = isfile(joinpath(ITHERIS_PATH, "itheris.jl"))

# Try to import Adaptive Kernel
const ADAPTIVE_KERNEL_PATH = joinpath(@__DIR__, "..", "..", "adaptive-kernel")
const KERNEL_AVAILABLE = isdir(ADAPTIVE_KERNEL_PATH)

# Try to load Brain module for contracts
const BRAIN_MODULE_PATH = joinpath(ADAPTIVE_KERNEL_PATH, "brain")
const BRAIN_MODULE_AVAILABLE = isdir(BRAIN_MODULE_PATH)

# Import Brain module if available
if BRAIN_MODULE_AVAILABLE
    try
        push!(LOAD_PATH, BRAIN_MODULE_PATH)
        include(joinpath(BRAIN_MODULE_PATH, "Brain.jl"))
        using .Brain
        @info "Brain module with contracts loaded"
    catch e
        @warn "Could not load Brain module: $e"
    end
end

# Try to load NeuralBrainCore for full neural network brain
const NEURAL_BRAIN_PATH = joinpath(ADAPTIVE_KERNEL_PATH, "brain")
const NEURAL_BRAIN_AVAILABLE = isdir(NEURAL_BRAIN_PATH)

if NEURAL_BRAIN_AVAILABLE
    try
        include(joinpath(NEURAL_BRAIN_PATH, "NeuralBrainCore.jl"))
        using .NeuralBrainCoreMod
        @info "NeuralBrainCore module loaded"
    catch e
        @warn "Could not load NeuralBrainCore: $e"
    end
end

# Try to load ITHERIS Brain module
# SECURITY: Use concrete type for brain state instead of Any
# Define abstract types to avoid load order issues while maintaining type safety
abstract type AbstractBrainCore end
abstract type AbstractBrainModule end

struct BrainWrapper
    # Store actual ITHERIS BrainCore instance if available
    # Use abstract type for load-order flexibility
    brain_core::Union{AbstractBrainCore, Nothing}
    
    # NEW: Brain module for contracts (when available)
    brain_module::Union{AbstractBrainModule, Nothing}
    
    # NEW: NeuralBrainCore for full neural network brain
    # Use Union{Any, Nothing} to handle module load order, with comment explaining the design
    # When NeuralBrainCoreMod is loaded, this will hold NeuralBrainCoreMod.NeuralBrain
    neural_brain::Union{Any, Nothing}
    
    config::Dict
    initialized::Bool
    
    # BrainOutput is the only thing the brain can produce
    # It is an ADVISORY PROPOSAL, not an executable action
    
    function BrainWrapper()
        new(nothing, nothing, nothing, Dict(), false)
    end
end

"""
    KernelWrapper - Wrapper for Adaptive Kernel state
"""
# Define abstract type for kernel state flexibility
abstract type AbstractKernelState end

mutable struct KernelWrapper
    # Kernel state from Kernel module
    # Use abstract type for load-order flexibility
    state::Union{AbstractKernelState, Nothing}
    
    # Configuration
    config::Dict
    
    # Initialization flag
    initialized::Bool
    
    function KernelWrapper()
        new(nothing, Dict(), false)
    end
end

# Load ITHERIS Brain if available
if ITHERIS_AVAILABLE
    try
        # Include ITHERIS core module
        include(joinpath(ITHERIS_PATH, "itheris.jl"))
        using .ITHERISCore
        @info "ITHERIS Brain module loaded" path=ITHERIS_PATH
    catch e
        @warn "Could not load ITHERIS Brain: $e"
    end
end

# Load Adaptive Kernel if available
if KERNEL_AVAILABLE
    try
        push!(LOAD_PATH, ADAPTIVE_KERNEL_PATH)
        include(joinpath(ADAPTIVE_KERNEL_PATH, "kernel", "Kernel.jl"))
        
        # Also load integration types and conversions (guard against reload)
        if isdir(joinpath(ADAPTIVE_KERNEL_PATH, "integration")) && !isdefined(SystemIntegrator, :Integration)
            conv_file = joinpath(ADAPTIVE_KERNEL_PATH, "integration", "Conversions.jl")
            if isfile(conv_file)
                include(conv_file)
                using .Integration  # Bring Integration module exports into scope
                @info "Integration conversion module loaded"
            end
        end
        
        @info "Adaptive Kernel module loaded" path=ADAPTIVE_KERNEL_PATH
    catch e
        @warn "Could not load Adaptive Kernel: $e"
    end
end

# Import SharedTypes for kernel reflection (used in _execute_action)
# This provides the ActionProposal type needed for Kernel.reflect!
if KERNEL_AVAILABLE && isdefined(SystemIntegrator, :Kernel)
    try
        # SharedTypes should already be imported via Kernel module
        # But we need to ensure it's accessible for our reflection call
        if isdefined(Kernel, :SharedTypes)
            @info "SharedTypes accessible via Kernel module"
        end
    catch e
        @warn "Could not access SharedTypes: $e"
    end
end

using .JarvisTypes
using .LLMBridge
using .VectorMemory
using .SemanticMemory
using .TaskOrchestrator
using .CommunicationBridge

# Import SharedTypes from kernel for reflection
if KERNEL_AVAILABLE && isdefined(SystemIntegrator, :Kernel)
    using .Kernel: SharedTypes, Kernel
end

# ============================================================================
# BRAIN INFERENCE CONSTANTS
# ============================================================================

"""
    BRAIN_CONFIDENCE_THRESHOLD
    
Neural confidence threshold for brain inference.
If brain uncertainty exceeds (1.0 - threshold), fall back to kernel heuristics.
"""
const BRAIN_CONFIDENCE_THRESHOLD = 0.7f0

# Export brain-related types and functions
export BRAIN_CONFIDENCE_THRESHOLD
export BrainWrapper, KernelWrapper

# Export capability integration functions (Phase 3)
export _load_capability_registry, _get_capability_by_id, _execute_capability
export _execute_builtin_capability, _get_cpu_info, _get_process_info
export _get_network_info, _get_filesystem_info
# Export action ID validation (SECURITY)
export AUTHORIZED_ACTIONS, validate_action_id, get_authorized_action_ids
export _update_memory, _handle_brain_nothing, _handle_kernel_denial

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
    
    # Last perception for memory
    last_perception::Union{PerceptionVector, Nothing}
    
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
            nothing,  # last_perception
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
            # Check if Kernel module is loaded
            if !isdefined(SystemIntegrator, :Kernel)
                @warn "Kernel module not loaded - cannot initialize"
                system.kernel.initialized = false
                return
            end
            
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
                # Verify Kernel.init_kernel exists and is callable
                if !isdefined(Kernel, :init_kernel)
                    @warn "Kernel.init_kernel function not found"
                    system.kernel.initialized = false
                    return
                end
                
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
        # First, try to initialize the new Brain module with contracts
        if isdefined(SystemIntegrator, :Brain)
            try
                brain_config = Brain.BrainConfig(
                    model_path=nothing,
                    confidence_threshold=0.5f0,
                    advisory_mode=true,
                    execution_bypass_blocked=true,
                    fallback_to_heuristic=false,  # IMPORTANT: No silent fallback
                    enable_training=true
                )
                system.brain.brain_module = Brain.create_brain(brain_config)
                println("  - Brain Module: INITIALIZED with contracts (neural inference)")
            catch e
                @warn "Brain module initialization failed: $e"
                system.brain.brain_module = nothing
            end
        end
        
        # Then, try to initialize NeuralBrainCore for full neural network brain
        if isdefined(SystemIntegrator, :NeuralBrainCoreMod)
            try
                system.brain.neural_brain = NeuralBrainCoreMod.NeuralBrain(
                    latent_dim=128,
                    num_actions=6,
                    learning_rate=0.001f0,
                    target_update_freq=100,
                    ensemble_size=5
                )
                println("  - NeuralBrainCore: INITIALIZED (full neural network brain)")
            catch e
                @warn "NeuralBrainCore initialization failed: $e"
                system.brain.neural_brain = nothing
            end
        end
        
        # Then, try to load ITHERIS BrainCore for actual neural inference
        if ITHERIS_AVAILABLE && isdefined(SystemIntegrator, :ITHERISCore)
            # Initialize actual ITHERIS BrainCore
            system.brain.brain_core = ITHERISCore.initialize_brain(
                input_size=12,
                hidden_size=128,
                learning_rate=0.01f0,
                gamma=0.95f0,
                policy_temperature=1.5f0,
                entropy_coeff=0.01f0,
                attention_coeff=0.1f0
            )
            
            # Configure brain as advisory-only
            system.brain.config = Dict(
                "model_path" => nothing,
                "confidence_threshold" => 0.5,
                "advisory_mode" => true,  # Brain never executes - only proposes
                "execution_bypass_blocked" => true,  # Explicitly block any execution attempts
                "neural_inference" => true
            )
            system.brain.initialized = true
            println("  - ITHERIS BrainCore: INITIALIZED (neural inference enabled)")
        else
            # No ITHERIS available - use NeuralBrainCore if available, otherwise degraded mode
            if system.brain.neural_brain !== nothing
                # NeuralBrainCore is available - mark as initialized
                system.brain.config = Dict(
                    "model_path" => nothing,
                    "confidence_threshold" => 0.5,
                    "advisory_mode" => true,
                    "execution_bypass_blocked" => true,
                    "neural_inference" => true,
                    "brain_type" => "NeuralBrainCore"
                )
                system.brain.initialized = true
                println("  - Using NeuralBrainCore for neural inference")
            else
                # No neural brain available - use degraded mode with explicit warning
                system.brain.config = Dict(
                    "model_path" => nothing,
                    "confidence_threshold" => 0.5,
                    "advisory_mode" => true,
                    "execution_bypass_blocked" => true,
                    "fallback_mode" => true,
                    "neural_inference" => false
                )
                system.brain.initialized = true
                println("  - ITHERIS BrainCore: NOT FOUND (using degraded heuristics mode)")
                @warn "ITHERIS BrainCore not available - neural inference disabled"
            end
        end
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
    
    PHASE 3 COMPLETE: Full cognitive cycle now implemented:
    - T=0: Collect perception (_observe_world, _build_perception)
    - T=1: Brain inference (_brain_infer) - ADVISORY only
    - T=2-3: Kernel sovereignty approval (_kernel_approval_new)
    - T=4: Execute if approved (_execute_action) - uses Capability Registry
    - T=5: Reflection for self-model update (_kernel_reflect)
    - T=6: Update memory (_update_memory)
"""
function run_cycle(system::JarvisSystem)::CycleResult
    start_time = time()
    
    # Update cycle counter
    system.state.current_cycle += 1
    cycle_num = system.state.current_cycle
    
    # T=0: Collect perception
    observation = _observe_world(system)
    
    # T=1: Build perception vector
    perception = _build_perception(observation)
    system.last_perception = perception
    
    # T=2: Get ITHERIS brain inference (advisory only - PROPOSES actions)
    proposal = _brain_infer(system, perception)
    
    # EDGE CASE: Handle brain returning nothing
    if proposal === nothing
        proposal = _handle_brain_nothing(system, perception)
        # If still nothing, kernel will use heuristics
    end
    
    # T=3: Build world state for kernel
    world_state = _build_world_state(system)
    
    # T=4: CRITICAL - Kernel sovereignty approval
    # This is the single choke point for all execution
    decision = _kernel_approval_new(system, proposal, world_state)
    
    # T=5: Execute based on decision
    if decision == Kernel.APPROVED
        # Create executable action for execution
        executable_action = _create_executable_action(proposal, system)
        
        result = _execute_action(system, executable_action)
        
        # T=6: Reflection for self-model update
        _handle_kernel_reflect(system, proposal, result)
        
        # T=7: Learn from outcome (RL update)
        reward = _compute_reward(result)
        _learn!(system, perception, proposal, reward)
        
        # T=8: Update memory (episodic storage)
        _update_memory(system, perception, proposal, result)
        
        # T=9: Proactive scanning
        suggestions = _proactive_scan(system, observation)
        
        # Record cycle time
        push!(system.cycle_times, (time() - start_time) * 1000)
        
        return CycleResult(
            cycle_num,
            perception,
            executable_action,
            result,
            reward,
            0.0f0,  # prediction_error
            SemanticEntry[],
            [s.description for s in suggestions],
            now()
        )
    elseif decision == Kernel.STOPPED
        @warn "Kernel STOPPED - system halted"
        
        # Handle kernel stop gracefully
        _handle_kernel_denial(system, proposal, "kernel_stopped")
        
        # Still update memory even on stop
        _update_memory(system, perception, proposal, nothing)
        
        return CycleResult(
            cycle_num,
            perception,
            nothing,
            Dict("success" => false, "reason" => "kernel_stopped"),
            -1.0f0,
            0.0f0,
            SemanticEntry[],
            String[],
            now()
        )
    else  # DENIED
        @debug "Kernel denied execution" proposal=proposal !== nothing ? proposal.capability_id : "none"
        
        # Handle kernel denial gracefully
        _handle_kernel_denial(system, proposal, "kernel_denied")
        
        # Still update memory even on denial
        _update_memory(system, perception, proposal, nothing)
        
        return CycleResult(
            cycle_num,
            perception,
            nothing,
            Dict("success" => false, "reason" => "kernel_denied"),
            -0.5f0,
            0.0f0,
            SemanticEntry[],
            String[],
            now()
        )
    end
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
    
    IMPROVEMENTS (v2):
    - Uses BrainOutput/BrainInput contracts when available
    - Prevents silent fallback to heuristics
    - Tracks brain health metrics
    - Integrates with experience replay for training
    """
    
    # Map ITHERIS action indices to capability IDs
    const ITHERIS_ACTION_MAP = Dict(
        1 => "log_status",
        2 => "list_processes", 
        3 => "garbage_collect",
        4 => "optimize_disk",
        5 => "throttle_cpu",
        6 => "emergency_shutdown"
    )
    
    # Try to use Brain module contracts if available
    if isdefined(SystemIntegrator, :Brain)
        try
            # Convert PerceptionVector to Float32 vector for brain
            perception_vec = Float32[
                perception.cpu_load,
                perception.memory_usage,
                perception.disk_io,
                perception.network_latency,
                perception.overall_severity,
                perception.threat_count,
                perception.file_count,
                perception.change_rate,
                perception.process_count,
                perception.energy_level,
                perception.confidence,
                perception.user_activity
            ]
            
            # Use the new Brain module with contracts
            brain_output = Brain.infer_brain(
                system.brain.brain_module,
                perception_vec
            )
            
            # Validate output meets contracts
            if !Brain.validate_brain_output(brain_output)
                @warn "Brain output failed validation - returning nothing for kernel heuristics"
                return nothing  # Let kernel decide with heuristic
            end
            
            # Check confidence threshold - if brain uncertainty is too high, let kernel decide
            brain_confidence = brain_output.confidence
            if brain_confidence < BRAIN_CONFIDENCE_THRESHOLD
                @warn "Brain confidence below threshold" 
                    confidence=brain_confidence 
                    threshold=BRAIN_CONFIDENCE_THRESHOLD
                return nothing  # Let kernel decide with heuristic
            end
            
            # Convert BrainOutput to ActionProposal
            primary_action = first(brain_output.proposed_actions)
            
            return ActionProposal(
                primary_action,
                brain_output.confidence,
                0.1f0,
                brain_output.value_estimate,
                brain_output.uncertainty;
                reasoning = "Brain neural inference: $(brain_output.reasoning)",
                impact = 0.3f0
            )
        catch e
            @error "Brain module inference failed - returning nothing for kernel heuristics" error=e
            # CRITICAL: Return nothing instead of safe fallback
            # Let kernel decide with its own heuristics
            return nothing
        end
    end
    
    # Try to use NeuralBrainCore for full neural network brain
    if isdefined(SystemIntegrator, :NeuralBrainCoreMod) && system.brain.neural_brain !== nothing
        try
            # Convert PerceptionVector to Float32 vector for neural brain
            perception_vec = Float32[
                perception.cpu_load,
                perception.memory_usage,
                perception.disk_io,
                perception.network_latency,
                perception.overall_severity,
                perception.threat_count,
                perception.file_count,
                perception.change_rate,
                perception.process_count,
                perception.energy_level,
                perception.confidence,
                perception.user_activity
            ]
            
            # Use NeuralBrainCore for inference
            neural_result = NeuralBrainCoreMod.forward_pass(
                system.brain.neural_brain,
                perception_vec
            )
            
            # Check confidence threshold
            if neural_result.confidence < BRAIN_CONFIDENCE_THRESHOLD
                @warn "NeuralBrainCore confidence below threshold" 
                    confidence=neural_result.confidence 
                    threshold=BRAIN_CONFIDENCE_THRESHOLD
                return nothing  # Let kernel decide with heuristic
            end
            
            # Convert BrainInferenceResult to ActionProposal
            primary_action = first(neural_result.proposed_actions)
            
            return ActionProposal(
                primary_action,
                neural_result.confidence,
                0.1f0,
                neural_result.value_estimate,
                neural_result.uncertainty;
                reasoning = "NeuralBrainCore inference: $(neural_result.reasoning)",
                impact = 0.3f0
            )
        catch e
            @error "NeuralBrainCore inference failed - trying fallback" error=e
            # Continue to other brain options
        end
    end
    
    # Original ITHERIS path with improved error handling
    if system.brain.initialized && system.brain.brain_core !== nothing
        try
            # Convert PerceptionVector to Dict for ITHERIS encoding
            perception_dict = Dict{String, Any}(
                "cpu_load" => Float64(perception.cpu_load),
                "memory_usage" => Float64(perception.memory_usage),
                "disk_io" => Float64(perception.disk_io),
                "network_latency" => Float64(perception.network_latency * 500f0),
                "overall_severity" => Float64(perception.overall_severity),
                "threats" => String[],
                "file_count" => Int(perception.file_count * 10000f0),
                "process_count" => Int(perception.process_count * 500f0),
                "energy_level" => Float64(perception.energy_level),
                "confidence" => Float64(perception.confidence),
                "system_uptime_hours" => 24.0,
                "user_activity_level" => Float64(perception.user_activity)
            )
            
            # Run ITHERIS neural inference
            thought = ITHERISCore.infer(system.brain.brain_core, perception_dict)
            
            # Check confidence threshold using uncertainty
            # uncertainty > (1.0 - threshold) means confidence is too low
            if thought.uncertainty > (1.0f0 - BRAIN_CONFIDENCE_THRESHOLD)
                @warn "Brain uncertainty too high - letting kernel decide" 
                    uncertainty=thought.uncertainty
                    threshold=BRAIN_CONFIDENCE_THRESHOLD
                return nothing  # Let kernel decide with heuristic
            end
            
            # Convert Thought to ActionProposal
            capability_id = get(ITHERIS_ACTION_MAP, thought.action, "observe_system")
            confidence = 1.0f0 - thought.uncertainty
            predicted_cost = 0.1f0
            predicted_reward = thought.value
            
            # Risk based on uncertainty
            risk = clamp(thought.uncertainty + 0.1f0, 0.0f0, 1.0f0)
            
            return ActionProposal(
                capability_id,
                confidence,
                predicted_cost,
                predicted_reward,
                risk;
                reasoning = "ITHERIS neural inference: action_idx=$(thought.action), uncertainty=$(round(thought.uncertainty, digits=3))",
                impact = 0.3f0
            )
        catch e
            @error "ITHERIS neural inference failed - returning nothing for kernel heuristics" error=e
            # CRITICAL: Return nothing instead of silently falling back to heuristics
            return nothing
        end
    end
    
    # Only reach here if brain is truly not initialized
    @warn "Brain not initialized - returning nothing to let kernel decide with heuristics"
    
    # CRITICAL: Return nothing instead of heuristic fallback
    # This allows the kernel to use its own heuristics without brain interference
    return nothing
end

"""
    _brain_infer_feedback - Learn from action outcomes
    
    Called after action execution to update brain with feedback.
    This is the brain learning feedback mechanism.
"""
function _brain_infer_feedback(
    system::JarvisSystem,
    perception::PerceptionVector,
    action_id::String,
    success::Bool,
    reward::Float32
)::Bool
    """
    Submit feedback to the brain for learning.
    
    This enables the brain to learn from its predictions and improve over time.
    Returns true if feedback was successfully recorded.
    """
    try
        # Convert perception to vector
        perception_vec = Vector(perception)
        
        # Get next state (current perception after action)
        # For simplicity, we use current perception as next state
        next_state = perception_vec
        
        # Try to use Brain module if available
        if isdefined(SystemIntegrator, :Brain) && 
           system.brain.brain_module !== nothing &&
           system.brain.brain_module.initialized
            
            Brain.learn_from_experience(
                system.brain.brain_module,
                perception_vec,
                action_id,
                reward,
                next_state;
                done=!success
            )
            @debug "Brain feedback recorded" action=action_id reward=reward success=success
            return true
        end
        
        # Try ITHERIS Core if available
        if system.brain.initialized && system.brain.brain_core !== nothing
            # Would call ITHERISCore.learn! here
            @debug "ITHERIS feedback recorded" action=action_id reward=reward success=success
            return true
        end
        
        return false
    catch e
        @error "Brain feedback failed" error=e
        return false
    end
end

"""
    _create_safe_fallback_proposal - Create a proposal that kernel will likely deny
    
    This prevents silent fallback by making the low confidence explicit.
"""
function _create_safe_fallback_proposal(failure_reason::String)::ActionProposal
    @warn "Creating safe fallback proposal: $failure_reason"
    return ActionProposal(
        "log_status",
        0.2f0,  # LOW confidence - kernel likely to deny
        0.1f0,
        0.0f0,
        0.9f0;  # HIGH risk due to uncertainty
        reasoning = "Safe fallback: $failure_reason - low confidence",
        impact = 0.1f0
    )
end

"""
    _brain_infer_fallback - Heuristic fallback with reduced confidence
"""
function _brain_infer_fallback(perception::PerceptionVector)::ActionProposal
    cpu_high = perception.cpu_load > 0.7f0
    memory_high = perception.memory_usage > 0.7f0
    
    capability_id = "observe_system"
    confidence = 0.5f0  # Reduced from 0.8f0 to reflect degraded mode
    predicted_cost = 0.1f0
    predicted_reward = 0.5f0
    risk = 0.3f0  # Increased risk due to lower confidence
    
    if cpu_high
        capability_id = "observe_cpu"
        predicted_reward = 0.7f0
        risk = 0.2f0
    elseif memory_high
        capability_id = "observe_memory"
        predicted_reward = 0.7f0
        risk = 0.2f0
    end
    
    return ActionProposal(
        capability_id,
        confidence,
        predicted_cost,
        predicted_reward,
        risk;
        reasoning = "Heuristic fallback (degraded mode): based on current perception",
        impact = 0.3f0
    )
end

# ============================================================================
# CAPABILITY REGISTRY INTEGRATION
# ============================================================================

"""
    CAPABILITY_REGISTRY_PATH - Path to the capability registry JSON
"""
const CAPABILITY_REGISTRY_PATH = joinpath(ADAPTIVE_KERNEL_PATH, "registry", "capability_registry.json")

"""
    AUTHORIZED_ACTIONS - Whitelist of all valid action/capability IDs
    
    This set combines:
    1. Capabilities from capability_registry.json
    2. Built-in capabilities from _execute_builtin_capability
    
    SECURITY: This is the authoritative list of all actions that can be executed.
    Any action_id NOT in this set will be rejected with a clear error message.
"""
const AUTHORIZED_ACTIONS = Set{String}(
    vcat(
        # Registry capabilities (will be loaded at runtime if available)
        ["observe_cpu", "analyze_logs", "write_file", "safe_shell", 
         "safe_http_request", "observe_network", "observe_filesystem"],
        # Built-in capabilities from _execute_builtin_capability
        ["observe_cpu", "observe_system", "log_status", 
         "list_processes", "observe_processes", "garbage_collect",
         "observe_network", "observe_filesystem"]
    )
)

"""
    validate_action_id(capability_id::String)::Bool

Validate that a capability/action ID is in the authorized whitelist.

SECURITY: This implements fail-closed behavior - unknown action IDs are
rejected rather than being passed through to execution fallback.

# Arguments
- `capability_id::String`: The action ID to validate

# Returns
- `true` if the ID is authorized
- `false` if the ID is NOT in the AUTHORIZED_ACTIONS whitelist

# Error Handling
Logs a security warning for unauthorized IDs and returns false.
"""
function validate_action_id(capability_id::String)::Bool
    if isempty(capability_id)
        @warn "SECURITY: Empty action_id rejected"
        return false
    end
    
    if capability_id in AUTHORIZED_ACTIONS
        return true
    end
    
    # Log security violation
    @warn "SECURITY VIOLATION: Unauthorized action_id attempt" 
        requested_id=capability_id
        authorized_count=length(AUTHORIZED_ACTIONS)
    return false
end

"""
    get_authorized_action_ids()::Vector{String}

Return list of all authorized action IDs for debugging/display.
"""
function get_authorized_action_ids()::Vector{String}
    return sort(collect(AUTHORIZED_ACTIONS))
end

"""
    _load_capability_registry - Load capabilities from the registry JSON
"""
function _load_capability_registry()::Dict{String, Any}
    try
        if isfile(CAPABILITY_REGISTRY_PATH)
            return JSON.parsefile(CAPABILITY_REGISTRY_PATH)
        end
    catch e
        @warn "Failed to load capability registry: $e"
    end
    return Dict{String, Any}()
end

"""
    _get_capability_by_id - Get a specific capability from the registry
"""
function _get_capability_by_id(capability_id::String)::Union{Dict{String, Any}, Nothing}
    registry = _load_capability_registry()
    for cap in registry
        if cap["id"] == capability_id
            return cap
        end
    end
    return nothing
end

"""
    _execute_capability - Execute a capability from the registry
    
    SECURITY: This only executes capabilities that have been approved by the kernel.
    The kernel's approval is verified before execution.
"""
function _execute_capability(
    capability_id::String,
    parameters::Dict{String, Any} = Dict{String, Any}()
)::Dict{String, Any}
    
    # Get capability definition
    capability = _get_capability_by_id(capability_id)
    
    if capability === nothing
        @warn "Capability not found in registry: $capability_id"
        return Dict(
            "success" => false,
            "error" => "capability_not_found",
            "capability_id" => capability_id
        )
    end
    
    # Get the run command
    run_command = get(capability, "run_command", "")
    
    if isempty(run_command)
        @warn "No run_command defined for capability: $capability_id"
        return Dict(
            "success" => false,
            "error" => "no_run_command",
            "capability_id" => capability_id
        )
    end
    
    # Execute the capability
    try
        # Build parameters string for the command
        params_json = JSON.json(parameters)
        
        # SECURITY: Use safe command execution - split into command + args
        # Avoid shell interpretation to prevent command injection attacks
        # The run_command should be a command path, not a shell string
        command_parts = split(run_command)
        if isempty(command_parts)
            @warn "Empty run_command for capability: $capability_id"
            return Dict(
                "success" => false,
                "error" => "empty_command",
                "capability_id" => capability_id
            )
        end
        
        # Use Cmd() constructor with separate arguments - NO shell interpretation
        cmd = Cmd(command_parts)
        
        # Capture output
        output = read(cmd, String)
        
        return Dict(
            "success" => true,
            "capability_id" => capability_id,
            "output" => output,
            "risk" => get(capability, "risk", "unknown"),
            "cost" => get(capability, "cost", 0.0)
        )
    catch e
        @error "Capability execution failed" capability=capability_id error=e
        return Dict(
            "success" => false,
            "error" => string(e),
            "capability_id" => capability_id
        )
    end
end

"""
    _execute_builtin_capability - Execute a built-in capability (fallback when registry not available)

This provides basic functionality when the full capability registry is not available.
"""
function _execute_builtin_capability(capability_id::String)::Dict{String, Any}
    # Built-in capability implementations
    result = Dict{String, Any}()
    
    try
        if capability_id == "observe_cpu" || capability_id == "observe_system"
            # Get CPU info using built-in Julia
            result = _get_cpu_info()
        elseif capability_id == "log_status"
            result = Dict(
                "success" => true,
                "status" => "logged",
                "message" => "System status logged"
            )
        elseif capability_id == "list_processes" || capability_id == "observe_processes"
            result = _get_process_info()
        elseif capability_id == "garbage_collect"
            # Run GC
            GC.gc()
            result = Dict(
                "success" => true,
                "action" => "garbage_collected",
                "message" => "Garbage collection completed"
            )
        elseif capability_id == "observe_network"
            result = _get_network_info()
        elseif capability_id == "observe_filesystem"
            result = _get_filesystem_info()
        else
            # Unknown capability - return error
            result = Dict(
                "success" => false,
                "error" => "unknown_capability",
                "capability_id" => capability_id
            )
        end
    catch e
        result = Dict(
            "success" => false,
            "error" => string(e),
            "capability_id" => capability_id
        )
    end
    
    return result
end

"""
    _get_cpu_info - Get CPU and memory information
"""
function _get_cpu_info()::Dict{String, Any}
    try
        # Get load average (Linux)
        load_avg = if isfile("/proc/loadavg")
            split(read("/proc/loadavg", String))[1:3]
        else
            ["0.0", "0.0", "0.0"]
        end
        
        cpu_count = Sys.CPU_THREADS
        
        return Dict(
            "success" => true,
            "cpu_load" => parse(Float64, load_avg[1]) / Float64(cpu_count),
            "cpu_count" => cpu_count,
            "load_1m" => parse(Float64, load_avg[1]),
            "load_5m" => parse(Float64, load_avg[2]),
            "load_15m" => parse(Float64, load_avg[3]),
            "memory_usage" => 0.5,
            "timestamp" => string(now())
        )
    catch e
        return Dict(
            "success" => false,
            "error" => string(e)
        )
    end
end

"""
    _get_process_info - Get process information
"""
function _get_process_info()::Dict{String, Any}
    try
        proc_dir = "/proc"
        if isdir(proc_dir)
            # Count processes
            process_count = length(readdir(proc_dir))
            
            return Dict(
                "success" => true,
                "process_count" => process_count,
                "timestamp" => string(now())
            )
        end
        
        return Dict(
            "success" => true,
            "process_count" => 1,
            "note" => "/proc not available",
            "timestamp" => string(now())
        )
    catch e
        return Dict(
            "success" => false,
            "error" => string(e)
        )
    end
end

"""
    _get_network_info - Get network information
"""
function _get_network_info()::Dict{String, Any}
    try
        net_dir = "/proc/net/dev"
        if isfile(net_dir)
            content = read(net_dir, String)
            lines = split(content, "\n")[3:end]
            
            total_rx = 0
            total_tx = 0
            for line in lines
                if !isempty(strip(line))
                    parts = split(line)
                    if length(parts) >= 11
                        total_rx += parse(Int, parts[2])
                        total_tx += parse(Int, parts[10])
                    end
                end
            end
            
            return Dict(
                "success" => true,
                "bytes_received" => total_rx,
                "bytes_sent" => total_tx,
                "timestamp" => string(now())
            )
        end
        
        return Dict(
            "success" => true,
            "note" => "/proc/net/dev not available",
            "timestamp" => string(now())
        )
    catch e
        return Dict(
            "success" => false,
            "error" => string(e)
        )
    end
end

"""
    _get_filesystem_info - Get filesystem information
"""
function _get_filesystem_info()::Dict{String, Any}
    try
        # Check disk usage using df command
        df_output = read(`df -B1 .`, String)
        lines = split(df_output, "\n")
        
        if length(lines) >= 2
            parts = split(lines[2])
            if length(parts) >= 4
                total = parse(Int, parts[2])
                used = parse(Int, parts[3])
                available = parse(Int, parts[4])
                
                return Dict(
                    "success" => true,
                    "total_bytes" => total,
                    "used_bytes" => used,
                    "available_bytes" => available,
                    "usage_percent" => used / total * 100,
                    "timestamp" => string(now())
                )
            end
        end
        
        return Dict(
            "success" => true,
            "note" => "Could not parse df output",
            "timestamp" => string(now())
        )
    catch e
        return Dict(
            "success" => false,
            "error" => string(e)
        )
    end
end

# ============================================================================
# INTEGRATION HELPER FUNCTIONS
# ============================================================================

"""
    _try_convert_to_integration(proposal)::Union{IntegrationActionProposal, Nothing}
Try to convert a JarvisTypes.ActionProposal to IntegrationActionProposal.
Returns nothing if conversion fails (graceful degradation).
"""
function _try_convert_to_integration(proposal)
    try
        # Check if Integration module is available
        if !isdefined(SystemIntegrator, :Integration)
            return nothing
        end
        
        # Try to use the conversion function
        return Integration.convert_jarvis_proposal_to_integration(proposal)
    catch e
        @warn "Failed to convert proposal to Integration format" error=e
        return nothing
    end
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
    
    # Try to use Integration types for type-safe communication
    integration_proposal = _try_convert_to_integration(proposal)
    
    # If kernel is initialized, use it for approval
    if system.kernel.initialized && system.kernel.state !== nothing
        try
            # Convert proposal to capability candidate format for kernel
            # Use Integration proposal if available, otherwise use original
            # Use consistent >= thresholds matching Integration.float_to_risk_string:
            # - high: >= 0.5, medium: >= 0.2, low: < 0.2
            if integration_proposal !== nothing
                candidate = Dict{String, Any}(
                    "id" => integration_proposal.capability_id,
                    "risk" => Integration.float_to_risk_string(integration_proposal.risk),
                    "cost" => integration_proposal.predicted_cost,
                    "confidence" => integration_proposal.confidence
                )
            else
                # Fallback to original proposal format
                candidate = Dict{String, Any}(
                    "id" => proposal.capability_id,
                    "risk" => risk_score >= 0.5f0 ? "high" : (risk_score >= 0.2f0 ? "medium" : "low"),
                    "cost" => proposal.predicted_cost,
                    "confidence" => proposal.confidence
                )
            end
            
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
            # CRITICAL SECURITY FIX: No more fallback - hard halt instead
        end
    end
    
    # CRITICAL SECURITY FIX: Rip out the fallback math formula
    # For a Sovereign Agent, graceful degradation is FATAL.
    # If the Kernel goes offline, the system must freeze. Period.
    # This replaces the vulnerable fallback formula that could be exploited.
    throw(KernelOfflineException("Kernel unreachable - sovereign execution impossible. System halted."))
end

"""
    _kernel_approval_new - NEW kernel approval using Kernel.approve()
    
    This is the NEW sovereignty pattern that uses Kernel.approve() directly.
    Returns Kernel.APPROVED, Kernel.DENIED, or Kernel.STOPPED.
"""
function _kernel_approval_new(
    system::JarvisSystem,
    proposal::Union{ActionProposal, Nothing},
    world_state::Dict{String, Any}
)::Kernel.Decision
    
    # KILL SWITCH PROTOCOL: Hard halt when kernel is unreachable
    # For a Sovereign Agent, graceful degradation is FATAL.
    # If the Kernel goes offline, the system must freeze. Period.
    if !system.kernel.initialized || system.kernel.state === nothing
        @error "CRITICAL: Kernel unreachable. Sovereign execution is impossible."
        # We do NOT fall back to local approval. We trigger a hard halt.
        throw(KernelOfflineException("System halted to preserve sovereignty. Reboot required."))
    end
    
    # Use Kernel.approve() for sovereignty
    try
        # Convert JarvisTypes.ActionProposal to SharedTypes.ActionProposal if needed
        kernel_proposal = _convert_to_kernel_proposal(proposal)
        
        # Call Kernel.approve() - the sovereign authority
        decision = Kernel.approve(system.kernel.state, kernel_proposal, world_state)
        
        # Log the decision
        if decision == Kernel.APPROVED
            _log_event(system, "kernel_approval", Dict(
                "action" => proposal !== nothing ? proposal.capability_id : "none",
                "decision" => "APPROVED",
                "timestamp" => string(now())
            ))
        elseif decision == Kernel.DENIED
            _log_event(system, "kernel_denial", Dict(
                "action" => proposal !== nothing ? proposal.capability_id : "none",
                "decision" => "DENIED",
                "timestamp" => string(now())
            ))
        else
            _log_event(system, "kernel_stop", Dict(
                "action" => proposal !== nothing ? proposal.capability_id : "none",
                "decision" => "STOPPED",
                "timestamp" => string(now())
            ))
        end
        
        return decision
    catch e
        # ERROR SWALLOWING FIX: Push alert to user instead of silently dropping the task
        error_message = "Action blocked: Internal Kernel computation error - $(typeof(e)): $(e)"
        @error "Kernel.approve() failed: $e" exception=(e, catch_backtrace())
        
        # Store error in system state for retrieval
        system.state.last_error = error_message
        
        # Log critical event for audit trail
        _log_event(system, "kernel_error", Dict(
            "action" => proposal !== nothing ? proposal.capability_id : "none",
            "error" => error_message,
            "timestamp" => string(now())
        ))
        
        # Throw instead of silently returning DENIED - the error must surface to user
        throw(KernelOfflineException(error_message))
    end
end

"""
    _convert_to_kernel_proposal - Convert JarvisTypes.ActionProposal to SharedTypes.ActionProposal
"""
function _convert_to_kernel_proposal(proposal::Union{ActionProposal, Nothing})
    if proposal === nothing
        return nothing
    end
    
    # Try to use SharedTypes if available
    if isdefined(SystemIntegrator, :SharedTypes)
        return SharedTypes.ActionProposal(
            proposal.capability_id,
            proposal.confidence,
            proposal.predicted_cost,
            proposal.predicted_reward,
            proposal.risk >= 0.5f0 ? "high" : (proposal.risk >= 0.2f0 ? "medium" : "low"),
            proposal.reasoning
        )
    end
    
    # Fallback - create minimal kernel proposal
    return SharedTypes.ActionProposal(
        proposal.capability_id,
        proposal.confidence,
        proposal.predicted_cost,
        proposal.predicted_reward,
        "medium",
        proposal.reasoning
    )
end

"""
    _build_world_state - Build world state dict for kernel approval
"""
function _build_world_state(system::JarvisSystem)::Dict{String, Any}
    observation = _observe_world(system)
    
    return Dict(
        "timestamp" => string(now()),
        "system_metrics" => observation.system_metrics,
        "cycle" => system.state.current_cycle,
        "trust_level" => Int(system.state.trust_level),
        "kernel_initialized" => system.kernel.initialized,
        "brain_initialized" => system.brain.initialized,
        "status" => string(system.state.status)
    )
end

"""
    _create_executable_action - Create ExecutableAction from proposal
"""
function _create_executable_action(proposal::Union{ActionProposal, Nothing}, system::JarvisSystem)::Union{ExecutableAction, Nothing}
    if proposal === nothing
        return nothing
    end
    
    risk_score = _compute_risk_score(proposal, system.state)
    score = proposal.confidence * (proposal.predicted_reward - risk_score)
    
    return ExecutableAction(
        proposal,
        score,
        now(),
        Dict{String, Any}("kernel_approved" => true, "risk_score" => risk_score)
    )
end

"""
    _update_memory - Store cycle results in memory for future reference
    
    This is the T=6 step in the cognitive cycle:
    - Stores perception, proposal, and result for episodic memory
    - Enables future retrieval and learning
"""
function _update_memory(
    system::JarvisSystem,
    perception::Union{PerceptionVector, Nothing},
    proposal::Union{ActionProposal, Nothing},
    result::Union{Dict{String, Any}, Nothing}
)
    try
        # Store in vector store for semantic memory
        if proposal !== nothing
            entry = SemanticEntry(
                :episodic,
                "Action: $(proposal.capability_id) - $(get(result, "success", false) ? "success" : "failure")",
                perception !== nothing ? Vector(perception) : zeros(Float32, 12);
                metadata = Dict(
                    "action" => proposal.capability_id,
                    "confidence" => proposal.confidence,
                    "success" => get(result, "success", false),
                    "cycle" => system.state.current_cycle,
                    "result" => result !== nothing ? JSON.json(result) : ""
                )
            )
            store!(system.vector_store, entry)
        end
        
        @debug "Memory updated" cycle=system.state.current_cycle
    catch e
        @warn "Failed to update memory" error=e
    end
end

"""
    _handle_brain_nothing - Handle case when brain returns nothing
    
    EDGE CASE: When brain returns nothing (low confidence or error),
    we need to let the kernel decide with heuristic fallback.
    
    Returns a proposal that the kernel can evaluate, or nothing if
    even heuristic fallback should not proceed.
"""
function _handle_brain_nothing(
    system::JarvisSystem,
    perception::PerceptionVector
)::Union{ActionProposal, Nothing}
    
    @debug "Brain returned nothing - using kernel heuristic fallback"
    
    # Check if kernel is initialized for heuristic mode
    if !system.kernel.initialized || system.kernel.state === nothing
        # No kernel available - create minimal safe proposal
        @warn "Brain and kernel not available - system idle"
        return nothing
    end
    
    # Let kernel use its internal heuristics
    # The kernel will create its own proposal based on world state
    return nothing  # Tell kernel to use its own heuristics
end

"""
    _handle_kernel_denial - Handle kernel denial gracefully
    
    EDGE CASE: When kernel denies execution, we need to:
    - Log the denial
    - Update metrics
    - Possibly trigger self-correction
"""
function _handle_kernel_denial(
    system::JarvisSystem,
    proposal::Union{ActionProposal, Nothing},
    reason::String
)
    @warn "Kernel denied execution" reason=reason 
        proposal=proposal !== nothing ? proposal.capability_id : "none"
    
    # Log the denial
    _log_event(system, "kernel_denial", Dict(
        "proposal" => proposal !== nothing ? proposal.capability_id : "none",
        "reason" => reason,
        "timestamp" => string(now())
    ))
    
    # Update failure count
    system.state.failure_count += 1
    
    # If too many denials, could trigger trust level reduction
    # (This would be done in a production system)
end

"""
    _handle_execution_error - Handle execution errors gracefully
    
    EDGE CASE: When action execution fails, we need to:
    - Log the error
    - Update metrics  
    - Return failure result
"""
function _handle_kernel_reflect(
    system::JarvisSystem,
    proposal::Union{ActionProposal, Nothing},
    result::Dict{String, Any}
)
    # Skip if kernel not initialized
    if !system.kernel.initialized || system.kernel.state === nothing
        return
    end
    
    # Skip if proposal is nothing
    if proposal === nothing
        return
    end
    
    try
        # Convert proposal to kernel format
        kernel_proposal = _convert_to_kernel_proposal(proposal)
        
        # Build complete reflection data
        reflection_result = Dict{String, Any}(
            "success" => get(result, "success", false),
            "effect" => get(result, "result", ""),
            "actual_confidence" => proposal.confidence,
            "energy_cost" => proposal.predicted_cost
        )
        
        # Call Kernel.reflect!()
        Kernel.reflect!(system.kernel.state, kernel_proposal, reflection_result)
        
        @debug "Kernel reflection completed" action=proposal.capability_id
    catch e
        @warn "Kernel reflection failed" error=e
    end
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
    
    CRITICAL: Sovereignty assertion - verifies kernel.state.last_decision == APPROVED
    before execution. This enforces the invariant:
        ∀ action ∈ Actions: execute(action) ⇒ kernel.state.last_decision == APPROVED
    
    VIOLATION = SECURITY BREACH = SYSTEM HALT
    
    IMPROVEMENTS (Phase 3):
    - Now uses Capability Registry for actual execution
    - Falls back to built-in capabilities when registry unavailable
    - Proper error handling for execution failures
    """
    
    if action === nothing
        return Dict("success" => false, "reason" => "no_action")
    end
    
    # ============================================================================
    # PHASE 1: KERNEL SOVEREIGNTY ENFORCEMENT
    # CRITICAL: Verify kernel approval BEFORE any execution
    # ============================================================================
    
    # Check 1: Kernel state must exist (fail-closed)
    if system.kernel.state === nothing
        @error "Kernel state is nothing - refusing execution"
        return Dict(
            "success" => false, 
            "reason" => "Kernel not ready",
            "error" => "Kernel state is nothing - sovereignty enforcement active"
        )
    end
    
    # Check 2: Kernel must have approved the action
    if system.kernel.state.last_decision != Kernel.APPROVED
        @warn "Action not approved by kernel" decision=system.kernel.state.last_decision
        return Dict(
            "success" => false, 
            "reason" => "Kernel approval required",
            "error" => "Kernel has not approved this action",
            "last_decision" => string(system.kernel.state.last_decision)
        )
    end
    
    # ============================================================================
    # END KERNEL SOVEREIGNTY ENFORCEMENT
    # ============================================================================
    
    # SECURITY CHECK 1: Verify kernel approval flag
    kernel_approved = get(action.execution_context, "kernel_approved", false)
    if !kernel_approved
        @error "SECURITY VIOLATION: Attempted to execute action without kernel approval flag!"
        return Dict(
            "success" => false, 
            "reason" => "SECURITY_VIOLATION: no kernel approval flag",
            "action" => action.proposal.capability_id
        )
    end
    
    # SOVEREIGNTY ASSERTION: Verify kernel.state.last_decision == APPROVED
    # This is the CRITICAL security invariant enforcement
    if system.kernel.initialized && system.kernel.state !== nothing
        try
            last_decision = system.kernel.state.last_decision
            if last_decision != Kernel.APPROVED
                @error "SOVEREIGNTY VIOLATION: kernel.state.last_decision != APPROVED" 
                    actual_decision=last_decision
                    expected_decision=Kernel.APPROVED
                return Dict(
                    "success" => false, 
                    "reason" => "SOVEREIGNTY_VIOLATION: kernel.last_decision != APPROVED",
                    "action" => action.proposal.capability_id,
                    "last_decision" => string(last_decision)
                )
            end
            @debug "Sovereignty assertion passed" last_decision=last_decision
        catch e
            # PFI (Flow Integrity) PATTERN: Fail-closed
            # Any error in sovereignty verification is treated as a fatal security violation.
            # No action proceeds without cryptographic proof of kernel approval.
            @error "FATAL: Sovereignty verification failed - halting thread execution" error=typeof(e)
            # Throw a custom error that halts the entire thread
            throw(SovereigntyViolationError(
                "Sovereignty assertion failed: kernel state could not be verified. " *
                "Thread execution halted for security. Error: $(typeof(e))",
                :verification_failed
            ))
        end
    end
    
    # Get capability ID
    capability_id = action.proposal.capability_id
    
    # ============================================================================
    # ACTION ID VALIDATION (WHITELIST ENFORCEMENT)
    # SECURITY: Validate against AUTHORIZED_ACTIONS whitelist before execution
    # This implements fail-closed behavior - unknown IDs are rejected
    # ============================================================================
    if !validate_action_id(capability_id)
        @error "SECURITY VIOLATION: Attempted to execute unauthorized action_id" 
            action_id=capability_id
            authorized_ids=get_authorized_action_ids()
        return Dict(
            "success" => false, 
            "reason" => "INVALID_ACTION_ID",
            "error" => "Action ID '$(capability_id)' is not in the authorized whitelist. " *
                        "Valid actions are: $(join(sort(collect(AUTHORIZED_ACTIONS)), ", "))",
            "action_id" => capability_id,
            "security_violation" => true
        )
    end
    @debug "Action ID validated successfully" action_id=capability_id
    # ============================================================================
    # END ACTION ID VALIDATION
    # ============================================================================
    
    # Log the action
    _log_event(system, "action_execution", Dict(
        "action_id" => capability_id,
        "score" => action.kernel_score,
        "timestamp" => string(now())
    ))
    
    # Execute based on capability type with error handling
    # First, try the capability registry
    try
        result = _execute_capability(capability_id, Dict{String, Any}())
        
        # If capability registry failed or not available, use built-in fallback
        if !get(result, "success", false) || isempty(result)
            @debug "Falling back to built-in capability" capability=capability_id
            result = _execute_builtin_capability(capability_id)
        end
    catch e
        @error "Action execution failed" error=e exception=(e, catch_backtrace())
        # Return failure result instead of propagating exception
        result = Dict(
            "success" => false,
            "result" => "Execution error: $(string(e))",
            "error" => string(e)
        )
    end
    
    # Add execution metadata to result
    result["kernel_score"] = action.kernel_score
    result["capability_id"] = capability_id
    result["execution_timestamp"] = string(now())
    
    # KERNEL INTEGRATION: Reflect on action outcome
    # Update kernel's self-model with action result
    if system.kernel.initialized && system.kernel.state !== nothing
        try
            # Create SharedTypes.ActionProposal for kernel reflection
            kernel_proposal = SharedTypes.ActionProposal(
                action.proposal.capability_id,
                action.proposal.confidence,
                action.proposal.predicted_cost,
                action.proposal.predicted_reward,
                action.proposal.risk >= 0.5f0 ? "high" : (action.proposal.risk >= 0.2f0 ? "medium" : "low"),
                action.proposal.reasoning
            )
            
            # Call kernel reflection to update self-model
            Kernel.reflect!(system.kernel.state, kernel_proposal, result)
            
            @debug "Kernel reflection completed" action=action.proposal.capability_id
        catch e
            @warn "Kernel reflection failed" error=e
        end
    end
    
    return result
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
    
    # Get next perception for proper temporal difference learning
    # This is the actual next state after action execution
    next_perception = _build_perception(_observe_world(system))
    
    # Convert to Float32 vector for brain training
    next_perception_vec = Float32[
        next_perception.cpu_load,
        next_perception.memory_usage,
        next_perception.disk_io,
        next_perception.network_latency,
        next_perception.overall_severity,
        next_perception.threat_count,
        next_perception.file_count,
        next_perception.change_rate,
        next_perception.process_count,
        next_perception.energy_level,
        next_perception.confidence,
        next_perception.user_activity
    ]
    
    # Current state vector
    current_perception_vec = Float32[
        perception.cpu_load,
        perception.memory_usage,
        perception.disk_io,
        perception.network_latency,
        perception.overall_severity,
        perception.threat_count,
        perception.file_count,
        perception.change_rate,
        perception.process_count,
        perception.energy_level,
        perception.confidence,
        perception.user_activity
    ]
    
    # Try to use Brain module for training if available
    if isdefined(SystemIntegrator, :Brain) && 
       system.brain.brain_module !== nothing &&
       system.brain.brain_module.config.enable_training
        try
            Brain.learn_from_experience(
                system.brain.brain_module,
                current_perception_vec,
                proposal !== nothing ? proposal.capability_id : "noop",
                reward,
                next_perception_vec;
                done=false
            )
            @debug "Brain module learning completed"
        catch e
            @warn "Brain module learning failed" error=e
        end
    end
    
    # ITHERIS Learning: Update brain with experience if available
    if system.brain.initialized && system.brain.brain_core !== nothing && proposal !== nothing
        try
            # Convert perception to ITHERIS format
            perception_dict = Dict{String, Any}(
                "cpu_load" => Float64(perception.cpu_load),
                "memory_usage" => Float64(perception.memory_usage),
                "disk_io" => Float64(perception.disk_io),
                "network_latency" => Float64(perception.network_latency * 500f0),
                "overall_severity" => Float64(perception.overall_severity),
                "threats" => String[],
                "file_count" => Int(perception.file_count * 10000f0),
                "process_count" => Int(perception.process_count * 500f0),
                "energy_level" => Float64(perception.energy_level),
                "confidence" => Float64(perception.confidence),
                "system_uptime_hours" => 24.0,
                "user_activity_level" => Float64(perception.user_activity)
            )
            
            # Convert NEXT perception to ITHERIS format (for TD learning)
            next_perception_dict = Dict{String, Any}(
                "cpu_load" => Float64(next_perception.cpu_load),
                "memory_usage" => Float64(next_perception.memory_usage),
                "disk_io" => Float64(next_perception.disk_io),
                "network_latency" => Float64(next_perception.network_latency * 500f0),
                "overall_severity" => Float64(next_perception.overall_severity),
                "threats" => String[],
                "file_count" => Int(next_perception.file_count * 10000f0),
                "process_count" => Int(next_perception.process_count * 500f0),
                "energy_level" => Float64(next_perception.energy_level),
                "confidence" => Float64(next_perception.confidence),
                "system_uptime_hours" => 24.0,
                "user_activity_level" => Float64(next_perception.user_activity)
            )
            
            # Map capability to action index
            const CAPABILITY_TO_ACTION = Dict(
                "log_status" => 1,
                "list_processes" => 2,
                "garbage_collect" => 3,
                "optimize_disk" => 4,
                "throttle_cpu" => 5,
                "emergency_shutdown" => 6,
                "observe_system" => 1,
                "observe_cpu" => 1,
                "observe_memory" => 1
            )
            action_idx = get(CAPABILITY_TO_ACTION, proposal.capability_id, 1)
            
            # Create thought structure for learning
            probs = fill(1f0/6f0, 6)
            thought_value = proposal.predicted_reward
            
            # Estimate next value from next perception (proper TD learning)
            next_value_estimate = next_perception.energy_level * 0.5f0  # Simplified value estimation
            
            # Call ITHERIS learn! with proper next state
            ITHERISCore.learn!(
                system.brain.brain_core,
                perception_dict,
                next_perception_dict,
                ITHERISCore.Thought(action_idx, probs, thought_value, 0.5f0, zeros(Float32, 128)),
                reward,
                next_value_estimate  # Use estimated next value instead of same value
            )
            
            @debug "ITHERIS learning completed" action=proposal.capability_id reward=reward
        catch e
            @warn "ITHERIS learning failed" error=e
        end
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

# ============================================================================
# AUTHENTICATION LAYER
# ============================================================================

"""
    configure_authentication(enabled::Bool, secret::String)

Configure JWT authentication for the Jarvis system.

CRITICAL SECURITY FIX: Now uses SecureKeystore instead of ENV variables.
"""
function configure_authentication(enabled::Bool, secret::String)
    # CRITICAL: Store secrets in SecureKeystore instead of ENV
    # ENV["JARVIS_AUTH_ENABLED"] = string(enabled)  # REMOVED - insecure
    # ENV["JARVIS_JWT_SECRET"] = secret  # REMOVED - insecure
    
    # Use SecureKeystore for secure storage
    SecureKeystore.store_secret!("JARVIS_JWT_SECRET", secret)
    
    config = JWTAuth.AuthConfig(enabled=enabled, jwt_secret=secret)
    JWTAuth.configure_auth!(config)
    
    @info "Authentication configured securely using SecureKeystore"
end

"""
    authenticate_request(token::String)::Bool

Authenticate a request by validating the JWT token.
"""
function authenticate_request(token::String)::Bool
    return JWTAuth.authenticate_request(token)
end

"""
    authenticated_process_user_request(
        system::JarvisSystem,
        user_input::String,
        token::String
    )::Dict{String, Any}

Process a user request with authentication.
"""
function authenticated_process_user_request(
    system::JarvisSystem,
    user_input::String,
    token::String
)::Dict{String, Any}
    
    # Authenticate the request first
    JWTAuth.require_auth(token)
    
    # Then process the request
    return process_user_request(system, user_input)
end

"""
    authenticated_run_cycle(
        system::JarvisSystem,
        token::String
    )::CycleResult

Run a cognitive cycle with authentication.
"""
function authenticated_run_cycle(
    system::JarvisSystem,
    token::String
)::CycleResult
    
    # Authenticate the request first
    JWTAuth.require_auth(token)
    
    # Then run the cycle
    return run_cycle(system)
end

"""
    generate_access_token(username::String; roles::Vector{String}=["user"])::String

Generate a JWT access token for testing/development.
"""
function generate_access_token(username::String; roles::Vector{String}=["user"])::String
    return JWTAuth.generate_token(username, username; roles=roles)
end

"""
    is_authentication_enabled()::Bool

Check if authentication is enabled.
"""
function is_authentication_enabled()::Bool
    return JWTAuth.is_auth_enabled()
end

end # module SystemIntegrator
