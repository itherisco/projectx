# planning/HierarchicalPlanner.jl - Hierarchical Planning (Manager Layer)
# Enables long-term planning by separating high-level "Missions" from low-level "Micro-Steps"

module HierarchicalPlanner

using Dates
using UUIDs
using Logging

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    Option - Abstract action representing a sequence of primitive actions
    Acts as a low-level policy (option) in hierarchical planning
"""
struct Option
    name::String
    primitive_actions::Vector{String}  # Sequence of primitive actions
    termination_condition::Function     # When to stop executing this option
    initiation_condition::Function     # When this option is valid
    
    function Option(
        name::String,
        primitive_actions::Vector{String},
        initiation_condition::Function,
        termination_condition::Function
    )
        return new(name, primitive_actions, termination_condition, initiation_condition)
    end
end

"""
    Mission - High-level goal that requires multiple options to complete
    Managed by the high-level policy (Manager)
"""
struct Mission
    id::UUID
    description::String
    target_state::Dict{Symbol, Any}
    deadline::Union{DateTime, Nothing}
    status::Symbol  # :pending, :in_progress, :completed, :failed
    created_at::DateTime
    started_at::Union{DateTime, Nothing}
    completed_at::Union{DateTime, Nothing}
    failure_reason::Union{String, Nothing}
    
    function Mission(
        description::String,
        target_state::Dict{Symbol, Any};
        deadline::Union{DateTime, Nothing} = nothing
    )
        return new(
            uuid4(),
            description,
            target_state,
            deadline,
            :pending,
            now(),
            nothing,
            nothing,
            nothing
        )
    end
end

"""
    MissionExecution - Runtime state for an active mission
"""
mutable struct MissionExecution
    mission::Mission
    selected_options::Vector{Option}
    current_option_index::Int
    current_action_index::Int
    execution_history::Vector{Dict{String, Any}}
    started_at::DateTime
    
    function MissionExecution(mission::Mission)
        return new(
            mission,
            Option[],
            1,
            1,
            Dict{String, Any}[],
            now()
        )
    end
end

"""
    HierarchicalPlanner - Manages high-level missions and low-level options
"""
mutable struct HierarchicalPlanner
    # Manager-level policy
    manager_policy::Function  # High-level policy that selects missions
    
    # Library of options (low-level policies)
    available_options::Dict{String, Option}
    
    # Active mission tracking
    active_mission::Union{Mission, Nothing}
    active_execution::Union{MissionExecution, Nothing}
    current_option::Union{Option, Nothing}
    
    # Execution state
    option_execution_state::Dict{String, Any}
    mission_queue::Vector{Mission}
    completed_missions::Vector{Mission}
    failed_missions::Vector{Mission}
    
    # Configuration
    default_option_timeout::Union{Dates.Period, Nothing}
    enable_async_execution::Bool
    
    # Callbacks
    on_mission_complete::Union{Function, Nothing}
    on_mission_fail::Union{Function, Nothing}
    on_option_complete::Union{Function, Nothing}
    
    function HierarchicalPlanner(;
        manager_policy::Function = (planner, context) -> select_mission_default(planner, context),
        default_timeout::Union{Dates.Period, Nothing} = Dates.Minute(5),
        enable_async::Bool = false
    )
        planner = new(
            manager_policy,
            Dict{String, Option}(),
            nothing,
            nothing,
            nothing,
            Dict{String, Any}(),
            Mission[],
            Mission[],
            Mission[],
            default_timeout,
            enable_async,
            nothing,
            nothing,
            nothing
        )
        
        # Initialize with predefined options
        initialize_predefined_options!(planner)
        
        return planner
    end
end

# ============================================================================
# CONSTRUCTOR FUNCTIONS
# ============================================================================

"""
    create_option(name, actions, init_cond, term_cond)
Create a new option with the given parameters.
"""
function create_option(
    name::String,
    primitive_actions::Vector{String},
    initiation_condition::Function,
    termination_condition::Function
)::Option
    return Option(name, primitive_actions, initiation_condition, termination_condition)
end

"""
    create_mission(description, target_state; deadline=nothing)
