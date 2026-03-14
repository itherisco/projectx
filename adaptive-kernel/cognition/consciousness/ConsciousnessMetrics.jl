"""
# ConsciousnessMetrics.jl

Module for quantifying consciousness-like properties in the ITHERIS + JARVIS cognitive architecture.

## 11 Core Metrics

1. **Phi (Φ)** - Consciousness indicator measuring information integration
2. **Global Workspace Score (GWS)** - Information sharing across cognitive modules
3. **Information Flow Entropy (IFE)** - Diversity of information flow
4. **World Model Coherence (WMC)** - Consistency between predicted and actual outcomes
5. **Belief Consistency Index (BCI)** - Temporal consistency of beliefs
6. **Self-Model Accuracy (SMA)** - Accuracy of self-prediction
7. **Confidence Calibration Score (CCS)** - Confidence vs actual outcomes
8. **Knowledge Boundary Accuracy (KBA)** - Knowing what you don't know
9. **Meta-Cognitive Awareness Index (MCAI)** - Awareness of own cognitive processes
10. **Contextual Depth Index (CDI)** - Depth of context maintenance
11. **Temporal Consistency Score (TCS)** - Consistency over time

## Telemetry Integration
- JSON export for persistence
- WebSocket real-time updates for dashboard

## References
- Integrated Information Theory (IIT): Tononi, G. (2004)
- Global Workspace Theory: Baars, B. J. (1997)
"""
module ConsciousnessMetrics

using Dates
using JSON
using Statistics

# Import from existing cognitive components
# These will be loaded at runtime via inclusion

# ============================================================================
# CORE DATA STRUCTURES
# ============================================================================

"""
    ConsciousnessSnapshot - Complete consciousness state at a point in time
"""
struct ConsciousnessSnapshot
    timestamp::DateTime
    cycle_number::Int64
    
    # Primary metrics - Information Integration
    phi::Float32                    # Phi consciousness indicator
    gws::Float32                    # Global workspace score
    ife::Float32                    # Information flow entropy
    
    # World-state metrics
    wmc::Float32                    # World model coherence
    bci::Float32                    # Belief consistency index
    sma::Float32                    # Self-model accuracy
    
    # Self-model metrics
    ccs::Float32                    # Confidence calibration score
    kba::Float32                    # Knowledge boundary accuracy
    mcai::Float32                   # Meta-cognitive awareness index
    
    # Multi-turn metrics
    cdi::Float32                    # Contextual depth index
    tcs::Float32                    # Temporal consistency score
    
    # Supporting data
    num_agents::Int
    num_proposals::Int
    conflict_rounds::Int
    working_memory_size::Int
    context_turn_count::Int
    
    function ConsciousnessSnapshot(;
        timestamp::DateTime=now(),
        cycle_number::Int64=0,
        phi::Float32=0.0f0,
        gws::Float32=0.0f0,
        ife::Float32=0.0f0,
        wmc::Float32=0.0f0,
        bci::Float32=0.0f0,
        sma::Float32=0.0f0,
        ccs::Float32=0.0f0,
        kba::Float32=0.0f0,
        mcai::Float32=0.0f0,
        cdi::Float32=0.0f0,
        tcs::Float32=0.0f0,
        num_agents::Int=0,
        num_proposals::Int=0,
        conflict_rounds::Int=0,
        working_memory_size::Int=0,
        context_turn_count::Int=0
    )
        new(
            timestamp, cycle_number,
            phi, gws, ife,
            wmc, bci, sma,
            ccs, kba, mcai,
            cdi, tcs,
            num_agents, num_proposals, conflict_rounds,
            working_memory_size, context_turn_count
        )
    end
end

