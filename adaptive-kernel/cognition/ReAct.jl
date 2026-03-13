# cognition/ReAct.jl - ReAct (Reason + Act) Framework
# Interleaves thoughts with actions for reliable autonomous operations
# Observe → Think → Act → Reflect → Repeat

module ReAct

using Dates
using UUIDs
using Statistics

# Import Input Sanitizer - SECURITY BOUNDARY for LLM interaction paths
include(joinpath(@__DIR__, "security", "InputSanitizer.jl"))
using .InputSanitizer

# Export all public functions and types
export
    # Types
    ReActState,
    ReActStep,
    ReActContext,
    
    # Core functions
    create_react_context,
    react_reason,
    react_act,
    react_observe,
    react_reflect,
    run_react_cycle,
    
    # Configuration
    ReActConfig

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    ReActConfig - Configuration for ReAct reasoning
"""
struct ReActConfig
    max_iterations::Int
    confidence_threshold::Float64
    coherence_weight::Float64
    reflection_weight::Float64
    iteration_weight::Float64
    min_coherence::Float64
    enable_backtracking::Bool
    max_reflection_rounds::Int
    
    function ReActConfig(;
        max_iterations::Int = 10,
        confidence_threshold::Float64 = 0.85,
        coherence_weight::Float64 = 0.3,
        reflection_weight::Float64 = 0.3,
        iteration_weight::Float64 = 0.2,
        min_coherence::Float64 = 0.5,
        enable_backtracking::Bool = true,
        max_reflection_rounds::Int = 3
    )
        new(
            max_iterations,
            confidence_threshold,
            coherence_weight,
            reflection_weight,
            iteration_weight,
            min_coherence,
            enable_backtracking,
            max_reflection_rounds
        )
    end
end

# ============================================================================
# REACT STATE TYPES
# ============================================================================

"""
    ReActState - Current state in the ReAct reasoning cycle
"""
@enum ReActState begin
    observing       # Initial observation of environment
    thinking        # Generating thought/action
    acting          # Executing the action
    observing_result  # Processing observation from action
    reflecting      # Evaluating reasoning quality
    completed       # Reasoning complete
end

"""
    ReActStep - Individual step in the ReAct cycle
"""
mutable struct ReActStep
    step_number::Int
    state::ReActState
    
    # Thought components
    thought::String
    action::String
    observation::Any
    
    # Reflection
    reflection::String
    reflection_score::Float64
    
    # Timing
    started_at::DateTime
    completed_at::Union{DateTime, Nothing}
    
    # Metadata
    coherence_breaks::Vector{Dict{String, Any}}
    node_ids::Vector{String}       # Knowledge graph nodes added
    edge_ids::Vector{String}       # Knowledge graph edges added
    
    function ReActStep(step_num::Int)
        new(
            step_num,
            observing,  # Use enum value directly without conversion
            "",
            "",
            nothing,
            "",
            0.0,
            now(),
            nothing,
            Dict{String, Any}[],
            String[],
            String[]
        )
    end
end

# Forward declarations for types from other modules
# These will be available when loaded through Cognition.jl

"""
    ReActContext - Holds the reasoning context for ReAct cycle
"""
mutable struct ReActContext
    # Configuration
    config::ReActConfig
    
    # Input context
    perception::Any  # Perception type from CognitionTypes
    task::String
    
    # Reasoning state
    current_state::ReActState
    iteration::Int
    
    # Reasoning steps
    steps::Vector{ReActStep}
    current_step::Union{ReActStep, Nothing}
    
    # Knowledge graph for coherence
    mindmap_agent::Any  # MindMapAgent from MindMapAgent module
    chain_id::String
    
    # Reasoning results
    final_proposal::Any  # AgentProposal from DecisionSpine
    is_complete::Bool
    termination_reason::Union{String, Nothing}
    
    # Tracking
    created_at::DateTime
    last_updated::DateTime
    
    # Loop detection
    action_history::Vector{String}
    thought_history::Vector{String}
    state_history::Vector{Symbol}
    
    function ReActContext(
        config::ReActConfig,
        perception::Any,
        task::String,
        mindmap_agent::Any
    )
        chain_id = "react_chain_" * string(uuid4())
        ctx = new(
            config,
            perception,
            task,
            :observing,
            1,
            ReActStep[],
            ReActStep(1),
            mindmap_agent,
            chain_id,
            nothing,
            false,
            nothing,
            now(),
            now(),
            String[],
            Symbol[],
            Symbol[:observing]
        )
        
        # Initialize knowledge graph with task context
        init_chain!(ctx)
        
        return ctx
    end
end

# ============================================================================
# INITIALIZATION
# ============================================================================

"""
    create_react_context - Initialize ReAct context with perception and task