Create a new mission with the given parameters.
"""
function create_mission(
    description::String,
    target_state::Dict{Symbol, Any};
    deadline::Union{DateTime, Nothing} = nothing
)::Mission
    return Mission(description, target_state; deadline = deadline)
end

# ============================================================================
# MISSION MANAGEMENT
# ============================================================================

"""
    select_mission(planner, context)
High-level decision: select which mission to pursue next.
"""
function select_mission(
    planner::HierarchicalPlanner,
    context::Dict{Symbol, Any}
)::Union{Mission, Nothing}
    # Use the manager policy to select mission
    return planner.manager_policy(planner, context)
end

"""
    select_mission_default - Default mission selection policy
Selects the highest priority pending mission based on deadline proximity
"""
function select_mission_default(
    planner::HierarchicalPlanner,
    context::Dict{Symbol, Any}
)::Union{Mission, Nothing}
    
    # First check if there's an active mission
    if planner.active_mission !== nothing
        if planner.active_mission.status == :in_progress
            return planner.active_mission
        end
    end
    
    # Find pending missions
    pending = filter(m -> m.status == :pending, planner.mission_queue)
    
    if isempty(pending)
        return nothing
    end
    
    # Sort by deadline (earliest deadline first, or no deadline last)
    now_dt = now()
    sorted = sort(pending, by = m -> begin
        if m.deadline === nothing
            return DateTime(9999, 12, 31)  # Far future for no deadline
        end
        return m.deadline
    end)
    
    return sorted[1]
end

"""
    promote_to_mission!(planner, goal_description)
Elevate a goal to a mission at the manager level.
"""
function promote_to_mission!(
    planner::HierarchicalPlanner,
    goal_description::String;
    target_state::Dict{Symbol, Any} = Dict{Symbol, Any}(),
    deadline::Union{DateTime, Nothing} = nothing
)::Mission
    
    mission = create_mission(goal_description, target_state; deadline = deadline)
    push!(planner.mission_queue, mission)
    
    @info "Promoted to mission: $(mission.description)" mission_id=mission.id
    
    return mission
end

"""
    add_mission!(planner, mission)
Add a mission to the planning queue.
"""
function add_mission!(planner::HierarchicalPlanner, mission::Mission)
    push!(planner.mission_queue, mission)
end

"""
    start_mission!(planner, mission)
Start executing a mission.
"""
function start_mission!(planner::HierarchicalPlanner, mission::Mission)
    mission.status = :in_progress
    mission.started_at = now()
    planner.active_mission = mission
    planner.active_execution = MissionExecution(mission)
    
    @info "Started mission: $(mission.description)"
end

"""
    complete_mission!(planner, mission)
Mark a mission as completed.
"""
function complete_mission!(planner::HierarchicalPlanner, mission::Mission)
    mission.status = :completed
    mission.completed_at = now()
    
    # Move from queue to completed
    filter!(m -> m.id != mission.id, planner.mission_queue)
    push!(planner.completed_missions, mission)
    
    # Execute callback if registered
    if planner.on_mission_complete !== nothing
        planner.on_mission_complete(mission)
    end
    
    # Clear active mission if this was it
    if planner.active_mission !== nothing && planner.active_mission.id == mission.id
        planner.active_mission = nothing
        planner.active_execution = nothing
    end
    
    @info "Completed mission: $(mission.description)"
end

"""
    fail_mission!(planner, mission, reason)
Mark a mission as failed.
"""
function fail_mission!(
    planner::HierarchicalPlanner,
    mission::Mission,
    reason::String
)
    mission.status = :failed
    mission.failure_reason = reason
    mission.completed_at = now()
    
    # Move from queue to failed
    filter!(m -> m.id != mission.id, planner.mission_queue)
    push!(planner.failed_missions, mission)
    
    # Execute callback if registered
    if planner.on_mission_fail !== nothing
        planner.on_mission_fail(mission, reason)
    end
    
    # Clear active mission if this was it
    if planner.active_mission !== nothing && planner.active_mission.id == mission.id
        planner.active_mission = nothing
        planner.active_execution = nothing
    end
    
    @warn "Failed mission: $(mission.description) reason: $reason"
end

# ============================================================================
# OPTION MANAGEMENT
# ============================================================================

"""
    select_option(planner, mission, state)
