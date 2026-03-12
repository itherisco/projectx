# cognition/agents/CodeAgent.jl - Code Agent
# Provides quantitative and analytical task capabilities for the multi-agent hierarchy
# Analyzes computational tasks, categorizes them, and generates code/execution strategy proposals

module CodeAgentModule

using Dates
using UUIDs
using JSON

# Import types (CodeAgent is now defined in types.jl)
include("../types.jl")
using ..CognitionTypes

# Import spine
include("../spine/DecisionSpine.jl")
using ..DecisionSpine

# Import ExecutionSandbox for safe code execution
include("../../sandbox/ExecutionSandbox.jl")
using ..ExecutionSandbox

# Import ToolRegistry for capability lookup
include("../../registry/ToolRegistry.jl")
using ..ToolRegistry

# Import Kernel for sovereign approval
include("../../kernel/Kernel.jl")
using ..Kernel

export CodeAgent, create_code_agent, generate_proposal

# ============================================================================
# CODE AGENT TYPE IS NOW DEFINED IN cognition/types.jl
# ============================================================================

# Task categories for computational work
@enum TaskCategory begin
    CALCULATION        # Mathematical computations
    DATA_ANALYSIS      # Data processing and analysis
    CODE_GENERATION    # Writing code snippets or programs
    SIMULATION         # Running simulations
    OPTIMIZATION       # Finding optimal solutions
end

# ============================================================================
# FACTORY FUNCTION
# ============================================================================

"""
    create_code_agent(id::String = "code_agent_001")::CodeAgent
    Factory function to create a CodeAgent instance
"""
function create_code_agent(id::String = "code_agent_001")::CodeAgent
    return CodeAgent(id)
end

# ============================================================================
# MAIN PROPOSAL GENERATION
# ============================================================================

"""
    generate_proposal(agent::CodeAgent, perception::Perception, task_context::Dict{String, Any})::AgentProposal
    Analyzes incoming tasks for computational needs and generates code/execution strategy proposals
"""
function generate_proposal(
    agent::CodeAgent,
    perception::Perception,
    task_context::Dict{String, Any}
)::AgentProposal
    
    # Extract the task from context
    task_description = get(task_context, "task", "")
    task_type = get(task_context, "type", "unknown")
    input_data = get(task_context, "input_data", nothing)
    
    # Analyze task for computational needs
    computational_needs = analyze_computational_needs(task_description, task_type)
    
    # Categorize the task
    task_category = categorize_task(task_description, task_type)
    
    # Generate execution strategy
    execution_strategy = generate_execution_strategy(task_category, task_description, computational_needs)
    
    # Calculate confidence based on task clarity and complexity
    confidence = calculate_code_confidence(task_description, computational_needs, task_category)
    
    # Generate evidence (supporting calculations/analysis)
    evidence = generate_evidence(task_category, computational_needs)
    
    # Generate alternative strategies
    alternatives = generate_alternative_strategies(task_category, task_description)
    
    # Build reasoning
    reasoning = build_code_reasoning(task_description, task_category, computational_needs, confidence)
    
    # Record in task history
    task_record = Dict{String, Any}(
        "task" => task_description,
        "type" => task_type,
        "category" => string(task_category),
        "strategy" => execution_strategy,
        "timestamp" => string(now())
    )
    push!(agent.task_history, task_record)
    
    return AgentProposal(
        agent.id,
        :code,
        execution_strategy,
        confidence,
        reasoning = reasoning,
        weight = 0.85,  # Default weight for code agent influence
        evidence = evidence,
        alternatives = alternatives
    )
end

# ============================================================================
# TASK ANALYSIS
# ============================================================================

"""
    analyze_computational_needs - Analyze task to determine computational requirements
"""
function analyze_computational_needs(task_description::String, task_type::String)::Dict{String, Any}
    needs = Dict{String, Any}()
    
    # Check if task requires computation
    needs["requires_computation"] = requires_computation(task_description, task_type)
    
    # Determine computational complexity
    needs["complexity"] = assess_complexity(task_description)
    
    # Check for data requirements
    needs["needs_data"] = requires_data(task_description)
    
    # Determine if simulation is needed
    needs["needs_simulation"] = requires_simulation(task_description)
    
    # Check for optimization requirements
    needs["needs_optimization"] = requires_optimization(task_description)
    
    # Identify preferred language
    needs["preferred_language"] = identify_language(task_description)
    
    # Check for safety concerns
    needs["safety_level"] = assess_safety_level(task_description)
    
    return needs