"""
function create_react_context(
    perception::Any,
    task::String,
    mindmap_agent::Any;
    config::ReActConfig = ReActConfig()
)::ReActContext
    
    return ReActContext(config, perception, task, mindmap_agent)
end

"""
    init_chain - Initialize the knowledge graph chain with task context
"""
function init_chain!(ctx::ReActContext)::Nothing
    # Add initial task node
    node_id = add_reasoning_node(
        ctx.mindmap_agent,
        ctx.chain_id,
        "Task: $(ctx.task)",
        0.9;
        source="ReAct",
        metadata=Dict{String, Any}("type" => "task_context")
    )
    
    # Add perception node
    perception_summary = "System: $(ctx.perception.system_state), Threat: $(ctx.perception.threat_level)"
    _ = add_reasoning_node(
        ctx.mindmap_agent,
        ctx.chain_id,
        perception_summary,
        ctx.perception.confidence;
        source="Perception",
        metadata=Dict{String, Any}("type" => "perception")
    )
    
    # Add initial goal node
    _ = add_reasoning_node(
        ctx.mindmap_agent,
        ctx.chain_id,
        "Goal: Complete task with high confidence",
        0.8;
        source="ReAct",
        metadata=Dict{String, Any}("type" => "goal")
    )
    
    nothing
end

# ============================================================================
# STATE MACHINE TRANSITIONS
# ============================================================================

"""
    get_next_state - Determine next state based on current state and results
"""
function get_next_state(
    current_state::ReActState,
    reflection_score::Float64,
    coherence_breaks::Vector{Dict{String, Any}},
    config::ReActConfig
)::ReActState
    
    # Check for early termination conditions
    if reflection_score >= config.confidence_threshold && isempty(coherence_breaks)
        return :completed
    end
    
    # Check for critical coherence breaks
    has_critical = any(b -> get(b, "severity", "") == "critical", coherence_breaks)
    if has_critical && !config.enable_backtracking
        return :completed
    end
    
    # State machine transitions
    return if current_state == :observing
        :thinking
    elseif current_state == :thinking
        :acting
    elseif current_state == :acting
        :observing_result
    elseif current_state == :observing_result
        :reflecting
    elseif current_state == :reflecting
        :thinking  # Loop back to thinking
    else
        :completed
    end
end

"""
    advance_state! - Advance the state machine
"""
function advance_state!(ctx::ReActContext)::Nothing
    current_step = ctx.current_step
    if current_step === nothing
        return nothing
    end
    
    # Determine next state
    next_state = get_next_state(
        current_step.state,
        current_step.reflection_score,
        current_step.coherence_breaks,
        ctx.config
    )
    
    # Record state transition
    push!(ctx.state_history, next_state)
    
    # Update current step
    current_step.state = next_state
    ctx.current_state = next_state
    
    # Handle state completion
    if next_state == :thinking && current_step.state != :thinking
        # Starting new iteration
        ctx.iteration += 1
        current_step.completed_at = now()
        
        # Check max iterations
        if ctx.iteration > ctx.config.max_iterations
            ctx.is_complete = true
            ctx.termination_reason = "max_iterations"
            ctx.current_state = :completed
            return nothing
        end
        
        # Create new step
        ctx.current_step = ReActStep(ctx.iteration)
    elseif next_state == :completed
        ctx.is_complete = true
        # Set termination reason - use existing reason if set, otherwise default to "completed"
        ctx.termination_reason = ctx.termination_reason !== nothing ? ctx.termination_reason : "completed"
    end
    
    ctx.last_updated = now()
    nothing
end

# ============================================================================
# CORE REACT FUNCTIONS
# ============================================================================

"""
    react_reason - Generate thought/action based on current state
    This is where the "Reasoning" happens in ReAct