Choose the best option for the given mission and current state.
"""
function select_option(
    planner::HierarchicalPlanner,
    mission::Mission,
    state::Dict{Symbol, Any}
)::Union{Option, Nothing}
    
    # Get applicable options based on initiation conditions
    applicable_options = Option[]
    
    for (name, option) in planner.available_options
        try
            if option.initiation_condition(state)
                push!(applicable_options, option)
            end
        catch e
            @debug "Option initiation check failed for $name: $e"
        end
    end
    
    if isempty(applicable_options)
        return nothing
    end
    
    # Simple selection: return first applicable option
    # In production, would use a more sophisticated selection policy
    return applicable_options[1]
end

"""
    step_option!(planner, state)
Execute one step of the current option.
Returns the action to execute, or nothing if option is complete.
"""
function step_option!(
    planner::HierarchicalPlanner,
    state::Dict{Symbol, Any}
)::Union{String, Nothing}
    
    # If no active execution, nothing to step
    if planner.active_execution === nothing
        return nothing
    end
    
    exec = planner.active_execution
    mission = exec.mission
    
    # If we need to select an option
    if isempty(exec.selected_options)
        # Try to select an option for this mission
        selected = select_option(planner, mission, state)
        
        if selected === nothing
            # No applicable option - mission fails
            fail_mission!(planner, mission, "No applicable option found")
            return nothing
        end
        
        push!(exec.selected_options, selected)
        planner.current_option = selected
    end
    
    # Get current option
    current_option = exec.selected_options[exec.current_option_index]
    
    # Check termination condition
    if is_option_terminated(planner, state)
        # Option completed - check if mission is complete
        if check_mission_complete(mission, state)
            complete_mission!(planner, mission)
            return nothing
        else
            # Need to select next option
            exec.current_option_index += 1
            exec.current_action_index = 1
            
            if exec.current_option_index > length(exec.selected_options)
                # No more options - need to select new one
                exec.selected_options = Option[]
                return step_option!(planner, state)  # Recurse to select next
            end
            
            current_option = exec.selected_options[exec.current_option_index]
            planner.current_option = current_option
        end
    end
    
    # Get next primitive action
    if exec.current_action_index > length(current_option.primitive_actions)
        # All actions in current option complete - check termination
        if is_option_terminated(planner, state)
            return step_option!(planner, state)  # Recurse
        end
        return nothing
    end
    
    action = current_option.primitive_actions[exec.current_action_index]
    exec.current_action_index += 1
    
    # Record in history
    push!(exec.execution_history, Dict(
        "action" => action,
        "option" => current_option.name,
        "timestamp" => now()
    ))
    
    return action
end

"""
    is_option_terminated(planner, state)
Check if the current option should terminate.
"""
function is_option_terminated(
    planner::HierarchicalPlanner,
    state::Dict{Symbol, Any}
)::Bool
    
    if planner.current_option === nothing
        return true
    end
    
    try
        return planner.current_option.termination_condition(state)
    catch e
        @debug "Option termination check failed: $e"
        return true  # Default to terminating on error
    end
end

"""
    check_mission_complete(mission, state)
Check if the mission target state has been achieved.
"""
function check_mission_complete(
    mission::Mission,
    state::Dict{Symbol, Any}
)::Bool
    
    # Check each key in target state
    for (key, expected_value) in mission.target_state
        current_value = get(state, key, nothing)
        
        if current_value === nothing
            return false
        end
        
        # Simple equality check - in production would be more sophisticated
        if current_value != expected_value
            return false
        end
    end
    
    return true
end

"""
    get_option_progress(planner)
