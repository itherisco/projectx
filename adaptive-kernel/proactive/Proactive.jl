# Proactive.jl - Parent module for Proactive Intelligence System
# Wraps PatternDetector, PredictiveAssistant, and ProactiveEngine

module Proactive

using Dates
using UUIDs
using Statistics
using Base.Threads

# Load submodules in dependency order
# PatternDetector first (no dependencies)
include("PatternDetector.jl")
# PredictiveAssistant depends on PatternDetector
include("PredictiveAssistant.jl")
# ProactiveEngine depends on both
include("ProactiveEngine.jl")

# Re-export all public types and functions
export 
    # From PatternDetector
    UserPattern,
    PatternType,
    PatternConfidence,
    BehavioralSignal,
    PatternSnapshot,
    PatternDetectorState,
    create_pattern_detector,
    record_user_action,
    detect_temporal_patterns,
    detect_preference_signals,
    analyze_task_repetition,
    get_identified_patterns,
    identify_recent_patterns,
    export_patterns,
    
    # From PredictiveAssistant
    Prediction,
    PredictionType,
    PreparationAction,
    PredictiveSuggestion,
    AssistantState,
    create_predictive_assistant,
    generate_predictions,
    suggest_preparations,
    prepare_resources,
    get_active_predictions,
    integrate_patterns,
    get_prediction_confidence,
    
    # From ProactiveEngine
    ProactiveEngine,
    EngineConfig,
    create_proactive_engine,
    analyze_user_behavior,
    process_user_action,
    start_engine,
    stop_engine,
    reset_engine,
    get_engine_status,
    get_recent_patterns,
    get_pending_suggestions,
    integrate_with_cognition,
    export_engine_state

end # module Proactive