"""
function react_reason(react_context::ReActContext)::String
    ctx = react_context
    step = ctx.current_step
    
    if step === nothing
        return "No active step - context not initialized"
    end
    
    # Generate reasoning based on current state
    thought = if step.state == :observing
        generate_observation_thought(ctx)
    elseif step.state == :thinking
        generate_thinking_thought(ctx)
    elseif step.state == :observing_result
        generate_observation_result_thought(ctx)
    elseif step.state == :reflecting
        generate_reflection_thought(ctx)
    else
        "Unknown state: $(step.state)"
    end
    
    step.thought = thought
    push!(ctx.thought_history, thought)
    
    # Generate action based on thought
    action = generate_action_from_thought(ctx, thought)
    step.action = action
    push!(ctx.action_history, action)
    
    # Add to knowledge graph
    add_reasoning_to_graph!(ctx, thought, action)
    
    return thought
end

"""
    generate_observation_thought - Generate thought during observation state
"""
function generate_observation_thought(ctx::ReActContext)::String
    perception = ctx.perception
    
    # Summarize current perception
    summary = "Observing environment: CPU=$(perception.system_state), " *
              "Threat=$(perception.threat_level), " *
              "Energy=$(perception.energy_level), " *
              "Confidence=$(perception.confidence)"
    
    return summary
end

"""
    generate_thinking_thought - Generate thought during thinking state
"""
function generate_thinking_thought(ctx::ReActContext)::String
    # Build context from previous steps
    context_parts = String["Task: $(ctx.task)"]
    
    # Add recent reasoning history
    if length(ctx.steps) > 0
        for i in max(1, length(ctx.steps)-2):length(ctx.steps)
            step = ctx.steps[i]
            if !isempty(step.thought)
                push!(context_parts, "Step $(step.step_number): $(step.thought)")
            end
        end
    end
    
    # Current observation
    if ctx.current_step !== nothing && ctx.current_step.observation !== nothing
        obs = ctx.current_step.observation
        push!(context_parts, "Observation: $obs")
    end
    
    # Recent reflections
    if length(ctx.steps) > 0 && !isempty(ctx.steps[end].reflection)
        push!(context_parts, "Latest reflection: $(ctx.steps[end].reflection)")
    end
    
    return join(context_parts, " | ")
end

"""
    generate_observation_result_thought - Generate thought after observing action result
"""
function generate_observation_result_thought(ctx::ReActContext)::String
    step = ctx.current_step
    
    if step === nothing || step.observation === nothing
        return "No observation to process"
    end
    
    obs = step.observation
    action = step.action
    
    # Analyze the observation
    thought = "After executing '$action', observed: $obs"
    
    return thought
end

"""
    generate_reflection_thought - Generate thought during reflection state
"""
function generate_reflection_thought(ctx::ReActContext)::String
    step = ctx.current_step
    
    if step === nothing
        return "Nothing to reflect on"
    end
    
    # Evaluate current reasoning chain
    breaks = detect_coherence_breaks(ctx.mindmap_agent, ctx.chain_id)
    step.coherence_breaks = breaks
    
    # Generate reflection
    if isempty(breaks)
        thought = "Reasoning chain is coherent. Progressing toward solution."
    else
        break_summary = join([b["message"] for b in breaks], "; ")
        thought = "Coherence issues detected: $break_summary"
    end
    
    return thought
end

"""
    generate_action_from_thought - Convert thought to actionable action
    SECURITY: Sanitizes action output to prevent prompt injection