"""
    ConsciousnessMetrics - Collector and aggregator for consciousness metrics
"""
mutable struct ConsciousnessMetrics
    # Configuration
    history_size::Int              # Number of snapshots to retain
    calculation_interval::Int      # Calculate every N cycles
    
    # State
    snapshots::Vector{ConsciousnessSnapshot}
    current_snapshot::Union{ConsciousnessSnapshot, Nothing}
    cycle_count::Int64
    
    # Integration points (set at runtime)
    decision_spine::Any  # Union{DecisionSpine, Nothing}
    self_model::Any      # Union{SelfModelCore, Nothing}
    world_model::Any     # Union{WorldModel, Nothing}
    context::Any         # Union{ConversationContext, Nothing}
    working_memory::Any  # Union{WorkingMemoryBuffer, Nothing}
    integrator::Any      # Union{Integrator, Nothing}
    
    # Telemetry
    json_export_enabled::Bool
    websocket_enabled::Bool
    websocket_clients::Vector{Any}
    
    function ConsciousnessMetrics(;
        history_size::Int=1000,
        calculation_interval::Int=1,
        json_export_enabled::Bool=true,
        websocket_enabled::Bool=false
    )
        new(
            history_size,
            calculation_interval,
            ConsciousnessSnapshot[],
            nothing,
            0,
            nothing, nothing, nothing, nothing, nothing, nothing,
            json_export_enabled,
            websocket_enabled,
            Any[]
        )
    end
end

"""
    ContextTracker - Tracks consciousness-relevant context across turns
"""
mutable struct ContextTracker
    # Conversation-level tracking
    conversation_id::String
    turn_count::Int
    
    # Consciousness-specific tracking
    belief_history::Vector{Dict{Symbol, Any}}
    decision_embedding_history::Vector{Float32}
    topic_transitions::Vector{Symbol}
    context_retention_history::Vector{Float32}
    working_memory_reuse_history::Vector{Int}
    
    # Sliding windows
    belief_window_size::Int
    embedding_window_size::Int
    
    # Temporal tracking
    cycle_of_last_update::Int64
    
    function ContextTracker(;
        belief_window_size::Int=20,
        embedding_window_size::Int=50,
        conversation_id::String=""
    )
        new(
            conversation_id,
            0,
            Dict{Symbol, Any}[],
            Float32[],
            Symbol[],
            Float32[],
            Int[],
            belief_window_size,
            embedding_window_size,
            0
        )
    end
end

# ============================================================================
# CATEGORY 1: INFORMATION INTEGRATION MEASUREMENT
# ============================================================================

"""
    calculate_phi(proposals, decision) -> Float32

Approximation of Integrated Information Theory's Phi metric.
Measures the "amount of consciousness" in the system's information processing.

Formula: Φ = √(I × C × S)

- I (information): weighted mutual information between modules
- C (coherence): coherence of agent proposals  
- S (synergy): information gained from integration

Range: [0.0, 1.0]
- Φ < 0.2: Minimal integration (degraded or fragmented processing)
- Φ 0.2-0.5: Moderate integration (normal operation)
- Φ 0.5-0.8: High integration (rich internal coordination)
- Φ > 0.8: Very high integration (optimal consciousness-like state)
"""
function calculate_phi(
    proposals::Vector{<:Any},
    decision_cycle::Any
)::Float32
    eps_val = eps(Float32)
    
    # Extract confidences from proposals
    confidences = Float32[]
    for p in proposals
        if hasproperty(p, :confidence)
            push!(confidences, p.confidence)
        elseif hasproperty(p, :score)
            push!(confidences, p.score)
        else
            push!(confidences, 0.5f0)
        end
    end
    
    n = length(confidences)
    
    # C_coherence: coherence of agent proposals
    if n > 1
        entropy_term = -sum(c * log(c + eps_val) for c in confidences if c > 0)
        coherence = 1.0f0 - (entropy_term / log(Float32(n)))
    else
        coherence = 0.5f0
    end
    
    # I_information: based on proposal variance and coherence
    proposal_variance = n > 1 ? var(confidences) : 0.0f0
    information = proposal_variance * coherence
    
    # S_synergy: based on how much committed decision differs from individual proposals
    synergy = 0.5f0  # Default if no decision data
    if decision_cycle !== nothing && hasproperty(decision_cycle, :committed_decision)
        committed = decision_cycle.committed_decision
        if hasproperty(committed, :decision)
            mean_prop = mean(confidences)
            synergy = 1.0f0 - abs(committed.decision - mean_prop)
        end
    end
    
    # Final Phi calculation
    phi = sqrt(information * coherence * max(synergy, 0.1f0))
    
    return clamp(phi, 0.0f0, 1.0f0)
