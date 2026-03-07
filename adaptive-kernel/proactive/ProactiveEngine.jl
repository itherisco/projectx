# ProactiveEngine.jl - Central Engine for Proactive Intelligence
# Central hub for analyzing user behavior, generating predictions, and suggesting preparations
# Integrates with existing cognition modules

module ProactiveEngine

using Dates
using UUIDs
using Statistics
using Base.Threads

# Import from submodules
using ..PatternDetector
using ..PredictiveAssistant

export 
    # Main engine type
    ProactiveEngine,
    EngineConfig,
    EngineState,
    # Core functions
    create_proactive_engine,
    analyze_user_behavior,
    generate_predictions,
    suggest_preparations,
    process_user_action,
    # Lifecycle
    start_engine,
    stop_engine,
    reset_engine,
    # Querying
    get_engine_status,
    get_recent_patterns,
    get_active_predictions,
    get_pending_suggestions,
    # Integration
    integrate_with_cognition,
    export_engine_state

# ============================================================================
# ENGINE CONFIGURATION
# ============================================================================

"""
    EngineConfig - Configuration for the proactive engine
    
    # Fields
    - `enabled::Bool`: Whether engine is enabled
    - `pattern_min_occurrences::Int`: Min occurrences to detect pattern
    - `temporal_window_hours::Int`: Hours to look back for temporal patterns
    - `prediction_horizon_hours::Int`: Hours ahead to predict
    - `min_prediction_confidence::Float32`: Min confidence for predictions
    - `auto_prepare_threshold::Float32`: Confidence threshold for auto-prepare
    - `privacy_mode::Bool`: Whether to run in privacy-respecting mode
    - `analysis_interval_minutes::Int`: How often to run analysis
"""
mutable struct EngineConfig
    enabled::Bool
    pattern_min_occurrences::Int
    temporal_window_hours::Int
    prediction_horizon_hours::Int
    min_prediction_confidence::Float32
    auto_prepare_threshold::Float32
    privacy_mode::Bool
    analysis_interval_minutes::Int
    
    EngineConfig(; 
        enabled::Bool=true,
        pattern_min_occurrences::Int=3,
        temporal_window_hours::Int=24,
        prediction_horizon_hours::Int=4,
        min_prediction_confidence::Float32=0.5f0,
        auto_prepare_threshold::Float32=0.8f0,
        privacy_mode::Bool=true,
        analysis_interval_minutes::Int=15
    ) = new(
        enabled,
        pattern_min_occurrences,
        temporal_window_hours,
        prediction_horizon_hours,
        min_prediction_confidence,
        auto_prepare_threshold,
        privacy_mode,
        analysis_interval_minutes
    )
end

"""
    EngineState - Runtime state of the proactive engine
    
    # Fields
    - `is_running::Bool`: Whether engine is currently running
    - `pattern_detector::PatternDetector`: Pattern detection subsystem
    - `predictive_assistant::AssistantState`: Prediction subsystem
    - `config::EngineConfig`: Engine configuration
    - `last_analysis::DateTime`: Last time analysis was run
    - `total_actions_processed::Int`: Total actions processed
    - `lock::ReentrantLock`: Thread safety
"""
mutable struct ProactiveEngine
    is_running::Bool
    pattern_detector::PatternDetector
    predictive_assistant::AssistantState
    config::EngineConfig
    last_analysis::DateTime
    total_actions_processed::Int
    lock::ReentrantLock
    
    ProactiveEngine(cfg::EngineConfig) = new(
        false,
        create_pattern_detector(min_occurrences=cfg.pattern_min_occurrences, 
                                 temporal_window_hours=cfg.temporal_window_hours),
        create_predictive_assistant(min_confidence=cfg.min_prediction_confidence,
                                     prediction_horizon_hours=cfg.prediction_horizon_hours),
        cfg,
        DateTime(1),  # Min DateTime
        0,
        ReentrantLock()
    )
end

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

"""
    create_proactive_engine(; kwargs...) -> ProactiveEngine
    
Create a new proactive engine with optional configuration
"""
function create_proactive_engine(; kwargs...)::ProactiveEngine
    config = EngineConfig(; kwargs...)
    ProactiveEngine(config)
end

"""
    start_engine(engine::ProactiveEngine) -> Bool
    
Start the proactive engine
"""
function start_engine(engine::ProactiveEngine)::Bool
    lock(engine.lock) do
        if engine.is_running
            @warn "ProactiveEngine is already running"
            return false
        end
        
        engine.is_running = true
        engine.last_analysis = now()
        
        @info "ProactiveEngine started successfully"
        true
    end
end

"""
    stop_engine(engine::ProactiveEngine) -> Bool
    
Stop the proactive engine
"""
function stop_engine(engine::ProactiveEngine)::Bool
    lock(engine.lock) do
        if !engine.is_running
            @warn "ProactiveEngine is not running"
            return false
        end
        
        engine.is_running = false
        
        @info "ProactiveEngine stopped"
        true
    end
end