"""
function generate_action_from_thought(ctx::ReActContext, thought::String)::String
    # In a real implementation, this would use LLM or heuristics
    # For now, generate reasonable actions based on task context
    
    # Simple action mapping based on state
    action = if ctx.current_step === nothing || ctx.current_step.state == :observing
        "analyze_environment"
    elseif ctx.current_step.state == :thinking
        "evaluate_options"
    elseif ctx.current_step.state == :observing_result
        "process_result"
    elseif ctx.current_step.state == :reflecting
        "assess_progress"
    else
        "continue_reasoning"
    end
    
    # SECURITY: Sanitize the generated action
    result = sanitize_input(action)
    if result.level == MALICIOUS
        @error "Malicious action generated by ReAct"
        return "continue_reasoning"  # Safe default
    end
    
    return result.sanitized !== nothing ? result.sanitized : action
end

"""
    add_reasoning_to_graph - Add thought and action to knowledge graph
"""
function add_reasoning_to_graph!(ctx::ReActContext, thought::String, action::String)::Nothing
    # Add thought node
    thought_node = add_reasoning_node(
        ctx.mindmap_agent,
        ctx.chain_id,
        "Thought: $thought",
        0.7;
        source="ReAct",
        metadata=Dict{String, Any}("type" => "thought", "action" => action)
    )
    push!(ctx.current_step.node_ids, thought_node)
    
    # Add edge from previous node if exists
    if length(ctx.steps) > 0
        last_step = ctx.steps[end]
        if !isempty(last_step.node_ids)
            last_node = last_step.node_ids[end]
            _ = add_reasoning_edge(
                ctx.mindmap_agent,
                ctx.chain_id,
                last_node,
                thought_node,
                :sequential;
                confidence=0.8
            )
        end
    end
    
    nothing
end

# ============================================================================
# ACTION EXECUTION
# ============================================================================

"""
    react_act - Execute the action generated by reasoning
"""
function react_act(react_context::ReActContext, action::String)::Any
    ctx = react_context
    step = ctx.current_step
    
    if step === nothing
        return Dict{String, Any}("error" => "No active step")
    end
    
    # Execute the action (simulated for now)
    result = execute_action(ctx, action)
    
    # Store action in step
    step.action = action
    
    return result
end

"""
    execute_action - Execute a specific action
    In production, this would call actual tools/capabilities
"""
function execute_action(ctx::ReActContext, action::String)::Any
    # Simulate action execution based on action type
    # In production, this would integrate with actual capability system
    
    perception = ctx.perception
    
    return if action == "analyze_environment"
        Dict{String, Any}(
            "type" => "environment_analysis",
            "cpu" => get(perception.system_state, "cpu", 0.0),
            "memory" => get(perception.system_state, "memory", 0.0),
            "status" => "analyzed"
        )
    elseif action == "evaluate_options"
        Dict{String, Any}(
            "type" => "options_evaluation",
            "options" => ["option_a", "option_b", "option_c"],
            "recommended" => "option_a",
            "status" => "evaluated"
        )
    elseif action == "process_result"
        Dict{String, Any}(
            "type" => "result_processing",
            "processed" => true,
            "insights" => ["insight_1", "insight_2"]
        )
    elseif action == "assess_progress"
        Dict{String, Any}(
            "type" => "progress_assessment",
            "progress" => 0.5,
            "remaining" => 5,
            "confidence" => perception.confidence
        )
    else
        Dict{String, Any}(
            "type" => "generic_action",
            "action" => action,
            "executed" => true
        )
    end
end

# ============================================================================
# OBSERVATION PROCESSING
# ============================================================================

"""
    react_observe - Process observation from action execution
"""
function react_observe(react_context::ReActContext, result::Any)::Any
    ctx = react_context
    step = ctx.current_step
    
    if step === nothing
        return result
    end
    
    # Store observation
    step.observation = result
    
    # Process and potentially add to knowledge graph
    processed = process_observation(ctx, result)
    
    # Add observation to knowledge graph
    obs_node = add_reasoning_node(
        ctx.mindmap_agent,
        ctx.chain_id,
        "Observation: $processed",
        0.8;
        source="Action",
        metadata=Dict{String, Any}("type" => "observation")
    )
    push!(step.node_ids, obs_node)
    
    # Add edge from thought to observation
    if !isempty(step.node_ids) && step.node_ids[end] != obs_node
        _ = add_reasoning_edge(
            ctx.mindmap_agent,
            ctx.chain_id,
            step.node_ids[end],
            obs_node,
            :causal;
            confidence=0.7
        )
    end
    
    return processed
end

"""
    process_observation - Process and summarize observation
