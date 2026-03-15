using Pkg

for pkg in ["Random", "Dates", "UUIDs", "Logging", "JSON", "ZMQ", "Statistics", "LinearAlgebra", "Serialization", "StatsBase", "Distributions"]
    try
        Base.require(Main, Symbol(pkg))
    catch
        try
            Pkg.add(pkg)
            Base.require(Main, Symbol(pkg))
        catch e
            @warn "Could not install package $pkg: $e"
        end
    end
end

using Random, Dates, UUIDs, Logging, JSON, ZMQ, Statistics, LinearAlgebra, Serialization, StatsBase, Distributions
using Distributions: Categorical
for pkg in ["Random",      "Dates",      "UUIDs",      "Logging",      "JSON",      "ZMQ",      "Statistics",      "LinearAlgebra",      "Serialization",      "StatsBase",      "Distributions"]
    try
        Base.require(Main,      Symbol(pkg))
    catch
        try
            Pkg.add(pkg)
            Base.require(Main,      Symbol(pkg))
        catch e
            @warn "Could not install package $pkg:$e"
        end
    end
end

using Random,      Dates,      UUIDs,      Logging,      JSON,      ZMQ,      Statistics,      LinearAlgebra,      Serialization,      StatsBase,      Distributions
using Distributions:Categorical

# Add ImaginaryExperience struct for simulated experiences
mutable struct ImaginaryExperience
    scenario::String
    predicted_state::Vector{Float32}
    predicted_reward::Float32
    confidence::Float32
end

mutable struct SelfModel
    traits::Dict{String,    Float32}
    competence::Float32
    identity_confidence::Float32
end

mutable struct NeuralLayer
    weights::Matrix{Float32}
    bias::Vector{Float32}
    activation::Function
end

mutable struct Obsession
    target::String
    intensity::Float32
    horizon::Int
    sub_obsessions::Vector{Obsession}
end

mutable struct Plan
    obsession_target::String
    actions::Vector{String}
    expected_rewards::Vector{Float32}
    horizon::Int
    confidence::Float32
    sub_plans::Vector{Plan}
end

mutable struct MetaGoal
    target::String
    priority::Float32
    horizon::Int
    confidence::Float32
    sub_obsessions::Vector{Obsession}
end

mutable struct SelfModification
    learning_rate::Float32
    gamma::Float32
    drive_weights::Dict{String,    Float32}
    layer_scaling::Dict{Int,    Float32}
    last_update_cycle::Int
end

mutable struct Memory
    episodic::Vector{Dict{String,    Any}}
    semantic::Dict{String,    Any}
    procedural::Dict{String,    Function}
    emotional_state::Dict{String,    Float32}
    working_memory::Vector{Any}
    drives::Dict{String,    Float32}
    narrative::Vector{String}
    obsessions::Vector{Obsession}
    plans::Vector{Plan}
    meta_goals::Vector{MetaGoal}
    self_mod::SelfModification
    imaginary_experiences::Vector{ImaginaryExperience}  # NEW:     For creative simulation
end

mutable struct Brain
    layers::Vector{NeuralLayer}
    memory::Memory
    value_network::NeuralLayer
    policy_network::NeuralLayer
    predictor_network::NeuralLayer
    context_state::Vector{Float32}
    belief_state::Vector{Float32}
    latent_belief::Vector{Float32}  # NEW:    hidden belief (64)
    belief_inertia::Float32
    self_model::SelfModel
    learning_rate::Float32
    gamma::Float32
    cycle_count::Int
    last_hidden::Vector{Float32}  # NEW:    Store last latent state
end

mutable struct PerceptionBoundary
    zmq_enabled::Bool
    zmq_context::Union{Nothing,    Context}
    zmq_socket::Union{Nothing,    Socket}
    endpoint::String
end

mutable struct ActionBoundary
    zmq_enabled::Bool
    zmq_context::Union{Nothing,    Context}
    zmq_socket::Union{Nothing,    Socket}
    endpoint::String
end

const ARCH_LOCK_CYCLES = 5000

function initialize_brain(input_size::Int=10,    hidden_size::Int=64)::Brain
    recurrence_input_size = input_size + hidden_size

    layer1 = NeuralLayer(
        randn(Float32,    hidden_size,    recurrence_input_size) .* 0.1f0,     
        zeros(Float32,    hidden_size),     
        x -> tanh.(x)
    )
    
    layer2 = NeuralLayer(
        randn(Float32,    hidden_size,    hidden_size) .* 0.1f0,     
        zeros(Float32,    hidden_size),     
        x -> max.(0f0,    x)
    )
    
    value_net = NeuralLayer(
        randn(Float32,    1,    hidden_size) .* 0.1f0,     
        zeros(Float32,    1),     
        identity
    )
    
    policy_net = NeuralLayer(
        randn(Float32,    4,    hidden_size) .* 0.1f0,     
        zeros(Float32,    4),     
        x -> begin
            exp_x = exp.(x .- maximum(x))
            exp_x ./ sum(exp_x)
        end
    )

    predictor_net = NeuralLayer(
        randn(Float32,    input_size,    hidden_size) .* 0.1f0,     
        zeros(Float32,    input_size),     
        identity
    )
    
    self_mod = SelfModification(
        0.01f0,    
        0.95f0,    
        Dict("curiosity" => 1.0f0,    "control" => 1.0f0,    "exploration" => 1.0f0,    "creativity" => 1.0f0),    
        Dict(1 => 1.0f0,    2 => 1.0f0),    
        0
    )
    
    memory = Memory(
        Dict{String,    Any}[],    
        Dict{String,    Any}(),    
        Dict{String,    Function}(),    
        Dict("valence" => 0.0f0,    "arousal" => 0.5f0,    "confidence" => 0.5f0),    
        Any[],    
        Dict(
            "curiosity" => 0.5f0,    
            "stability" => 0.5f0,    
            "boredom" => 0.0f0,    
            "control" => 0.5f0,    
            "creativity" => 0.3f0
        ),    
        String[],    
        Obsession[],    
        Plan[],    
        MetaGoal[],    
        self_mod,    
        ImaginaryExperience[]  # Initialize imaginary experiences
    )
    
    self_model = SelfModel(
        Dict(
            "risk_tolerance" => 0.5f0,    
            "curiosity_bias" => 0.5f0,    
            "control_need" => 0.5f0
        ),    
        0.5f0,    
        0.9f0
    )
    
    return Brain([layer1,    layer2],    memory,    value_net,    policy_net,    predictor_net,    
                 zeros(Float32,    hidden_size),    
                 zeros(Float32,    input_size),    
                 zeros(Float32,    hidden_size),     # Initialize latent_belief
                 0.97f0,    
                 self_model,    
                 0.01f0,    
                 0.95f0,    
                 0,    
                 zeros(Float32,    hidden_size))  # Initialize last_hidden
