"""
    VLMClient - Vision Language Model abstraction
Supports: GPT-4V, Claude Vision, LLaVA
"""
abstract type VLMClient end

"""
    VisionResult - Structured result from VLM analysis
"""
struct VisionResult
    description::String
    objects::Vector{String}
    text_detected::String
    confidence::Float32
end

# GPT-4V Implementation
struct GPT4VClient <: VLMClient
    api_key::String
    model::String
    max_tokens::Int
    
    function GPT4VClient(;api_key::String=get(ENV, "JARVIS_OPENAI_API_KEY", ""),
                         model::String="gpt-4-vision-preview")
        isempty(api_key) && @warn "OpenAI API key not set - GPT-4V will fail"
        new(api_key, model, 2048)
    end
end

# Claude Vision Implementation
struct ClaudeVisionClient <: VLMClient
    api_key::String
    model::String
    
    function ClaudeVisionClient(;api_key::String=get(ENV, "JARVIS_ANTHROPIC_API_KEY", ""),
                               model::String="claude-3-opus-20240229")
        isempty(api_key) && @warn "Anthropic API key not set - Claude Vision will fail"
        new(api_key, model)
    end
end

# LLaVA (local) Implementation
struct LLaVAClient <: VLMClient
    endpoint::String
    model_name::String
    
    function LLaVAClient(;endpoint::String="http://localhost:8080",
                        model_name::String="llava-1.5-7b")
        new(endpoint, model_name)
    end
end

"""
    analyze_image(client::VLMClient, image_data::Vector{UInt8}, prompt::String)::VisionResult
Send image to VLM and get structured analysis
"""
function analyze_image(client::VLMClient, image_data::Vector{UInt8}, prompt::String)::VisionResult
    # Default implementation - should be overridden by each client type
    return VisionResult(
        description="[VLM analysis unavailable]",
        objects=String[],
        text_detected="",
        confidence=0.0f0
    )
end

# GPT-4V specific implementation
function analyze_image(client::GPT4VClient, image_data::Vector{UInt8}, prompt::String)::VisionResult
    if isempty(client.api_key)
        return VisionResult(
            description="[GPT-4V unavailable - no API key]",
            objects=String[],
            text_detected="",
            confidence=0.0f0
        )
    end
    
    # Implementation would call OpenAI API
    # For now, return placeholder
    return VisionResult(
        description="[GPT-4V analysis]",
        objects=String[],
        text_detected="",
        confidence=0.8f0
    )
end

"""
    is_available(client::VLMClient)::Bool
Check if VLM client is available for use
"""
function is_available(client::VLMClient)::Bool
    return false  # Default to false - override in implementations
end

function is_available(client::GPT4VClient)::Bool
    return !isempty(client.api_key)
end

function is_available(client::ClaudeVisionClient)::Bool
    return !isempty(client.api_key)
end
