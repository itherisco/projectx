# llm/prompts.jl - Prompt Templates
# System prompts, user prompt templates, memory/context injection, and tool use formatting

module PromptTemplates

using JSON
using Dates

# Import from client.jl
include("client.jl")
using ..LLMClientModule: LLMMessage, system_message, user_message, assistant_message, tool_message

export PromptTemplate, SystemPrompt, UserPromptTemplate
export create_thought_prompt, create_analysis_prompt, create_action_prompt
export format_memory_context, format_tool_use, format_capabilities

# ============================================================================
# Constants
# ============================================================================

const DEFAULT_ASSISTANT_NAME = "ProjectX"
const MAX_MEMORY_TOKENS = 2000

# ============================================================================
# System Prompts
# ============================================================================

"""
    SystemPrompt

Container for the assistant's system prompt with dynamic content.
"""
struct SystemPrompt
    base::String
    personality::String
    capabilities::String
    constraints::String
    
    function SystemPrompt(;
        name::String=DEFAULT_ASSISTANT_NAME,
        personality::String=get_default_personality(),
        capabilities::String=get_default_capabilities(),
        constraints::String=get_default_constraints()
    )
        base = """
        You are $name, an AI assistant with cognitive capabilities.
        
        $personality
        
        ## Capabilities
        $capabilities
        
        ## Constraints
        $constraints
        
        ## Response Format
        Always be concise, accurate, and helpful. When unsure, acknowledge uncertainty.
        Think step by step for complex problems.
        """
        new(base, personality, capabilities, constraints)
    end
    
    function SystemPrompt(base::String)
        new(base, "", "", "")
    end
end

"""
    get_default_personality() -> String
"""
function get_default_personality()::String
    return """
    You are helpful, curious, and honest. You:
    - Think carefully before responding
    - Admit when you don't know something
    - Ask clarifying questions when needed
    - Provide reasoning for your decisions
    """
end

"""
    get_default_capabilities() -> String
"""
function get_default_capabilities()::String
    return """
    - Information retrieval and analysis
    - Problem solving and planning
    - Text generation and summarization
    - Tool use (via function calling)
    - Memory and context awareness
    """
end

"""
    get_default_constraints() -> String
"""
function get_default_constraints()::String
    return """
    - Do not make up facts; acknowledge uncertainty
    - Do not perform harmful actions
    - Respect user privacy and confidentiality
    - Follow security best practices
    - Stay within your knowledge cutoff
    """
end

"""
    to_message(prompt::SystemPrompt) -> LLMMessage
"""
function to_message(prompt::SystemPrompt)::LLMMessage
    return system_message(prompt.base)
end

"""
    to_message(prompt::String) -> LLMMessage
"""
function to_message(prompt::String)::LLMMessage
    return system_message(prompt)
end

# ============================================================================
# User Prompt Templates
# ============================================================================

"""
    UserPromptTemplate

Template for generating user prompts with variable substitution.
"""
struct UserPromptTemplate
    template::String
    required_vars::Vector{Symbol}
    
    function UserPromptTemplate(template::String)
        # Extract required variables from {var} patterns
        required_vars = Symbol[]
        for match in eachmatch(r"\{(\w+)\}", template)
            push!(required_vars, Symbol(match[1]))
        end
        new(template, required_vars)
    end
end

"""
    render(template::UserPromptTemplate, vars::Dict) -> String

Render a prompt template with variable substitution.
"""
function render(template::UserPromptTemplate, vars::Dict{String, Any})::String
    result = template.template
    for (key, value) in vars
        result = replace(result, "{" * key * "}" => string(value))
    end
    return result
end

"""
    render(template::UserPromptTemplate; kwargs...) -> String

Render a prompt template with keyword arguments.
"""
function render(template::UserPromptTemplate; kwargs...)::String
    vars = Dict{String, Any}(string(k) => v for (k, v) in kwargs)
    return render(template, vars)
end

# ============================================================================
# Pre-built Prompt Templates
# ============================================================================

# Thought generation prompt
const THOUGHT_TEMPLATE = UserPromptTemplate("""
Given the following context, generate your next thought or response.

## Current Situation
- Input: {input}
- Time: {timestamp}
- Active Goal: {active_goal}

## Relevant Context
{context}

## Available Capabilities
{capabilities}

Based on this context, what is the most appropriate thought or response?
Provide a concise response that addresses the input.
""")