end

function encode_perception(perception::Dict{String,    Any})::Vector{Float32}
    features = Float32[
        get(perception,    "cpu_load",    0.5),    
        get(perception,    "memory_usage",    0.5),    
        get(perception,    "disk_io",    0.3),    
        get(perception,    "network_latency",    50.0) / 200.0,    
        get(perception,    "overall_severity",    0.0),    
        length(get(perception,    "threats",    [])) / 10.0,    
        get(perception,    "file_count",    0) / 1000.0,    
        get(perception,    "process_count",    100) / 200.0,    
        0.0f0,    
        0.0f0
    ]
    return features
end

function forward_pass(layer::NeuralLayer,    input::Vector{Float32})::Vector{Float32}
    @assert size(layer.weights,    2) == length(input) """
    Forward pass dimension mismatch: expected $(size(layer.weights,    2)),    
    got $(length(input))
    """
    return layer.activation.(layer.weights * input .+ layer.bias)
end

function emotion_gates(brain::Brain)
    e = brain.memory.emotional_state
    return (
        exploration = clamp(1f0 - e["confidence"],    0.1f0,    1f0),    
        inhibition = clamp(-e["valence"],    0f0,    1f0)
    )
end

function update_belief!(brain::Brain,    perception_vec::Vector{Float32})
    @assert length(brain.belief_state) == length(perception_vec)
    
    brain.belief_state .=
        brain.belief_inertia .* brain.belief_state .+
        (1f0 - brain.belief_inertia) .* perception_vec
    
    # Update latent belief
    if norm(brain.last_hidden) > 1f-6
        brain.latent_belief .=
            0.9f0 .* brain.latent_belief .+
            0.1f0 .* brain.last_hidden
    end
end

function self_evaluate(brain::Brain,    thought::Dict{String,    Any})
    expected_value = thought["value_estimate"]
    self_expectation = brain.self_model.competence

    return expected_value - self_expectation
end

function update_narrative!(brain::Brain; recent_n::Int=20)
    if isempty(brain.memory.episodic)
        return
    end

    recent = brain.memory.episodic[max(1,    end-recent_n+1):end]

    story_lines = [
        "Cycle $(e["thought"]["cycle"]): Performed $(e["thought"]["action"]) with confidence $(round(e["thought"]["confidence"],    digits=2)),    reward $(round(get(e["outcome"],    "reward",    0.0),    digits=2))"
        for e in recent
    ]

    push!(brain.memory.narrative,    join(story_lines,    "; "))
    if length(brain.memory.narrative) > 50
        popfirst!(brain.memory.narrative)
    end
end

function spawn_obsession!(brain::Brain)
    drives = brain.memory.drives
    if drives["curiosity"] > 0.7 && rand() < 0.2
        obs = Obsession("Investigate high severity threats",    0.8f0,    50,    Obsession[])
        push!(brain.memory.obsessions,    obs)
        @info "New obsession spawned: $(obs.target)"
    end
end

function apply_obsession_bias!(brain::Brain, action_probs::Vector{Float32})
    if !isempty(brain.memory.obsessions)
        top_obs = brain.memory.obsessions[end]
        if top_obs.intensity > 0.5
            if top_obs.target == "Investigate high severity threats"
                idx = findfirst(==("alert"),    ["monitor",    "optimize",    "alert",    "mitigate"])
                if idx !== nothing
                    action_probs[idx] += 0.3f0
                    action_probs ./= sum(action_probs)
                end
            end
            top_obs.horizon -= 1
            if top_obs.horizon <= 0
                pop!(brain.memory.obsessions)
            end
        end
    end
    return action_probs
end

function generate_sub_obsessions!(obs::Obsession)
    if obs.intensity > 0.7 && isempty(obs.sub_obsessions)
        push!(obs.sub_obsessions,    Obsession(obs.target * " - scan critical nodes",    0.5f0,    20,    Obsession[]))
        push!(obs.sub_obsessions,    Obsession(obs.target * " - monitor anomalies",    0.5f0,    25,    Obsession[]))
    end
end

function generate_plan!(brain::Brain,    obs::Obsession,    perception::Dict{String,    Any})
    # Prevent duplicate plans
    if any(p -> p.obsession_target == obs.target,    brain.memory.plans)
        return
    end
    
    action_seq = String[]
    expected_rewards = Float32[]
    
    if obs.target == "Investigate high severity threats"
        action_seq = ["monitor",    "alert",    "mitigate"]
        expected_rewards = [0.1f0,    0.3f0,    0.5f0]
    elseif occursin("scan critical nodes",    obs.target)
        action_seq = ["monitor",    "optimize"]
        expected_rewards = [0.1f0,    0.2f0]
    elseif occursin("monitor anomalies",    obs.target)
        action_seq = ["monitor",    "alert"]
        expected_rewards = [0.1f0,    0.3f0]
    else
        action_seq = ["monitor",    "optimize"]
        expected_rewards = [0.1f0,    0.2f0]
    end
    
    plan = Plan(obs.target,    action_seq,    expected_rewards,    length(action_seq),    0.9f0,    Plan[])
    push!(brain.memory.plans,    plan)
    @info "Plan created for obsession: $(obs.target)"
