# PatternDetector.jl - User Pattern Detection Module
# Detects user patterns, repeated tasks, and preference signals
# Privacy-respecting behavior tracking
# Part of Proactive module

# ============================================================================
# PATTERN TYPES
# ============================================================================

@enum PatternType begin
    TEMPORAL_ACCESS      # Time-based file/app access patterns
    SEQUENTIAL_WORKFLOW # Task sequence patterns
    PREFERENCE_SIGNAL   # User preference indicators
    REPEATED_TASK       # Regularly repeated tasks
    CONTEXTUAL_TRIGGER  # Context-dependent patterns
end

@enum PatternConfidence begin
    LOW_CONFIDENCE
    MEDIUM_CONFIDENCE
    HIGH_CONFIDENCE
    VERIFIED_CONFIDENCE
end

"""
    UserPattern - Represents a detected user behavior pattern
"""
mutable struct UserPattern
    id::UUID
    pattern_type::PatternType
    description::String
    occurrences::Int
    first_seen::DateTime
    last_seen::DateTime
    confidence::PatternConfidence
    associated_data::Dict{String, Any}
    is_active::Bool
    
    UserPattern(pt::PatternType, desc::String) = new(
        uuid4(),
        pt,
        desc,
        1,
        now(),
        now(),
        LOW_CONFIDENCE,
        Dict{String, Any}(),
        true
    )
end

"""
    BehavioralSignal - A signal extracted from user behavior
"""
mutable struct BehavioralSignal
    signal_type::String
    timestamp::DateTime
    context::Dict{String, Any}
    importance::Float32
    
    BehavioralSignal(st::String, imp::Float32=0.5f0) = new(
        st,
        now(),
        Dict{String, Any}(),
        imp
    )
end

"""
    PatternSnapshot - Snapshot of pattern detection state
"""
struct PatternSnapshot
    timestamp::DateTime
    total_patterns::Int
    active_patterns::Int
    new_signals::Int
end

"""
    PatternDetectorState - Main pattern detection state
"""
mutable struct PatternDetectorState
    patterns::Vector{UserPattern}
    recent_signals::Vector{BehavioralSignal}
    action_history::Vector{Dict{String, Any}}
    lock::ReentrantLock
    min_occurrences::Int
    temporal_window::Dates.Hour
    
    PatternDetectorState(; min_occurrences::Int=3, temporal_window_hours::Int=24) = new(
        UserPattern[],
        BehavioralSignal[],
        Dict{String, Any}[],
        ReentrantLock(),
        min_occurrences,
        Dates.Hour(temporal_window_hours)
    )
end

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

function create_pattern_detector(; min_occurrences::Int=3, temporal_window_hours::Int=24)::PatternDetectorState
    PatternDetectorState(min_occurrences=min_occurrences, temporal_window_hours=temporal_window_hours)
end

function record_user_action(pd::PatternDetectorState, action::Dict{String, Any})::Bool
    lock(pd.lock) do
        try
            safe_action = Dict{String, Any}()
            
            if haskey(action, "action_type")
                safe_action["action_type"] = action["action_type"]
            end
            if haskey(action, "target")
                safe_action["target"] = action["target"]
            end
            if haskey(action, "timestamp")
                safe_action["timestamp"] = action["timestamp"]
            else
                safe_action["timestamp"] = now()
            end
            if haskey(action, "context")
                safe_action["context"] = action["context"]
            end
            
            push!(pd.action_history, safe_action)
            
            signal = BehavioralSignal(
                get(safe_action, "action_type", "unknown"),
                0.5f0
            )
            signal.context = safe_action
            push!(pd.recent_signals, signal)
            
            cutoff = now() - pd.temporal_window
            filter!(s -> s.timestamp > cutoff, pd.recent_signals)
            
            if length(pd.action_history) > 1000
                pd.action_history = pd.action_history[end-999:end]
            end
            
            true
        catch e
            @error "Failed to record user action: $e"
            false
        end
    end
end

function detect_temporal_patterns(pd::PatternDetectorState)::Vector{UserPattern}
    lock(pd.lock) do
        new_patterns = UserPattern[]
        
        action_types = Dict{String, Vector{DateTime}}()
        for action in pd.action_history
            at = get(action, "action_type", "unknown")
            ts = get(action, "timestamp", now())
            if !haskey(action_types, at)
                action_types[at] = DateTime[]
            end
            push!(action_types[at], ts)
        end
        
        for (action_type, timestamps) in action_types
            if length(timestamps) >= pd.min_occurrences
                hours = [hour(ts) for ts in timestamps]
                mean_hour = round(Int, mean(hours))
                hour_variance = var(hours)
                
                if hour_variance < 2.0 && length(unique(hours)) < 5
                    pattern = UserPattern(
                        TEMPORAL_ACCESS,
                        "User typically performs '$action_type' around $mean_hour:00"
                    )
                    pattern.associated_data["action_type"] = action_type
                    pattern.associated_data["typical_hour"] = mean_hour
                    pattern.confidence = length(timestamps) >= 5 ? HIGH_CONFIDENCE : MEDIUM_CONFIDENCE
                    push!(new_patterns, pattern)
                end
            end
        end
        
        for np in new_patterns
            existing = findfirst(p -> 
                p.pattern_type == np.pattern_type && 
                get(p.associated_data, "action_type", "") == get(np.associated_data, "action_type", ""),
                pd.patterns
            )
            
            if existing !== nothing
                pd.patterns[existing].occurrences += 1
                pd.patterns[existing].last_seen = now()
                pd.patterns[existing].confidence = compute_pattern_strength(pd.patterns[existing])
            else
                push!(pd.patterns, np)
            end
        end
        
        new_patterns
    end
