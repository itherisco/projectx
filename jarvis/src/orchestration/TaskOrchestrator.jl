# jarvis/src/orchestration/TaskOrchestrator.jl - Proactive Task Planning & Optimization
# Scans WorldState to suggest optimizations and proactive actions

module TaskOrchestrator

using Dates
using UUIDs
using Statistics

export 
    OrchestratorConfig,
    ProactiveSuggestion,
    analyze_and_suggest,
    check_system_health,
    generate_optimization_suggestions,
    schedule_proactive_tasks

# Import Jarvis types
include("../types.jl")
using ..JarvisTypes

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    OrchestratorConfig - Configuration for proactive orchestration
"""
struct OrchestratorConfig
    scan_interval::Second        # How often to scan for opportunities
    suggestion_threshold::Float32  # Minimum impact to trigger suggestion
    max_suggestions::Int         # Maximum suggestions per cycle
    enable_auto_optimization::Bool  # Whether to auto-apply safe optimizations
    
    function OrchestratorConfig(;
        scan_interval::Second = Second(60),
        suggestion_threshold::Float32 = 0.3f0,
        max_suggestions::Int = 3,
        enable_auto_optimization::Bool = false
    )
        new(scan_interval, suggestion_threshold, max_suggestions, enable_auto_optimization)
    end
end

# ============================================================================
# SUGGESTION TYPES
# ============================================================================

"""
    ProactiveSuggestion - A proactive suggestion for the user
"""
struct ProactiveSuggestion
    id::UUID
    title::String
    description::String
    category::Symbol  # :optimization, :safety, :productivity, :resource
    estimated_impact::Float32  # [0, 1]
    action_id::Union{String, Nothing}  # Capability to execute
    auto_applicable::Bool
    created_at::DateTime
    
    function ProactiveSuggestion(
        title::String,
        description::String,
        category::Symbol;
        estimated_impact::Float32 = 0.5f0,
        action_id::Union{String, Nothing} = nothing,
        auto_applicable::Bool = false
    )
        new(uuid4(), title, description, category, estimated_impact, action_id, auto_applicable, now())
    end
end

# ============================================================================
# SYSTEM HEALTH ANALYSIS
# ============================================================================

"""
    check_system_health - Analyze system metrics for anomalies
"""
function check_system_health(
    metrics::Dict{String, Float32}
)::Dict{Symbol, Any}
    
    health = Dict{Symbol, Any}()
    
    # CPU health
    cpu = get(metrics, "cpu_load", 0.0)
    if cpu > 0.9
        health[:cpu] = :critical
    elseif cpu > 0.7
        health[:cpu] = :warning
    else
        health[:cpu] = :healthy
    end
    
    # Memory health
    mem = get(metrics, "memory_usage", 0.0)
    if mem > 0.9
        health[:memory] = :critical
    elseif mem > 0.75
        health[:memory] = :warning
    else
        health[:memory] = :healthy
    end
    
    # Disk health
    disk = get(metrics, "disk_usage", 0.0)
    if disk > 0.95
        health[:disk] = :critical
    elseif disk > 0.85
        health[:disk] = :warning
    else
        health[:disk] = :healthy
    end
    
    # Network
    latency = get(metrics, "network_latency", 0.0)
    if latency > 200
        health[:network] = :warning
    else
        health[:network] = :healthy
    end
    
    # Overall
    statuses = values(health)
    if :critical in statuses
        health[:overall] = :critical
    elseif :warning in statuses
        health[:overall] = :warning
    else
        health[:overall] = :healthy
    end
    
    return health
end

# ============================================================================
# OPTIMIZATION SUGGESTIONS
# ============================================================================

"""
    generate_optimization_suggestions - Analyze and generate optimization suggestions
