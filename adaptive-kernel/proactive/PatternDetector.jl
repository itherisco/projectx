# PatternDetector.jl - User Pattern Detection Module
# Detects user patterns, repeated tasks, and preference signals
# Privacy-respecting behavior tracking

module PatternDetector

using Dates
using UUIDs
using Statistics
using Base.Threads

export 
    # Main types
    UserPattern,
    PatternType,
    PatternConfidence,
    BehavioralSignal,
    PatternSnapshot,
    PatternDetectorState,
    # Core functions
    create_pattern_detector,
    record_user_action,
    detect_temporal_patterns,
    detect_preference_signals,
    get_identified_patterns,
    analyze_task_repetition,
    # Pattern analysis
    compute_pattern_strength,
    identify_recent_patterns,
    export_patterns

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

"""
    PatternConfidence - Confidence level for detected patterns
"""
@enum PatternConfidence begin
    LOW_CONFIDENCE
    MEDIUM_CONFIDENCE
    HIGH_CONFIDENCE
    VERIFIED_CONFIDENCE
end

"""
    UserPattern - Represents a detected user behavior pattern
    
    # Fields
    - `id::UUID`: Unique pattern identifier
    - `pattern_type::PatternType`: Type of pattern detected
    - `description::String`: Human-readable pattern description
    - `occurrences::Int`: Number of times pattern has been observed
    - `first_seen::DateTime`: When pattern was first detected
    - `last_seen::DateTime`: Most recent occurrence
    - `confidence::PatternConfidence`: Confidence level
    - `associated_data::Dict{String, Any}`: Pattern-specific data
    - `is_active::Bool`: Whether pattern is currently relevant
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
    
    # Fields
    - `signal_type::String`: Type of signal (e.g., "file_access", "app_launch")
    - `timestamp::DateTime`: When signal was recorded
    - `context::Dict{String, Any}`: Contextual information
    - `importance::Float32`: Signal importance score [0,1]
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
    
    # Fields
    - `timestamp::DateTime`: When snapshot was taken
    - `total_patterns::Int`: Total patterns detected
    - `active_patterns::Int`: Currently active patterns
    - `new_signals::Int`: New signals since last snapshot
"""
struct PatternSnapshot
    timestamp::DateTime
    total_patterns::Int
    active_patterns::Int
    new_signals::Int
end

# ============================================================================
# PATTERN DETECTOR STATE
# ============================================================================

"""
    PatternDetector - Main pattern detection state
    
    # Fields
    - `patterns::Vector{UserPattern}`: Detected patterns
    - `recent_signals::Vector{BehavioralSignal}`: Recent behavioral signals
    - `action_history::Vector{Dict{String, Any}}`: History of user actions
    - `lock::ReentrantLock`: Thread safety
    - `min_occurrences::Int`: Minimum occurrences to establish pattern
    - `temporal_window::Dates.Hour`: Time window for temporal analysis
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

"""
    create_pattern_detector(; min_occurrences=3, temporal_window_hours=24) -> PatternDetector
"""
function create_pattern_detector(; min_occurrences::Int=3, temporal_window_hours::Int=24)::PatternDetectorState
    PatternDetectorState(min_occurrences=min_occurrences, temporal_window_hours=temporal_window_hours)
end

"""
    record_user_action(pd::PatternDetector, action::Dict{String, Any}) -> Bool
    
Record a user action and analyze for patterns. Privacy-respecting:
- Only stores action type and metadata, not sensitive content
- Actions are time-bounded
"""
function record_user_action(pd::PatternDetectorState, action::Dict{String, Any})::Bool
    lock(pd.lock) do
        try
            # Extract non-sensitive action metadata
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
            
            # Add to history
            push!(pd.action_history, safe_action)
            
            # Create behavioral signal
            signal = BehavioralSignal(
                get(safe_action, "action_type", "unknown"),
                0.5f0
            )
            signal.context = safe_action
            push!(pd.recent_signals, signal)
            
            # Prune old signals (beyond temporal window)
            cutoff = now() - pd.temporal_window
            filter!(s -> s.timestamp > cutoff, pd.recent_signals)
            
            # Prune old actions (keep last 1000)
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

"""
    detect_temporal_patterns(pd::PatternDetector) -> Vector{UserPattern}
    