"""
    process_user_action(engine::ProactiveEngine, action::Dict{String, Any}) -> Bool
    
Process a user action through the proactive engine
"""
function process_user_action(engine::ProactiveEngine, action::Dict{String, Any})::Bool
    lock(engine.lock) do
        if !engine.is_running || !engine.config.enabled
            return false
        end
        
        try
            # Record action in pattern detector
            record_user_action(engine.pattern_detector, action)
            engine.total_actions_processed += 1
            
            # Periodically run analysis
            time_since_analysis = now() - engine.last_analysis
            if time_since_analysis > Dates.Minute(engine.config.analysis_interval_minutes)
                _run_analysis(engine)
            end
            
            true
        catch e
            @error "Failed to process user action: $e"
            false
        end
    end
end

"""
    analyze_user_behavior(engine::ProactiveEngine) -> Dict{String, Any}
    
Analyze user behavior and return comprehensive analysis results
"""
function analyze_user_behavior(engine::ProactiveEngine)::Dict{String, Any}
    lock(engine.lock) do
        if !engine.is_running
            return Dict("error" => "Engine not running")
        end
        
        # Run full analysis
        _run_analysis(engine)
        
        # Collect results
        patterns = get_identified_patterns(engine.pattern_detector)
        recent_patterns = identify_recent_patterns(engine.pattern_detector, hours=24)
        predictions = get_active_predictions(engine.predictive_assistant)
        
        # Pattern statistics
        pattern_stats = Dict(
            "total_patterns" => length(patterns),
            "temporal_patterns" => count(p -> p.pattern_type == TEMPORAL_ACCESS, patterns),
            "preference_patterns" => count(p -> p.pattern_type == PREFERENCE_SIGNAL, patterns),
            "workflow_patterns" => count(p -> p.pattern_type == SEQUENTIAL_WORKFLOW, patterns),
            "recent_patterns" => length(recent_patterns)
        )
        
        # Prediction statistics
        prediction_stats = Dict(
            "total_predictions" => length(predictions),
            "high_confidence" => count(p -> p.confidence >= 0.8f0, predictions),
            "avg_confidence" => isempty(predictions) ? 0.0 : mean(p.confidence for p in predictions)
        )
        
        Dict(
            "timestamp" => string(now()),
            "engine_running" => engine.is_running,
            "total_actions_processed" => engine.total_actions_processed,
            "last_analysis" => string(engine.last_analysis),
            "patterns" => pattern_stats,
            "predictions" => prediction_stats
        )
    end
end

"""
    _run_analysis(engine::ProactiveEngine) -> Nothing
    
Internal function to run pattern analysis and predictions
"""
function _run_analysis(engine::ProactiveEngine)::Nothing
    # Detect temporal patterns
    detect_temporal_patterns(engine.pattern_detector)
    
    # Detect preference signals
    detect_preference_signals(engine.pattern_detector)
    
    # Analyze task repetition
    analyze_task_repetition(engine.pattern_detector)
    
    # Integrate patterns with predictive assistant
    integrate_patterns(engine.predictive_assistant, engine.pattern_detector)
    
    # Generate predictions
    generate_predictions(engine.predictive_assistant)
    
    engine.last_analysis = now()
    
    nothing
end

"""
    generate_predictions(engine::ProactiveEngine) -> Vector{Prediction}
    
Generate predictions based on current analysis
"""
function generate_predictions(engine::ProactiveEngine)::Vector{Prediction}
    lock(engine.lock) do
        if !engine.is_running
            return Prediction[]
        end
        
        # Ensure analysis is up to date
        _run_analysis(engine)
        
        # Get active predictions
        get_active_predictions(engine.predictive_assistant)
    end
end

"""
    suggest_preparations(engine::ProactiveEngine) -> Vector{PredictiveSuggestion}
    
Generate preparation suggestions based on current predictions
"""
function suggest_preparations(engine::ProactiveEngine)::Vector{PredictiveSuggestion}
    lock(engine.lock) do
        if !engine.is_running
            return PredictiveSuggestion[]
        end
        
        # Generate suggestions
        suggestions = suggest_preparations(engine.predictive_assistant)
        
        # Auto-prepare for high confidence predictions
        for suggestion in suggestions
            if suggestion.auto_prepare && engine.config.auto_prepare_threshold > 0
                pred = findfirst(p -> p.id == suggestion.prediction_id, 
                                 engine.predictive_assistant.predictions)
                if pred !== nothing && engine.predictive_assistant.predictions[pred].confidence >= engine.config.auto_prepare_threshold
                    prepare_resources(engine.predictive_assistant, suggestion.prediction_id)
                end
            end
        end
        
        suggestions
    end
end