end

"""
    calculate_gws(modules_active, total_modules, attention_coverage, wm_integration) -> Float32

Global Workspace Score - Measures information sharing across cognitive modules.

Formula: GWS = (M/N) × A × W

- M: count of cognitive modules producing output
- N: total cognitive modules
- A: proportion of perception attended to
- W: working memory integration ratio

Range: [0.0, 1.0]
"""
function calculate_gws(
    modules_active::Int,
    total_modules::Int=9,
    attention_coverage::Float32=0.5f0,
    wm_integration::Float32=0.5f0
)::Float32
    if total_modules == 0
        return 0.5f0
    end
    
    module_ratio = Float32(modules_active) / Float32(total_modules)
    gws = module_ratio * attention_coverage * wm_integration
    
    return clamp(gws, 0.0f0, 1.0f0)
end

"""
    calculate_ife(decision_cycle) -> Float32

Information Flow Entropy - Measures diversity and unpredictability of information flow.

Formula: IFE = -Σᵢ p(i) × log(p(i))

Range: [0.0, ~2.0] (natural log scale)
"""
function calculate_ife(decision_cycle::Any)::Float32
    eps_val = eps(Float32)
    
    # Collect path information
    paths = Float32[]
    
    if decision_cycle !== nothing
        # Number of agent paths
        if hasproperty(decision_cycle, :proposals)
            push!(paths, Float32(length(decision_cycle.proposals)))
        end
        
        # Conflict resolution depth
        if hasproperty(decision_cycle, :conflict_resolution)
            if hasproperty(decision_cycle.conflict_resolution, :round)
                push!(paths, Float32(decision_cycle.conflict_resolution.round))
            end
        end
        
        # Decision influencers
        if hasproperty(decision_cycle, :committed_decision)
            if hasproperty(decision_cycle.committed_decision, :agent_influence)
                push!(paths, Float32(length(decision_cycle.committed_decision.agent_influence)))
            end
        end
    end
    
    # Default if no data
    if isempty(paths)
        return 1.0f0
    end
    
    # Normalize to probability distribution
    total = sum(paths) + eps_val
    probs = paths ./ total
    
    # Shannon entropy
    ife = -sum(p * log(p + eps_val) for p in probs if p > 0)
    
    return clamp(ife, 0.0f0, 2.0f0)
end

# ============================================================================
# CATEGORY 2: INTERNAL WORLD-STATE CONSISTENCY
# ============================================================================

"""
    calculate_wmc(world_model, outcome) -> Float32

World Model Coherence - Measures consistency between predicted and actual outcomes.

Formula: WMC = 1 - (Σ |predicted - actual| / N) / uncertainty_range

Range: [0.0, 1.0]
"""
function calculate_wmc(
    world_model::Any,
    outcome::Any
)::Float32
    eps_val = eps(Float32)
    
    # Default to 0.5 if no data
    if world_model === nothing || outcome === nothing
        return 0.5f0
    end
    
    # Try to get actual vs expected data
    errors = Float32[]
    
    if hasproperty(outcome, :actual_vs_expected)
        if !isempty(outcome.actual_vs_expected)
            for (key, val) in outcome.actual_vs_expected
                push!(errors, abs(val))
            end
        end
    end
    
    if isempty(errors)
        return 0.5f0
    end
    
    # Normalize by uncertainty range (typically 2.0 for normalized states)
    mean_error = mean(errors)
    wmc = 1.0f0 - (mean_error / 2.0f0)
    
    return clamp(wmc, 0.0f0, 1.0f0)
end

