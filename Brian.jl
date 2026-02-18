# Brian.jl - Voice-Activated Personal Assistant
# Main entry point for the autonomous agent "Brian"
# Combines Adaptive Kernel (Safety), Itheris (Brain), VectorMemory, CommunicationBridge, and OpenClaw

module Brian

using Dates
using JSON
using Logging
using UUIDs
using HTTP
using Base64
using TOML

# Import project modules
include("jarvis/src/types.jl")
include("jarvis/src/bridge/CommunicationBridge.jl")
include("jarvis/src/bridge/OpenClawBridge.jl")
include("jarvis/src/memory/VectorMemory.jl")
include("jarvis/src/llm/LLMBridge.jl")

# Try to import Adaptive Kernel
const ADAPTIVE_KERNEL_PATH = joinpath(@__DIR__, "adaptive-kernel")
const KERNEL_AVAILABLE = false  # Disabled due to import issues in adaptive-kernel

# Load Adaptive Kernel if available (currently disabled)
# if KERNEL_AVAILABLE
#     try
#         push!(LOAD_PATH, ADAPTIVE_KERNEL_PATH)
#         include(joinpath(ADAPTIVE_KERNEL_PATH, "kernel", "Kernel.jl"))
#         @info "Brian: Adaptive Kernel module loaded"
#     catch e
#         @warn "Brian: Could not load Adaptive Kernel: $e"
#     end
# end

using .JarvisTypes
using .CommunicationBridge
using .OpenClawBridge
using .VectorMemory
using .LLMBridge

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    BrianConfig - Configuration for Brian the assistant
"""
struct BrianConfig
    # Communication
    communication::CommunicationConfig
    
    # OpenClaw
    openclaw::OpenClawConfig
    
    # LLM
    llm::LLMConfig
    
    # Vector Memory
    vector_store_path::String
    
    # Wake word
    wake_word::String
    
    # Mode
    demo_mode::Bool
    
    function BrianConfig(;
        communication::CommunicationConfig = CommunicationConfig(),
        openclaw::OpenClawConfig = OpenClawConfig(),
        llm::LLMConfig = LLMConfig(),
        vector_store_path::String = "./brian_vector_store.json",
        wake_word::String = "Brian",
        demo_mode::Bool = true
    )
        new(communication, openclaw, llm, vector_store_path, wake_word, demo_mode)
    end
end

"""
    load_config - Load Brian configuration from TOML file
"""
function load_config(config_path::String)::BrianConfig
    if !isfile(config_path)
        @warn string("Config file not found: ", config_path, " - using defaults")
        return BrianConfig()
    end
    
    try
        config_data = TOML.parsefile(config_path)
        
        # Parse communication config
        comm_data = get(config_data, "communication", Dict())
        communication = CommunicationConfig(
            stt_provider = Symbol(get(comm_data, "stt_provider", "openai")),
            stt_api_key = get(comm_data, "stt_api_key", ""),
            tts_provider = Symbol(get(comm_data, "tts_provider", "elevenlabs")),
            tts_api_key = get(comm_data, "tts_api_key", ""),
            tts_voice_id = get(comm_data, "tts_voice_id", "21m00Tcm4TlvDq8ikWAM"),
            vlm_provider = Symbol(get(comm_data, "vlm_provider", "openai")),
            vlm_api_key = get(comm_data, "vlm_api_key", "")
        )
        
        # Parse OpenClaw config
        claw_data = get(config_data, "openclaw", Dict())
        openclaw = OpenClawConfig(
            endpoint = get(claw_data, "endpoint", "http://localhost:3000"),
            api_key = get(claw_data, "api_key", ""),
            timeout = get(claw_data, "timeout", 30.0),
            retry_count = get(claw_data, "retry_count", 3),
            kernel_veto_enabled = get(claw_data, "kernel_veto_enabled", true)
        )
        
        # Parse LLM config
        llm_data = get(config_data, "llm", Dict())
        llm = LLMConfig(
            provider = Symbol(get(llm_data, "provider", "openai")),
            api_key = get(llm_data, "api_key", ""),
            model = get(llm_data, "model", "gpt-4"),
            temperature = Float32(get(llm_data, "temperature", 0.7)),
            max_tokens = get(llm_data, "max_tokens", 2000)
        )
        
        return BrianConfig(
            communication = communication,
            openclaw = openclaw,
            llm = llm,
            vector_store_path = get(config_data, "vector_store_path", "./brian_vector_store.json"),
            wake_word = get(config_data, "wake_word", "Brian"),
            demo_mode = get(config_data, "demo_mode", true)
        )
    catch e
        @error string("Failed to load config: ", e)
        return BrianConfig()
    end
end

# ============================================================================
# BRIAN SYSTEM STATE
# ============================================================================

"""
    BrianState - Runtime state of Brian
