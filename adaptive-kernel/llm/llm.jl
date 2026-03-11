# llm.jl - LLM Integration Module
# Main entry point for the LLM integration

module LLM

# Import all submodules
include("client.jl")
include("openai.jl")
include("ollama.jl")
include("prompts.jl")
include("config.jl")

# Re-export commonly used types and functions
export LLMClientModule
export OpenAIClientModule
export OllamaClientModule
export PromptTemplates
export LLMConfig

# Re-export from client.jl
export AbstractLLMClient, LLMClient, LLMMessage, LLMResponse, MessageRole
export SYSTEM, USER, ASSISTANT, TOOL
export system_message, user_message, assistant_message, tool_message
export generate, generate_stream, list_models

# Re-export from openai.jl
export OpenAIClient
export DEFAULT_OPENAI_MODEL, GPT4_MODELS, GPT4O_MODELS

# Re-export from ollama.jl
export OllamaClient
export DEFAULT_OLLAMA_BASE_URL, DEFAULT_OLLAMA_MODEL
export OLLAMA_MODELS

# Re-export from config.jl
export LLMProvider, LLMConfig
export load_llm_config, create_llm_client, create_llm_client_auto
export get_global_client, get_global_config, init_llm
export is_llm_available, get_available_models

# Re-export from prompts.jl
export SystemPrompt, UserPromptTemplate
export create_thought_prompt, create_analysis_prompt, create_action_prompt
export format_memory_context, format_capabilities, format_tool_use

# ============================================================================
# Convenience Functions
# ============================================================================

"""
    generate_thought(client::AbstractLLMClient, input::String; kwargs...) -> LLMResponse

Generate a thought response from the LLM.
"""
function generate_thought(client::AbstractLLMClient, input::String; kwargs...)::LLMResponse
    messages = PromptTemplates.create_thought_prompt(input)
    return generate(client, messages; kwargs...)
end

"""
    analyze_with_llm(client::AbstractLLMClient, situation::String; kwargs...) -> LLMResponse

Analyze a situation using the LLM.
"""
function analyze_with_llm(client::AbstractLLMClient, situation::String; kwargs...)::LLMResponse
    messages = PromptTemplates.create_analysis_prompt(situation)
    return generate(client, messages; kwargs...)
end

"""
    select_action_with_llm(client::AbstractLLMClient, goal::String, actions::Vector{Dict}; kwargs...) -> LLMResponse

Select an action using the LLM.
"""
function select_action_with_llm(client::AbstractLLMClient, goal::String, actions::Vector{Dict}; kwargs...)::LLMResponse
    messages = PromptTemplates.create_action_prompt(goal, actions)
    return generate(client, messages; kwargs...)
end

end # module
