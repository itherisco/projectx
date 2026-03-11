# llm/openai.jl - OpenAI Adapter
# Provides OpenAI API integration with support for GPT-4, GPT-4o, GPT-4o-mini

module OpenAIClientModule

using HTTP
using JSON
using Logging
using UUIDs
using Base.Threads: @spawn

# Import from client.jl
include("client.jl")
using ..LLMClientModule: AbstractLLMClient, LLMClient, LLMMessage, LLMResponse, MessageRole
using ..LLMClientModule: SYSTEM, USER, ASSISTANT, TOOL, system_message, user_message, assistant_message
using ..LLMClientModule: messages_to_dicts, create_error_response, get_default_kwargs

export OpenAIClient, OpenAIChatClient
export DEFAULT_OPENAI_MODEL, GPT4_MODELS, GPT4O_MODELS

# ============================================================================
# Constants
# ============================================================================

# Default models
const DEFAULT_OPENAI_MODEL = "gpt-4o"
const GPT4_MODELS = ["gpt-4", "gpt-4-32k", "gpt-4-turbo", "gpt-4-turbo-preview"]
const GPT4O_MODELS = ["gpt-4o", "gpt-4o-mini", "gpt-4o-2024-05-13", "gpt-4o-mini-2024-07-18"]
const GPT35_MODELS = ["gpt-3.5-turbo", "gpt-3.5-turbo-0125"]

# Default endpoints
const DEFAULT_OPENAI_BASE_URL = "https://api.openai.com/v1"
const DEFAULT_OPENAI_API_PATH = "/chat/completions"

# ============================================================================
# Client Types
# ============================================================================

"""
    OpenAIClient

Client for OpenAI's Chat Completions API.
Supports GPT-4, GPT-4o, GPT-4o-mini, and OpenAI-compatible APIs.
"""
mutable struct OpenAIClient <: AbstractLLMClient
    api_key::String
    base_url::String
    model::String
    organization::Union{String, Nothing}
    headers::Dict{String, String}
    timeout::Float64
    
    function OpenAIClient(
        api_key::String;
        base_url::String=DEFAULT_OPENAI_BASE_URL,
        model::String=DEFAULT_OPENAI_MODEL,
        organization::Union{String, Nothing}=nothing,
        timeout::Float64=60.0
    )
        headers = Dict{String, String}(
            "Content-Type" => "application/json",
            "Authorization" => "Bearer $api_key"
        )
        if organization !== nothing
            headers["OpenAI-Organization"] = organization
        end
        
        new(api_key, base_url, model, organization, headers, timeout)
    end
end

# Alias for backward compatibility
const OpenAIChatClient = OpenAIClient

# ============================================================================
# API Methods
# ============================================================================

"""
    build_url(client::OpenAIClient, path::String) -> String

Build the full API URL.
"""
function build_url(client::OpenAIClient, path::String)::String
    base = rstrip(client.base_url, '/')
    return "$base$path"
end

"""
    make_request(client::OpenAIClient, method::String, path::String, body::Dict=Dict()) -> HTTP.Response

Make an HTTP request to the OpenAI API.
"""
function make_request(client::OpenAIClient, method::String, path::String, body::Dict=Dict())::HTTP.Response
    url = build_url(client, path)
    
    headers = copy(client.headers)
    
    if method == "GET"
        return HTTP.get(url; headers=headers, timeout=client.timeout)
    elseif method == "POST"
        json_body = JSON.json(body)
        return HTTP.post(url; headers=headers, body=json_body, timeout=client.timeout)
    else
        error("Unsupported HTTP method: $method")
    end
end

