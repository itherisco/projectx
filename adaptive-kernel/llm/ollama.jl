# llm/ollama.jl - Ollama Local Adapter
# Provides integration with Ollama for local LLM inference
# Supports llama3, mistral, codellama, phi3, and other Ollama models

module OllamaClientModule

using HTTP
using JSON
using Logging
using UUIDs
using Base.Threads: @spawn
using Sockets

# Import from client.jl
include("client.jl")
using ..LLMClientModule: AbstractLLMClient, LLMClient, LLMMessage, LLMResponse, MessageRole
using ..LLMClientModule: SYSTEM, USER, ASSISTANT, TOOL, system_message, user_message, assistant_message
using ..LLMClientModule: messages_to_dicts, create_error_response, get_default_kwargs

export OllamaClient
export DEFAULT_OLLAMA_BASE_URL, DEFAULT_OLLAMA_MODEL
export OLLAMA_MODELS, install_ollama

# ============================================================================
# Constants
# ============================================================================

const DEFAULT_OLLAMA_BASE_URL = "http://localhost:11434"
const DEFAULT_OLLAMA_MODEL = "llama3"

# Popular Ollama models
const OLLAMA_MODELS = Dict(
    # General purpose
    "llama3" => "Meta's Llama 3 - latest general purpose model",
    "llama3:70b" => "Meta's Llama 3 70B - larger version",
    "mistral" => "Mistral AI's Mistral - efficient general purpose",
    "mixtral" => "Mistral AI's Mixtral - mixture of experts",
    
    # Coding
    "codellama" => "Code Llama - specialized for code generation",
    "codellama:70b" => "Code Llama 70B - larger code model",
    "deepseek-coder" => "DeepSeek Coder - code specialized",
    
    # Small/fast models
    "phi3" => "Microsoft Phi-3 - small efficient model",
    "phi3:14b" => "Microsoft Phi-3 14B",
    "gemma" => "Google Gemma - efficient general purpose",
    "gemma:7b" => "Google Gemma 7B",
    
    # Specialized
    "orca-mini" => "Orca Mini - lightweight alternative",
    "neural-chat" => "Neural Chat - optimized for conversation"
)

# ============================================================================
# Client Type
# ============================================================================

"""
    OllamaClient

Client for Ollama local LLM inference.
No API costs - runs models locally on your machine.
"""
mutable struct OllamaClient <: AbstractLLMClient
    base_url::String
    model::String
    timeout::Float64
    headers::Dict{String, String}
    
    function OllamaClient(
        base_url::String=DEFAULT_OLLAMA_BASE_URL,
        model::String=DEFAULT_OLLAMA_MODEL;
        timeout::Float64=120.0  # Longer timeout for local inference
    )
        headers = Dict{String, String}(
            "Content-Type" => "application/json"
        )
        
        new(base_url, model, timeout, headers)
    end
end

# ============================================================================
# API Methods
# ============================================================================

"""
    build_url(client::OllamaClient, path::String) -> String

Build the full API URL for Ollama.
"""
function build_url(client::OllamaClient, path::String)::String
    base = rstrip(client.base_url, '/')
    return "$base$path"
end

"""
    check_ollama_running() -> Bool

Check if Ollama server is running and accessible.
"""
function check_ollama_running(base_url::String=DEFAULT_OLLAMA_BASE_URL)::Bool
    try
        response = HTTP.get("$base_url/api/tags"; timeout=5.0)
        return response.status == 200
    catch e
        return false
    end
end

"""
    make_request(client::OllamaClient, method::String, path::String, body::Dict=Dict()) -> HTTP.Response

Make an HTTP request to the Ollama API.
"""
function make_request(client::OllamaClient, method::String, path::String, body::Dict=Dict())::HTTP.Response
    url = build_url(client, path)
    
    if method == "GET"
        return HTTP.get(url; headers=client.headers, timeout=client.timeout)
    elseif method == "POST"
        json_body = JSON.json(body)
        return HTTP.post(url; headers=client.headers, body=json_body, timeout=client.timeout)
    else
        error("Unsupported HTTP method: $method")
    end
end

"""
    convert_messages_to_ollama_format(messages::Vector{LLMMessage}) -> Vector{Dict{String, Any}}

Convert messages to Ollama's format (different from OpenAI).
"""
function convert_messages_to_ollama_format(messages::Vector{LLMMessage})::Vector{Dict{String, Any}}
    role_map = Dict(
        SYSTEM => "system",
        USER => "user",
        ASSISTANT => "assistant",
        TOOL => "tool"
    )
    
    result = Dict{String, Any}[]
    for msg in messages
        d = Dict{String, Any}(
            "role" => role_map[msg.role],
            "content" => msg.content
        )
        push!(result, d)
    end
    return result
