# jarvis/src/llm/LLMBridge.jl - Asynchronous LLM Bridge for GPT-4o/Claude 3.5
# Parses natural language into structured Goal objects and 12D PerceptionVector

module LLMBridge

using HTTP
using JSON
using Dates
using UUIDs
using Base.Threads: @spawn, Channel

export 
    LLMConfig,
    LLMResponse,
    parse_user_intent,
    generate_response,
    build_perception_vector_from_nl,
    retrieve_context,
    async_llm_request

# Import Jarvis types from parent module
using ..JarvisTypes

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    LLMConfig - Configuration for LLM provider
    SECURITY: Requires valid API key at initialization
"""
struct LLMConfig
    provider::Symbol  # :openai, :anthropic
    api_key::String
    model::String
    max_tokens::Int
    temperature::Float32
    base_url::String
    timeout::Int  # HTTP timeout in seconds
    
    function LLMConfig(;
        provider::Symbol = :openai,
        api_key::String = get(ENV, "JARVIS_LLM_API_KEY", ""),
        model::String = "gpt-4o",
        max_tokens::Int = 2048,
        temperature::Float32 = 0.7f0,
        timeout::Int = 30  # Default 30 second timeout
    )
        # Allow empty API key for demo mode, but warn about it
        if isempty(api_key)
            @warn "LLM API key not set. Running in demo mode. Set JARVIS_LLM_API_KEY environment variable for full functionality."
        end
        
        if provider == :openai
            base_url = "https://api.openai.com/v1"
        elseif provider == :anthropic
            base_url = "https://api.anthropic.com/v1"
        else
            error("Unknown LLM provider: $provider")
        end
        new(provider, api_key, model, max_tokens, temperature, base_url, timeout)
    end
end

# ============================================================================
# RESPONSE TYPES
# ============================================================================

"""
    LLMResponse - Parsed response from LLM
"""
struct LLMResponse
    raw_content::String
    parsed_goal::Union{JarvisGoal, Nothing}
    intent::String
    entities::Dict{String, Any}
    confidence::Float32
    suggested_actions::Vector{String}
    context_needed::Vector{Symbol}  # :preferences, :conversations, :knowledge
    timestamp::DateTime
end

# ============================================================================
# PROMPTS
# ============================================================================

const INTENT_PARSING_PROMPT = """
You are Jarvis, an advanced neuro-symbolic autonomous assistant. Parse the user's request into a structured goal.

Respond with JSON in this exact format:
{
    "intent": "one of: task_execution, information_query, system_observation, planning, confirmation_request, proactive_suggestion",
    "entities": {
        "target": "what the user wants to affect (file, process, system, etc.)",
        "action": "the action to perform",
        "parameters": "any specific parameters or constraints",
        "priority": "critical, high, medium, low, background"
    },
    "confidence": 0.0-1.0,
    "requires_confirmation": true/false,
    "context_needed": ["preferences", "conversations", "knowledge", "none"]
}

User request: {user_input}
"""

const RESPONSE_GENERATION_PROMPT = """
You are Jarvis, a helpful and intelligent assistant. Generate a natural, concise response.

Context:
- Recent conversation history: {conversation_history}
- Relevant user preferences: {preferences}
- System state: {system_state}

User request: {user_input}
Jarvis's action: {action_taken}
Result: {result}

Generate a helpful response:
"""

# ============================================================================
# HTTP HELPERS
# ============================================================================

"""
    async_llm_request - Make async request to LLM API
"""
function async_llm_request(
    config::LLMConfig,
    prompt::String;
    channel::Channel{String} = Channel{String}(1)
)::Task
    return @spawn begin
        try
            if config.provider == :openai
                response = _openai_request(config, prompt)
            elseif config.provider == :anthropic
                response = _anthropic_request(config, prompt)
            else
                error("Unknown provider: $(config.provider)")
            end
            put!(channel, response)
        catch e
            put!(channel, "ERROR: $(string(e))")
        end
    end
end

function _openai_request(config::LLMConfig, prompt::String)::String
    # SECURITY: Mask API key in logs
    headers = [
        "Authorization" => "Bearer $(config.api_key)",
        "Content-Type" => "application/json"
    ]
    
    body = JSON.json(Dict(
        "model" => config.model,
        "messages" => [
            Dict("role" => "system", "content" => "You are Jarvis, an AI assistant."),
            Dict("role" => "user", "content" => prompt)
        ],
        "max_tokens" => config.max_tokens,
        "temperature" => config.temperature
    ))
    
    # Use timeout from config
    response = HTTP.post(
        "$(config.base_url)/chat/completions", 
        headers, 
        body;
        timeout=config.timeout
    )
    data = JSON.parse(String(response.body))
    return data["choices"][1]["message"]["content"]
end

function _anthropic_request(config::LLMConfig, prompt::String)::String
    headers = [
        "x-api-key" => config.api_key,
        "anthropic-version" => "2023-06-01",
        "Content-Type" => "application/json"
    ]
    
    body = JSON.json(Dict(
        "model" => config.model,
        "max_tokens" => config.max_tokens,
        "temperature" => config.temperature,
        "messages" => [
            Dict("role" => "user", "content" => prompt)
        ]
    ))
    
    # Use timeout from config
    response = HTTP.post(
        "$(config.base_url)/messages", 
        headers, 
        body;
        timeout=config.timeout
    )
    data = JSON.parse(String(response.body))
    return data["content"][1]["text"]
end

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

"""
    parse_user_intent - Parse natural language into JarvisGoal