end

function select_action_hierarchical!(brain::Brain,    perception::Dict{String,    Any})
    if isempty(brain.memory.plans)
        return nothing
    end

    plan_confidences = [p.confidence for p in brain.memory.plans]
    max_conf_idx = argmax(plan_confidences)
    plan = brain.memory.plans[max_conf_idx]

    current_plan = plan
    plan_stack = [plan]
    
    while !isempty(current_plan.sub_plans)
        sub_plan_confidences = [sp.confidence for sp in current_plan.sub_plans]
        max_sub_conf_idx = argmax(sub_plan_confidences)
        sub_plan = current_plan.sub_plans[max_sub_conf_idx]
        
        if sub_plan.horizon > 0
            current_plan = sub_plan
            push!(plan_stack,    sub_plan)
        else
            deleteat!(current_plan.sub_plans,    max_sub_conf_idx)
            break
        end
    end

    if current_plan.horizon > 0 && !isempty(current_plan.actions)
        action_idx = length(current_plan.actions) - current_plan.horizon + 1
        if action_idx <= length(current_plan.actions)
            action = current_plan.actions[action_idx]
            current_plan.horizon -= 1
            
            if current_plan.horizon <= 0
                if length(plan_stack) > 1
                    parent_plan = plan_stack[end-1]
                    plan_to_remove_idx = findfirst(sp -> sp === current_plan,    parent_plan.sub_plans)
                    if plan_to_remove_idx !== nothing
                        deleteat!(parent_plan.sub_plans,    plan_to_remove_idx)
                    end
                else
                    deleteat!(brain.memory.plans,    max_conf_idx)
                end
            end
            
            return action
        end
    else
        deleteat!(brain.memory.plans,    max_conf_idx)
        return nothing
    end
    
    return nothing
end

function adapt_plans_hierarchical!(brain::Brain,    perception::Dict{String,    Any},    outcome::Dict{String,    Any})
    reward = Float32(get(outcome,    "reward",    0.0))
    for plan in brain.memory.plans
        adapt_plan_recursive!(plan,    reward)
    end
end

function adapt_plan_recursive!(plan::Plan,    reward::Float32)
    if plan.horizon < length(plan.expected_rewards) && plan.horizon >= 0
        expected_idx = length(plan.expected_rewards) - plan.horizon
        if expected_idx <= length(plan.expected_rewards) && expected_idx > 0
            predicted = plan.expected_rewards[expected_idx]
            drift = abs(reward - predicted)
            plan.confidence *= (0.9f0 ^ drift)
            plan.confidence = clamp(plan.confidence,    0.1f0,    1.0f0)
        end
    end
    
    for sub_plan in plan.sub_plans
        adapt_plan_recursive!(sub_plan,    reward)
    end
end

function evaluate_obsessions!(brain::Brain)
    for obs in brain.memory.obsessions
        obs_priority = obs.intensity * 0.6 + brain.memory.emotional_state["arousal"] * 0.4
        obs.intensity = clamp(obs_priority,    0f0,    1f0)
    end
end

function generate_meta_goals!(brain::Brain)
    brain.memory.meta_goals = [g for g in brain.memory.meta_goals if g.horizon > 0]

    for obs in brain.memory.obsessions
        if !any(g -> any(o -> o.target == obs.target, g.sub_obsessions), brain.memory.meta_goals)
            meta = MetaGoal(
                "Strategic: " * obs.target,    
                obs.intensity,    
                obs.horizon,    
                obs.intensity,    
                [obs]
            )
            push!(brain.memory.meta_goals,    meta)
            @info "Meta-goal created: $(meta.target)"
        end
    end
end

function select_action_meta!(brain::Brain,    perception::Dict{String,    Any})
    if isempty(brain.memory.meta_goals)
        return nothing
    end

    meta_priorities = [g.priority * g.confidence for g in brain.memory.meta_goals]
    if isempty(meta_priorities)
        return nothing
    end
    max_meta_idx = argmax(meta_priorities)
    meta = brain.memory.meta_goals[max_meta_idx]

    candidate_plans = Plan[]
    for obs in meta.sub_obsessions
        candidate_plans = vcat(candidate_plans,    [p for p in brain.memory.plans if p.obsession_target == obs.target])
    end

    if isempty(candidate_plans)
        return nothing
    end

    plan_confidences = [p.confidence for p in candidate_plans]
    max_plan_idx = argmax(plan_confidences)
    plan = candidate_plans[max_plan_idx]

    current_plan = plan
    while !isempty(current_plan.sub_plans)
        sub_plan_confidences = [sp.confidence for sp in current_plan.sub_plans]
        if !isempty(sub_plan_confidences)
            max_sub_idx = argmax(sub_plan_confidences)
            sub_plan = current_plan.sub_plans[max_sub_idx]
            if sub_plan.horizon > 0
                current_plan = sub_plan
            else
                deleteat!(current_plan.sub_plans,    max_sub_idx)
                break
            end
        else
            break
        end
    end

    if current_plan.horizon > 0 && !isempty(current_plan.actions)
        action_idx = length(current_plan.actions) - current_plan.horizon + 1
        if action_idx <= length(current_plan.actions)
            action = current_plan.actions[action_idx]
            current_plan.horizon -= 1
            meta.confidence *= 0.99f0
            meta.horizon -= 1
            return action
        end
    else
        plan_idx = findfirst(p -> p === plan,    brain.memory.plans)
        if plan_idx !== nothing
            deleteat!(brain.memory.plans,    plan_idx)
        end
        return nothing
    end
    
    return nothing
end