"""
    calculate_bci(beliefs) -> Float32

Belief Consistency Index - Measures temporal consistency of beliefs across multi-turn contexts.

Formula: BCI = 1 - (contradictions / total_beliefs)

Range: [0.0, 1.0]
"""
function calculate_bci(beliefs::Vector{<:Dict})::Float32
    if isempty(beliefs)
        return 0.5f0
    end
    
    contradictions = 0
    total_beliefs = length(beliefs)
    
    # Check for contradictions between beliefs
    for i in 1:total_beliefs
        for j in (i+1):total_beliefs
            b1 = beliefs[i]
            b2 = beliefs[j]
            
            # Check if beliefs contradict
            if haskey(b1, :predicate) && haskey(b2, :predicate)
                if b1[:predicate] == b2[:predicate] && 
                   haskey(b1, :value) && haskey(b2, :value) &&
                   b1[:value] != b2[:value]
                    contradictions += 1
                end
            end
        end
    end
    
    bci = 1.0f0 - (Float32(contradictions) / Float32(total_beliefs))
    return clamp(bci, 0.0f0, 1.0f0)
end

"""
    calculate_sma(self_model) -> Float32

Self-Model Accuracy - How accurately the AI predicts its own behavior and capabilities.

Formula: SMA = 1 - |predicted_capability - actual_performance|

Range: [0.0, 1.0]
"""
function calculate_sma(self_model::Any)::Float32
    if self_model === nothing
        return 0.5f0
    end
    
    eps_val = eps(Float32)
    
    # Use calibration error as primary indicator
    calibration = 0.5f0
    if hasproperty(self_model, :calibration_error)
        calibration = self_model.calibration_error
    elseif hasproperty(self_model, :recent_accuracy)
        calibration = 1.0f0 - self_model.recent_accuracy
    end
    
    # Factor in capability confidence
    cap_confidences = Float32[]
    if hasproperty(self_model, :capability_confidence)
        for (cap, conf) in self_model.capability_confidence
            push!(cap_confidences, conf)
        end
    end
    
    mean_conf = isempty(cap_confidences) ? 0.5f0 : mean(cap_confidences)
    
    # Combined score
    sma = (1.0f0 - calibration) * mean_conf
    return clamp(sma, 0.0f0, 1.0f0)
end

# ============================================================================
# CATEGORY 3: SELF-MODEL ACCURACY METRICS
# ============================================================================

"""
    calculate_ccs(self_model) -> Float32

Confidence Calibration Score - Measures how well confidence levels match actual outcomes.

Formula: CCS = 1 - (Σ |confidence_i - outcome_i| / N)

Range: [0.0, 1.0]
"""
function calculate_ccs(self_model::Any)::Float32
    if self_model === nothing
        return 0.5f0
    end
    
    # Try to get prediction and outcome history
    predictions = Float32[]
    outcomes = Float32[]
    
    if hasproperty(self_model, :_prediction_history)
        predictions = collect(self_model._prediction_history)
    end
    
    if hasproperty(self_model, :_outcome_history)
        outcomes = collect(self_model._outcome_history)
    end
    
    n = length(predictions)
    if n < 10 || length(outcomes) != n
        return 0.5f0  # Insufficient data
    end
    
    total_error = 0.0f0
    for (pred, outcome) in zip(predictions, outcomes)
        actual = outcome ? 1.0f0 : 0.0f0
        total_error += abs(pred - actual)
    end
    
    ccs = 1.0f0 - (total_error / Float32(n))
    return clamp(ccs, 0.0f0, 1.0f0)
end

"""
    calculate_kba(self_model) -> Float32

Knowledge Boundary Accuracy - Measures how well the AI knows what it doesn't know.

Formula: KBA = (true_positives + true_negatives) / total_queries

Range: [0.0, 1.0]
"""
function calculate_kba(self_model::Any)::Float32
    if self_model === nothing
        return 0.5f0
    end
    
    known_count = 0
    unknown_count = 0
    total_queries = 0
    
    # Count known vs unknown domains
    if hasproperty(self_model, :known_domains)
        known_count = length(self_model.known_domains)
    end
    
    if hasproperty(self_model, :unknown_domains)
        unknown_count = length(self_model.unknown_domains)
    end
    
    total_queries = known_count + unknown_count
    
    if total_queries == 0
        return 0.5f0
    end
    
    # Simplified KBA calculation
    kba = Float32(known_count) / Float32(total_queries)
    return clamp(kba, 0.0f0, 1.0f0)