end

"""
    requires_computation - Determine if task requires computational work
"""
function requires_computation(task_description::String, task_type::String)::Bool
    # If task type explicitly indicates computation
    if task_type in ["calculation", "computation", "analysis", "simulation", "optimization"]
        return true
    end
    
    # Check for computation-related keywords
    computation_keywords = [
        "calculate", "compute", "analyze", "process", "simulate", 
        "optimize", "solve", "execute", "run", "algorithm",
        "statistical", "regression", "model", "predict", "transform"
    ]
    
    task_lower = lowercase(task_description)
    return any(occursin(kw, task_lower) for kw in computation_keywords)
end

"""
    assess_complexity - Assess computational complexity of the task
"""
function assess_complexity(task_description::String)::String
    task_lower = lowercase(task_description)
    
    # High complexity indicators
    high_complexity = ["machine learning", "deep learning", "neural network", "optimization", 
                      "simulation", "parallel", "distributed", "advanced"]
    if any(occursin(kw, task_lower) for kw in high_complexity)
        return "high"
    end
    
    # Medium complexity indicators
    medium_complexity = ["algorithm", "statistical", "analysis", "processing", "transform"]
    if any(occursin(kw, task_lower) for kw in medium_complexity)
        return "medium"
    end
    
    return "low"
end

"""
    requires_data - Check if task requires data input
"""
function requires_data(task_description::String)::Bool
    data_keywords = ["dataset", "data", "file", "input", "csv", "json", "parse", "load"]
    task_lower = lowercase(task_description)
    return any(occursin(kw, task_lower) for kw in data_keywords)
end

"""
    requires_simulation - Check if task requires simulation
"""
function requires_simulation(task_description::String)::Bool
    simulation_keywords = ["simulate", "simulation", "model", "emulate", "scenario", "forecast"]
    task_lower = lowercase(task_description)
    return any(occursin(kw, task_lower) for kw in simulation_keywords)
end

"""
    requires_optimization - Check if task requires optimization
"""
function requires_optimization(task_description::String)::Bool
    optimization_keywords = ["optimize", "optimal", "minimize", "maximize", "best", "optimal"]
    task_lower = lowercase(task_description)
    return any(occursin(kw, task_lower) for kw in optimization_keywords)
end

"""
    identify_language - Identify preferred programming language
"""
function identify_language(task_description::String)::String
    task_lower = lowercase(task_description)
    
    # Julia-specific tasks
    if occursin("julia", task_lower)
        return "julia"
    end
    
    # Python-specific tasks
    if any(occursin(kw, task_lower) for kw in ["python", "pandas", "numpy", "sklearn", "pytorch"])
        return "python"
    end
    
    # JavaScript tasks
    if any(occursin(kw, task_lower) for kw in ["javascript", "js", "node", "browser"])
        return "javascript"
    end
    
    # Shell/scripting
    if any(occursin(kw, task_lower) for kw in ["shell", "bash", "script", "command"])
        return "shell"
    end
    
    # Default to Julia for the adaptive-kernel system
    return "julia"
end

"""
    assess_safety_level - Assess safety level of the computational task
"""
function assess_safety_level(task_description::String)::String
    task_lower = lowercase(task_description)
    
    # High risk operations
    high_risk = ["delete", "remove", "drop", "destroy", "format", "rm -rf"]
    if any(occursin(kw, task_lower) for kw in high_risk)
        return "high"
    end
    
    # Medium risk operations
    medium_risk = ["write", "modify", "update", "execute", "run"]
    if any(occursin(kw, task_lower) for kw in medium_risk)
        return "medium"
    end
    
    return "low"
end

# ============================================================================
# TASK CATEGORIZATION
# ============================================================================