Detect time-based patterns in user behavior (e.g., daily file access)
"""
function detect_temporal_patterns(pd::PatternDetectorState)::Vector{UserPattern}
    lock(pd.lock) do
        new_patterns = UserPattern[]
        
        # Group actions by type
        action_types = Dict{String, Vector{DateTime}}()
        for action in pd.action_history
            at = get(action, "action_type", "unknown")
            ts = get(action, "timestamp", now())
            if !haskey(action_types, at)
                action_types[at] = DateTime[]
            end
            push!(action_types[at], ts)
        end
        
        # Check for daily patterns (same action at similar times)
        for (action_type, timestamps) in action_types
            if length(timestamps) >= pd.min_occurrences
                # Analyze time distribution
                hours = [hour(ts) for ts in timestamps]
                mean_hour = round(Int, mean(hours))
                hour_variance = var(hours)
                
                # Low variance = consistent time pattern
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
        
        # Add new patterns
        for np in new_patterns
            # Check if similar pattern already exists
            existing = findfirst(p -> 
                p.pattern_type == np.pattern_type && 
                get(p.associated_data, "action_type", "") == get(np.associated_data, "action_type", ""),
                pd.patterns
            )
            
            if existing !== nothing
                # Update existing pattern
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

"""
    detect_preference_signals(pd::PatternDetector) -> Vector{UserPattern}
    
Detect user preferences from behavior (e.g., preferred file types, tools)
"""
function detect_preference_signals(pd::PatternDetectorState)::Vector{UserPattern}
    lock(pd.lock) do
        new_patterns = UserPattern[]
        
        # Analyze target preferences
        targets = Dict{String, Int}()
        for action in pd.action_history
            target = get(action, "target", "")
            if target !== ""
                targets[target] = get(targets, target, 0) + 1
            end
        end
        
        # Find frequently accessed targets
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
        
        # Add new preference patterns
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

"""
    analyze_task_repetition(pd::PatternDetector) -> Vector{UserPattern}
    
Detect repeated tasks in user workflow
"""
function analyze_task_repetition(pd::PatternDetectorState)::Vector{UserPattern}
    lock(pd.lock) do
        new_patterns = UserPattern[]
        
        if length(pd.action_history) < 2
            return new_patterns
        end
        
        # Look for sequential patterns (same action sequences)
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
        
        # Find repeated sequences
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
        
        # Add to existing patterns
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

"""
    compute_pattern_strength(pattern::UserPattern) -> PatternConfidence
    
Compute the confidence level based on pattern occurrences
"""
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

"""
    get_identified_patterns(pd::PatternDetector; pattern_type::Union{PatternType, Nothing}=nothing) -> Vector{UserPattern}
    
Get all identified patterns, optionally filtered by type
"""
function get_identified_patterns(pd::PatternDetectorState; pattern_type::Union{PatternType, Nothing}=nothing)::Vector{UserPattern}
    lock(pd.lock) do
        if pattern_type === nothing
            filter(p -> p.is_active, pd.patterns)
        else
            filter(p -> p.is_active && p.pattern_type == pattern_type, pd.patterns)
        end
    end
end

"""
    identify_recent_patterns(pd::PatternDetector; hours::Int=24) -> Vector{UserPattern}
    
Get patterns detected within recent time window
"""
function identify_recent_patterns(pd::PatternDetector; hours::Int=24)::Vector{UserPattern}
    lock(pd.lock) do
        cutoff = now() - Dates.Hour(hours)
        filter(p -> p.last_seen > cutoff && p.is_active, pd.patterns)
    end
end

"""
    export_patterns(pd::PatternDetector) -> Dict{String, Any}
    
Export pattern data for external analysis (privacy-respecting)
"""
function export_patterns(pd::PatternDetector)::Dict{String, Any}
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

end # module PatternDetector