end

"""
    generate(client::OllamaClient, messages::Vector{LLMMessage}; kwargs...) -> LLMResponse

Generate a non-streaming response from Ollama.
"""
function generate(client::OllamaClient, messages::Vector{LLMMessage};
    model::Union{String, Nothing}=nothing,
    temperature::Float64=0.7,
    max_tokens::Int=2000,
    top_p::Float64=0.9,
    stop::Union{Vector{String}, Nothing}=nothing,
    kwargs...
)::LLMResponse
    
    model_name = model !== nothing ? model : client.model
    
    # Convert messages to Ollama format
    ollama_messages = convert_messages_to_ollama_format(messages)
    
    # Build request body
    body = Dict{String, Any}(
        "model" => model_name,
        "messages" => ollama_messages,
        "stream" => false,
        "options" => Dict{String, Any}(
            "temperature" => temperature,
            "num_predict" => max_tokens,
            "top_p" => top_p
        )
    )
    
    if stop !== nothing
        body["options"]["stop"] = stop
    end
    
    try
        response = make_request(client, "POST", "/api/chat", body)
        
        if response.status != 200
            error_msg = String(response.body)
            try
                error_data = JSON.parse(error_msg)
                error_msg = get(error_data, "error", error_msg)
            catch
            end
            return create_error_response("Ollama API error (status $(response.status)): $error_msg", model_name)
        end
        
        data = JSON.parse(String(response.body))
        
        message = get(data, "message", Dict())
        content = get(message, "content", "")
        finish_reason = get(data, "done", true) ? "stop" : "length"
        
        # Extract usage if available (Ollama doesn't always provide this)
        usage = Dict{Symbol, Int}(
            :prompt => get(data, "prompt_eval_count", 0),
            :completion => get(data, "eval_count", 0),
            :total => get(data, "prompt_eval_count", 0) + get(data, "eval_count", 0)
        )
        
        return LLMResponse(content, finish_reason, model_name; usage=usage, raw=data)
        
    catch e
        @error "Ollama request failed" exception=e
        return create_error_response(string(e), model_name)
    end
end

"""
    generate_stream(client::OllamaClient, messages::Vector{LLMMessage}; kwargs...) -> Channel

Generate a streaming response from Ollama.
"""
function generate_stream(client::OllamaClient, messages::Vector{LLMMessage};
    model::Union{String, Nothing}=nothing,
    temperature::Float64=0.7,
    max_tokens::Int=2000,
    top_p::Float64=0.9,
    stop::Union{Vector{String}, Nothing}=nothing,
    kwargs...
)::Channel
    
    model_name = model !== nothing ? model : client.model
    
    ollama_messages = convert_messages_to_ollama_format(messages)
    
    body = Dict{String, Any}(
        "model" => model_name,
        "messages" => ollama_messages,
        "stream" => true,
        "options" => Dict{String, Any}(
            "temperature" => temperature,
            "num_predict" => max_tokens,
            "top_p" => top_p
        )
    )
    
    if stop !== nothing
        body["options"]["stop"] = stop
    end
    
    url = build_url(client, "/api/chat")
    channel = Channel{LLMResponse}(10)
    
    @spawn begin
        content = ""
        try
            json_body = JSON.json(body)
            
            response = HTTP.post(url; headers=client.headers, body=json_body, timeout=client.timeout)
            
            if response.status != 200
                error("API error: status $(response.status)")
            end
            
            # Parse SSE-like stream from Ollama
            body_str = String(response.body)
            lines = split(body_str, '\n')
            
            for line in lines
                line = strip(line)
                if isempty(line)
                    continue
                end
                
                try
                    data = JSON.parse(line)
                    
                    message = get(data, "message", Dict())
                    chunk_content = get(message, "content", "")
                    
                    if !isempty(chunk_content)
                        content *= chunk_content
                        put!(channel, LLMResponse(
                            chunk_content,
                            "length",
                            model_name;
                            raw=data
                        ))
                    end
                    
                    # Check if done
                    if get(data, "done", false)
                        usage = Dict{Symbol, Int}(
                            :prompt => get(data, "prompt_eval_count", 0),
                            :completion => get(data, "eval_count", 0),
                            :total => get(data, "prompt_eval_count", 0) + get(data, "eval_count", 0)
                        )
                        
                        # Send final message
                        put!(channel, LLMResponse(
                            "",
                            "stop",
                            model_name;
                            usage=usage,
                            raw=Dict("done" => true)
                        ))
                        break
                    end
                catch e
                    @debug "Skipping malformed chunk" exception=e
                end
            end
            
        catch e
            @error "Ollama streaming failed" exception=e
            put!(channel, create_error_response(string(e), model_name))
        finally
            close(channel)
        end
    end
    
    return channel