"""
function parse_user_intent(
    user_input::String,
    config::LLMConfig;
    conversation_history::Vector{ConversationEntry} = ConversationEntry[]
)::LLMResponse
    # Build context from history
    history_text = ""
    if !isempty(conversation_history)
        recent = conversation_history[max(1, end-4):end]
        history_text = join([
            "User: $(c.user_message)\nJarvis: $(c.jarvis_response)"
            for c in recent
        ], "\n")
    end
    
    # Build prompt with context
    prompt = replace(INTENT_PARSING_PROMPT, "{user_input}" => user_input)
    if !isempty(history_text)
        prompt = "Recent conversation:\n$history_text\n\n$prompt"
    end
    
    # Make request (API key is guaranteed to be present due to LLMConfig validation)
    if config.provider == :openai
        raw = _openai_request(config, prompt)
    else
        raw = _anthropic_request(config, prompt)
    end
    
    return _parse_llm_response(raw, user_input)
end

function _mock_intent_parse(user_input::String)::LLMResponse
    # Simple keyword-based parsing for testing without API key
    input_lower = lowercase(user_input)
    
    intent = "task_execution"
    target = "unknown"
    priority = "medium"
    
    if occursin("check", input_lower) || occursin("show", input_lower) || occursin("what", input_lower)
        intent = "information_query"
    elseif occursin("schedule", input_lower) || occursin("plan", input_lower)
        intent = "planning"
    elseif occursin("confirm", input_lower) || occursin("approve", input_lower)
        intent = "confirmation_request"
    end
    
    if occursin("cpu", input_lower) || occursin("memory", input_lower) || occursin("system", input_lower)
        target = "system"
    elseif occursin("file", input_lower)
        target = "filesystem"
    end
    
    if occursin("urgent", input_lower) || occursin("asap", input_lower)
        priority = "high"
    elseif occursin("whenever", input_lower) || occursin("later", input_lower)
        priority = "low"
    end
    
    entities = Dict{String, Any}(
        "target" => target,
        "action" => "analyze",
        "parameters" => user_input,
        "priority" => priority
    )
    
    # Create goal with 12D vector
    target_state = _keyword_to_target_state(target, priority)
    
    return LLMResponse(
        user_input,
        JarvisGoal(user_input, target_state, _priority_str_to_enum(priority)),
        intent,
        entities,
        0.85f0,
        String[],
        Symbol[:conversations],
        now()
    )
end

function _priority_str_to_enum(p::String)::GoalPriority
    p_lower = lowercase(p)
    p_lower == "critical" && return PRIORITY_CRITICAL
    p_lower == "high" && return PRIORITY_HIGH
    p_lower == "low" && return PRIORITY_LOW
    p_lower == "background" && return PRIORITY_BACKGROUND
    return PRIORITY_MEDIUM
end

function _keyword_to_target_state(target::String, priority::String)::Vector{Float32}
    # Map keywords to 12D perception vector target state
    base = fill(0.5f0, 12)
    
    if target == "system"
        base[1] = 0.8f0  # cpu_load
        base[2] = 0.8f0  # memory_usage
    elseif target == "filesystem"
        base[7] = 0.8f0  # file_count
        base[8] = 0.8f0  # change_rate
    end
    
    return base
end

function _parse_llm_response(raw::String, user_input::String)::LLMResponse
    # Parse JSON from LLM response
    try
        data = JSON.parse(raw)
        
        intent = get(data, "intent", "unknown")
        entities = get(data, "entities", Dict{String, Any}())
        confidence = Float32(get(data, "confidence", 0.5))
        requires_confirm = get(data, "requires_confirmation", false)
        
        # Extract priority
        priority_str = get(entities, "priority", "medium")
        priority = _priority_str_to_enum(priority_str)
        
        # Build target state from entities
        target_state = _entities_to_target_state(entities)
        
        goal = JarvisGoal(user_input, target_state, priority)
        
        context_needed = Symbol[]
        for c in get(data, "context_needed", ["none"])
            push!(context_needed, Symbol(c))
        end
        
        return LLMResponse(
            user_input,
            goal,
            intent,
            entities,
            confidence,
            String[],
            context_needed,
            now()
        )
    catch e
        # Fallback if parsing fails
        return LLMResponse(
            user_input,
            nothing,
            "unknown",
            Dict{String, Any}("raw" => raw),
            0.0f0,
            String[],
            Symbol[:conversations],
            now()
        )
    end
end

function _entities_to_target_state(entities::Dict{String, Any})::Vector{Float32}
    target = get(entities, "target", "unknown")
    action = get(entities, "action", "analyze")
    
    base = fill(0.5f0, 12)
    
    # Map action/target to appropriate dimensions
    if target == "system"
        base[1:4] .= 0.7f0  # System metrics
    elseif target == "filesystem"
        base[7:8] .= 0.7f0  # File system
    elseif target == "security"
        base[5:6] .= 0.7f0  # Security
    end
    
    return base
end

"""
    generate_response - Generate natural language response