end

function detect_preference_signals(pd::PatternDetectorState)::Vector{UserPattern}
    lock(pd.lock) do
        new_patterns = UserPattern[]
        
        targets = Dict{String, Int}()
        for action in pd.action_history
            target = get(action, "target", "")
            if target !== ""
                targets[target] = get(targets, target, 0) + 1
            end
        end
        
        for (target, count) in targets
            if count >= pd.min_occurrences
                pattern = UserPattern(
                    PREFERENCE_SIGNAL,
                    "User shows preference for '$target'"
                )
                pattern.associated_data["target"] = target
                pattern.associated_data["access_count"] = count
                pattern.confidence = count >= 5 ? HIGH_CONFIDENCE : MEDIUM_CONFIDENCE
                push!(new_patterns, pattern)
            end
        end
        
        for np in new_patterns
            existing = findfirst(p -> 
                p.pattern_type == np.pattern_type && 
                get(p.associated_data, "target", "") == get(np.associated_data, "target", ""),
                pd.patterns
            )
            
            if existing !== nothing
                pd.patterns[existing].occurrences += 1
                pd.patterns[existing].last_seen = now()
            else
                push!(pd.patterns, np)
            end
        end
        
        new_patterns
    end
end

function analyze_task_repetition(pd::PatternDetectorState)::Vector{UserPattern}
    lock(pd.lock) do
        new_patterns = UserPattern[]
        
        if length(pd.action_history) < 2
            return new_patterns
        end
        
        sequence_length = 3
        sequences = Dict{String, Int}()
        
        for i in 1:(length(pd.action_history) - sequence_length + 1)
            sequence = ""
            for j in i:(i + sequence_length - 1)
                at = get(pd.action_history[j], "action_type", "unknown")
                sequence *= at * "->"
            end
            sequences[sequence] = get(sequences, sequence, 0) + 1
        end
        
        for (sequence, count) in sequences
            if count >= pd.min_occurrences
                pattern = UserPattern(
                    SEQUENTIAL_WORKFLOW,
                    "Repeated workflow sequence detected"
                )
                pattern.associated_data["sequence"] = sequence
                pattern.associated_data["repeat_count"] = count
                pattern.confidence = count >= 3 ? HIGH_CONFIDENCE : MEDIUM_CONFIDENCE
                push!(new_patterns, pattern)
            end
        end
        
        for np in new_patterns
            existing = findfirst(p -> 
                p.pattern_type == np.pattern_type && 
                get(p.associated_data, "sequence", "") == get(np.associated_data, "sequence", ""),
                pd.patterns
            )
            
            if existing !== nothing
                pd.patterns[existing].occurrences += 1
                pd.patterns[existing].last_seen = now()
            else
                push!(pd.patterns, np)
            end
        end
        
        new_patterns
    end
end

function compute_pattern_strength(pattern::UserPattern)::PatternConfidence
    if pattern.occurrences >= 10
        VERIFIED_CONFIDENCE
    elseif pattern.occurrences >= 5
        HIGH_CONFIDENCE
    elseif pattern.occurrences >= 3
        MEDIUM_CONFIDENCE
    else
        LOW_CONFIDENCE
    end
end

function get_identified_patterns(pd::PatternDetectorState; pattern_type::Union{PatternType, Nothing}=nothing)::Vector{UserPattern}
    lock(pd.lock) do
        if pattern_type === nothing
            filter(p -> p.is_active, pd.patterns)
        else
            filter(p -> p.is_active && p.pattern_type == pattern_type, pd.patterns)
        end
    end
end

function identify_recent_patterns(pd::PatternDetectorState; hours::Int=24)::Vector{UserPattern}
    lock(pd.lock) do
        cutoff = now() - Dates.Hour(hours)
        filter(p -> p.last_seen > cutoff && p.is_active, pd.patterns)
    end
end

function export_patterns(pd::PatternDetectorState)::Dict{String, Any}
    lock(pd.lock) do
        patterns_data = []
        for p in pd.patterns
            push!(patterns_data, Dict(
                "id" => string(p.id),
                "type" => string(p.pattern_type),
                "description" => p.description,
                "occurrences" => p.occurrences,
                "confidence" => string(p.confidence),
                "first_seen" => string(p.first_seen),
                "last_seen" => string(p.last_seen),
                "is_active" => p.is_active
            ))
        end
        
        Dict(
            "timestamp" => string(now()),
            "total_patterns" => length(pd.patterns),
            "active_patterns" => count(p -> p.is_active, pd.patterns),
            "patterns" => patterns_data
        )
    end
end