end

"""
    list_models(client::OllamaClient) -> Vector{String}

List available models from Ollama.
"""
function list_models(client::OllamaClient)::Vector{String}
    try
        response = make_request(client, "GET", "/api/tags")
        
        if response.status != 200
            return [client.model]
        end
        
        data = JSON.parse(String(response.body))
        models_data = get(data, "models", [])
        
        models = String[]
        for model_data in models_data
            name = get(model_data, "name", "")
            if !isempty(name)
                # Remove size suffix (e.g., ":7b" -> "")
                push!(models, first(split(name, ':')))
            end
        end
        
        return isempty(models) ? [client.model] : models
        
    catch e
        @warn "Failed to list Ollama models" exception=e
        return [client.model]
    end
end

"""
    is_available(client::OllamaClient) -> Bool

Check if Ollama is running and accessible.
"""
function is_available(client::OllamaClient)::Bool
    return check_ollama_running(client.base_url)
end

# ============================================================================
# Model Management
# ============================================================================

"""
    pull_model(client::OllamaClient, model::String) -> Bool

Pull/download a model from Ollama registry.
"""
function pull_model(client::OllamaClient, model::String)::Bool
    @info "Pulling Ollama model: $model"
    
    body = Dict{String, Any}(
        "name" => model,
        "stream" => true
    )
    
    try
        url = build_url(client, "/api/pull")
        response = HTTP.post(url; headers=client.headers, body=JSON.json(body), timeout=300.0)
        
        return response.status == 200
    catch e
        @error "Failed to pull model" model=model exception=e
        return false
    end
end

"""
    get_model_info(client::OllamaClient, model::String) -> Dict{String, Any}

Get information about a specific model.
"""
function get_model_info(client::OllamaClient, model::String)::Dict{String, Any}
    try
        response = make_request(client, "GET", "/api/tags")
        data = JSON.parse(String(response.body))
        
        models_data = get(data, "models", [])
        for model_data in models_data
            if startswith(get(model_data, "name", ""), model)
                return Dict{String, Any}(
                    "name" => get(model_data, "name", ""),
                    "size" => get(model_data, "size", 0),
                    "modified_at" => get(model_data, "modified_at", "")
                )
            end
        end
        
        return Dict{String, Any}()
    catch e
        return Dict{String, Any}()
    end
end

# ============================================================================
# Factory Functions
# ============================================================================

"""
    create_ollama_client(; base_url=DEFAULT_OLLAMA_BASE_URL, model=DEFAULT_OLLAMA_MODEL, kwargs...) -> OllamaClient

Create an Ollama client with default or custom settings.
"""
function create_ollama_client(;
    base_url::String=DEFAULT_OLLAMA_BASE_URL,
    model::String=DEFAULT_OLLAMA_MODEL,
    kwargs...
)::OllamaClient
    return OllamaClient(base_url, model; kwargs...)
end

"""
    create_ollama_client_auto() -> Union{OllamaClient, Nothing}

Try to create an Ollama client, returns nothing if Ollama is not available.
"""
function create_ollama_client_auto()::Union{OllamaClient, Nothing}
    if check_ollama_running()
        return create_ollama_client()
    else
        @warn "Ollama is not running. Start it with: ollama serve"
        return nothing
    end
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
    get_default_model() -> String

Get the default Ollama model.
"""
function get_default_model()::String
    return DEFAULT_OLLAMA_MODEL
end

"""
    install_ollama_instructions() -> String

Get instructions for installing Ollama.
"""
function install_ollama_instructions()::String
    return """
    # Install Ollama (macOS/Linux)
    curl -fsSL https://ollama.com/install.sh | sh
    
    # Or on Linux:
    # curl -fsSL https://ollama.com/install.sh | sh
    
    # Start Ollama server
    ollama serve
    
    # Pull a model
    ollama pull llama3
    
    # Verify it's running
    curl http://localhost:11434/api/tags
    """
end

end # module
