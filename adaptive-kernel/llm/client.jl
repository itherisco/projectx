# llm/client.jl - Abstract LLM Client Interface
# Defines the contract for LLM providers (OpenAI, Ollama, etc.)

module LLMClientModule

using UUIDs
using Logging

export LLMClient, LLMMessage, LLMResponse, MessageRole
export generate, generate_stream, list_models
export AbstractLLMClient

"""
    MessageRole

Enum for message roles in a conversation.
"""
@enum MessageRole begin
    SYSTEM = 1
    USER = 2
    ASSISTANT = 3
    TOOL = 4
end

"""
    LLMMessage

Represents a single message in an LLM conversation.
"""
struct LLMMessage
    role::MessageRole
    content::String
    name::Union{String, Nothing}
    
    function LLMMessage(role::MessageRole, content::String; name::Union{String, Nothing}=nothing)
        new(role, content, name)
    end
end

"""
    System message constructor
"""
system_message(content::String) = LLMMessage(SYSTEM, content)

"""
    User message constructor
"""
user_message(content::String) = LLMMessage(USER, content)

"""
    Assistant message constructor
"""
assistant_message(content::String; name::Union{String, Nothing}=nothing) = LLMMessage(ASSISTANT, content; name=name)

"""
    Tool message constructor
"""
tool_message(content::String, name::String) = LLMMessage(TOOL, content; name=name)

"""
    LLMResponse

Represents a response from an LLM.
"""
struct LLMResponse
    content::String
    finish_reason::String
    model::String
    usage::Dict{Symbol, Int}
    raw::Dict{String, Any}
    
    function LLMResponse(content::String, finish_reason::String, model::String; 
                         usage::Dict{Symbol, Int}=Dict(:prompt=>0, :completion=>0, :total=>0),
                         raw::Dict{String, Any}=Dict{String, Any}())
        new(content, finish_reason, model, usage, raw)
    end
end

"""
    AbstractLLMClient

Abstract type for all LLM clients. Implementations must provide:
- generate(client, messages; kwargs...)
- generate_stream(client, messages; kwargs...)
- list_models(client)
"""
abstract type AbstractLLMClient end

"""
    generate(client::AbstractLLMClient, messages::Vector{LLMMessage}; kwargs...) -> LLMResponse
    
Generate a non-streaming response from the LLM.

# Arguments
- `client::AbstractLLMClient` - The LLM client
- `messages::Vector{LLMMessage}` - Conversation history
- `model::String` - Optional model override
- `temperature::Float64` - Sampling temperature (0.0-2.0)
- `max_tokens::Int` - Maximum tokens to generate
- `top_p::Float64` - Nucleus sampling parameter
- `stop::Vector{String}` - Stop sequences

# Returns
- `LLMResponse` with the generated content
"""
function generate end

"""
    generate_stream(client::AbstractLLMClient, messages::Vector{LLMMessage}; kwargs...) -> IteratorExtras.Channel

Generate a streaming response from the LLM.

# Arguments
- `client::AbstractLLMClient` - The LLM client
- `messages::Vector{LLMMessage}` - Conversation history
- `model::String` - Optional model override
- `temperature::Float64` - Sampling temperature (0.0-2.0)
- `max_tokens::Int` - Maximum tokens to generate

# Returns
- A Channel that yields chunks of the response as they arrive
"""
function generate_stream end

"""
    list_models(client::AbstractLLMClient) -> Vector{String}

List available models for the client.

# Returns
- Vector of model identifiers
"""
function list_models end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    messages_to_dicts(messages::Vector{LLMMessage}) -> Vector{Dict{String, Any}}

Convert LLMMessage vector to the format expected by API providers.
"""
function messages_to_dicts(messages::Vector{LLMMessage})::Vector{Dict{String, Any}}
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
        if msg.name !== nothing
            d["name"] = msg.name
        end
        if msg.role == TOOL && msg.name !== nothing
            d["tool_call_id"] = msg.name
        end
        push!(result, d)
    end
    return result
end

"""
    parse_response_content(content::String, format::Symbol=:text) -> Any

Parse LLM response content based on expected format.
"""
function parse_response_content(content::String, format::Symbol=:text)
    if format == :json
        try
            return JSON.parse(content)
        catch
            return nothing
        end
    end
    return content
end

"""
    create_error_response(message::String, model::String="unknown") -> LLMResponse

Create an error response object.
"""
function create_error_response(message::String, model::String="unknown")::LLMResponse
    @error "LLM Error: $message"
    return LLMResponse(
        "Error: $message",
        "error",
        model;
        raw=Dict("error" => Dict("message" => message))
    )
end

"""
    is_available(client::AbstractLLMClient) -> Bool

Check if the LLM client is available/responsive.
Default implementation tries to list models.
"""
function is_available(client::AbstractLLMClient)::Bool
    try
        models = list_models(client)
        return true
    catch e
        @warn "LLM client not available" exception=e
        return false
    end
end

# ============================================================================
# Configuration Helpers
# ============================================================================

"""
    get_default_kwargs(; kwargs...) -> Dict{Symbol, Any}

Merge provided kwargs with sensible defaults.
"""
function get_default_kwargs(; 
    temperature::Float64=0.7,
    max_tokens::Int=2000,
    top_p::Float64=1.0,
    model::Union{String, Nothing}=nothing,
    stop::Union{Vector{String}, Nothing}=nothing,
    kwargs...
)::Dict{Symbol, Any}
    result = Dict{Symbol, Any}(
        :temperature => temperature,
        :max_tokens => max_tokens,
        :top_p => top_p
    )
    
    if model !== nothing
        result[:model] = model
    end
    if stop !== nothing
        result[:stop] = stop
    end
    
    return result
end

end # module
