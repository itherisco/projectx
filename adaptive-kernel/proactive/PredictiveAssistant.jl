# PredictiveAssistant.jl - Predictive Assistance Module
# Generates predictive assistance based on user patterns
# Example: user opens same files daily -> assistant prepares them automatically

module PredictiveAssistant

using Dates
using UUIDs
using Statistics
using Base.Threads

# Import from PatternDetector
using ..PatternDetector

export 
    # Main types
    Prediction,
    PredictionType,
    PreparationAction,
    PredictiveSuggestion,
    AssistantState,
    # Core functions
    create_predictive_assistant,
    generate_predictions,
    suggest_preparations,
    prepare_resources,
    get_active_predictions,
    # Integration
    integrate_patterns,
    get_prediction_confidence

# ============================================================================
# PREDICTION TYPES
# ============================================================================

@enum PredictionType begin
    FILE_ACCESS_PREDICTION      # User will open specific files
    APP_LAUNCH_PREDICTION       # User will launch specific applications
    TASK_PREDICTION             # User will perform specific tasks
    WORKFLOW_PREDICTION         # User will follow a workflow
    CONTEXTUAL_PREDICTION       # Context-dependent prediction
end

"""
    Prediction - Represents a prediction about future user behavior
    
    # Fields
    - `id::UUID`: Unique prediction identifier
    - `prediction_type::PredictionType`: Type of prediction
    - `description::String`: Human-readable prediction
    - `confidence::Float32`: Confidence score [0,1]
    - `predicted_time::DateTime`: When prediction is expected
    - `preparation_actions::Vector{PreparationAction}`: Actions to prepare
    - `created_at::DateTime`: When prediction was made
    - `is_active::Bool`: Whether prediction is still valid
    - `evidence::Vector{String}`: Supporting evidence for prediction
"""
mutable struct Prediction
    id::UUID
    prediction_type::PredictionType
    description::String
    confidence::Float32
    predicted_time::DateTime
    preparation_actions::Vector{PreparationAction}
    created_at::DateTime
    is_active::Bool
    evidence::Vector{String}
    
    Prediction(pt::PredictionType, desc::String, conf::Float32) = new(
        uuid4(),
        pt,
        desc,
        conf,
        now(),
        PreparationAction[],
        now(),
        true,
        String[]
    )
end

"""
    PreparationAction - Action to prepare for predicted behavior
    
    # Fields
    - `action_type::String`: Type of preparation action
    - `target::String`: Target of the action
    - `priority::Int`: Priority (1=highest)
    - `estimated_impact::Float32`: Expected impact [0,1]
    - `is_executed::Bool`: Whether action has been executed
"""
mutable struct PreparationAction
    action_type::String
    target::String
    priority::Int
    estimated_impact::Float32
    is_executed::Bool
    
    PreparationAction(at::String, target::String, priority::Int=5, impact::Float32=0.5f0) = new(
        at,
        target,
        priority,
        impact,
        false
    )
end

"""
    PredictiveSuggestion - A suggestion generated for the user
    
    # Fields
    - `id::UUID`: Unique suggestion identifier
    - `prediction_id::UUID`: Associated prediction
    - `message::String`: Suggestion message
    - `suggested_actions::Vector{String}`: Actions user can take
    - `auto_prepare::Bool`: Whether to auto-prepare resources
    - `created_at::DateTime`: When suggestion was generated
"""
mutable struct PredictiveSuggestion
    id::UUID
    prediction_id::UUID
    message::String
    suggested_actions::Vector{String}
    auto_prepare::Bool
    created_at::DateTime
    
    PredictiveSuggestion(pred_id::UUID, msg::String; auto_prepare::Bool=false) = new(
        uuid4(),
        pred_id,
        msg,
        String[],
        auto_prepare,
        now()
    )
end

"""
    AssistantState - State of the predictive assistant
    
    # Fields
    - `predictions::Vector{Prediction}`: Active predictions
    - `suggestions::Vector{PredictiveSuggestion}`: Generated suggestions
    - `preparation_history::Vector{Dict{String, Any}}`: History of preparations
    - `lock::ReentrantLock`: Thread safety
    - `min_confidence::Float32`: Minimum confidence for predictions
    - `prediction_horizon::Dates.Hour`: How far ahead to predict
"""
mutable struct AssistantState
    predictions::Vector{Prediction}
    suggestions::Vector{PredictiveSuggestion}
    preparation_history::Vector{Dict{String, Any}}
    lock::ReentrantLock
    min_confidence::Float32
    prediction_horizon::Dates.Hour
    
    AssistantState(; min_confidence::Float32=0.5f0, prediction_horizon_hours::Int=4) = new(
        Prediction[],
        PredictiveSuggestion[],
        Dict{String, Any}[],
        ReentrantLock(),
        min_confidence,
        Dates.Hour(prediction_horizon_hours)
    )
end

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