"""
mutable struct BrianState
    is_active::Bool
    current_cycle::Int
    last_user_input::String
    last_response::String
    trust_level::TrustLevel
    phrase_cache::PhraseCache
    vector_store::VectorStore
    kernel_state::Any  # Kernel.KernelState if available
    initialized::Bool
    
    function BrianState()
        new(
            false,
            0,
            "",
            "",
            TRUST_STANDARD,
            PhraseCache(100),
            VectorStore(),
            nothing,
            false
        )
    end
end

"""
    BrianSystem - Complete Brian system
"""
mutable struct BrianSystem
    config::BrianConfig
    state::BrianState
    
    function BrianSystem(config::BrianConfig)
        state = BrianState()
        new(config, state)
    end
end

# ============================================================================
# INITIALIZATION
# ============================================================================

"""
    initialize_brian! - Initialize the Brian system
"""
function initialize_brian!(config_path::String = "./config.toml")::BrianSystem
    println("="^60)
    println("  INITIALIZING BRIAN - Voice-Activated Personal Assistant")
    println("="^60)
    
    # Load configuration
    config = load_config(config_path)
    
    # Create system
    system = BrianSystem(config)
    
    # Initialize vector store
    if isfile(config.vector_store_path)
        system.state.vector_store = load_from_file(config.vector_store_path)
    else
        system.state.vector_store = VectorStore()
    end
    
    # Initialize phrase cache with common phrases
    warm_cache!(system.state.phrase_cache, COMMON_PHRASES, config.communication)
    
    # Test OpenClaw connection
    println("[BRIAN] Testing OpenClaw connection...")
    connected, msg = test_connection(config.openclaw)
    if connected
        println("  ✓ OpenClaw: Connected")
    else
        println(string("  ⚠ OpenClaw: ", msg))
    end
    
    # Mark as initialized
    system.state.initialized = true
    
    println("✓ Brian initialized successfully")
    println(string("  - Wake word: ", config.wake_word))
    println(string("  - Demo mode: ", config.demo_mode))
    println("="^60)
    
    return system
end

# ============================================================================
# CORE LIFECYCLE
# ============================================================================

"""
    wait_for_wake_word - Wait for the wake word to be detected
    Returns true when wake word is detected
"""
function wait_for_wake_word(
    system::BrianSystem;
    timeout_seconds::Float64 = 60.0
)::Bool
    
    println("[EARS] Waiting for wake word '$(system.config.wake_word)'...")
    
    if system.config.demo_mode
        # In demo mode, simulate wake word detection after a short delay
        sleep(1.0)
        return true
    end
    
    # In real implementation, this would use keyword detection
    # For now, we'll wait for audio input and check for wake word
    start_time = time()
    
    while (time() - start_time) < timeout_seconds
        # In real implementation: check for wake word in audio stream
        # For now, we'll use a simple timeout
        sleep(0.1)
    end
    
    return false
end

"""
    listen - Listen for user input (the "Ears")