"""
    categorize_task - Categorize task into computational type
"""
function categorize_task(task_description::String, task_type::String)::TaskCategory
    # Check explicit type first
    if task_type == "calculation" || task_type == "computation"
        return CALCULATION
    elseif task_type == "data_analysis" || task_type == "analysis"
        return DATA_ANALYSIS
    elseif task_type == "code_generation" || task_type == "generation"
        return CODE_GENERATION
    elseif task_type == "simulation"
        return SIMULATION
    elseif task_type == "optimization"
        return OPTIMIZATION
    end
    
    # Infer from description
    task_lower = lowercase(task_description)
    
    # Calculation keywords
    if any(occursin(kw, task_lower) for kw in ["calculate", "compute", "math", "sum", "average", "statistic"])
        return CALCULATION
    end
    
    # Data analysis keywords
    if any(occursin(kw, task_lower) for kw in ["analyze", "data", "dataset", "filter", "sort", "aggregate"])
        return DATA_ANALYSIS
    end
    
    # Code generation keywords
    if any(occursin(kw, task_lower) for kw in ["write code", "generate", "implement", "create function", "program"])
        return CODE_GENERATION
    end
    
    # Simulation keywords
    if any(occursin(kw, task_lower) for kw in ["simulate", "model", "forecast", "predict", "emulate"])
        return SIMULATION
    end
    
    # Optimization keywords
    if any(occursin(kw, task_lower) for kw in ["optimize", "minimize", "maximize", "best", "optimal"])
        return OPTIMIZATION
    end
    
    # Default to calculation for unknown types
    return CALCULATION
end

# ============================================================================
# EXECUTION STRATEGY GENERATION
# ============================================================================

"""
    generate_execution_strategy - Generate the code/execution approach
"""
function generate_execution_strategy(
    category::TaskCategory,
    task_description::String,
    needs::Dict{String, Any}
)::String
    language = get(needs, "preferred_language", "julia")
    complexity = get(needs, "complexity", "low")
    safety = get(needs, "safety_level", "low")
    
    # Build strategy based on category
    strategy_parts = String[]
    
    push!(strategy_parts, "language:$language")
    push!(strategy_parts, "complexity:$complexity")
    push!(strategy_parts, "safety:$safety")
    
    # Category-specific strategy
    if category == CALCULATION
        push!(strategy_parts, "approach:direct_computation")
    elseif category == DATA_ANALYSIS
        push!(strategy_parts, "approach:pipeline_processing")
    elseif category == CODE_GENERATION
        push!(strategy_parts, "approach:generate_and_validate")
    elseif category == SIMULATION
        push!(strategy_parts, "approach:iterative_simulation")
    elseif category == OPTIMIZATION
        push!(strategy_parts, "approach:iterative_optimization")
    end
    
    # Sandbox execution recommendation
    if safety in ["medium", "high"]
        push!(strategy_parts, "sandboxed:true")
    else
        push!(strategy_parts, "sandboxed:false")
    end
    
    return join(strategy_parts, " | ")
end

"""
    calculate_code_confidence - Calculate confidence based on task clarity and complexity
"""
function calculate_code_confidence(
    task_description::String,
    needs::Dict{String, Any},
    category::TaskCategory
)::Float64
    base_confidence = 0.5
    
    # Clear task descriptions get higher confidence
    if length(task_description) > 10 && length(task_description) < 1000
        base_confidence += 0.15
    end
    
    # Specific language specification increases confidence
    language = get(needs, "preferred_language", "")
    if language != ""
        base_confidence += 0.1
    end
    
    # Lower complexity gets higher confidence (easier to verify)
    complexity = get(needs, "complexity", "high")
    if complexity == "low"
        base_confidence += 0.15
    elseif complexity == "medium"
        base_confidence += 0.05
    end
    
    # Safety assessment
    safety = get(needs, "safety_level", "low")
    if safety == "low"
        base_confidence += 0.1
    end
    
    return clamp(base_confidence, 0.0, 1.0)
end

# ============================================================================
# EVIDENCE AND ALTERNATIVES
# ============================================================================

"""
    generate_evidence - Generate supporting calculations/analysis evidence
"""
function generate_evidence(category::TaskCategory, needs::Dict{String, Any})::Vector{String}
    evidence = String[]
    
    # Add complexity analysis
    complexity = get(needs, "complexity", "unknown")
    push!(evidence, "complexity_analysis:$complexity")
    
    # Add language specification
    language = get(needs, "preferred_language", "julia")
    push!(evidence, "language:$language")
    
    # Add safety assessment
    safety = get(needs, "safety_level", "low")
    push!(evidence, "safety_assessment:$safety")
    
    # Add data requirements if applicable
    if get(needs, "needs_data", false)
        push!(evidence, "data_required:true")
    end
    
    return evidence