"""
function process_observation(ctx::ReActContext, result::Any)::String
    # Convert result to string summary
    if result isa Dict
        # Extract key information
        result_type = get(result, "type", "unknown")
        return "Action result type: $result_type, data: $(keys(result))"
    else
        return string(result)
    end
end

# ============================================================================
# REFLECTION
# ============================================================================

"""
    react_reflect - Evaluate current reasoning quality
    Returns reflection score [0, 1]
"""
function react_reflect(react_context::ReActContext)::Float64
    ctx = react_context
    step = ctx.current_step
    
    if step === nothing
        return 0.0
    end
    
    # Evaluate multiple factors
    coherence_score = evaluate_coherence(ctx)
    progress_score = evaluate_progress(ctx)
    reflection_score = evaluate_reflection_quality(ctx)
    
    # Combine scores with weights
    config = ctx.config
    final_score = (
        coherence_score * config.coherence_weight +
        progress_score * config.iteration_weight +
        reflection_score * config.reflection_weight
    )
    
    # Store reflection
    step.reflection_score = final_score
    step.reflection = "Coherence: $(round(coherence_score, 2)), " *
                      "Progress: $(round(progress_score, 2)), " *
                      "Reflection: $(round(reflection_score, 2))"
    
    # Check for coherence breaks
    breaks = detect_coherence_breaks(ctx.mindmap_agent, ctx.chain_id)
    step.coherence_breaks = breaks
    
    # Handle coherence breaks
    if !isempty(breaks) && ctx.config.enable_backtracking
        handle_coherence_break!(ctx, breaks)
    end
    
    return final_score
end

"""
    evaluate_coherence - Evaluate logical coherence of reasoning chain
"""
function evaluate_coherence(ctx::ReActContext)::Float64
    # Check coherence breaks
    breaks = detect_coherence_breaks(ctx.mindmap_agent, ctx.chain_id)
    
    if isempty(breaks)
        return 1.0
    end
    
    # Penalize based on severity
    critical_count = count(b -> get(b, "severity", "") == "critical", breaks)
    high_count = count(b -> get(b, "severity", "") == "high", breaks)
    medium_count = count(b -> get(b, "severity", "") == "medium", breaks)
    
    penalty = critical_count * 0.5 + high_count * 0.25 + medium_count * 0.1
    
    return max(0.0, 1.0 - penalty)
end

"""
    evaluate_progress - Evaluate progress toward solution
"""
function evaluate_progress(ctx::ReActContext)::Float64
    # Based on iteration count vs max iterations
    progress = ctx.iteration / ctx.config.max_iterations
    
    # Bonus for having more steps with observations
    if length(ctx.steps) > 0
        observations_count = count(s -> s.observation !== nothing, ctx.steps)
        obs_bonus = min(0.2, observations_count * 0.05)
        progress = min(1.0, progress + obs_bonus)
    end
    
    return progress
end

"""
    evaluate_reflection_quality - Evaluate quality of reflection
"""
function evaluate_reflection_quality(ctx::ReActContext)::Float64
    # Check if we're making progress (different thoughts over iterations)
    if length(ctx.thought_history) < 2
        return 0.5
    end
    
    # Check for thought diversity (avoiding loops)
    unique_thoughts = length(unique(ctx.thought_history))
    total_thoughts = length(ctx.thought_history)
    
    diversity = unique_thoughts / max(1, total_thoughts)
    
    # Check for action diversity
    if !isempty(ctx.action_history)
        unique_actions = length(unique(ctx.action_history))
        total_actions = length(ctx.action_history)
        action_diversity = unique_actions / max(1, total_actions)
    else
        action_diversity = 0.5
    end
    
    return (diversity + action_diversity) / 2.0
end

"""
    handle_coherence_break - Handle detected coherence breaks