"""
    create_predictive_assistant(; min_confidence=0.5, prediction_horizon_hours=4) -> AssistantState
"""
function create_predictive_assistant(; min_confidence::Float32=0.5f0, prediction_horizon_hours::Int=4)::AssistantState
    AssistantState(min_confidence=min_confidence, prediction_horizon_hours=prediction_horizon_hours)
end

"""
    integrate_patterns(as::AssistantState, pd::PatternDetector) -> Vector{Prediction]
    
Integrate patterns from PatternDetector and generate predictions
"""
function integrate_patterns(as::AssistantState, pd::PatternDetector)::Vector{Prediction}
    lock(as.lock) do
        new_predictions = Prediction[]
        
        # Get active patterns
        patterns = get_identified_patterns(pd)
        
        for pattern in patterns
            prediction = nothing
            
            if pattern.pattern_type == TEMPORAL_ACCESS
                # Predict file/app access based on time
                action_type = get(pattern.associated_data, "action_type", "")
                typical_hour = get(pattern.associated_data, "typical_hour", -1)
                
                if typical_hour >= 0
                    now_hour = hour(now())
                    time_diff = abs(typical_hour - now_hour)
                    
                    # If within prediction horizon
                    if time_diff <= 4 || (now_hour > typical_hour && typical_hour + 24 - now_hour <= 4)
                        prediction = Prediction(
                            FILE_ACCESS_PREDICTION,
                            "User likely to access '$action_type' soon",
                            _confidence_to_float(pattern.confidence)
                        )
                        prediction.predicted_time = now() + Dates.Minute(time_diff * 15)
                        
                        # Add preparation action
                        push!(prediction.preparation_actions, PreparationAction(
                            "preload",
                            action_type,
                            3,
                            0.7f0
                        ))
                        push!(prediction.evidence, "Temporal pattern: $typical_hour:00")
                    end
                end
                
            elseif pattern.pattern_type == PREFERENCE_SIGNAL
                # Predict based on user preferences
                target = get(pattern.associated_data, "target", "")
                access_count = get(pattern.associated_data, "access_count", 0)
                
                if access_count >= 3
                    prediction = Prediction(
                        FILE_ACCESS_PREDICTION,
                        "User may access preferred resource '$target'",
                        _confidence_to_float(pattern.confidence)
                    )
                    prediction.predicted_time = now() + Dates.Hour(1)
                    
                    push!(prediction.preparation_actions, PreparationAction(
                        "cache",
                        target,
                        2,
                        0.8f0
                    ))
                    push!(prediction.evidence, "Frequent access: $access_count times")
                end
                
            elseif pattern.pattern_type == SEQUENTIAL_WORKFLOW
                # Predict workflow continuation
                sequence = get(pattern.associated_data, "sequence", "")
                repeat_count = get(pattern.associated_data, "repeat_count", 0)
                
                if repeat_count >= 2
                    prediction = Prediction(
                        WORKFLOW_PREDICTION,
                        "User may continue workflow: $sequence",
                        _confidence_to_float(pattern.confidence)
                    )
                    prediction.predicted_time = now() + Dates.Minute(30)
                    
                    push!(prediction.preparation_actions, PreparationAction(
                        "prepare_next",
                        "workflow_continuation",
                        4,
                        0.6f0
                    ))
                    push!(prediction.evidence, "Repeated sequence: $repeat_count times")
                end
            end
            
            # Add prediction if valid and meets confidence threshold
            if prediction !== nothing && prediction.confidence >= as.min_confidence
                # Check for duplicate predictions
                existing = findfirst(p -> 
                    p.prediction_type == prediction.prediction_type &&
                    p.description == prediction.description,
                    as.predictions
                )
                
                if existing === nothing
                    push!(new_predictions, prediction)
                    push!(as.predictions, prediction)
                end
            end
        end
        
        new_predictions
    end
end

"""
    _confidence_to_float(confidence::PatternConfidence) -> Float32
"""
function _confidence_to_float(confidence::PatternConfidence)::Float32
    if confidence == VERIFIED_CONFIDENCE
        return 0.95f0
    elseif confidence == HIGH_CONFIDENCE
        return 0.8f0
    elseif confidence == MEDIUM_CONFIDENCE
        return 0.6f0
    else
        return 0.4f0
    end
end

"""
    generate_predictions(as::AssistantState; force::Bool=false) -> Vector[Prediction]
    
Generate new predictions based on current state and patterns
"""
function generate_predictions(as::AssistantState; force::Bool=false)::Vector{Prediction}
    lock(as.lock) do
        # Clean up old predictions
        cutoff = now() - as.prediction_horizon
        filter!(p -> p.predicted_time > cutoff && p.is_active, as.predictions)
        
        # If no force and we have recent predictions, return existing
        if !force && !isempty(as.predictions)
            recent_cutoff = now() - Dates.Minute(30)
            return filter(p -> p.created_at > recent_cutoff, as.predictions)
        end
        
        as.predictions
    end