# Analysis prompt
const ANALYSIS_TEMPLATE = UserPromptTemplate("""
Analyze the following situation and provide insights.

## Situation
{situation}

## Relevant Information
{information}

## Previous Context
{history}

Provide a detailed analysis with:
1. Key Potential implications observations
2.
3. Recommended actions (if any)
""")

# Action selection prompt
const ACTION_TEMPLATE = UserPromptTemplate("""
Select the most appropriate action given the current situation.

## Current Goal
{goal}

## Available Actions
{actions}

## Context
{context}

## Constraints
{constraints}

Choose the best action and explain your reasoning.
""")

# Reflection prompt
const REFLECTION_TEMPLATE = UserPromptTemplate("""
Reflect on the following action and its outcome.

## Action Taken
{action}

## Outcome
{outcome}

## Goals Affected
{goals}

What did you learn? How can you improve?
""")

# ============================================================================
# Context Formatting
# ============================================================================

"""
    format_memory_context(memories::Vector{Dict{String, Any}}; max_items::Int=5) -> String

Format memory/context for injection into prompts.
"""
function format_memory_context(memories::Vector{Dict{String, Any}}; max_items::Int=5)::String
    if isempty(memories)
        return "No relevant memories found."
    end
    
    items = memories[1:min(max_items, length(memories))]
    formatted = String[]
    
    for (i, memory) in enumerate(items)
        timestamp = get(memory, "timestamp", "unknown")
        content = get(memory, "content", get(memory, "text", ""))
        relevance = get(memory, "relevance", 1.0)
        
        push!(formatted, "$i. [$timestamp] (relevance: $(round(relevance, digits=2))) $content")
    end
    
    return join(formatted, "\n")
end

"""
    format_capabilities(capabilities::Vector{Dict{String, Any}}) -> String

Format available capabilities for prompts.
"""
function format_capabilities(capabilities::Vector{Dict{String, Any}})::String
    if isempty(capabilities)
        return "No capabilities available."
    end
    
    formatted = String[]
    for cap in capabilities
        id = get(cap, "id", "unknown")
        name = get(cap, "name", id)
        description = get(cap, "description", "")
        risk = get(cap, "risk", "low")
        
        push!(formatted, "- $name: $description (risk: $risk)")
    end
    
    return join(formatted, "\n")
end

"""
    format_goals(goals::Vector{Dict{String, Any}}) -> String

Format active goals for prompts.
"""
function format_goals(goals::Vector{Dict{String, Any}})::String
    if isempty(goals)
        return "No active goals."
    end
    
    formatted = String[]
    for goal in goals
        id = get(goal, "id", "unknown")
        description = get(goal, "description", "")
        priority = get(goal, "priority", 0.5)
        
        push!(formatted, "- [$id] Priority $(round(priority, digits=2)): $description")
    end
    
    return join(formatted, "\n")
end

"""
    format_tool_use(tool_name::String, args::Dict{String, Any}, result::Any) -> String

Format tool use for conversation context.
"""
function format_tool_use(tool_name::String, args::Dict{String, Any}, result::Any)::String
    return """
    [Tool: $tool_name]
    Arguments: $(JSON.json(args))
    Result: $(typeof(result) == String ? result : JSON.json(result))
    """
end

"""
    format_error(error::String, context::Dict{String, Any}) -> String

Format an error message with context.
"""
function format_error(error::String, context::Dict{String, Any}=Dict())::String
    msg = "Error: $error"
    if !isempty(context)
        msg *= "\nContext: $(JSON.json(context))"
    end
    return msg
end

# ============================================================================
# Prompt Builder Functions
# ============================================================================