Get the progress of the current option execution.
"""
function get_option_progress(
    planner::HierarchicalPlanner
)::Dict{Symbol, Any}
    
    if planner.active_execution === nothing
        return Dict(:active => false)
    end
    
    exec = planner.active_execution
    current_option = exec.selected_options[exec.current_option_index]
    
    total_actions = length(current_option.primitive_actions)
    completed_actions = exec.current_action_index - 1
    
    return Dict(
        :active => true,
        :mission => exec.mission.description,
        :option => current_option.name,
        :actions_completed => completed_actions,
        :total_actions => total_actions,
        :progress => total_actions > 0 ? completed_actions / total_actions : 0.0
    )
end

# ============================================================================
# OPTION REGISTRATION
# ============================================================================

"""
    register_option!(planner, option)
Register a new option in the planner's library.
"""
function register_option!(planner::HierarchicalPlanner, option::Option)
    planner.available_options[option.name] = option
    @info "Registered option: $(option.name)"
end

"""
    get_option(planner, name)
Get an option by name.
"""
function get_option(
    planner::HierarchicalPlanner,
    name::String
)::Union{Option, Nothing}
    return get(planner.available_options, name, nothing)
end

"""
    list_options(planner)
List all available options.
"""
function list_options(planner::HierarchicalPlanner)::Vector{String}
    return collect(keys(planner.available_options))
end

# ============================================================================
# PREDEFINED OPTIONS
# ============================================================================

"""
    initialize_predefined_options!(planner)
Add predefined options to the planner.
"""
function initialize_predefined_options!(planner::HierarchicalPlanner)
    
    # Option: optimize_workspace
    # Closes unused applications, clears memory, sets focus mode
    optimize_workspace_init(state) = begin
        # Initiation: workspace is cluttered or performance is degraded
        get(state, :workspace_cluttered, false) || 
        get(state, :performance_degraded, false) ||
        get(state, :cpu_usage, 0.0) > 0.7
    end
    
    optimize_workspace_term(state) = begin
        # Termination: workspace is optimized
        get(state, :workspace_optimized, false)
    end
    
    optimize_workspace = create_option(
        "optimize_workspace",
        ["close_unused", "clear_memory", "set_focus_mode"],
        optimize_workspace_init,
        optimize_workspace_term
    )
    register_option!(planner, optimize_workspace)
    
    # Option: research_topic
    # Opens browser, searches web, saves notes
    research_topic_init(state) = begin
        # Initiation: need to research a topic
        get(state, :needs_research, false)
    end
    
    research_topic_term(state) = begin
        # Termination: research complete
        get(state, :research_complete, false)
    end
    
    research_topic = create_option(
        "research_topic",
        ["open_browser", "search_web", "save_notes"],
        research_topic_init,
        research_topic_term
    )
    register_option!(planner, research_topic)
    
    # Option: fix_bug
    # Analyzes error, searches similar issues, applies fix, tests solution
    fix_bug_init(state) = begin
        # Initiation: bug detected or reported
        get(state, :bug_detected, false) || get(state, :error_detected, false)
    end
    
    fix_bug_term(state) = begin
        # Termination: bug is fixed and tested
        get(state, :bug_fixed, false) && get(state, :tests_passed, false)
    end
    
    fix_bug = create_option(
        "fix_bug",
        ["analyze_error", "search_similar", "apply_fix", "test_solution"],
        fix_bug_init,
        fix_bug_term
    )
    register_option!(planner, fix_bug)
    
    # Option: write_document
    # Opens word processor, writes content, saves document
    write_document_init(state) = begin
        # Initiation: need to write a document
        get(state, :needs_writing, false)
    end
    
    write_document_term(state) = begin
        # Termination: document is written and saved
        get(state, :document_written, false)
    end
    
    write_document = create_option(
        "write_document",
        ["open_word_processor", "write_content", "save_document"],
        write_document_init,
        write_document_term
    )
    register_option!(planner, write_document)
    
    # Option: analyze_data
    # Collects data, processes data, generates insights
    analyze_data_init(state) = begin
        # Initiation: need to analyze data
        get(state, :needs_analysis, false)
    end
    
    analyze_data_term(state) = begin
        # Termination: analysis complete
        get(state, :analysis_complete, false)
    end
    
    analyze_data = create_option(
        "analyze_data",
        ["collect_data", "process_data", "generate_insights"],
        analyze_data_init,
        analyze_data_term
    )
    register_option!(planner, analyze_data)
    
    # Option: deploy_system
    # Prepares deployment, runs deployment, verifies deployment
    deploy_system_init(state) = begin
        # Initiation: ready to deploy
        get(state, :ready_to_deploy, false)
    end
    
    deploy_system_term(state) = begin
        # Termination: deployment successful
        get(state, :deployment_successful, false)
    end
    
    deploy_system = create_option(
        "deploy_system",
        ["prepare_deployment", "run_deployment", "verify_deployment"],
        deploy_system_init,
        deploy_system_term
    )
    register_option!(planner, deploy_system)
    
    @info "Initialized $(length(planner.available_options)) predefined options"
end

# ============================================================================
# PLANNER STATE FUNCTIONS
# ============================================================================

"""
    has_active_mission(planner)