function adapt_meta_goals!(brain::Brain,    outcome::Dict{String,    Any})
    reward = Float32(get(outcome,    "reward",    0.0))
    
    for meta in brain.memory.meta_goals
        meta.priority = clamp(meta.priority + 0.1f0 * reward,    0f0,    1f0)
        meta.priority *= 0.98f0  # Decay priority over time
        meta.confidence *= 0.99f0  # Decay confidence over time
        brain.memory.drives["curiosity"] += 0.05f0 * meta.priority
        brain.memory.drives["control"] += 0.03f0 * meta.priority
        
        for drive in keys(brain.memory.drives)
            brain.memory.drives[drive] = clamp(brain.memory.drives[drive],    0f0,    1f0)
        end
    end
    
    # Prune low-priority meta-goals
    brain.memory.meta_goals =
        [g for g in brain.memory.meta_goals if g.priority > 0.05 && g.horizon > 0]
end

function bias_obsessions_with_drives!(brain::Brain)
    for obs in brain.memory.obsessions
        obs.intensity *= brain.memory.self_mod.drive_weights["curiosity"]
        obs.intensity = clamp(obs.intensity,    0f0,    1f0)
    end
end

# NEW:    Creative imagination function - simulate hypothetical scenarios
function imagine_scenarios!(brain::Brain,    perception::Dict{String,    Any})
    # Only imagine when creativity drive is high
    if brain.memory.drives["creativity"] < 0.6
        return
    end
    
    # Use consistent input space aligned with inference dynamics
    encoded_input = encode_perception(perception)
    prediction_error = encoded_input .- brain.belief_state
    current_state = vcat(
        prediction_error,
        brain.context_state
    )
    
    # Generate multiple hypothetical scenarios
    scenarios = [
        "high_load_scenario",    
        "network_failure_scenario",    
        "memory_pressure_scenario",    
        "optimal_performance_scenario"
    ]
    
    for scenario in scenarios
        # Simulate forward using the predictor network with noise
        h1 = forward_pass(brain.layers[1],    current_state)
        h2 = forward_pass(brain.layers[2],    h1)
        brain.last_hidden .= h2
        brain.context_state .= clamp.(brain.context_state, -1f0, 1f0)
        brain.context_state ./= max(norm(brain.context_state), 1f0)
        
        # Add creativity-based noise to predictions
        noise_level = 0.1f0 * brain.memory.drives["creativity"]
        predicted_state = forward_pass(brain.predictor_network,    h2)
        @assert length(predicted_state) == length(brain.belief_state) "Predictor output must match perception space"
        predicted_state .+= randn(Float32,    length(predicted_state)) .* noise_level
        
        # Estimate reward for this scenario
        predicted_reward = mean(predicted_state) * brain.memory.drives["creativity"]
        
        # Create imaginary experience
        imaginary_exp = ImaginaryExperience(
            scenario,    
            predicted_state,    
            predicted_reward,    
            brain.memory.drives["creativity"]
        )
        
        push!(brain.memory.imaginary_experiences,    imaginary_exp)
    end
    
    # Limit imaginary experiences to prevent memory overflow
    if length(brain.memory.imaginary_experiences) > 100
        deleteat!(brain.memory.imaginary_experiences,    1:10)
    end
    
    @info "Generated $(length(scenarios)) imaginary scenarios for creative planning"
end

# NEW:    Use imaginary experiences to enhance planning
function enhance_planning_with_imagination!(brain::Brain)
    if isempty(brain.memory.imaginary_experiences) || isempty(brain.memory.plans)
        return
    end
    
    # Use the most confident imaginary experiences to adjust plan confidence
    recent_imaginary = brain.memory.imaginary_experiences[max(1,    end-10):end]
    
    for plan in brain.memory.plans
        # Adjust plan confidence based on how well it would perform in imaginary scenarios
        for imaginary_exp in recent_imaginary
            # Decay imaginary experience confidence
            imaginary_exp.confidence *= 0.98f0
            
            # Simple heuristic: if the plan's expected rewards align with imaginary rewards
            if !isempty(plan.expected_rewards)
                avg_expected = mean(plan.expected_rewards)
                reward_alignment = 1.0f0 - abs(avg_expected - imaginary_exp.predicted_reward) / max(abs(avg_expected),    abs(imaginary_exp.predicted_reward),    1f-5)
                plan.confidence = clamp(plan.confidence * (1.0f0 + 0.1f0 * reward_alignment * imaginary_exp.confidence),    0.1f0,    1.0f0)
            end
        end
    end
    
    # Prune low-confidence imaginary experiences
    brain.memory.imaginary_experiences =
        [ie for ie in brain.memory.imaginary_experiences if ie.confidence > 0.1f0]
end

function evaluate_self_modification!(brain::Brain)
    # Lock self-modification until system is stable
    if brain.cycle_count < ARCH_LOCK_CYCLES
        return
    end
    
    insights = reflect(brain)
    stability_score = 1.0f0 - abs(insights["avg_reward"])
    
    brain.memory.self_mod.learning_rate *= 1.0f0 + 0.1f0*(0.5f0 - stability_score)
    brain.learning_rate = clamp(brain.memory.self_mod.learning_rate,    0.001f0,    0.1f0)
    
    brain.memory.self_mod.gamma *= 1.0f0 + 0.05f0*(insights["avg_confidence"] - 0.5f0)
    brain.gamma = clamp(brain.memory.self_mod.gamma,    0.8f0,    0.99f0)
    
    for (i,    layer) in enumerate(brain.layers)
        activity = mean(abs.(layer.weights))
        scale = 1.0f0 + 0.1f0*(0.5 - activity)
        brain.memory.self_mod.layer_scaling[i] = scale
        layer.weights .*= scale
    end
    
    brain.memory.self_mod.drive_weights["curiosity"] *= 1.0f0 + 0.05f0*(1.0 - stability_score)
    brain.memory.self_mod.drive_weights["control"] *= 1.0f0 + 0.03f0*stability_score
    brain.memory.self_mod.drive_weights["creativity"] *= 1.0f0 + 0.02f0*(1.0 - stability_score)
    
    for drive in keys(brain.memory.self_mod.drive_weights)
        brain.memory.self_mod.drive_weights[drive] = clamp(brain.memory.self_mod.drive_weights[drive],    0.1f0,    2.0f0)
    end
    
    brain.memory.self_mod.last_update_cycle = brain.cycle_count
    @info "Self-modification applied: learning_rate=$(round(brain.learning_rate,    digits=4)),    gamma=$(round(brain.gamma,    digits=3))"