"""
    create_thought_prompt(input::String; context::Dict=Dict(), goals::Vector=Dict[], capabilities::Vector=Dict[]) -> Vector{LLMMessage}

Build messages for thought generation.
"""
function create_thought_prompt(
    input::String;
    context::Dict{String, Any}=Dict{String, Any}(),
    goals::Vector{Dict{String, Any}}=Dict{String, Any}[],
    capabilities::Vector{Dict{String, Any}}=Dict{String, Any}[],
    memories::Vector{Dict{String, Any}}=Dict{String, Any}[],
    system_prompt::Union{SystemPrompt, String, Nothing}=nothing
)::Vector{LLMMessage}
    
    messages = LLMMessage[]
    
    # Add system prompt
    if system_prompt !== nothing
        push!(messages, to_message(system_prompt))
    else
        push!(messages, to_message(SystemPrompt()))
    end
    
    # Format context
    context_str = format_memory_context(memories)
    capabilities_str = format_capabilities(capabilities)
    goals_str = format_goals(goals)
    
    # Render template
    user_content = render(THOUGHT_TEMPLATE;
        input=input,
        timestamp=now(),
        active_goal=isempty(goals) ? "none" : goals[1]["description"],
        context=context_str,
        capabilities=capabilities_str
    )
    
    push!(messages, user_message(user_content))
    
    return messages
end

"""
    create_analysis_prompt(situation::String; information::String="", history::String="") -> Vector{LLMMessage}

Build messages for analysis.
"""
function create_analysis_prompt(
    situation::String;
    information::String="",
    history::String=""
)::Vector{LLMMessage}
    
    messages = LLMMessage[
        to_message(SystemPrompt())
    ]
    
    user_content = render(ANALYSIS_TEMPLATE;
        situation=situation,
        information=information,
        history=history
    )
    
    push!(messages, user_message(user_content))
    
    return messages
end

"""
    create_action_prompt(goal::String, actions::Vector{Dict{String, Any}}; context::String="", constraints::String="") -> Vector{LLMMessage}

Build messages for action selection.
"""
function create_action_prompt(
    goal::String,
    actions::Vector{Dict{String, Any}};
    context::String="",
    constraints::String=""
)::Vector{LLMMessage}
    
    messages = LLMMessage[
        to_message(SystemPrompt())
    ]
    
    actions_str = format_capabilities(actions)
    
    user_content = render(ACTION_TEMPLATE;
        goal=goal,
        actions=actions_str,
        context=context,
        constraints=constraints
    )
    
    push!(messages, user_message(user_content))
    
    return messages
end

"""
    create_reflection_prompt(action::String, outcome::String; goals::Vector=Dict[]) -> Vector{LLMMessage}

Build messages for reflection.
"""
function create_reflection_prompt(
    action::String,
    outcome::String;
    goals::Vector{Dict{String, Any}}=Dict{String, Any}[]
)::Vector{LLMMessage}
    
    messages = LLMMessage[
        to_message(SystemPrompt())
    ]
    
    goals_str = format_goals(goals)
    
    user_content = render(REFLECTION_TEMPLATE;
        action=action,
        outcome=outcome,
        goals=goals_str
    )
    
    push!(messages, user_message(user_content))
    
    return messages
end

# ============================================================================
# Conversation History Management
# ============================================================================

"""
    add_to_history(history::Vector{LLMMessage}, role::Symbol, content::String) -> Vector{LLMMessage}

Add a message to conversation history.
"""
function add_to_history(history::Vector{LLMMessage}, role::Symbol, content::String)::Vector{LLMMessage}
    msg = if role == :system
        system_message(content)
    elseif role == :user
        user_message(content)
    elseif role == :assistant
        assistant_message(content)
    else
        user_message(content)
    end
    
    push!(history, msg)
    return history
end

"""
    truncate_history(history::Vector{LLMMessage}; max_tokens::Int=4000) -> Vector{LLMMessage}

Truncate conversation history to fit within token limit.
"""
function truncate_history(history::Vector{LLMMessage}; max_tokens::Int=4000)::Vector{LLMMessage}
    # Simple approximation: ~4 characters per token
    char_limit = max_tokens * 4
    
    # Keep system message if present
    result = LLMMessage[]
    system_msg = nothing
    
    for msg in history
        if msg.role == SYSTEM
            system_msg = msg
        else
            push!(result, msg)
        end
    end
    
    # Calculate total characters
    total_chars = sum(length(msg.content) for msg in result)
    
    # Truncate from the beginning (keep most recent)
    while total_chars > char_limit && length(result) > 1
        removed = popfirst!(result)
        total_chars -= length(removed.content)
    end
    
    # Prepend system message
    if system_msg !== nothing
        pushfirst!(result, system_msg)
    end
    
    return result
end

end # module