Check if the planner has an active mission.
"""
function has_active_mission(planner::HierarchicalPlanner)::Bool
    return planner.active_mission !== nothing && 
           planner.active_mission.status == :in_progress
end

"""
    get_mission_status(planner, mission_id)
Get the status of a specific mission.
"""
function get_mission_status(
    planner::HierarchicalPlanner,
    mission_id::UUID
)::Union{Symbol, Nothing}
    
    # Check active mission
    if planner.active_mission !== nothing && planner.active_mission.id == mission_id
        return planner.active_mission.status
    end
    
    # Check queue
    for mission in planner.mission_queue
        if mission.id == mission_id
            return mission.status
        end
    end
    
    # Check completed
    for mission in planner.completed_missions
        if mission.id == mission_id
            return :completed
        end
    end
    
    # Check failed
    for mission in planner.failed_missions
        if mission.id == mission_id
            return :failed
        end
    end
    
    return nothing
end

"""
    get_planner_stats(planner)
Get statistics about the planner's state.
"""
function get_planner_stats(planner::HierarchicalPlanner)::Dict{Symbol, Any}
    return Dict(
        :pending_missions => length(planner.mission_queue),
        :completed_missions => length(planner.completed_missions),
        :failed_missions => length(planner.failed_missions),
        :available_options => length(planner.available_options),
        :active_mission => planner.active_mission !== nothing ? planner.active_mission.description : nothing,
        :current_option => planner.current_option !== nothing ? planner.current_option.name : nothing
    )
end

# ============================================================================
# CALLBACK REGISTRATION
# ============================================================================

"""
    set_mission_complete_callback!(planner, callback)
Register a callback for mission completion.
"""
function set_mission_complete_callback!(
    planner::HierarchicalPlanner,
    callback::Function
)
    planner.on_mission_complete = callback
end

"""
    set_mission_fail_callback!(planner, callback)
Register a callback for mission failure.
"""
function set_mission_fail_callback!(
    planner::HierarchicalPlanner,
    callback::Function
)
    planner.on_mission_fail = callback
end

"""
    set_option_complete_callback!(planner, callback)
Register a callback for option completion.
"""
function set_option_complete_callback!(
    planner::HierarchicalPlanner,
    callback::Function
)
    planner.on_option_complete = callback
end

# ============================================================================
# EXPORTS
# ============================================================================

export 
    # Types
    Option,
    Mission,
    MissionExecution,
    HierarchicalPlanner,
    
    # Constructor functions
    create_option,
    create_mission,
    
    # Mission management
    select_mission,
    promote_to_mission!,
    add_mission!,
    start_mission!,
    complete_mission!,
    fail_mission!,
    has_active_mission,
    get_mission_status,
    get_planner_stats,
    
    # Option management
    select_option,
    step_option!,
    is_option_terminated,
    register_option!,
    get_option,
    list_options,
    get_option_progress,
    
    # Callbacks
    set_mission_complete_callback!,
    set_mission_fail_callback!,
    set_option_complete_callback!

end # module HierarchicalPlanner