"""
function handle_coherence_break!(ctx::ReActContext, breaks::Vector{Dict{String, Any}})::Nothing
    # In a full implementation, this would backtrack to a previous state
    # For now, log the breaks and potentially adjust confidence
    
    critical_breaks = filter(b -> get(b, "severity", "") == "critical", breaks)
    
    if !isempty(critical_breaks)
        # Reduce confidence when critical breaks detected
        if ctx.perception.confidence > 0.3
            ctx.perception.confidence -= 0.2
        end
    end
    
    nothing
end

# ============================================================================
# MAIN REACT CYCLE
# ============================================================================

"""
    run_react_cycle - Execute full ReAct reasoning cycle
    Returns AgentProposal with final decision
"""
function run_react_cycle(
    react_context::ReActContext;
    max_iterations::Int = 10
)::Any  # AgentProposal
    ctx = react_context
    
    # Override config if provided
    if max_iterations != 10
        ctx.config = ReActConfig(max_iterations = max_iterations)
    end
    
    # Initialize first step
    ctx.current_step = ReActStep(1)
    ctx.current_state = :observing
    
    # Main ReAct loop
    while !ctx.is_complete && ctx.iteration <= ctx.config.max_iterations
        # Execute current state
        execute_state!(ctx)
        
        # Advance to next state
        advance_state!(ctx)
        
        # Check for early termination
        if ctx.current_step !== nothing && 
           ctx.current_step.reflection_score >= ctx.config.confidence_threshold
            ctx.is_complete = true
            ctx.termination_reason = "confidence_threshold"
        end
    end
    
    # Finalize and generate proposal
    ctx.is_complete = true
    final_proposal = generate_proposal(ctx)
    ctx.final_proposal = final_proposal
    
    return final_proposal
end

"""
    execute_state - Execute the current state
"""
function execute_state!(ctx::ReActContext)::Nothing
    step = ctx.current_step
    if step === nothing
        return nothing
    end
    
    if step.state == :observing || step.state == :thinking
        # Generate thought and action
        _ = react_reason(ctx)
    elseif step.state == :acting
        # Execute action
        result = react_act(ctx, step.action)
        step.observation = result
    elseif step.state == :observing_result
        # Process observation
        if step.observation !== nothing
            _ = react_observe(ctx, step.observation)
        end
    elseif step.state == :reflecting
        # Evaluate reasoning
        _ = react_reflect(ctx)
    end
    
    ctx.last_updated = now()
    nothing
end

# ============================================================================
# PROPOSAL GENERATION
# ============================================================================

"""
    generate_proposal - Generate final AgentProposal from ReAct cycle
"""
function generate_proposal(ctx::ReActContext)::Any  # AgentProposal
    # Calculate final confidence
    confidence = calculate_final_confidence(ctx)
    
    # Build reasoning summary
    reasoning = build_reasoning_summary(ctx)
    
    # Build evidence from knowledge graph
    evidence = collect_graph_evidence(ctx)
    
    # Determine decision
    decision = determine_final_decision(ctx)
    
    # Create proposal - use the constructor directly
    proposal = AgentProposal(
        "react_agent",
        :react,
        decision,
        confidence;
        reasoning = reasoning,
        weight = 1.0,
        evidence = evidence,
        alternatives = collect_alternatives(ctx)
    )
    
    return proposal
end

"""
    calculate_final_confidence - Calculate final confidence score
"""
function calculate_final_confidence(ctx::ReActContext)::Float64
    # Base confidence from perception
    base_conf = ctx.perception.confidence
    
    # Adjust based on coherence
    coherence = evaluate_coherence(ctx)
    
    # Adjust based on progress
    progress = evaluate_progress(ctx)
    
    # Adjust based on iterations (more iterations = potentially more refined)
    iteration_factor = min(1.0, ctx.iteration / ctx.config.max_iterations)
    
    # Combine
    confidence = (
        base_conf * 0.3 +
        coherence * 0.3 +
        progress * 0.2 +
        iteration_factor * 0.2
    )
    
    return clamp(confidence, 0.0, 1.0)
end

"""
    build_reasoning_summary - Build human-readable reasoning summary
    SECURITY: Sanitizes output to prevent prompt injection via reasoning