end

"""
    calculate_mcai(self_model, kba, ccs) -> Float32

Meta-Cognitive Awareness Index - Overall measure of AI's awareness of its own cognitive processes.

Formula: MCAI = (KBA × 0.3) + (CCS × 0.3) + (uncertainty_estimate × 0.4)

Note: Uncertainty estimate is inverted (high estimate = low awareness)

Range: [0.0, 1.0]
"""
function calculate_mcai(
    self_model::Any,
    kba::Float32=0.5f0,
    ccs::Float32=0.5f0
)::Float32
    # Get uncertainty estimate
    uncertainty = 0.5f0
    if self_model !== nothing && hasproperty(self_model, :uncertainty_estimate)
        uncertainty = 1.0f0 - self_model.uncertainty_estimate  # Invert
    end
    
    # Weighted combination
    mcai = (kba * 0.3f0) + (ccs * 0.3f0) + (uncertainty * 0.4f0)
    
    return clamp(mcai, 0.0f0, 1.0f0)
end

# ============================================================================
# CATEGORY 4: MULTI-TURN CONTEXT METRICS
# ============================================================================

"""
    calculate_cdi(context_tracker, working_memory) -> Float32

Contextual Depth Index - Measures how deeply the system maintains and integrates information.

Formula: CDI = (C + W + B) / 3

- C: context_retention = messages_retrieved / total_messages
- W: working_integration = working_memory_reused / new_entries
- B: belief_accumulation = new_beliefs / decay_rate

Range: [0.0, 1.0]
"""
function calculate_cdi(
    context_tracker::ContextTracker,
    working_memory::Any
)::Float32
    eps_val = eps(Float32)
    
    # C: Context retention
    context_retention = 0.5f0
    if !isempty(context_tracker.context_retention_history)
        context_retention = mean(context_tracker.context_retention_history)
    end
    
    # W: Working memory integration
    working_integration = 0.5f0
    if !isempty(context_tracker.working_memory_reuse_history)
        total_ops = sum(context_tracker.working_memory_reuse_history)
        if total_ops > 0
            reused = count>(0, context_tracker.working_memory_reuse_history)
            working_integration = Float32(reused) / Float32(length(context_tracker.working_memory_reuse_history))
        end
    end
    
    # B: Belief accumulation
    belief_accumulation = 0.5f0
    if !isempty(context_tracker.belief_history)
        # New beliefs relative to decay
        belief_accumulation = min(1.0f0, Float32(length(context_tracker.belief_history)) / 10.0f0)
    end
    
    cdi = (context_retention + working_integration + belief_accumulation) / 3.0f0
    return clamp(cdi, 0.0f0, 1.0f0)
end

"""
    calculate_tcs(context_tracker) -> Float32

Temporal Consistency Score - Measures consistency of decisions and beliefs over time.

Formula: TCS = 1 - variance(decision_embedding_space) / max_variance

Range: [0.0, 1.0]
"""
function calculate_tcs(context_tracker::ContextTracker)::Float32
    eps_val = eps(Float32)
    
    embeddings = context_tracker.decision_embedding_history
    
    if length(embeddings) < 3
        return 0.5f0
    end
    
    # Calculate variance in embedding space
    variance_val = var(embeddings)
    max_variance = 0.333f0  # Maximum possible variance for uniform distribution
    
    tcs = 1.0f0 - (variance_val / max_variance)
    return clamp(tcs, 0.0f0, 1.0f0)
end

"""
    calculate_belief_strength(belief, age_cycles, reinforcement_count) -> Float32

Temporal decay model for beliefs in context window.
"""
function calculate_belief_strength(
    belief::Dict{Symbol, Any},
    age_cycles::Int,
    reinforcement_count::Int
)::Float32
    # Base decay: 0.95^age (5% decay per cycle)
    base_strength = 0.95f0 ^ age_cycles
    
    # Reinforcement bonus: +0.1 per reinforcement, max +0.3
    reinforcement_bonus = min(0.3f0, 0.1f0 * Float32(reinforcement_count))
    
    return clamp(base_strength + reinforcement_bonus, 0.0f1, 1.0f0)