end

function infer(brain::Brain,    perception::Dict{String,    Any})
    encoded_input = encode_perception(perception)
    update_belief!(brain,    encoded_input)
    
    combined_input = vcat(
        encoded_input .- brain.belief_state,    
        brain.context_state
    )
    
    h1 = forward_pass(brain.layers[1],    combined_input)
    brain.context_state .= 0.8f0 .* brain.context_state .+ 0.2f0 .* h1 
    # Apply proper context state normalization to prevent latent explosion
    brain.context_state .= clamp.(brain.context_state,    -1f0,    1f0)
    brain.context_state ./= max(norm(brain.context_state),    1f0)
    h2 = forward_pass(brain.layers[2],    h1)
    
    # Store the last hidden state - this is the key addition
    brain.last_hidden .= h2
    
    value = forward_pass(brain.value_network,    h2)[1]
    action_probs = forward_pass(brain.policy_network,    h2)
    
    action_probs = apply_obsession_bias!(brain,    action_probs)
    
    predicted_next_state = forward_pass(brain.predictor_network,    h2)
    
    thought_dict = Dict{String,    Any}("value_estimate" => Float64(value))
    self_error = self_evaluate(brain,    thought_dict)

    if abs(self_error) > 0.3
        brain.memory.emotional_state["arousal"] += 0.2f0
        brain.memory.emotional_state["confidence"] *= 0.9f0
    end
    
    gates = emotion_gates(brain)
    
    temp = gates.exploration
    scaled = exp.(log.(action_probs .+ 1f-8) ./ temp)
    scaled ./= sum(scaled)
    
    action_idx = rand(Categorical(scaled))
    action_map = ["monitor",    "optimize",    "alert",    "mitigate"]
    
    # Fix confidence saturation
    entropy = -sum(scaled .* log.(scaled .+ 1f-8))
    confidence = clamp(1.0 - entropy / log(length(scaled)), 0.05, 0.95)
    
    return Dict(
        "action" => action_map[action_idx],    
        "action_idx" => action_idx,    
        "action_probs" => action_probs,    
        "value_estimate" => Float64(value),    
        "prediction" => predicted_next_state,    
        "confidence" => confidence,    
        "perception_hash" => hash(JSON.json(perception)),    
        "cycle" => brain.cycle_count
    )
end

function assimilate_thought!(brain::Brain,    thought::Dict{String,    Any})
    value = Float32(get(thought,    "value_estimate",    0.0))
    if value > 0.5
        brain.memory.emotional_state["valence"] =
            0.9f0 * brain.memory.emotional_state["valence"] + 0.1f0 * value
    else
        brain.memory.emotional_state["valence"] =
            0.9f0 * brain.memory.emotional_state["valence"] - 0.1f0 * abs(value)
    end
    brain.memory.emotional_state["confidence"] = Float32(get(thought,    "confidence",    0.5))
end

function update_drives!(brain::Brain,    prediction_error::Float32)
    d = brain.memory.drives

    d["curiosity"] += 0.1f0 * prediction_error
    d["boredom"] += 0.01f0
    d["stability"] -= 0.05f0 * prediction_error
    d["creativity"] += 0.02f0 * abs(prediction_error)  # Creativity increases with uncertainty

    for k in keys(d)
        d[k] = clamp(d[k],    0f0,    1f0)
    end
end

function update_identity!(brain::Brain,    reward::Float32)
    sm = brain.self_model
    lr = 1f0 - sm.identity_confidence

    sm.competence = clamp(
        sm.competence + lr * reward,    
        0f0,    1f0
    )

    sm.traits["risk_tolerance"] =
        clamp(sm.traits["risk_tolerance"] + lr * reward,    0f0,    1f0)
end

function learn_from_experience!(brain::Brain,    
                                perception::Dict{String,    Any},    
                                next_perception::Dict{String,    Any},    
                                thought::Dict{String,    Any},    
                                outcome::Dict{String,    Any})
    reward = Float32(get(outcome,    "reward",    0.0))
    encoded = encode_perception(perception)
    update_belief!(brain,    encoded)
    combined_input = vcat(
        encoded .- brain.belief_state,    
        brain.context_state
    )
    hidden1 = forward_pass(brain.layers[1],    combined_input)
    hidden2 = forward_pass(brain.layers[2],    hidden1)
    current_value = forward_pass(brain.value_network,    hidden2)[1]
    next_value = Float32(get(outcome,    "next_value",    0.0f0))
    td_error = reward + brain.gamma * next_value - current_value
    
    brain.value_network.weights .+= brain.learning_rate * td_error * hidden2'
    brain.value_network.bias .+= brain.learning_rate * td_error
    
    probs = get(thought,    "action_probs",    Float32[])
    a = get(thought,    "action_idx",    1)
    if a > 0 && a <= length(probs)
        advantage = td_error
        # Fix policy gradient - use proper log-prob gradient
        h = hidden2 ./ max(norm(hidden2), 1f0)
        for i in 1:length(probs)
            indicator = (i == a) ? 1f0 : 0f0
            grad_scalar = advantage * (indicator - probs[i])
            # The gradient for the weights is the outer product of the error signal and the hidden state
            grad = grad_scalar .* h
            brain.policy_network.weights[i,    :] .+= (brain.learning_rate * 0.3f0) .* clamp.(grad,    -1f0,    1f0)
            brain.policy_network.bias[i] += brain.learning_rate * 0.3f0 * grad_scalar
        end
    end
    
    push!(brain.memory.episodic,    Dict(
        "perception" => perception,    
        "next_perception" => next_perception,    
        "thought" => thought,    
        "outcome" => outcome,    
        "timestamp" => now()
    ))
    
    if length(brain.memory.episodic) > 1000
        popfirst!(brain.memory.episodic)
    end
    
    update_identity!(brain,    reward)
end