"""
function listen(system::BrianSystem)::String
    println("[EARS] Listening for input...")
    
    # Use CommunicationBridge to listen and transcribe
    voice_input = listen_and_transcribe(
        system.config.communication;
        timeout_seconds = 30.0
    )
    
    if voice_input.transcript !== nothing && !isempty(voice_input.transcript)
        println(string("[EARS] Heard: ", voice_input.transcript))
        return voice_input.transcript
    end
    
    return ""
end

"""
    decide - Use Adaptive Kernel to make a decision (the "Conscience")
"""
function decide(system::BrianSystem, user_input::String)
    println("[KERNEL] Processing decision...")
    
    # In the full implementation, this would use the actual Kernel
    # For now, we'll use a simple scoring approach
    
    # Parse user intent using LLM
    intent = _parse_intent(system, user_input)
    
    # Score the action using kernel's formula: score = priority * (reward - risk)
    priority = intent.priority
    reward = intent.predicted_reward
    risk = intent.risk
    score = priority * (reward - risk)
    
    decision = Dict{String, Any}(
        "intent" => intent,
        "score" => score,
        "action" => intent.action,
        "parameters" => intent.parameters
    )
    
    println(string("[KERNEL] Decision score: ", round(score; digits=2)))
    
    return decision
end

"""
    Intent - Parsed user intent
"""
struct Intent
    action::String
    parameters::Dict{String, Any}
    priority::Float32
    predicted_reward::Float32
    risk::Float32
end

"""
    _parse_intent - Parse user input into an actionable intent
"""
function _parse_intent(system::BrianSystem, user_input::String)::Intent
    # Simple keyword-based intent parsing
    # In full implementation, this would use the LLM
    
    input_lower = lowercase(user_input)
    
    # Calendar actions
    if occursin("calendar", input_lower) || occursin("schedule", input_lower)
        if occursin("add", input_lower) || occursin("create", input_lower) || occursin("new", input_lower)
            return Intent(
                "google_calendar_insert",
                Dict{String, Any}("title" => _extract_title(user_input)),
                0.8f0, 0.7f0, 0.3f0
            )
        else
            return Intent(
                "google_calendar_list",
                Dict{String, Any}("max_results" => 10),
                0.5f0, 0.3f0, 0.1f0
            )
        end
    end
    
    # Email actions
    if occursin("email", input_lower) || occursin("mail", input_lower) || occursin("gmail", input_lower)
        if occursin("send", input_lower)
            return Intent(
                "gmail_send",
                Dict{String, Any}(
                    "to" => _extract_email(user_input),
                    "subject" => _extract_subject(user_input),
                    "body" => user_input
                ),
                0.9f0, 0.8f0, 0.6f0
            )
        else
            return Intent(
                "gmail_read",
                Dict{String, Any}("max_results" => 5),
                0.5f0, 0.3f0, 0.2f0
            )
        end
    end
    
    # System info
    if occursin("system", input_lower) || occursin("cpu", input_lower) || occursin("memory", input_lower)
        return Intent(
            "system_info",
            Dict{String, Any}(),
            0.6f0, 0.5f0, 0.1f0
        )
    end
    
    # Search
    if occursin("search", input_lower) || occursin("find", input_lower) || occursin("look up", input_lower)
        query = _extract_query(user_input)
        return Intent(
            "web_search",
            Dict{String, Any}("query" => query, "num_results" => 5),
            0.7f0, 0.6f0, 0.1f0
        )
    end
    
    # File operations
    if occursin("read", input_lower) || occursin("show", input_lower)
        return Intent(
            "file_read",
            Dict{String, Any}("path" => _extract_path(user_input)),
            0.5f0, 0.4f0, 0.1f0
        )
    end
    
    if occursin("write", input_lower) || occursin("save", input_lower) || occursin("create", input_lower)
        return Intent(
            "file_write",
            Dict{String, Any}("path" => _extract_path(user_input), "content" => user_input),
            0.6f0, 0.5f0, 0.5f0
        )
    end
    
    # Notification
    if occursin("notify", input_lower) || occursin("tell me", input_lower) || occursin("alert", input_lower)
        return Intent(
            "notification_send",
            Dict{String, Any}("title" => "Brian", "message" => user_input),
            0.4f0, 0.3f0, 0.1f0
        )
    end
    
    # Help/default
    return Intent(
        "help",
        Dict{String, Any}("query" => user_input),
        0.3f0, 0.2f0, 0.0f0
    )
end

# Simple extraction helpers (in full implementation, use LLM)
_extract_title(s::String) = "New Event"
_extract_email(s::String) = ""
_extract_subject(s::String) = "Email"
_extract_path(s::String) = "./"
_extract_query(s::String) = s

"""
    select_action - Use Itheris brain to select the best action