end

# ============================================================================
# MAIN UPDATE FUNCTION
# ============================================================================

"""
    update_metrics!(metrics::ConsciousnessMetrics, context_tracker::ContextTracker) -> ConsciousnessSnapshot

Calculate all 11 metrics and return a snapshot.
"""
function update_metrics!(
    metrics::ConsciousnessMetrics,
    context_tracker::ContextTracker
)::ConsciousnessSnapshot
    metrics.cycle_count += 1
    cycle_number = metrics.cycle_count
    
    # Get data from integration points
    proposals = []
    decision_cycle = nothing
    self_model = metrics.self_model
    world_model = metrics.world_model
    working_memory = metrics.working_memory
    integrator = metrics.integrator
    
    # Extract data from DecisionSpine
    if metrics.decision_spine !== nothing
        ds = metrics.decision_spine
        if hasproperty(ds, :proposals)
            proposals = ds.proposals
        end
        if hasproperty(ds, :decision_cycle)
            decision_cycle = ds.decision_cycle
        end
    end
    
    # Calculate Category 1: Information Integration
    phi = calculate_phi(proposals, decision_cycle)
    gws = calculate_gws(
        integrator !== nothing && hasproperty(integrator, :active_modules) ? 
            length(integrator.active_modules) : 3,
        9,
        0.7f0,
        0.6f0
    )
    ife = calculate_ife(decision_cycle)
    
    # Calculate Category 2: World-State Consistency
    outcome = decision_cycle !== nothing && hasproperty(decision_cycle, :committed_decision) ? 
        decision_cycle.committed_decision : nothing
    wmc = calculate_wmc(world_model, outcome)
    bci = calculate_bci(context_tracker.belief_history)
    sma = calculate_sma(self_model)
    
    # Calculate Category 3: Self-Model Metrics
    ccs = calculate_ccs(self_model)
    kba = calculate_kba(self_model)
    mcai = calculate_mcai(self_model, kba, ccs)
    
    # Calculate Category 4: Multi-Turn Context
    cdi = calculate_cdi(context_tracker, working_memory)
    tcs = calculate_tcs(context_tracker)
    
    # Create snapshot
    snapshot = ConsciousnessSnapshot(
        timestamp=now(),
        cycle_number=cycle_number,
        phi=phi,
        gws=gws,
        ife=ife,
        wmc=wmc,
        bci=bci,
        sma=sma,
        ccs=ccs,
        kba=kba,
        mcai=mcai,
        cdi=cdi,
        tcs=tcs,
        num_agents=length(proposals),
        num_proposals=length(proposals),
        conflict_rounds=decision_cycle !== nothing && hasproperty(decision_cycle, :conflict_resolution) && 
            hasproperty(decision_cycle.conflict_resolution, :round) ? 
            decision_cycle.conflict_resolution.round : 0,
        working_memory_size=working_memory !== nothing && hasproperty(working_memory, :buffer) ? 
            length(working_memory.buffer) : 0,
        context_turn_count=context_tracker.turn_count
    )
    
    # Store snapshot
    push!(metrics.snapshots, snapshot)
    
    # Trim history if needed
    if length(metrics.snapshots) > metrics.history_size
        metrics.snapshots = metrics.snapshots[end-metrics.history_size+1:end]
    end
    
    metrics.current_snapshot = snapshot
    
    return snapshot
end

# ============================================================================
# TELEMETRY EXPORT
# ============================================================================

