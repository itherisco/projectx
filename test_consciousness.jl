using Pkg
Pkg.activate(".")

using Dates
using JSON
using Statistics

println("Testing ConsciousnessMetrics.jl syntax...")

# Include the main module
include("adaptive-kernel/cognition/consciousness/ConsciousnessMetrics.jl")

using ConsciousnessMetrics

println("✓ Module loaded successfully")

# Test creating a snapshot
snapshot = ConsciousnessSnapshot(
    timestamp=now(),
    cycle_number=1,
    phi=0.72f0,
    gws=0.85f0,
    ife=1.34f0,
    wmc=0.78f0,
    bci=0.91f0,
    sma=0.83f0,
    ccs=0.76f0,
    kba=0.88f0,
    mcai=0.81f0,
    cdi=0.69f0,
    tcs=0.94f0,
    num_agents=9,
    num_proposals=5,
    conflict_rounds=2,
    working_memory_size=23,
    context_turn_count=47
)

println("✓ ConsciousnessSnapshot created")

# Test creating metrics collector
metrics = ConsciousnessMetrics(history_size=100)
println("✓ ConsciousnessMetrics created")

# Test context tracker
context_tracker = ContextTracker(belief_window_size=20, embedding_window_size=50)
println("✓ ContextTracker created")

# Test JSON export
json_str = to_json(snapshot)
println("✓ JSON export works: ", json_str[1:50], "...")

# Test update_metrics!
result = update_metrics!(metrics, context_tracker)
println("✓ update_metrics! works, cycle_count: ", metrics.cycle_count)

# Test status functions
status = get_metric_status(:phi, 0.72f0)
color = get_status_color(status)
println("✓ Status functions work: phi=$status, color=$color")

# Test summary stats
stats = get_summary_stats(metrics)
println("✓ Summary stats: ", stats)

println("\n✅ All ConsciousnessMetrics.jl tests passed!")