function recall_recent_context(brain::Brain,    n::Int=5)
    if isempty(brain.memory.episodic)
        return []
    end
    return brain.memory.episodic[max(1,    end-n+1):end]
end

function decay_weights!(layer::NeuralLayer; rate=1f-4)
    layer.weights .*= (1f0 - rate)
end

function check_value_drift!(brain::Brain)
    if !isempty(brain.memory.episodic)
        # Guard against zero last_hidden
        if norm(brain.last_hidden) < 1f-6
            return
        end
        
        # Use the stored latent state instead of belief state
        latent = brain.last_hidden
        pred = forward_pass(brain.predictor_network,    latent)
        @assert length(pred) == length(encode_perception(brain.memory.episodic[end]["perception"])) "Predictor output must match perception space"

        # Now comparing in correct sensory space
        drift = mean(abs.(pred - encode_perception(brain.memory.episodic[end]["perception"])))

        if drift > 0.3
            brain.memory.emotional_state["arousal"] += 0.2
            brain.memory.drives["curiosity"] += 0.1
            brain.memory.drives["creativity"] += 0.1  # High drift creativity
            @warn "Value drift detected! Cognitive recalibration triggered (drift:$(round(drift,    digits=4)))"
        end
    end
end

function dream!(brain::Brain)
    if length(brain.memory.episodic) < 10
        return 0.0f0
    end
    
    batch_size = min(length(brain.memory.episodic),    32)
    samples = brain.memory.episodic[shuffle(1:length(brain.memory.episodic))[1:batch_size]]
    
    total_prediction_error = 0.0f0
    
    for experience in samples
        state_t = encode_perception(experience["perception"])
        state_t_plus_1 = encode_perception(experience["next_perception"])
        # Fix dream input to avoid temporal leakage - use self-contained state
        dream_input = vcat(state_t .- state_t,    zeros(Float32,    length(brain.context_state)))
        
        h1 = forward_pass(brain.layers[1],    dream_input)
        h2 = forward_pass(brain.layers[2],    h1)
        prediction = forward_pass(brain.predictor_network,    h2)
        @assert length(prediction) == length(state_t_plus_1) "Predictor output must match perception space"
        error = prediction - state_t_plus_1
        loss = sum(error .^ 2)
        total_prediction_error += loss
        # Fix backprop - use outer product instead of element-wise multiplication
        grad = -2.0f0 .* clamp.(error * h2', -1f0, 1f0)
        brain.predictor_network.weights .+= (brain.learning_rate * 0.5f0) .* grad
    end
    
    avg_error = total_prediction_error / Float32(batch_size)
    @info "Dream cycle complete. World Model Error:$(round(avg_error,    digits=4))"
    
    update_drives!(brain,    avg_error)
    brain.memory.drives["creativity"] *= exp(-0.1f0 * avg_error)
    
    return avg_error
end

function reflect(brain::Brain)::Dict{String,    Any}
    if isempty(brain.memory.episodic)
        # Fix return contract to be consistent
        return Dict(
            "avg_reward" => 0.0,    
            "avg_confidence" => 0.5,    
            "action_distribution" => Dict(),    
            "emotional_trend" => 0.0,    
            "experience_count" => 0,    
            "learning_stable" => true
        )
    end
    
    recent = brain.memory.episodic[max(1,    end-99):end]
    avg_reward = mean([Float32(get(e["outcome"],    "reward",    0.0)) for e in recent])
    avg_confidence = mean([Float32(get(e["thought"],    "confidence",    0.5)) for e in recent])
    
    action_counts = Dict{String,    Int}()
    for e in recent
        action = get(e["thought"],    "action",    "unknown")
        if isa(action,    String)
            action_counts[action] = get(action_counts,    action,    0) + 1
        end
    end
    
    emotional_trend = brain.memory.emotional_state["valence"]
    
    return Dict{String,    Any}(
        "avg_reward" => Float64(avg_reward),    
        "avg_confidence" => Float64(avg_confidence),    
        "action_distribution" => action_counts,    
        "emotional_trend" => Float64(emotional_trend),    
        "experience_count" => length(recent),    
        "learning_stable" => abs(avg_reward) < 1.0
    )
end

function create_perception_boundary(enable_zmq::Bool=false,    
                                   endpoint::String="tcp://127.0.0.1:5566")::PerceptionBoundary
    if enable_zmq
        ctx = Context()
        sock = Socket(ctx,    SUB)
        connect(sock,    endpoint)
        setsockopt(sock,    SUBSCRIBE,    "ITHERIS_STREAM")
        @info "Perception boundary connected to $endpoint"
        return PerceptionBoundary(true,    ctx,    sock,    endpoint)
    else
        @info "Perception boundary using internal sensors only"
        return PerceptionBoundary(false,    nothing,    nothing,    endpoint)
    end
end

function perceive_environment(boundary::PerceptionBoundary)::Dict{String,    Any}
    context = Dict{String,    Any}()
    
    try
        total_mem = Sys.total_memory()
        free_mem = Sys.free_memory()
        context["memory_usage"] = 1.0 - (free_mem / total_mem)
    catch
        context["memory_usage"] = 0.5
    end
    
    context["cpu_load"] = rand(0.15:0.01:0.95)
    context["disk_io"] = rand(0.1:0.01:0.6)
    context["network_latency"] = rand(10.0:1.0:200.0)
    context["file_count"] = length(readdir("."))
    context["process_count"] = 100
    context["threats"] = []
    
    severity = (context["cpu_load"] + context["memory_usage"] + context["disk_io"]) / 3
    context["overall_severity"] = severity
    
    if boundary.zmq_enabled && boundary.zmq_socket !== nothing
        try
            if ZMQ.poll([ZMQ.PollItem(boundary.zmq_socket,    ZMQ.POLLIN)],    10) != 0
                topic,    payload_raw = recv_multipart(boundary.zmq_socket)
                external_data = JSON.parse(String(payload_raw))
                
                if haskey(external_data,    "payload")
                    merge!(context,    external_data["payload"])
                end
            end
        catch e
            @warn "Failed to read external sensors" exception=e
        end
    end
    
    context["timestamp"] = now()
    context["source"] = boundary.zmq_enabled ? "hybrid" : "internal"
    
    return context
end

function create_action_boundary(enable_zmq::Bool=false,    
                               endpoint::String="tcp://127.0.0.1:5567")::ActionBoundary
    if enable_zmq
        ctx = Context()
        sock = Socket(ctx,    PUB)
        bind(sock,    endpoint)
        sleep(0.1)
        @info "Action boundary broadcasting on $endpoint"
        return ActionBoundary(true,    ctx,    sock,    endpoint)
    else
        @info "Action boundary running local-only"
        return ActionBoundary(false,    nothing,    nothing,    endpoint)
    end
end

function emit_action_intent(boundary::ActionBoundary,    thought::Dict{String,    Any})
    intent = Dict{String,    Any}(
        "sender" => "ITHERIS_BRAIN",    
        "type" => "INTENT",    
        "action" => get(thought,    "action",    "unknown"),    
        "confidence" => Float64(get(thought,    "confidence",    0.0)),    
        "value_estimate" => Float64(get(thought,    "value_estimate",    0.0)),    
        "emotional_state" => get(thought,    "emotional_state",    Dict()),    
        "context_hash" => get(thought,    "perception_hash",    ""),    
        "cycle" => get(thought,    "cycle",    0),    
        "timestamp" => string(now())
    )
    
    if boundary.zmq_enabled && boundary.zmq_socket !== nothing
        try
            send_multipart(boundary.zmq_socket,    [
                Vector{UInt8}("BRAIN_INTENT"),    
                Vector{UInt8}(JSON.json(intent))
            ])
        catch e
            @warn "Failed to emit intent over ZMQ" exception=e
        end
    end
    
    @info "Intent: $(get(thought,    "action",    "unknown")) | Confidence: $(round(Float64(get(thought,    "confidence",    0.0)),    digits=3))"
end

function evaluate_action(context::Dict{String,Any},    
                        action::String,    
                        thought::Dict{String,Any})::Dict{String,Any}
    severity = Float32(get(context,    "overall_severity",    0.0))
    reward = 0.0f0
    
    if action == "monitor"
        reward = severity < 0.5 ? 0.1f0 : -0.1f0
    elseif action == "optimize"
        reward = severity > 0.5 && severity < 0.8 ? 0.5f0 : 0.0f0
    elseif action == "alert"
        reward = severity > 0.7 ? 0.3f0 : -0.2f0
    elseif action == "mitigate"
        reward = severity > 0.8 ? 0.8f0 : -0.5f0
    end
    
    confidence = Float32(get(thought,    "confidence",    0.5))
    if confidence < 0.5
        reward *= 0.5f0
    end
    
    return Dict{String,    Any}(
        "reward" => Float64(reward),    
        "success" => reward > 0,    
        "next_severity" => Float64(max(0.0,    severity - (reward * 0.1))),    
        "next_value" => 0.0,    
        "timestamp" => now()
    )
end

function counterfactual_infer(brain::Brain,    perception::Dict{String,Any})
    original = infer(brain,    perception)

    # Save state before mutation for counterfactual integrity
    saved_context = copy(brain.context_state)
    saved_belief = copy(brain.belief_state)
    saved_emotion = copy(brain.memory.emotional_state)

    brain.memory.emotional_state["confidence"] *= 0.8f0
    alt = infer(brain,    perception)

    # Restore state after second inference to maintain cognitive integrity
    brain.context_state .= saved_context
    brain.belief_state .= saved_belief
    brain.memory.emotional_state = saved_emotion

    return Float32(get(original,    "confidence", 0.0)) > Float32(get(alt,    "confidence",  0.0)) ? original : alt
end

function run_itheris_brain(enable_zmq::Bool=false,    cycles::Int=1000)
    println("\n" * "="^60)
    println("  ITHERIS v11 - PURE COGNITIVE CORE")
    println("  ZMQ Boundaries: $(enable_zmq ? "ENABLED" : "DISABLED")")
    println("="^60 * "\n")

    brain = initialize_brain()
    perception_boundary = create_perception_boundary(enable_zmq)
    action_boundary = create_action_boundary(enable_zmq)
    
    println("Brain initialized. Starting cognitive loop...\n")
    
    try
        for cycle in 1:cycles
            brain.cycle_count = cycle
            
            if brain.memory.drives["boredom"] > 0.7
                brain.memory.emotional_state["arousal"] = 1.0f0
            end
            
            sanity_gate!(brain)
            perception = perceive_environment(perception_boundary)
            
            # NEW:    Creative imagination phase
            if cycle % 15 == 0
                imagine_scenarios!(brain,    perception)
            end
            
            if cycle % 20 == 0
                spawn_obsession!(brain)
            end

            for obs in brain.memory.obsessions
                generate_sub_obsessions!(obs)
            end

            for obs in brain.memory.obsessions
                generate_plan!(brain,    obs,    perception)
                
                for sub_obs in obs.sub_obsessions
                    generate_plan!(brain,    sub_obs,    perception)
                end
            end

            thought = counterfactual_infer(brain,    perception)
            
            evaluate_obsessions!(brain)
            generate_meta_goals!(brain)
            bias_obsessions_with_drives!(brain)
            
            # NEW:    Enhance planning with imagination
            enhance_planning_with_imagination!(brain)
            
            plan_action = select_action_meta!(brain,    perception)
            if plan_action !== nothing
                thought["action"] = plan_action
                thought["confidence"] = min(Float32(get(thought,    "confidence",    0.5)) + 0.2f0,    1.0f0)
            end
            
            assimilate_thought!(brain,    thought)
            
            thought_with_emotion = merge(thought,    Dict("emotional_state" => copy(brain.memory.emotional_state)))
            emit_action_intent(action_boundary,    thought_with_emotion)
            
            sleep(0.01)
            next_perception = perceive_environment(perception_boundary)
            
            outcome = evaluate_action(perception,    string(get(thought,    "action",    "monitor")),    thought)
            
            learn_from_experience!(brain,    perception,    next_perception,    thought,    outcome)
            
            adapt_plans_hierarchical!(brain,    perception,    outcome)
            adapt_meta_goals!(brain,    outcome)
            
            update_identity!(brain,    Float32(get(outcome,    "reward",    0.0f0)))
            update_narrative!(brain)
            check_value_drift!(brain)
            
            if cycle % 50 == 0
                for layer in brain.layers
                    decay_weights!(layer)
                end
                decay_weights!(brain.value_network)
                decay_weights!(brain.policy_network)
                decay_weights!(brain.predictor_network)
            end
            
            if cycle % 100 == 0
                println("\n--- Entering REM Sleep (Dreaming) ---")
                update_narrative!(brain)
                dream_error = dream!(brain)
                insights = reflect(brain)

                evaluate_obsessions!(brain)
                generate_meta_goals!(brain)
                bias_obsessions_with_drives!(brain)

                evaluate_self_modification!(brain)
                
                println("\n" * "="^60)
                println("Reflection (Cycle $cycle)")
                println("="^60)
                println("Avg Reward:$(round(Float64(get(insights,    "avg_reward",    0.0)),    digits=3))")
                println("Avg Confidence: $(round(Float64(get(insights,    "avg_confidence",    0.0)),    digits=3))")
                println("Emotional Trend: $(round(Float64(get(insights,    "emotional_trend",    0.0)),    digits=3))")
                println("Action Distribution: $(get(insights,    "action_distribution",    Dict()))")
                println("World Model Accuracy (Error):$(round(Float64(dream_error),    digits=4))")
                println("Drives: $(brain.memory.drives)")
                println("Identity: competence=$(round(brain.self_model.competence,    digits=3)),    traits=$(brain.self_model.traits)")
                println("Self-Modification:")
                println("  Learning Rate: $(round(brain.learning_rate,    digits=4))")
                println("  Gamma:$(round(brain.gamma,    digits=3))")
                println("  Drive Weights: $(brain.memory.self_mod.drive_weights)")
                println("  Layer Scaling: $(brain.memory.self_mod.layer_scaling)")
                if !isempty(brain.memory.narrative)
                    println("Recent Narrative: $(brain.memory.narrative[end])")
                end
                if !isempty(brain.memory.obsessions)
                    println("Current Obsessions: $(length(brain.memory.obsessions))")
                    for obs in brain.memory.obsessions
                        println("  - $(obs.target) (intensity:$(round(obs.intensity,    digits=2)),    horizon: $(obs.horizon))")
                        if !isempty(obs.sub_obsessions)
                            println("    Sub-obsessions: $(length(obs.sub_obsessions))")
                        end
                    end
                end
                if !isempty(brain.memory.plans)
                    println("Active Plans: $(length(brain.memory.plans))")
                end
                if !isempty(brain.memory.meta_goals)
                    println("Meta-Goals: $(length(brain.memory.meta_goals))")
                    for meta in brain.memory.meta_goals
                        println("  - $(meta.target) (priority:$(round(meta.priority,    digits=2)),    confidence: $(round(meta.confidence,    digits=2)))")
                    end
                end
                if !isempty(brain.memory.imaginary_experiences)
                    println("Imaginary Experiences: $(length(brain.memory.imaginary_experiences))")
                end
                println("="^60 * "\n")
            end
            
            sleep(0.1)
        end
        
    catch e
        if isa(e,    InterruptException)
            println("\n\nInterrupt received")
        else
            @error "Error in cognitive loop" exception=e
        end
    finally
        if perception_boundary.zmq_enabled && perception_boundary.zmq_socket !== nothing
            close(perception_boundary.zmq_socket)
            close(perception_boundary.zmq_context)
        end
        
        if action_boundary.zmq_enabled && action_boundary.zmq_socket !== nothing
            close(action_boundary.zmq_socket)
            close(action_boundary.zmq_context)
        end
        
        println("\nBrain shutdown complete")
        
        final_insights = reflect(brain)
        println("\nFinal State: ")
        println("  Total Experiences: $(length(brain.memory.episodic))")
        println("  Final Emotional State: $(brain.memory.emotional_state)")
        println("  Final Drives: $(brain.memory.drives)")
        println("  Final Identity: competence=$(round(brain.self_model.competence,    digits=3)),    traits=$(brain.self_model.traits)")
        println("  Learning Stable: $(get(final_insights,    "learning_stable",    true))")
        if !isempty(brain.memory.narrative)
            println("  Final Narrative Entries: $(length(brain.memory.narrative))")
        end
        if !isempty(brain.memory.obsessions)
            println("  Active Obsessions: $(length(brain.memory.obsessions))")
        end
        if !isempty(brain.memory.plans)
            println("  Active Plans:$(length(brain.memory.plans))")
        end
        if !isempty(brain.memory.meta_goals)
            println("  Active Meta-Goals:$(length(brain.memory.meta_goals))")
        end
        if !isempty(brain.memory.imaginary_experiences)
            println("  Imaginary Experiences: $(length(brain.memory.imaginary_experiences))")
        end
        println("  Self-Modification Status: ")
        println("    Learning Rate: $(round(brain.learning_rate,    digits=4))")
        println("Gamma: $(round(brain.gamma,    digits=3))")
        println("    Drive Weights: $(brain.memory.self_mod.drive_weights)")
        println("    Layer Scaling: $(brain.memory.self_mod.layer_scaling)")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    enable_zmq = parse(Bool,    get(ENV,    "ITHERIS_ZMQ",    "false"))
    cycles = parse(Int,    get(ENV,    "ITHERIS_CYCLES",    "1000"))
    run_itheris_brain(enable_zmq,    cycles)
end

function sanity_gate!(brain::Brain)
    if brain.memory.emotional_state["arousal"] > 0.9
        brain.memory.drives["creativity"] *= 0.7
        brain.memory.drives["curiosity"] *= 0.8
    end
end

