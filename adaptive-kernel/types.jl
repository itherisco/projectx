# types.jl - Shared type definitions for Adaptive Kernel and ITHERIS
# This file consolidates common structs used across the system

module SharedTypes

using Dates

export ActionProposal, Goal, Thought

# ============================================================================
# Action Proposal - Consolidated definition
# ============================================================================

"""
    ActionProposal represents a selected action with metadata for decision making.
"""
struct ActionProposal
    capability_id::String
    confidence::Float32
    predicted_cost::Float32
    predicted_reward::Float32
    risk::String
    reasoning::String
end

# Constructor for backward compatibility
function ActionProposal(
    cap_id::String, 
    conf::Float32, 
    cost::Float32, 
    reward::Float32, 
    risk::String, 
    reason::String
)
    return ActionProposal(cap_id, conf, cost, reward, risk, reason)
end

# ============================================================================
# Goal - Represents an objective for the kernel
# ============================================================================

struct Goal
    id::String
    description::String
    priority::Float32  # [0, 1]
    created_at::DateTime
end

# ============================================================================
# Thought - Represents ITHERIS cognitive output
# ============================================================================

struct Thought
    action::Int
    probs::Vector{Float32}
    value::Float32
    uncertainty::Float32
    context_vector::Vector{Float32}
end

end # module SharedTypes