"""
function select_action(system::BrianSystem, decision::Dict{String, Any})::Dict{String, Any}
    println("[BRAIN] Selecting action...")
    
    # In full implementation, this would use the Itheris neural network
    # For now, use the decision directly
    action = decision["action"]
    parameters = decision["parameters"]
    
    println(string("[BRAIN] Selected action: ", action))
    
    return Dict(
        "tool" => action,
        "parameters" => parameters,
        "requires_confirmation" => _requires_confirmation(action)
    )
end

function _requires_confirmation(action::String)::Bool
    high_risk_actions = ["gmail_send", "file_write", "system_shell"]
    return action in high_risk_actions
end

"""
    execute - Execute an action via OpenClaw or internally
"""
function execute(system::BrianSystem, action::Dict{String, Any})
    println("[EXECUTOR] Executing action...")
    
    tool_name = action["tool"]
    parameters = action["parameters"]
    
    # Check if it's an internal action
    if tool_name == "help"
        return _execute_help(system, parameters)
    end
    
    # Use OpenClaw to execute
    result = call_tool(system.config.openclaw, tool_name, parameters)
    
    if result.success
        println("[EXECUTOR] Action completed successfully")
    else
        println(string("[EXECUTOR] Action failed: ", result.error))
    end
    
    return result
end

function _execute_help(system::BrianSystem, parameters::Dict{String, Any})::Dict{String, Any}
    query = get(parameters, "query", "")
    
    # Use vector memory to find relevant knowledge
    results = search(system.state.vector_store, query, k=3)
    
    if isempty(results)
        return Dict(
            "success" => true,
            "result" => "I can help you with calendar events, email, system info, web searches, and file operations. Just ask!"
        )
    end
    
    return Dict(
        "success" => true,
        "result" => "Based on my knowledge: $(join([r.content for r in results], " "))"
    )
end

"""
    speak - Generate voice output (the "Mouth")
"""
function speak(system::BrianSystem, text::String)
    println(string("[MOUTH] Speaking: ", text))
    
    # Call CommunicationBridge.speak explicitly to avoid recursion
    voice_output = CommunicationBridge.speak(text, system.config.communication; use_cache = true)
    
    # In full implementation, play the audio
    # For now, just log it
    
    return voice_output
end

"""
    dream - Update neural weights based on result (Itheris learning)
"""
function dream(system::BrianSystem, result::ClawResult)
    println("[BRAIN] Dreaming (learning from result)...")
    
    # In full implementation, this would:
    # 1. Extract features from the result
    # 2. Update neural network weights via backpropagation
    # 3. Store the experience in memory
    
    # For now, just log it
    if result.success
        println("[BRAIN] Positive outcome - reinforcing learned patterns")
    else
        println("[BRAIN] Negative outcome - adjusting decision model")
    end
    
    # Store in vector memory for future reference
    memory_entry = SemanticEntry(
        uuid4(),
        string("Action result: ", result.success ? "success" : "failure"),
        [0.5f0],  # Simple embedding
        [:result, :experience],
        "system"
    )
    store!(system.state.vector_store, memory_entry)
    
    # Save vector store periodically
    save_to_file(system.state.vector_store, system.config.vector_store_path)
end

# ============================================================================
# MAIN LOOP
# ============================================================================

"""
    run_brian! - Main execution loop for Brian
