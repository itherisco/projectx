"""
# ConsciousnessMetricsIntegration.jl

Integration layer for ConsciousnessMetrics with the ITHERIS cognitive architecture.
Provides hooks into DecisionSpine, SelfModel, WorldModel, WorkingMemory, and Integrator.
"""
module ConsciousnessMetricsIntegration

using ..ConsciousnessMetrics

# Import from other cognitive modules (loaded at runtime)
# - DecisionSpine
# - SelfModel  
# - WorldModel
# - WorkingMemory
# - Integrator

"""
    MetricsIntegrationState - Holds integration state with cognitive components
"""
mutable struct MetricsIntegrationState
    # Integration status
    decision_spine_connected::Bool
    self_model_connected::Bool
    world_model_connected::Bool
    working_memory_connected::Bool
    integrator_connected::Bool
    
    # Callback functions
    on_metrics_updated::Union{Function, Nothing}
    
    # Configuration
    auto_export_json::Bool
    json_export_path::String
    export_interval_seconds::Float64
    last_export_time::Float64
    
    function MetricsIntegrationState(;
        on_metrics_updated::Union{Function, Nothing}=nothing,
        auto_export_json::Bool=true,
        json_export_path::String="./consciousness_metrics.json",
        export_interval_seconds::Float64=60.0
    )
        new(
            false, false, false, false, false,
            on_metrics_updated,
            auto_export_json,
            json_export_path,
            export_interval_seconds,
            time()
        )
    end
end

"""
    connect_decision_spine!(metrics::ConsciousnessMetrics, state::MetricsIntegrationState, decision_spine)

Connect to DecisionSpine for proposal and decision data.
"""
function connect_decision_spine!(
    metrics::ConsciousnessMetrics,
    state::MetricsIntegrationState,
    decision_spine
)
    metrics.decision_spine = decision_spine
    state.decision_spine_connected = true
end

"""
    connect_self_model!(metrics::ConsciousnessMetrics, state::MetricsIntegrationState, self_model)

Connect to SelfModel for calibration and capability data.
"""
function connect_self_model!(
    metrics::ConsciousnessMetrics,
    state::MetricsIntegrationState,
    self_model
)
    metrics.self_model = self_model
    state.self_model_connected = true
end

"""
    connect_world_model!(metrics::ConsciousnessMetrics, state::MetricsIntegrationState, world_model)

Connect to WorldModel for prediction and consistency data.
"""
function connect_world_model!(
    metrics::ConsciousnessMetrics,
    state::MetricsIntegrationState,
    world_model
)
    metrics.world_model = world_model
    state.world_model_connected = true
end

"""
    connect_working_memory!(metrics::ConsciousnessMetrics, state::MetricsIntegrationState, working_memory)

Connect to WorkingMemory for context tracking.
"""
function connect_working_memory!(
    metrics::ConsciousnessMetrics,
    state::MetricsIntegrationState,
    working_memory
)
    metrics.working_memory = working_memory
    state.working_memory_connected = true
end

"""
    connect_integrator!(metrics::ConsciousnessMetrics, state::MetricsIntegrationState, integrator)

Connect to Integrator for module activity data.
"""
function connect_integrator!(
    metrics::ConsciousnessMetrics,
    state::MetricsIntegrationState,
    integrator
)
    metrics.integrator = integrator
    state.integrator_connected = true
end

"""
    check_integration_status(state::MetricsIntegrationState) -> Dict

Check which components are connected.
"""
function check_integration_status(state::MetricsIntegrationState)::Dict
    return Dict(
        "decision_spine" => state.decision_spine_connected,
        "self_model" => state.self_model_connected,
        "world_model" => state.world_model_connected,
        "working_memory" => state.working_memory_connected,
        "integrator" => state.integrator_connected,
        "all_connected" => (
            state.decision_spine_connected &&
            state.self_model_connected &&
            state.world_model_connected &&
            state.working_memory_connected &&
            state.integrator_connected
        )
    )
end

"""
    run_metrics_cycle!(metrics::ConsciousnessMetrics, context_tracker::ContextTracker, state::MetricsIntegrationState)

Run a complete metrics calculation cycle.
"""
function run_metrics_cycle!(
    metrics::ConsciousnessMetrics,
    context_tracker::ContextTracker,
    state::MetricsIntegrationState
)
    # Calculate all metrics
    snapshot = update_metrics!(metrics, context_tracker)
    
    # Auto-export JSON if enabled
    if state.auto_export_json
        current_time = time()
        if current_time - state.last_export_time >= state.export_interval_seconds
            export_to_file(metrics, state.json_export_path)
            state.last_export_time = current_time
        end
    end
    
    # Call callback if registered
    if state.on_metrics_updated !== nothing
        state.on_metrics_updated(snapshot)
    end
    
    return snapshot
end

"""
    process_decision_event!(context_tracker::ContextTracker, decision)

Process a decision event and update context tracking.
"""
function process_decision_event!(
    context_tracker::ContextTracker,
    decision
)
    # Extract decision embedding (simplified hash-based)
    if hasproperty(decision, :content)
        embedding = Float32(hash(decision.content) % 1000) / 1000.0
        add_decision_embedding!(context_tracker, embedding)
    end
end

"""
    process_belief_update!(context_tracker::ContextTracker, belief::Dict)

Process a belief update from WorldModel.
"""
function process_belief_update!(
    context_tracker::ContextTracker,
    belief::Dict{Symbol, Any}
)
    add_belief!(context_tracker, belief)
end

"""
    process_turn!(context_tracker::ContextTracker)

Process a new conversation turn.
"""
function process_turn!(context_tracker::ContextTracker)
    increment_turn!(context_tracker)
end

"""
    create_integrated_metrics_system(;
    decision_spine=nothing,
    self_model=nothing,
    world_model=nothing,
    working_memory=nothing,
    integrator=nothing,
    kwargs...
) -> Tuple{ConsciousnessMetrics, ContextTracker, MetricsIntegrationState}

Create and initialize a complete metrics system with all integrations.
"""
function create_integrated_metrics_system(;
    decision_spine=nothing,
    self_model=nothing,
    world_model=nothing,
    working_memory=nothing,
    integrator=nothing,
    kwargs...
)::Tuple{ConsciousnessMetrics, ContextTracker, MetricsIntegrationState}
    
    # Create base metrics and context tracker
    metrics, context_tracker = create_default_metrics(;kwargs...)
    
    # Create integration state
    state = MetricsIntegrationState(;kwargs...)
    
    # Connect components if provided
    if decision_spine !== nothing
        connect_decision_spine!(metrics, state, decision_spine)
    end
    
    if self_model !== nothing
        connect_self_model!(metrics, state, self_model)
    end
    
    if world_model !== nothing
        connect_world_model!(metrics, state, world_model)
    end
    
    if working_memory !== nothing
        connect_working_memory!(metrics, state, working_memory)
    end
    
    if integrator !== nothing
        connect_integrator!(metrics, state, integrator)
    end
    
    return metrics, context_tracker, state
end

# Export public API
export
    MetricsIntegrationState,
    connect_decision_spine!,
    connect_self_model!,
    connect_world_model!,
    connect_working_memory!,
    connect_integrator!,
    check_integration_status,
    run_metrics_cycle!,
    process_decision_event!,
    process_belief_update!,
    process_turn!,
    create_integrated_metrics_system

end # module