"""
function generate_optimization_suggestions(
    metrics::Dict{String, Float32},
    recent_actions::Vector{Dict{String, Any}},
    config::OrchestratorConfig
)::Vector{ProactiveSuggestion}
    
    suggestions = ProactiveSuggestion[]
    
    # CPU optimization
    cpu = get(metrics, "cpu_load", 0.0)
    if cpu > 0.8
        push!(suggestions, ProactiveSuggestion(
            "High CPU Usage Detected",
            "Your CPU is at $(round(cpu*100))% utilization. Consider throttling background tasks.",
            :resource;
            estimated_impact = cpu,
            action_id = "throttle_background_tasks",
            auto_applicable = true
        ))
    end
    
    # Memory optimization
    mem = get(metrics, "memory_usage", 0.0)
    if mem > 0.85
        push!(suggestions, ProactiveSuggestion(
            "High Memory Usage",
            "Memory usage is at $(round(mem*100))%. Consider clearing cache or closing unused applications.",
            :resource;
            estimated_impact = mem,
            action_id = "clear_cache"
        ))
    end
    
    # Disk space
    disk = get(metrics, "disk_usage", 0.0)
    if disk > 0.9
        push!(suggestions, ProactiveSuggestion(
            "Low Disk Space",
            "Disk is $(round(disk*100))% full. Consider cleaning temporary files.",
            :safety;
            estimated_impact = disk,
            action_id = "clean_temp_files"
        ))
    end
    
    # Analyze action patterns for productivity suggestions
    if length(recent_actions) > 10
        action_counts = Dict{String, Int}()
        for action in recent_actions
            aid = get(action, "action_id", "unknown")
            action_counts[aid] = get(action_counts, aid, 0) + 1
        end
        
        # Find repetitive actions
        for (action, count) in action_counts
            if count > 5
                push!(suggestions, ProactiveSuggestion(
                    "Repetitive Task Detected",
                    "You've executed '$action' $count times recently. Consider automating this.",
                    :productivity;
                    estimated_impact = 0.6f0,
                    action_id = "create_automation"
                ))
            end
        end
    end
    
    # Sort by impact and limit
    sort!(suggestions, by = s -> s.estimated_impact, rev = true)
    
    return suggestions[1:min(config.max_suggestions, length(suggestions))]
end

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================

"""
    analyze_and_suggest - Main orchestration function
    Returns proactive suggestions based on current state
"""
function analyze_and_suggest(
    world_observation::WorldObservation,
    recent_actions::Vector{Dict{String, Any}},
    config::OrchestratorConfig
)::Vector{ProactiveSuggestion}
    
    suggestions = ProactiveSuggestion[]
    
    # Check system health
    health = check_system_health(world_observation.system_metrics)
    
    # Generate optimization suggestions
    opt_suggestions = generate_optimization_suggestions(
        world_observation.system_metrics,
        recent_actions,
        config
    )
    append!(suggestions, opt_suggestions)
    
    # Check for safety issues
    if health[:overall] == :critical
        push!(suggestions, ProactiveSuggestion(
            "System Health Critical",
            "One or more system metrics are at critical levels. Immediate attention recommended.",
            :safety;
            estimated_impact = 1.0f0
        ))
    end
    
    # Check goal deadlines
    for goal in world_observation.active_goals
        time_until_deadline = (goal.deadline - now())
        if time_until_deadline < Minute(5) && goal.status == :pending
            push!(suggestions, ProactiveSuggestion(
                "Deadline Approaching",
                "Goal '$(goal.description)' has less than 5 minutes remaining.",
                :productivity;
                estimated_impact = 0.9f0
            ))
        end
    end
    
    # Filter by threshold
    filter!(s -> s.estimated_impact >= config.suggestion_threshold, suggestions)
    
    return suggestions
end

"""
    schedule_proactive_tasks - Create scheduled proactive tasks
"""
function schedule_proactive_tasks(
    suggestions::Vector{ProactiveSuggestion},
    current_time::DateTime = now()
)::Vector{Dict{String, Any}}
    
    scheduled = Dict{String, Any}[]
    
    for suggestion in suggestions
        if suggestion.auto_applicable && suggestion.action_id !== nothing
            # Auto-schedule for immediate execution
            push!(scheduled, Dict(
                "action_id" => suggestion.action_id,
                "scheduled_for" => current_time,
                "reason" => suggestion.description,
                "impact" => suggestion.estimated_impact
            ))
        end
    end
    
    return scheduled
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    format_suggestion - Format suggestion for user display
"""
function format_suggestion(suggestion::ProactiveSuggestion)::String
    impact_str = round(suggestion.estimated_impact * 100)
    return """
    📌 $(suggestion.title)
       $(suggestion.description)
       Impact: $(impact_str)% | Category: $(suggestion.category)
    """
end

"""
    format_all_suggestions - Format multiple suggestions
"""
function format_all_suggestions(suggestions::Vector{ProactiveSuggestion})::String
    if isempty(suggestions)
        return "✓ No proactive suggestions at this time."
    end
    
    lines = ["🎯 Proactive Suggestions:"]
    for suggestion in suggestions
        push!(lines, format_suggestion(suggestion))
    end
    
    return join(lines, "\n")
end

end # module TaskOrchestrator