"""
function build_reasoning_summary(ctx::ReActContext)::String
    parts = String[]
    
    push!(parts, "ReAct Reasoning Summary")
    push!(parts, "========================")
    push!(parts, "Task: $(ctx.task)")
    push!(parts, "Iterations: $(ctx.iteration)")
    push!(parts, "Steps: $(length(ctx.steps))")
    
    if ctx.termination_reason !== nothing
        push!(parts, "Termination: $(ctx.termination_reason)")
    end
    
    # Add key reflections
    if length(ctx.steps) > 0
        last_step = ctx.steps[end]
        if !isempty(last_step.reflection)
            # SECURITY: Sanitize reflection before adding to reasoning
            sanitized_reflection = _sanitize_for_reasoning(last_step.reflection)
            push!(parts, "Last Reflection: $sanitized_reflection")
        end
    end
    
    reasoning = join(parts, "\n")
    
    # Final sanitization pass
    return _sanitize_for_reasoning(reasoning)
end

"""
    _sanitize_for_reasoning - Internal sanitization for reasoning output
"""
function _sanitize_for_reasoning(text::String)::String
    result = sanitize_input(text)
    
    if result.level == MALICIOUS
        @error "Malicious reasoning content detected and blocked"
        return "[BLOCKED] Reasoning filtered by security policy"
    elseif result.level == SUSPICIOUS
        return result.sanitized !== nothing ? result.sanitized : text
    else
        return result.sanitized !== nothing ? result.sanitized : text
    end
end

"""
    collect_graph_evidence - Collect evidence IDs from knowledge graph
"""
function collect_graph_evidence(ctx::ReActContext)::Vector{String}
    evidence = String[]
    
    # Collect all node IDs
    for step in ctx.steps
        append!(evidence, step.node_ids)
    end
    
    return evidence
end

"""
    determine_final_decision - Determine the final decision from reasoning
"""
function determine_final_decision(ctx::ReActContext)::String
    # Based on task and reasoning progress
    if ctx.iteration >= ctx.config.max_iterations
        return "complete_task_with_current_analysis"
    elseif ctx.current_step !== nothing && ctx.current_step.reflection_score >= ctx.config.confidence_threshold
        return "proceed_with_high_confidence"
    else
        return "continue_reasoning"
    end
end

"""
    collect_alternatives - Collect rejected alternatives
"""
function collect_alternatives(ctx::ReActContext)::Vector{String}
    alternatives = String[]
    
    # Based on action history
    unique_actions = unique(ctx.action_history)
    if length(unique_actions) > 1
        # The last action is the final choice, others are alternatives
        for action in unique_actions[1:end-1]
            push!(alternatives, "rejected: $action")
        end
    end
    
    return alternatives
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_react_state_name - Get string name of ReAct state
"""
function get_react_state_name(state::ReActState)::String
    return string(state)[2:end]  # Remove leading colon
end

"""
    is_terminal_state - Check if state is terminal
"""
function is_terminal_state(state::ReActState)::Bool
    return state == :completed
end

"""
    get_cycle_summary - Get summary of ReAct cycle
"""
function get_cycle_summary(ctx::ReActContext)::Dict{String, Any}
    return Dict{String, Any}(
        "task" => ctx.task,
        "iterations" => ctx.iteration,
        "steps" => length(ctx.steps),
        "is_complete" => ctx.is_complete,
        "termination_reason" => ctx.termination_reason,
        "confidence" => ctx.final_proposal !== nothing ? ctx.final_proposal.confidence : 0.0,
        "decision" => ctx.final_proposal !== nothing ? ctx.final_proposal.decision : "none"
    )
end

end # module ReAct