"""
    to_json(snapshot::ConsciousnessSnapshot) -> String

Export snapshot to JSON format for telemetry.
"""
function to_json(snapshot::ConsciousnessSnapshot)::String
    data = Dict(
        "timestamp" => string(snapshot.timestamp),
        "consciousness" => Dict(
            "phi" => round(snapshot.phi, digits=3),
            "global_workspace_score" => round(snapshot.gws, digits=3),
            "information_flow_entropy" => round(snapshot.ife, digits=3),
            "world_model_coherence" => round(snapshot.wmc, digits=3),
            "belief_consistency" => round(snapshot.bci, digits=3),
            "self_model_accuracy" => round(snapshot.sma, digits=3),
            "confidence_calibration" => round(snapshot.ccs, digits=3),
            "knowledge_boundary_accuracy" => round(snapshot.kba, digits=3),
            "metacognitive_awareness" => round(snapshot.mcai, digits=3),
            "contextual_depth" => round(snapshot.cdi, digits=3),
            "temporal_consistency" => round(snapshot.tcs, digits=3)
        ),
        "context" => Dict(
            "cycle_number" => snapshot.cycle_number,
            "turn_count" => snapshot.context_turn_count,
            "working_memory_entries" => snapshot.working_memory_size,
            "active_modules" => snapshot.num_agents,
            "num_proposals" => snapshot.num_proposals,
            "conflict_rounds" => snapshot.conflict_rounds
        )
    )
    
    return JSON.json(data)
end

"""
    to_json(metrics::ConsciousnessMetrics) -> String

Export full metrics state to JSON.
"""
function to_json(metrics::ConsciousnessMetrics)::String
    if metrics.current_snapshot === nothing
        return "{}"
    end
    
    data = Dict(
        "current" => JSON.parse(to_json(metrics.current_snapshot)),
        "history_size" => metrics.history_size,
        "cycle_count" => metrics.cycle_count,
        "snapshot_count" => length(metrics.snapshots)
    )
    
    return JSON.json(data)
end

"""
    export_to_file(metrics::ConsciousnessMetrics, filepath::String)

Export metrics to JSON file.
"""
function export_to_file(metrics::ConsciousnessMetrics, filepath::String)
    json_str = to_json(metrics)
    open(filepath, "w") do f
        write(f, json_str)
    end
end

# ============================================================================
# CONTEXT TRACKING
# ============================================================================

"""
    add_belief!(context_tracker::ContextTracker, belief::Dict{Symbol, Any})

Add a new belief to the context tracker.
"""
function add_belief!(context_tracker::ContextTracker, belief::Dict{Symbol, Any})
    push!(context_tracker.belief_history, belief)
    
    # Trim to window size
    if length(context_tracker.belief_history) > context_tracker.belief_window_size
        context_tracker.belief_history = context_tracker.belief_history[
            end-context_tracker.belief_window_size+1:end
        ]
    end
end

"""
    add_decision_embedding!(context_tracker::ContextTracker, embedding::Float32)

Add a decision embedding for temporal consistency tracking.
"""
function add_decision_embedding!(context_tracker::ContextTracker, embedding::Float32)
    push!(context_tracker.decision_embedding_history, embedding)
    
    # Trim to window size
    if length(context_tracker.decision_embedding_history) > context_tracker.embedding_window_size
        context_tracker.decision_embedding_history = context_tracker.decision_embedding_history[
            end-context_tracker.embedding_window_size+1:end
        ]
    end
end

"""
    increment_turn!(context_tracker::ContextTracker)

Increment the conversation turn counter.
"""
function increment_turn!(context_tracker::ContextTracker)
    context_tracker.turn_count += 1
end

"""
    record_context_retention!(context_tracker::ContextTracker, retention_rate::Float32)

Record context retention for CDI calculation.
"""
function record_context_retention!(context_tracker::ContextTracker, retention_rate::Float32)
    push!(context_tracker.context_retention_history, retention_rate)
    
    # Keep only recent history
    if length(context_tracker.context_retention_history) > 20
        context_tracker.context_retention_history = context_tracker.context_retention_history[end-19:end]
    end
end

"""
    record_working_memory_reuse!(context_tracker::ContextTracker, reused_count::Int)

Record working memory reuse for CDI calculation.
"""
function record_working_memory_reuse!(context_tracker::ContextTracker, reused_count::Int)
    push!(context_tracker.working_memory_reuse_history, reused_count)
    
    # Keep only recent history
    if length(context_tracker.working_memory_reuse_history) > 20
        context_tracker.working_memory_reuse_history = context_tracker.working_memory_reuse_history[end-19:end]
    end
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_metric_status(metric_name::Symbol, value::Float32) -> Symbol

