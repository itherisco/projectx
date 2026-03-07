#!/usr/bin/env julia

# Test script for Proactive modules

include("Proactive.jl")
using .Proactive

# Test basic functionality
println("Testing PatternDetector...")
pd = create_pattern_detector()
record_user_action(pd, Dict{String, Any}("action_type" => "file_open", "target" => "notes.txt"))
patterns = get_identified_patterns(pd)
println("  - Created and recorded action, found $(length(patterns)) patterns")

println("Testing PredictiveAssistant...")
as = create_predictive_assistant()
predictions = generate_predictions(as)
println("  - Created, generated $(length(predictions)) predictions")

println("Testing ProactiveEngine...")
engine = create_proactive_engine()
println("  - Created engine successfully")

# Test engine functions
start_engine(engine)
status = get_engine_status(engine)
println("  - Engine status: running=$(status["running"]), enabled=$(status["enabled"])")

# Test pattern detection with multiple actions
for i in 1:5
    record_user_action(pd, Dict{String, Any}("action_type" => "file_open", "target" => "daily_report.txt"))
end

detect_temporal_patterns(pd)
patterns = get_identified_patterns(pd)
println("  - After more actions: $(length(patterns)) patterns detected")

println("\n✓ All Proactive modules loaded and working!")