"""
    generate(client::OpenAIClient, messages::Vector{LLMMessage}; kwargs...) -> LLMResponse

Generate a non-streaming response from OpenAI.
"""
function generate(client::OpenAIClient, messages::Vector{LLMMessage}; 
    model::Union{String, Nothing}=nothing,
    temperature::Float64=0.7,
    max_tokens::Int=2000,
    top_p::Float64=1.0,
    frequency_penalty::Float64=0.0,
    presence_penalty::Float64=0.0,
    stop::Union{Vector{String}, Nothing}=nothing,
    kwargs...
)::LLMResponse
    
    # Use provided model or fall back to client default
    model_name = model !== nothing ? model : client.model
    
    # Build request body
    body = Dict{String, Any}(
        "model" => model_name,
        "messages" => messages_to_dicts(messages),
        "temperature" => temperature,
        "max_tokens" => max_tokens,
        "top_p" => top_p,
        "frequency_penalty" => frequency_penalty,
        "presence_penalty" => presence_penalty,
        "stream" => false
    )
    
    if stop !== nothing
        body["stop"] = stop
    end
    
    try
        response = make_request(client, "POST", DEFAULT_OPENAI_API_PATH, body)
        
        if response.status != 200
            error_msg = String(response.body)
            try
                error_data = JSON.parse(error_msg)
                error_msg = get(error_data, "error", Dict("message" => error_msg))["message"]
            catch
            end
            return create_error_response("API error (status $(response.status)): $error_msg", model_name)
        end
        
        data = JSON.parse(String(response.body))
        
        # Extract response data
        choices = get(data, "choices", [])
        if isempty(choices)
            return create_error_response("No choices in response", model_name)
        end
        
        choice = choices[1]
        message = get(choice, "message", Dict())
        content = get(message, "content", "")
        finish_reason = get(choice, "finish_reason", "unknown")
        
        # Extract usage
        usage_data = get(data, "usage", Dict())
        usage = Dict{Symbol, Int}(
            :prompt => get(usage_data, "prompt_tokens", 0),
            :completion => get(usage_data, "completion_tokens", 0),
            :total => get(usage_data, "total_tokens", 0)
        )
        
        return LLMResponse(content, finish_reason, model_name; usage=usage, raw=data)
        
    catch e
        @error "OpenAI request failed" exception=e
        return create_error_response(string(e), model_name)
    end
end

"""
    generate_stream(client::OpenAIClient, messages::Vector{LLMMessage}; kwargs...) -> Channel{LLMResponse}

Generate a streaming response from OpenAI using SSE.
"""
function generate_stream(client::OpenAIClient, messages::Vector{LLMMessage};
    model::Union{String, Nothing}=nothing,
    temperature::Float64=0.7,
    max_tokens::Int=2000,
    top_p::Float64=1.0,
    frequency_penalty::Float64=0.0,
    presence_penalty::Float64=0.0,
    stop::Union{Vector{String}, Nothing}=nothing,
    kwargs...
)::Channel
    
    model_name = model !== nothing ? model : client.model
    
    # Build request body
    body = Dict{String, Any}(
        "model" => model_name,
        "messages" => messages_to_dicts(messages),
        "temperature" => temperature,
        "max_tokens" => max_tokens,
        "top_p" => top_p,
        "frequency_penalty" => frequency_penalty,
        "presence_penalty" => presence_penalty,
        "stream" => true
    )
    
    if stop !== nothing
        body["stop"] = stop
    end
    
    url = build_url(client, DEFAULT_OPENAI_API_PATH)
    headers = copy(client.headers)
    headers["Accept"] = "text/event-stream"
    
    channel = Channel{LLMResponse}(10)
    
    @spawn begin
        try
            json_body = JSON.json(body)
            
            # Use HTTP.Stream for SSE parsing
            response = HTTP.post(url; headers=headers, body=json_body, timeout=client.timeout)
            
            if response.status != 200
                error("API error: status $(response.status)")
            end
            
            # Parse SSE stream
            content = ""
            finish_reason = "unknown"
            
            body_str = String(response.body)
            lines = split(body_str, '\n')
            
            for line in lines
                line = strip(line)
                if startswith(line, "data: ")
                    data_str = line[7:end]
                    
                    if data_str == "[DONE]"
                        finish_reason = "stop"
                        break
                    end
                    
                    try
                        data = JSON.parse(data_str)
                        choices = get(data, "choices", [])
                        if !isempty(choices)
                            choice = choices[1]
                            delta = get(choice, "delta", Dict())
                            chunk_content = get(delta, "content", "")
                            content *= chunk_content
                            
                            # Send chunk to channel
                            finish = get(choice, "finish_reason", nothing)
                            
                            put!(channel, LLMResponse(
                                chunk_content,
                                finish !== nothing ? finish : "length",
                                model_name;
                                raw=data
                            ))
                            
                            if finish !== nothing
                                finish_reason = finish
                                break
                            end
                        end
                    catch e
                        # Skip parsing errors for malformed chunks
                        @debug "Skipping malformed SSE chunk" exception=e
                    end
                end
            end
            
            # Send final message with empty content to signal completion
            put!(channel, LLMResponse("", finish_reason, model_name; raw=Dict("done" => true)))
            
        catch e
            @error "OpenAI streaming failed" exception=e
            put!(channel, create_error_response(string(e), model_name))
        finally
            close(channel)
        end
    end
    
    return channel