"""
function run_brian!(system::BrianSystem; max_cycles::Int = 0)
    println("\n" * "="^60)
    println("  BRIAN IS NOW ACTIVE")
    println("="^60 * "\n")
    
    system.state.is_active = true
    cycle_count = 0
    
    try
        while system.state.is_active
            cycle_count += 1
            system.state.current_cycle = cycle_count
            
            println(string("\n[CYCLE ", cycle_count, "]"))
            
            # 1. Wait for wake word
            if !wait_for_wake_word(system)
                println("[BRIAN] Wake word timeout, continuing...")
                continue
            end
            
            # Acknowledge wake word
            speak(system, "On it, Brian")
            
            # 2. Listen for input
            user_input = listen(system)
            if isempty(user_input)
                speak(system, "I didn't catch that. Could you repeat?")
                continue
            end
            system.state.last_user_input = user_input
            
            # 3. Decide (Kernel)
            decision = decide(system, user_input)
            
            # 4. Select action (Brain)
            action = select_action(system, decision)
            
            # 5. Execute
            result = execute(system, action)
            
            # 6. Speak result
            response_text = _format_response(result)
            speak(system, response_text)
            system.state.last_response = response_text
            
            # 7. Dream (learn)
            dream(system, result)
            
            # Check for exit condition
            if max_cycles > 0 && cycle_count >= max_cycles
                println("[BRIAN] Reached maximum cycles, shutting down...")
                break
            end
            
            # Check for quit command
            if occursin(lowercase(user_input), "quit") || 
               occursin(lowercase(user_input), "exit") ||
               occursin(lowercase(user_input), "goodbye")
                println("[BRIAN] User requested shutdown")
                break
            end
        end
    catch e
        println(string("[BRIAN] Error: ", e))
        @error string("Brian error: ", e) exception=(e, catch_backtrace())
    finally
        shutdown_brian!(system)
    end
end

function _format_response(result::ClawResult)::String
    if result.success
        if result.result === nothing
            return "Done"
        elseif typeof(result.result) <: AbstractString
            return string(result.result)[1:min(200, length(string(result.result)))]
        else
            return "Completed successfully"
        end
    else
        return string("Sorry, I couldn't do that: ", result.error)
    end
end

"""
    shutdown_brian! - Clean shutdown
"""
function shutdown_brian!(system::BrianSystem)
    println("\n[BRIAN] Shutting down...")
    
    # Save vector store
    save_to_file(system.state.vector_store, system.config.vector_store_path)
    
    system.state.is_active = false
    
    println("[BRIAN] Goodbye!")
end

# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

"""
    single_turn - Run a single interaction (useful for testing)
"""
function single_turn(system::BrianSystem, user_input::String)::String
    # Skip wake word for single turn
    system.state.last_user_input = user_input
    
    # Decide
    decision = decide(system, user_input)
    
    # Select action
    action = select_action(system, decision)
    
    # Execute
    result = execute(system, action)
    
    # Format response
    response_text = _format_response(result)
    
    # Dream
    dream(system, result)
    
    system.state.last_response = response_text
    
    return response_text
end

# ============================================================================
# ENTRY POINT
# ============================================================================

"""
    main - Entry point for Brian
"""
function main(args::Vector{String} = ARGS)
    # Parse arguments
    config_path = "./config.toml"
    max_cycles = 0  # 0 = infinite
    
    for (i, arg) in enumerate(args)
        if arg == "--config" && i < length(args)
            config_path = args[i + 1]
        elseif arg == "--cycles" && i < length(args)
            max_cycles = parse(Int, args[i + 1])
        elseif arg == "--help"
            println("Brian - Voice-Activated Personal Assistant")
            println("Usage: julia Brian.jl [options]")
            println("Options:")
            println("  --config <path>   Configuration file (default: ./config.toml)")
            println("  --cycles <n>      Maximum cycles to run (0 = infinite)")
            println("  --help            Show this help message")
            return
        end
    end
    
    # Initialize
    system = initialize_brian!(config_path)
    
    # Run main loop
    run_brian!(system; max_cycles = max_cycles)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module Brian