end

"""
    suggest_preparations(as::AssistantState) -> Vector{PredictiveSuggestion]
    
Generate preparation suggestions based on active predictions
"""
function suggest_preparations(as::AssistantState)::Vector{PredictiveSuggestion}
    lock(as.lock) do
        new_suggestions = PredictiveSuggestion[]
        
        # Get active predictions
        active_preds = filter(p -> p.is_active, as.predictions)
        
        # Sort by confidence and time
        sort!(active_preds, by = p -> (-p.confidence, p.predicted_time))
        
        for pred in active_preds
            if pred.confidence < as.min_confidence
                continue
            end
            
            # Generate suggestion message
            suggestion = PredictiveSuggestion(
                pred.id,
                _generate_suggestion_message(pred),
                auto_prepare = pred.confidence > 0.8f0
            )
            
            # Add suggested actions
            for action in pred.preparation_actions
                if !action.is_executed
                    push!(suggestion.suggested_actions, 
                        "$(action.action_type): $(action.target)")
                end
            end
            
            push!(new_suggestions, suggestion)
            push!(as.suggestions, suggestion)
        end
        
        new_suggestions
    end
end

"""
    _generate_suggestion_message(pred::Prediction) -> String
"""
function _generate_suggestion_message(pred::Prediction)::String
    if pred.prediction_type == FILE_ACCESS_PREDICTION
        return "I noticed you often access certain files around this time. " *
               "Would you like me to prepare them for you?"
    elseif pred.prediction_type == APP_LAUNCH_PREDICTION
        return "Based on your patterns, you might want to launch an application soon. " *
               "Should I have it ready?"
    elseif pred.prediction_type == TASK_PREDICTION
        return "I predict you'll want to perform a task soon. " *
               "Shall I prepare the necessary resources?"
    elseif pred.prediction_type == WORKFLOW_PREDICTION
        return "I see you're following a workflow pattern. " *
               "Would you like me to continue preparing the next steps?"
    else
        return "Based on your patterns, I'm preparing suggestions for you."
    end
end

"""
    prepare_resources(as::AssistantState, prediction_id::UUID) -> Vector{PreparationAction}
    
Execute preparation actions for a specific prediction
"""
function prepare_resources(as::AssistantState, prediction_id::UUID)::Vector{PreparationAction}
    lock(as.lock) do
        executed_actions = PreparationAction[]
        
        # Find prediction
        pred_idx = findfirst(p -> p.id == prediction_id, as.predictions)
        if pred_idx === nothing
            return executed_actions
        end
        
        prediction = as.predictions[pred_idx]
        
        # Execute preparation actions
        for action in prediction.preparation_actions
            if !action.is_executed
                action.is_executed = true
                push!(executed_actions, action)
                
                # Record in history
                push!(as.preparation_history, Dict(
                    "prediction_id" => string(prediction_id),
                    "action_type" => action.action_type,
                    "target" => action.target,
                    "timestamp" => string(now())
                ))
            end
        end
        
        executed_actions
    end
end

"""
    get_active_predictions(as::AssistantState) -> Vector{Prediction}
    
Get all currently active predictions
"""
function get_active_predictions(as::AssistantState)::Vector{Prediction}
    lock(as.lock) do
        cutoff = now() - as.prediction_horizon
        filter(p -> p.is_active && p.predicted_time > cutoff, as.predictions)
    end
end

"""
    get_prediction_confidence(as::AssistantState, prediction_id::UUID) -> Float32
    
Get confidence score for a specific prediction
"""
function get_prediction_confidence(as::AssistantState, prediction_id::UUID)::Float32
    lock(as.lock) do
        pred = findfirst(p -> p.id == prediction_id, as.predictions)
        if pred === nothing
            return 0.0f0
        end
        as.predictions[pred].confidence
    end
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    export_predictions(as::AssistantState) -> Dict{String, Any}
    
Export predictions for external analysis
"""
function export_predictions(as::AssistantState)::Dict{String, Any}
    lock(as.lock) do
        predictions_data = []
        for p in as.predictions
            actions_data = []
            for a in p.preparation_actions
                push!(actions_data, Dict(
                    "type" => a.action_type,
                    "target" => a.target,
                    "priority" => a.priority,
                    "executed" => a.is_executed
                ))
            end
            
            push!(predictions_data, Dict(
                "id" => string(p.id),
                "type" => string(p.prediction_type),
                "description" => p.description,
                "confidence" => p.confidence,
                "predicted_time" => string(p.predicted_time),
                "is_active" => p.is_active,
                "preparation_actions" => actions_data,
                "evidence" => p.evidence
            ))
        end
        
        Dict(
            "timestamp" => string(now()),
            "total_predictions" => length(as.predictions),
            "active_predictions" => count(p -> p.is_active, as.predictions),
            "predictions" => predictions_data
        )
    end
end

end # module PredictiveAssistant