"""
function generate_response(
    user_input::String,
    action_taken::String,
    result::Dict{String, Any},
    config::LLMConfig;
    conversation_history::Vector{ConversationEntry} = ConversationEntry[],
    preferences::Vector{UserPreference} = UserPreference[],
    system_state::Dict{String, Any} = Dict()
)::String
    # Build context strings
    history_text = isempty(conversation_history) ? "No recent context" : 
        join([c.user_message for c in conversation_history[max(1,end-2):end]], " | ")
    
    pref_text = isempty(preferences) ? "No specific preferences" :
        join(["$(p.key): $(p.value)" for p in preferences[1:min(3,end)]], ", ")
    
    state_text = isempty(system_state) ? "System nominal" : 
        join(["$k: $v" for (k,v) in system_state], ", ")
    
    prompt = replace(RESPONSE_GENERATION_PROMPT, 
        "{user_input}" => user_input,
        "{conversation_history}" => history_text,
        "{preferences}" => pref_text,
        "{system_state}" => state_text,
        "{action_taken}" => action_taken,
        "{result}" => JSON.json(result)
    )
    
    # API key is guaranteed to be present
    if config.provider == :openai
        return _openai_request(config, prompt)
    else
        return _anthropic_request(config, prompt)
    end
end

function _mock_response(action::String, result::Dict{String, Any})::String
    success = get(result, "success", false)
    if success
        return "I've completed that task. $(get(result, "message", "Done."))"
    else
        return "I attempted $(action) but encountered an issue: $(get(result, "error", "Unknown error"))"
    end
end

"""
    build_perception_vector_from_nl - Extract 12D vector from system description
"""
function build_perception_vector_from_nl(
    system_description::Dict{String, Any}
)::PerceptionVector
    # Extract values with defaults
    cpu = Float32(get(system_description, "cpu_load", 0.5))
    mem = Float32(get(system_description, "memory_usage", 0.5))
    disk = Float32(get(system_description, "disk_io", 0.5))
    net = Float32(get(system_description, "network_latency", 0.5))
    
    severity = Float32(get(system_description, "overall_severity", 0.0))
    threats = Float32(get(system_description, "threat_count", 0.0))
    
    files = Float32(get(system_description, "file_count", 0.5))
    changes = Float32(get(system_description, "change_rate", 0.5))
    
    procs = Float32(get(system_description, "process_count", 0.5))
    energy = Float32(get(system_description, "energy_level", 0.9))
    conf = Float32(get(system_description, "confidence", 0.7))
    activity = Float32(get(system_description, "user_activity_level", 0.5))
    
    return PerceptionVector(
        cpu, mem, disk, net,
        severity, threats,
        files, changes,
        procs, energy, conf, activity
    )
end

"""
    retrieve_context - Get relevant context from vector store for RAG
"""
function retrieve_context(
    query::String,
    vector_store::Any;  # VectorStore type
    max_results::Int = 5,
    collection::Symbol = :all
)::Vector{SemanticEntry}
    # This will be implemented in VectorMemory module
    # Placeholder for now
    return SemanticEntry[]
end

end # module LLMBridge