Get metric status based on thresholds.
"""
function get_metric_status(metric_name::Symbol, value::Float32)::Symbol
    thresholds = Dict(
        :phi => (0.2, 0.4, 0.6, 0.8),
        :gws => (0.3, 0.5, 0.7, 0.85),
        :wmc => (0.3, 0.5, 0.7, 0.85),
        :sma => (0.3, 0.5, 0.7, 0.85),
        :ccs => (0.3, 0.5, 0.7, 0.85),
        :cdi => (0.2, 0.4, 0.6, 0.8),
        :tcs => (0.4, 0.6, 0.8, 0.9)
    )
    
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

"""
    get_status_color(status::Symbol) -> String

Get color for metric status.
"""
function get_status_color(status::Symbol)::String
    colors = Dict(
        :critical => "#ff4444",   # Red
        :warning => "#ff8800",    # Orange
        :normal => "#ffcc00",     # Yellow
        :good => "#44bb44",      # Green
        :excellent => "#4488ff",  # Blue
        :unknown => "#888888"     # Gray
    )
    
    return get(colors, status, "#888888")
end

"""
    get_summary_stats(metrics::ConsciousnessMetrics) -> Dict

Get summary statistics across all metrics.
"""
function get_summary_stats(metrics::ConsciousnessMetrics)::Dict
    if isempty(metrics.snapshots)
        return Dict()
    end
    
    recent = metrics.snapshots[max(1, end-100):end]
    
    stats = Dict(
        "phi_mean" => mean(s.phi for s in recent),
        "phi_std" => std(s.phi for s in recent),
        "gws_mean" => mean(s.gws for s in recent),
        "wmc_mean" => mean(s.wmc for s in recent),
        "sma_mean" => mean(s.sma for s in recent),
        "ccs_mean" => mean(s.ccs for s in recent),
        "cdi_mean" => mean(s.cdi for s in recent),
        "tcs_mean" => mean(s.tcs for s in recent),
        "total_cycles" => metrics.cycle_count,
        "snapshot_count" => length(metrics.snapshots)
    )
    
    return stats
end

# ============================================================================
# INITIALIZATION
# ============================================================================

"""
    create_default_metrics(;kwargs...) -> Tuple{ConsciousnessMetrics, ContextTracker}

Create default metrics collector and context tracker.
"""
function create_default_metrics(;
    history_size::Int=1000,
    calculation_interval::Int=1,
    json_export_enabled::Bool=true,
    websocket_enabled::Bool=false
)::Tuple{ConsciousnessMetrics, ContextTracker}
    
    metrics = ConsciousnessMetrics(
        history_size=history_size,
        calculation_interval=calculation_interval,
        json_export_enabled=json_export_enabled,
        websocket_enabled=websocket_enabled
    )
    
    context_tracker = ContextTracker(
        belief_window_size=20,
        embedding_window_size=50
    )
    
    return metrics, context_tracker
end

# Export public API
export
    ConsciousnessSnapshot,
    ConsciousnessMetrics,
    ContextTracker,
    # Category 1: Information Integration
    calculate_phi,
    calculate_gws,
    calculate_ife,
    # Category 2: World-State Consistency
    calculate_wmc,
    calculate_bci,
    calculate_sma,
    # Category 3: Self-Model Metrics
    calculate_ccs,
    calculate_kba,
    calculate_mcai,
    # Category 4: Multi-Turn Context
    calculate_cdi,
    calculate_tcs,
    calculate_belief_strength,
    # Main update
    update_metrics!,
    # Telemetry
    to_json,
    export_to_file,
    # Context tracking
    add_belief!,
    add_decision_embedding!,
    increment_turn!,
    record_context_retention!,
    record_working_memory_reuse!,
    # Utilities
    get_metric_status,
    get_status_color,
    get_summary_stats,
    create_default_metrics

end # module
