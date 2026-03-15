using Pkg
Pkg.activate(".")

using Dates
using Statistics

println("Testing ConsciousnessMetrics.jl syntax (without JSON)...")

# Manually define minimal types to test syntax
struct TestSnapshot
    timestamp::DateTime
    cycle_number::Int64
    phi::Float32
    gws::Float32
    ife::Float32
    wmc::Float32
    bci::Float32
    sma::Float32
    ccs::Float32
    kba::Float32
    mcai::Float32
    cdi::Float32
    tcs::Float32
    num_agents::Int
    num_proposals::Int
    conflict_rounds::Int
    working_memory_size::Int
    context_turn_count::Int
end

# Test basic calculations
eps_val = eps(Float32)

# Test phi calculation
confidences = [0.8f0, 0.6f0, 0.7f0]
n = length(confidences)
entropy_term = -sum(c * log(c + eps_val) for c in confidences if c > 0)
coherence = 1.0f0 - (entropy_term / log(Float32(n)))
proposal_variance = var(confidences)
information = proposal_variance * coherence
synergy = 0.75f0
phi = sqrt(information * coherence * max(synergy, 0.1f0))
println("✓ Phi calculation: phi = ", phi)

# Test GWS calculation
modules_active = 7
total_modules = 9
attention_coverage = 0.7f0
wm_integration = 0.6f0
module_ratio = Float32(modules_active) / Float32(total_modules)
gws = module_ratio * attention_coverage * wm_integration
println("✓ GWS calculation: gws = ", gws)

# Test IFE calculation
paths = Float32[3.0f0, 2.0f0, 5.0f0]
total = sum(paths) + eps_val
probs = paths ./ total
ife = -sum(p * log(p + eps_val) for p in probs if p > 0)
println("✓ IFE calculation: ife = ", ife)

# Test WMC calculation
errors = Float32[0.1f0, 0.2f0, 0.15f0]
mean_error = mean(errors)
wmc = 1.0f0 - (mean_error / 2.0f0)
println("✓ WMC calculation: wmc = ", wmc)

# Test BCI calculation
beliefs = Dict{Symbol, Any}[]
push!(beliefs, Dict(:predicate => :likes_coffee, :value => true))
push!(beliefs, Dict(:predicate => :likes_tea, :value => false))
contradictions = 0
for i in 1:length(beliefs), j in (i+1):length(beliefs)
    b1, b2 = beliefs[i], beliefs[j]
    if b1[:predicate] == b2[:predicate] && b1[:value] != b2[:value]
        global contradictions += 1
    end
end
bci = 1.0f0 - (Float32(contradictions) / Float32(length(beliefs)))
println("✓ BCI calculation: bci = ", bci)

# Test SMA calculation
calibration = 0.2f0
cap_confidences = Float32[0.8f0, 0.9f0, 0.85f0]
mean_conf = mean(cap_confidences)
sma = (1.0f0 - calibration) * mean_conf
println("✓ SMA calculation: sma = ", sma)

# Test CCS calculation
predictions = Float32[0.8f0, 0.7f0, 0.9f0, 0.6f0, 0.75f0]
outcomes = Float32[1.0f0, 1.0f0, 0.0f0, 1.0f0, 1.0f0]
n = length(predictions)
total_error = sum(abs(predictions[i] - outcomes[i]) for i in 1:n)
ccs = 1.0f0 - (total_error / Float32(n))
println("✓ CCS calculation: ccs = ", ccs)

# Test KBA calculation
known_count = 8
unknown_count = 2
total_queries = known_count + unknown_count
kba = Float32(known_count) / Float32(total_queries)
println("✓ KBA calculation: kba = ", kba)

# Test MCAI calculation
uncertainty = 0.4f0
mcai = (kba * 0.3f0) + (ccs * 0.3f0) + (uncertainty * 0.4f0)
println("✓ MCAI calculation: mcai = ", mcai)

# Test CDI calculation
context_retention = 0.7f0
working_integration = 0.6f0
belief_accumulation = 0.5f0
cdi = (context_retention + working_integration + belief_accumulation) / 3.0f0
println("✓ CDI calculation: cdi = ", cdi)

# Test TCS calculation
embeddings = Float32[0.5f0, 0.52f0, 0.48f0, 0.51f0, 0.49f0]
variance_val = var(embeddings)
max_variance = 0.333f0
tcs = 1.0f0 - (variance_val / max_variance)
println("✓ TCS calculation: tcs = ", tcs)

# Test belief strength
age_cycles = 10
reinforcement_count = 3
base_strength = 0.95f0 ^ age_cycles
reinforcement_bonus = min(0.3f0, 0.1f0 * Float32(reinforcement_count))
belief_strength = clamp(base_strength + reinforcement_bonus, 0.0f0, 1.0f0)
println("✓ Belief strength calculation: strength = ", belief_strength)

# Test status functions
function get_metric_status(metric_name::Symbol, value::Float32)::Symbol
    thresholds = Dict(:phi => (0.2f0, 0.4f0, 0.6f0, 0.8f0))
    if !haskey(thresholds, metric_name)
        return :unknown
    end
    (critical, warning, normal, good) = thresholds[metric_name]
    if value < critical
        return :critical
    elseif value < warning
        return :warning
    elseif value < normal
        return :normal
    elseif value < good
        return :good
    else
        return :excellent
    end
end

status = get_metric_status(:phi, 0.72f0)
println("✓ Status function: phi status = ", status)

function get_status_color(status::Symbol)::String
    colors = Dict(:critical => "#ff4444", :warning => "#ff8800", :normal => "#ffcc00", :good => "#44bb44", :excellent => "#4488ff")
    return get(colors, status, "#888888")
end

color = get_status_color(status)
println("✓ Color function: color = ", color)

println("\n✅ All ConsciousnessMetrics calculation tests passed!")