end

"""
    list_models(client::OpenAIClient) -> Vector{String}

List available models from OpenAI.
"""
function list_models(client::OpenAIClient)::Vector{String}
    try
        response = make_request(client, "GET", "/models")
        
        if response.status != 200
            return [client.model]  # Fallback to current model
        end
        
        data = JSON.parse(String(response.body))
        models_data = get(data, "data", [])
        
        models = String[]
        for model_data in models_data
            id = get(model_data, "id", "")
            if !isempty(id) && startswith(id, "gpt")
                push!(models, id)
            end
        end
        
        return isempty(models) ? [client.model] : models
        
    catch e
        @warn "Failed to list models, using default" exception=e
        return [client.model]
    end
end

"""
    is_available(client::OpenAIClient) -> Bool

Check if OpenAI API is accessible.
"""
function is_available(client::OpenAIClient)::Bool
    try
        # Try to list models - requires valid API key
        models = list_models(client)
        return length(models) > 0
    catch e
        @warn "OpenAI client not available" exception=e
        return false
    end
end

# ============================================================================
# Factory Functions
# ============================================================================

"""
    create_openai_client(; api_key=ENV["OPENAI_API_KEY"], kwargs...) -> OpenAIClient

Create an OpenAI client from environment or parameters.
"""
function create_openai_client(; 
    api_key::Union{String, Nothing}=nothing,
    kwargs...
)::OpenAIClient
    
    if api_key === nothing
        api_key = get(ENV, "OPENAI_API_KEY", "")
    end
    
    if isempty(api_key)
        @warn "No OpenAI API key provided. Set OPENAI_API_KEY environment variable."
    end
    
    return OpenAIClient(api_key; kwargs...)
end

"""
    create_openai_compatible_client(base_url::String, api_key::String; kwargs...) -> OpenAIClient

Create an OpenAI-compatible client (for use with proxies, local models, etc.)
"""
function create_openai_compatible_client(
    base_url::String, 
    api_key::String; 
    kwargs...
)::OpenAIClient
    return OpenAIClient(api_key; base_url=base_url, kwargs...)
end

# ============================================================================
# Model Helpers
# ============================================================================

"""
    get_default_model() -> String

Get the default model based on what's available.
"""
function get_default_model()::String
    return DEFAULT_OPENAI_MODEL
end

"""
    is_vision_model(model::String) -> Bool

Check if model supports vision/images.
"""
function is_vision_model(model::String)::Bool
    return model in ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4-turbo-preview"]
end

"""
    is_latest_model(model::String) -> Bool

Check if model is the latest version.
"""
function is_latest_model(model::String)::Bool
    return model in GPT4O_MODELS
end

end # module
