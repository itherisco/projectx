# ProactiveEngine.jl - Central Engine for Proactive Intelligence
# Part of Proactive module

# ============================================================================
# ENGINE CONFIGURATION
# ============================================================================

"""
    EngineConfig - Configuration for the proactive engine
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
    ProactiveEngine - Runtime state of the proactive engine
"""
mutable struct ProactiveEngine
    is_running::Bool
    pattern_detector::PatternDetectorState
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
        DateTime(1),
        0,
        ReentrantLock()
    )
end

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

function create_proactive_engine(; kwargs...)::ProactiveEngine
    config = EngineConfig(; kwargs...)
    ProactiveEngine(config)
end

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

function process_user_action(engine::ProactiveEngine, action::Dict{String, Any})::Bool
    lock(engine.lock) do
        if !engine.is_running || !engine.config.enabled
            return false
        end
        
        try
            record_user_action(engine.pattern_detector, action)
            engine.total_actions_processed += 1
            
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

function analyze_user_behavior(engine::ProactiveEngine)::Dict{String, Any}
    lock(engine.lock) do
        if !engine.is_running
            return Dict("error" => "Engine not running")
        end
        
        _run_analysis(engine)
        
        patterns = get_identified_patterns(engine.pattern_detector)
        recent_patterns = identify_recent_patterns(engine.pattern_detector, hours=24)
        predictions = get_active_predictions(engine.predictive_assistant)
        
        pattern_stats = Dict(
            "total_patterns" => length(patterns),
            "temporal_patterns" => count(p -> p.pattern_type == TEMPORAL_ACCESS, patterns),
            "preference_patterns" => count(p -> p.pattern_type == PREFERENCE_SIGNAL, patterns),
            "workflow_patterns" => count(p -> p.pattern_type == SEQUENTIAL_WORKFLOW, patterns),
            "recent_patterns" => length(recent_patterns)
        )
        
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

function _run_analysis(engine::ProactiveEngine)::Nothing
    detect_temporal_patterns(engine.pattern_detector)
    detect_preference_signals(engine.pattern_detector)
    analyze_task_repetition(engine.pattern_detector)
    integrate_patterns(engine.predictive_assistant, engine.pattern_detector)
    generate_predictions(engine.predictive_assistant)
    engine.last_analysis = now()
    nothing
end

function generate_predictions(engine::ProactiveEngine)::Vector{Prediction}
    lock(engine.lock) do
        if !engine.is_running
            return Prediction[]
        end
        
        _run_analysis(engine)
        get_active_predictions(engine.predictive_assistant)
    end
end

function suggest_preparations(engine::ProactiveEngine)::Vector{PredictiveSuggestion}
    lock(engine.lock) do
        if !engine.is_running
            return PredictiveSuggestion[]
        end
        
        suggestions = suggest_preparations(engine.predictive_assistant)
        
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

function reset_engine(engine::ProactiveEngine)::Bool
    lock(engine.lock) do
        was_running = engine.is_running
        
        engine.is_running = false
        
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

function get_recent_patterns(engine::ProactiveEngine; hours::Int=24)::Vector{UserPattern}
    lock(engine.lock) do
        identify_recent_patterns(engine.pattern_detector, hours=hours)
    end
end

function get_pending_suggestions(engine::ProactiveEngine)::Vector{PredictiveSuggestion}
    lock(engine.lock) do
        engine.predictive_assistant.suggestions
    end
end

# ============================================================================
# INTEGRATION
# ============================================================================

function integrate_with_cognition(engine::ProactiveEngine, cognition_module::Any)::Bool
    lock(engine.lock) do
        try
            @info "ProactiveEngine cognition integration placeholder"
            @info "Cognition module type: $(typeof(cognition_module))"
            true
        catch e
            @error "Failed to integrate with cognition: $e"
            false
        end
    end
end

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