end

"""
    generate_alternative_strategies - Generate alternative computational strategies
"""
function generate_alternative_strategies(category::TaskCategory, task_description::String)::Vector{String}
    alternatives = String[]
    
    # Alternative 1: Different language approach
    if category == CALCULATION
        push!(alternatives, "language:python | approach:direct_computation")
        push!(alternatives, "language:julia | approach:vectorized")
    elseif category == DATA_ANALYSIS
        push!(alternatives, "language:python | approach:pandas_pipeline")
        push!(alternatives, "language:julia | approach:dataframes")
    elseif category == CODE_GENERATION
        push!(alternatives, "template_based:true")
        push!(alternatives, "llm_assisted:true")
    elseif category == SIMULATION
        push!(alternatives, "iterative:true")
        push!(alternatives, "monte_carlo:true")
    elseif category == OPTIMIZATION
        push!(alternatives, "method:gradient_descent")
        push!(alternatives, "method:genetic_algorithm")
    end
    
    return alternatives
end

"""
    build_code_reasoning - Build human-readable reasoning for the proposal
"""
function build_code_reasoning(
    task_description::String,
    category::TaskCategory,
    needs::Dict{String, Any},
    confidence::Float64
)::String
    reasoning_parts = String[]
    
    push!(reasoning_parts, "Computational task analysis")
    push!(reasoning_parts, "Category: $(string(category))")
    
    complexity = get(needs, "complexity", "unknown")
    push!(reasoning_parts, "Complexity: $complexity")
    
    language = get(needs, "preferred_language", "julia")
    push!(reasoning_parts, "Language: $language")
    
    safety = get(needs, "safety_level", "low")
    push!(reasoning_parts, "Safety: $safety")
    
    push!(reasoning_parts, "Confidence: $(round(confidence * 100))%")
    
    return join(reasoning_parts, ". ") * "."
end

# ============================================================================
# SANDBOX EXECUTION (using ExecutionSandbox)
# ============================================================================