"""
    reset_engine(engine::ProactiveEngine) -> Bool
    
Reset the engine to initial state
"""
function reset_engine(engine::ProactiveEngine)::Bool
    lock(engine.lock) do
        was_running = engine.is_running
        
        # Stop if running
        engine.is_running = false
        
        # Create new pattern detector and assistant
        engine.pattern_detector = create_pattern_detector(
            min_occurrences=engine.config.pattern_min_occurrences,
            temporal_window_hours=engine.config.temporal_window_hours
        )
        engine.predictive_assistant = create_predictive_assistant(
            min_confidence=engine.config.min_prediction_confidence,
            prediction_horizon_hours=engine.config.prediction_horizon_hours
        )
        
        engine.last_analysis = DateTime(1)
        engine.total_actions_processed = 0
        
        # Restart if was running
        if was_running
            engine.is_running = true
        end
        
        @info "ProactiveEngine reset"
        true
    end
end

# ============================================================================
# QUERYING FUNCTIONS
# ============================================================================

"""
    get_engine_status(engine::ProactiveEngine) -> Dict{String, Any}
    
Get current engine status
"""
function get_engine_status(engine::ProactiveEngine)::Dict{String, Any}
    lock(engine.lock) do
        Dict(
            "running" => engine.is_running,
            "enabled" => engine.config.enabled,
            "total_actions_processed" => engine.total_actions_processed,
            "last_analysis" => string(engine.last_analysis),
            "patterns_detected" => length(get_identified_patterns(engine.pattern_detector)),
            "active_predictions" => length(get_active_predictions(engine.predictive_assistant)),
            "privacy_mode" => engine.config.privacy_mode
        )
    end
end

"""
    get_recent_patterns(engine::ProactiveEngine; hours::Int=24) -> Vector{UserPattern}
    
Get patterns detected in recent time window
"""
function get_recent_patterns(engine::ProactiveEngine; hours::Int=24)::Vector{UserPattern}
    lock(engine.lock) do
        identify_recent_patterns(engine.pattern_detector, hours=hours)
    end
end

"""
    get_pending_suggestions(engine::ProactiveEngine) -> Vector{PredictiveSuggestion}
    
Get pending suggestions that haven't been acted upon
"""
function get_pending_suggestions(engine::ProactiveEngine)::Vector{PredictiveSuggestion}
    lock(engine.lock) do
        # Return all current suggestions
        engine.predictive_assistant.suggestions
    end
end

# ============================================================================
# INTEGRATION WITH COGNITION
# ============================================================================

"""
    integrate_with_cognition(engine::ProactiveEngine, cognition_module::Any) -> Bool
    
Integrate with existing cognition modules
This allows the proactive engine to:
- Receive perception data from cognition
- Feed predictions back to cognition for decision making
"""
function integrate_with_cognition(engine::ProactiveEngine, cognition_module::Any)::Bool
    lock(engine.lock) do
        try
            # This is a placeholder for integration logic
            # In practice, this would connect to specific cognition APIs
            
            @info "ProactiveEngine cognition integration placeholder"
            @info "Cognition module type: $(typeof(cognition_module))"
            
            true
        catch e
            @error "Failed to integrate with cognition: $e"
            false
        end
    end
end

"""
    export_engine_state(engine::ProactiveEngine) -> Dict{String, Any}
    
Export complete engine state for debugging/analysis
"""
function export_engine_state(engine::ProactiveEngine)::Dict{String, Any}
    lock(engine.lock) do
        Dict(
            "config" => Dict(
                "enabled" => engine.config.enabled,
                "pattern_min_occurrences" => engine.config.pattern_min_occurrences,
                "temporal_window_hours" => engine.config.temporal_window_hours,
                "prediction_horizon_hours" => engine.config.prediction_horizon_hours,
                "min_prediction_confidence" => engine.config.min_prediction_confidence,
                "auto_prepare_threshold" => engine.config.auto_prepare_threshold,
                "privacy_mode" => engine.config.privacy_mode,
                "analysis_interval_minutes" => engine.config.analysis_interval_minutes
            ),
            "status" => get_engine_status(engine),
            "patterns" => export_patterns(engine.pattern_detector),
            "predictions" => export_predictions(engine.predictive_assistant)
        )
    end
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_pattern_summary(engine::ProactiveEngine) -> String
    
Get human-readable summary of detected patterns
"""
function get_pattern_summary(engine::ProactiveEngine)::String
    lock(engine.lock) do
        patterns = get_identified_patterns(engine.pattern_detector)
        
        if isempty(patterns)
            return "No patterns detected yet."
        end
        
        lines = String[]
        push!(lines, "Detected Patterns:")
        
        for p in patterns
            push!(lines, "  - $(p.description) ($(p.occurrences) occurrences)")
        end
        
        join(lines, "\n")
    end
end

"""
    get_prediction_summary(engine::ProactiveEngine) -> String
    
Get human-readable summary of active predictions
"""
function get_prediction_summary(engine::ProactiveEngine)::String
    lock(engine.lock) do
        predictions = get_active_predictions(engine.predictive_assistant)
        
        if isempty(predictions)
            return "No active predictions."
        end
        
        lines = String[]
        push!(lines, "Active Predictions:")
        
        for p in predictions
            push!(lines, "  - $(p.description) (confidence: $(round(p.confidence, digits=2)))")
        end
        
        join(lines, "\n")
    end
end

end # module ProactiveEngine
