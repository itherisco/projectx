module Planner

# Import HierarchicalPlanner for manager layer capabilities
include("HierarchicalPlanner.jl")
using .HierarchicalPlanner

export PlanProposal, propose_plans, score_plan,
       # Hierarchical planning types
       HierarchicalPlanner, Option, Mission, MissionExecution,
       # Hierarchical planning functions
       create_option, create_mission, promote_to_mission!, step_option!,
       select_mission, select_option, register_option!, has_active_mission,
       get_planner_stats, get_option_progress

using Dates
using Statistics

struct PlanProposal
    id::String
    steps::Vector{String}
    cumulative_cost::Float32
    cumulative_risk::String
    expected_reward::Float32
    uncertainty::Float32
    justification::String
end

# wrapper entrypoints using `invokelatest` to avoid world-age warnings
propose_plans(args...)=invokelatest(_propose_plans, args...)
score_plan(args...)=invokelatest(_score_plan, args...)

"""
propose_plans(capabilities::Vector{Dict}, memory_adjust::Function; min_steps=2, max_steps=5)
Generate candidate multi-step plans by combining capabilities.
This is a heuristic generator (combinatorial, limited breadth).
"""
function _propose_plans(capabilities::Vector{Dict{String,Any}}, memory_adjust::Function; min_steps::Int=2, max_steps::Int=4)
    plans = PlanProposal[]
    n = length(capabilities)
    # Simple breadth-limited combinations: pairwise and triplets
    ids = [get(c, "id", "unknown") for c in capabilities]
    idxs = collect(1:n)
    plan_id = 1
    for len in min_steps:max_steps
        # limit combinations to avoid explosion
        for i in 1:min(n, 8)
            selected = [ids[((i + j - 1) % n) + 1] for j in 0:len-1]
            # aggregate metadata
            costs = Float32[Float32(get(findcap(capabilities, s), "cost", 0.1)) for s in selected]
            risks = [get(findcap(capabilities, s), "risk", "low") for s in selected]
            rewards = Float32[get(findcap(capabilities, s), "estimated_reward", 1.0) for s in selected]
            uncertainties = Float32[get(findcap(capabilities, s), "uncertainty", 0.2) for s in selected]
            # memory_adjust can tweak estimates; be defensive about its return
            adj = memory_adjust(selected)
            if !(adj isa Dict)
                adj = Dict(:cost_multiplier=>1.0f0, :reward_multiplier=>1.0f0, :uncertainty_offset=>0.0f0)
            end
            cum_cost = sum(costs) * Float32(get(adj, :cost_multiplier, 1.0))
            cum_reward = sum(rewards) * Float32(get(adj, :reward_multiplier, 1.0))
            unc = mean(uncertainties) + Float32(get(adj, :uncertainty_offset, 0.0))
            # risk = max risk (defensive lookup)
            risk_levels = Dict("low" => 1, "medium" => 2, "high" => 3)
            idxs = [get(risk_levels, r, 1) for r in risks]
            maxrisk = argmax(idxs)
            cum_risk = risks[maxrisk]
            justification = "Plan of length $(len): $(join(selected, ", "))"
            push!(plans, PlanProposal("plan_$(plan_id)", selected, cum_cost, cum_risk, cum_reward, unc, justification))
            plan_id += 1
            if plan_id > 50
                break
            end
        end
        if plan_id > 50
            break
        end
    end
    return plans
end

function findcap(caps::Vector{Dict{String,Any}}, id::String)
    for c in caps
        if get(c, "id", "") == id
            return c
        end
    end
    return Dict{String,Any}()
end

"""
score_plan(plan::PlanProposal; cost_weight=1.0, risk_penalty=0.2)
Return a scalar score for ranking plans.
"""
function _score_plan(plan::PlanProposal; cost_weight::Float32=1.0f0, risk_penalty::Float32=0.2f0)
    risk_map = Dict("low" => 0.0f0, "medium" => 0.1f0, "high" => 0.3f0)
    rp = get(risk_map, plan.cumulative_risk, 0.1f0)
    score = plan.expected_reward - cost_weight * plan.cumulative_cost - (rp + plan.uncertainty * risk_penalty)
    return score
end

end # module