"""
    execute_code_safely - Safely execute code using ExecutionSandbox
    
    This function implements the full sandbox execution pipeline:
    1. Look up capability_code_interpreter in ToolRegistry
    2. Call Kernel.approve() for sovereign approval (LEP score calculation)
    3. Check agent's energy_acc (viability budget) against metabolic clock (136.1 Hz)
    4. Execute in ExecutionSandbox with namespace isolation
    5. Capture BrainOutput and compute RPE signal
    6. Send RPE back via lock-free ring buffer IPC to update policy gradients
"""
function execute_code_safely(
    agent::CodeAgent,
    code::String,
    language::String,
    params::Dict{String, Any},
    registry::Union{ToolRegistry, Nothing}=nothing,
    kernel::Union{KernelState, Nothing}=nothing
)::Dict{String, Any}
    # Step 1: Look up capability_code_interpreter in ToolRegistry
    tool_id = "capability_code_interpreter"
    
    if registry !== nothing
        metadata = get_tool_metadata(registry, tool_id)
        if metadata === nothing
            return Dict{String, Any}(
                "success" => false,
                "output" => nothing,
                "error" => "Code interpreter capability not registered",
                "execution_time" => 0.0,
                "sandbox_mode" => "none",
                "rpe" => 0.0
            )
        end
        
        # Validate parameters against metadata
        if !validate_params(metadata, params)
            return Dict{String, Any}(
                "success" => false,
                "output" => nothing,
                "error" => "Invalid parameters for code interpreter",
                "execution_time" => 0.0,
                "sandbox_mode" => "none",
                "rpe" => 0.0
            )
        end
    end
    
    # Step 2: Call Kernel.approve() for sovereign approval
    if kernel !== nothing
        # Create ActionProposal for approval
        proposal = ActionProposal(
            id=string(uuid4()),
            action_type="code_execution",
            parameters=Dict{String, Any}(
                "code" => code,
                "language" => language
            ),
            risk=0.8,  # Code execution is high risk
            expected_reward=0.5,
            timestamp=now()
        )
        
        # Get kernel decision
        decision = approve(kernel, proposal, Dict{String, Any}())
        
        # Fail-closed: deny if kernel doesn't approve
        if decision !== APPROVED
            return Dict{String, Any}(
                "success" => false,
                "output" => nothing,
                "error" => "Kernel denied code execution approval",
                "execution_time" => 0.0,
                "sandbox_mode" => "none",
                "rpe" => 0.0
            )
        end
    end
    
    # Step 3: Check agent's energy_acc against metabolic clock (136.1 Hz)
    # Configure sandbox with timeout in ms
    timeout_ms = get(params, "timeout", 500) * 1000  # Convert to ms, default 500ms
    
    config = SandboxConfig(
        timeout_ms = timeout_ms,
        memory_limit_mb = get(params, "memory_limit", 512),
        cpu_limit = get(params, "cpu_limit", 0.5),
        network_allowed = get(params, "network_allowed", false),
        filesystem_allowed = get(params, "filesystem_allowed", false),
        isolation_level = PROCESS_ISOLATION,
        enable_wdt = get(params, "enable_wdt", true),
        scratch_pad_path = get(params, "scratch_pad_path", nothing)
    )
    
    # Calculate required energy based on timeout and cpu limit
    required_energy = calculate_energy_consumption(Float64(timeout_ms), config.cpu_limit)
    
    # Check energy budget (fail-closed)
    if !check_energy_budget(agent.energy_acc, required_energy)
        return Dict{String, Any}(
            "success" => false,
            "output" => nothing,
            "error" => "Insufficient energy for code execution (metabolic gating)",
            "execution_time" => 0.0,
            "sandbox_mode" => "none",
            "rpe" => 0.0
        )
    end
    
    # Step 4: Execute in ExecutionSandbox with namespace isolation
    # Select sandbox mode based on language and security requirements
    mode = WardenSandbox(PROCESS_ISOLATION)
    
    # Build execution params
    execution_params = Dict{String, Any}(
        "code" => code,
        "language" => language
    )
    
    # Execute in sandbox
    result = execute_in_sandbox(tool_id, execution_params, mode, registry, config)
    
    # Step 5: Capture BrainOutput and compute RPE signal
    rpe = 0.0
    if result.brain_output !== nothing
        # Deduct energy consumed from agent's energy_acc
        agent.energy_acc -= result.brain_output.energy_consumed
        
        # Compute RPE for policy gradient updates
        rpe = compute_rpe_from_brain_output(result.brain_output)
        
        # Update brain output with RPE
        result.brain_output.rpe_signal = rpe
    end
    
    # Step 6: Send RPE back via lock-free ring buffer IPC
    execution_id = generate_execution_id()
    send_rpe_to_warden(rpe, execution_id)
    
    # Track success/failure
    if result.success
        agent.successful_executions += 1
    else
        agent.failed_executions += 1
    end
    
    return Dict{String, Any}(
        "success" => result.success,
        "output" => result.output,
        "error" => result.error,
        "execution_time" => result.execution_time,
        "sandbox_mode" => string(result.sandbox_mode),
        "rpe" => rpe,
        "energy_remaining" => agent.energy_acc
    )
end

# ============================================================================
# METRICS AND TRACKING
# ============================================================================

"""
    get_execution_accuracy - Calculate the agent's execution accuracy
"""
function get_execution_accuracy(agent::CodeAgent)::Float64
    total = agent.successful_executions + agent.failed_executions
    if total == 0
        return 0.0
    end
    return agent.successful_executions / total
end

"""
    validate_task_input - Validate task input for safety
"""
function validate_task_input(task_description::String)::Tuple{Bool, String}
    # Check for empty input
    if isempty(strip(task_description))
        return false, "Empty task description"
    end
    
    # Check for dangerous operations
    dangerous_patterns = [
        r"rm\s+-rf",
        r"drop\s+table",
        r"delete\s+from",
        r"format\s+drive",
        r"shutdown",
        r"reboot"
    ]
    
    task_lower = lowercase(task_description)
    for pattern in dangerous_patterns
        if occursin(pattern, task_lower)
            return false, "Potentially dangerous operation detected"
        end
    end
    
    return true, "Valid"
end

end # module CodeAgentModule
