# PredictiveAssistant.jl - Predictive Assistance Module
# Generates predictive assistance based on user patterns
# Part of Proactive module

# ============================================================================
# PREDICTION TYPES
# ============================================================================

@enum PredictionType begin
    FILE_ACCESS_PREDICTION
    APP_LAUNCH_PREDICTION
    TASK_PREDICTION
    WORKFLOW_PREDICTION
    CONTEXTUAL_PREDICTION
end

"""
    PreparationAction - Action to prepare for predicted behavior
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
    Prediction - Represents a prediction about future user behavior
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
    PredictiveSuggestion - A suggestion generated for the user
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

function create_predictive_assistant(; min_confidence::Float32=0.5f0, prediction_horizon_hours::Int=4)::AssistantState
    AssistantState(min_confidence=min_confidence, prediction_horizon_hours=prediction_horizon_hours)
end

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

function integrate_patterns(as::AssistantState, pd::PatternDetectorState)::Vector{Prediction}
    lock(as.lock) do
        new_predictions = Prediction[]
        
        patterns = get_identified_patterns(pd)
        
        for pattern in patterns
            prediction = nothing
            
            if pattern.pattern_type == TEMPORAL_ACCESS
                action_type = get(pattern.associated_data, "action_type", "")
                typical_hour = get(pattern.associated_data, "typical_hour", -1)
                
                if typical_hour >= 0
                    now_hour = hour(now())
                    time_diff = abs(typical_hour - now_hour)
                    
                    if time_diff <= 4 || (now_hour > typical_hour && typical_hour + 24 - now_hour <= 4)
                        prediction = Prediction(
                            FILE_ACCESS_PREDICTION,
                            "User likely to access '$action_type' soon",
                            _confidence_to_float(pattern.confidence)
                        )
                        prediction.predicted_time = now() + Dates.Minute(time_diff * 15)
                        
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
            
            if prediction !== nothing && prediction.confidence >= as.min_confidence
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

function generate_predictions(as::AssistantState; force::Bool=false)::Vector{Prediction}
    lock(as.lock) do
        cutoff = now() - as.prediction_horizon
        filter!(p -> p.predicted_time > cutoff && p.is_active, as.predictions)
        
        if !force && !isempty(as.predictions)
            recent_cutoff = now() - Dates.Minute(30)
            return filter(p -> p.created_at > recent_cutoff, as.predictions)
        end
        
        as.predictions
    end
end

function _generate_suggestion_message(pred::Prediction)::String
    if pred.prediction_type == FILE_ACCESS_PREDICTION
        return "I noticed you often access certain files around this time. Would you like me to prepare them for you?"
    elseif pred.prediction_type == APP_LAUNCH_PREDICTION
        return "Based on your patterns, you might want to launch an application soon. Should I have it ready?"
    elseif pred.prediction_type == TASK_PREDICTION
        return "I predict you'll want to perform a task soon. Shall I prepare the necessary resources?"
    elseif pred.prediction_type == WORKFLOW_PREDICTION
        return "I see you're following a workflow pattern. Would you like me to continue preparing the next steps?"
    else
        return "Based on your patterns, I'm preparing suggestions for you."
    end
end

function suggest_preparations(as::AssistantState)::Vector{PredictiveSuggestion}
    lock(as.lock) do
        new_suggestions = PredictiveSuggestion[]
        
        active_preds = filter(p -> p.is_active, as.predictions)
        
        sort!(active_preds, by = p -> (-p.confidence, p.predicted_time))
        
        for pred in active_preds
            if pred.confidence < as.min_confidence
                continue
            end
            
            suggestion = PredictiveSuggestion(
                pred.id,
                _generate_suggestion_message(pred),
                auto_prepare = pred.confidence > 0.8f0
            )
            
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

function prepare_resources(as::AssistantState, prediction_id::UUID)::Vector{PreparationAction}
    lock(as.lock) do
        executed_actions = PreparationAction[]
        
        pred_idx = findfirst(p -> p.id == prediction_id, as.predictions)
        if pred_idx === nothing
            return executed_actions
        end
        
        prediction = as.predictions[pred_idx]
        
        for action in prediction.preparation_actions
            if !action.is_executed
                action.is_executed = true
                push!(executed_actions, action)
                
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

function get_active_predictions(as::AssistantState)::Vector{Prediction}
    lock(as.lock) do
        cutoff = now() - as.prediction_horizon
        filter(p -> p.is_active && p.predicted_time > cutoff, as.predictions)
    end
end

function get_prediction_confidence(as::AssistantState, prediction_id::UUID)::Float32
    lock(as.lock) do
        pred = findfirst(p -> p.id == prediction_id, as.predictions)
        if pred === nothing
            return 0.0f0
        end
        as.predictions[pred].confidence
    end
end

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
