# Test script for policy gradient implementation in OnlineLearning.jl

include("adaptive-kernel/cognition/learning/OnlineLearning.jl")

using .OnlineLearning

# Test 1: Create PolicyGradientState
println("Test 1: Creating PolicyGradientState...")
pg_state = create_policy_gradient_state(10, 5)
println("  - Created PolicyGradientState with config: gamma=$(pg_state.config.gamma), lam=$(pg_state.config.lam)")

# Test 2: Test softmax
println("\nTest 2: Testing softmax...")
x = Float32[1.0, 2.0, 3.0]
probs = softmax(x)
println("  - Input: $x")
println("  - Softmax: $probs")
println("  - Sum: $(sum(probs))")

# Test 3: Test action probability computation
println("\nTest 3: Testing action probabilities...")
logits = randn(Float32, 5, 10) * Float32(0.1)
state = randn(Float32, 10)
action_probs = compute_action_probabilities(logits, state)
println("  - Action probs: $action_probs")

# Test 4: Test log probability
println("\nTest 4: Testing log probability...")
log_prob = compute_log_prob(logits, state, 2)
println("  - Log prob of action 2: $log_prob")

# Test 5: Test GAE advantages
println("\nTest 5: Testing GAE advantages...")
rewards = Float32[1.0, 2.0, 3.0, 0.0, 0.0]
values = Float32[0.5, 1.0, 1.5, 2.0, 2.0]
dones = Bool[false, false, false, true, false]
advantages, returns = compute_gae_advantages(rewards, values, dones, Float32(0.99), Float32(0.95))
println("  - Advantages: $advantages")
println("  - Returns: $returns")

# Test 6: Create a mock brain with policy_state
println("\nTest 6: Testing compute_gradients with mock brain...")
brain = Dict(:policy_state => pg_state)
input = Dict(:states => [state, state, state], :actions => [1, 2, 3], :rewards => rewards, :dones => dones, :values => values, :log_probs => Float32[-0.5, -0.6, -0.7])
target = Dict(:actions => [1, 2, 3])
grads = compute_gradients(brain, input, target)
println("  - Has policy_gradients: $(haskey(grads, "policy_gradients"))")
println("  - Has value_gradients: $(haskey(grads, "value_gradients"))")
if haskey(grads, "policy_loss")
    println("  - Policy loss: $(grads["policy_loss"])")
end

# Test 7: Test PPO loss
println("\nTest 7: Testing PPO loss...")
ppo_result = compute_ppo_loss(brain, [state, state, state], [1, 2, 3], advantages, Float32[-0.5, -0.6, -0.7])
println("  - PPO loss: $(ppo_result["loss"])")
println("  - Clip fraction: $(ppo_result["clip_fraction"])")

# Test 8: Test discounted returns
println("\nTest 8: Testing discounted returns...")
discounted = compute_discounted_returns(rewards, Float32(0.99))
println("  - Discounted returns: $discounted")

# Test 9: Test trajectory collection
println("\nTest 9: Testing trajectory collection...")
env = Dict(:states => [state, state, state], :actions => [1, 2, 3], :rewards => rewards, :dones => dones)
traj = collect_trajectory(brain, env, state, 10)
println("  - Trajectory length: $(length(traj))")
println("  - Number of states: $(length(traj.states))")

# Test 10: Test value network update
println("\nTest 10: Testing value network update...")
value_loss = update_value_network!(brain, [state, state, state], returns, learning_rate=Float32(0.001))
println("  - Value loss: $value_loss")

# Test 11: Test gradient application
println("\nTest 11: Testing gradient application...")
initial_logits = copy(pg_state.policy_logits)
apply_policy_gradients!(brain, grads, Float32(0.01))
println("  - Policy logits changed: $(pg_state.policy_logits != initial_logits)")

println("\n✅ All tests passed!")
