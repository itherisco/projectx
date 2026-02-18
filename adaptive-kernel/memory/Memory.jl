module Memory

export MemoryStore, ingest_episode!, compress_memory!, failure_catalog, get_adjustments, decay_memory!

using Dates, JSON

mutable struct MemoryStore
    episodes::Vector{Dict{String,Any}}
    failures::Vector{Dict{String,Any}}
    capability_stats::Dict{String, Dict{String,Any}}  # success_count, fail_count, avg_error
    last_compaction::DateTime
    MemoryStore() = new(Dict{String,Any}[], Dict{String,Any}[], Dict{String, Dict{String,Any}}(), now())
end

function ingest_episode!(ms::MemoryStore, episode::Dict{String,Any})
    push!(ms.episodes, episode)
    # update capability stats
    aid = get(episode, "action_id", "unknown")
    stats = get(ms.capability_stats, aid, Dict("success" => 0, "fail" => 0, "sum_error" => 0.0, "count" => 0))
    if get(episode, "result", false)
        stats["success"] = stats["success"] + 1
    else
        stats["fail"] = stats["fail"] + 1
        push!(ms.failures, Dict("action" => aid, "cycle" => episode["cycle"], "context" => get(episode, "context", Dict())))
    end
    pe = Float64(get(episode, "prediction_error", 0.0))
    stats["sum_error"] = stats["sum_error"] + pe
    stats["count"] = stats["count"] + 1
    ms.capability_stats[aid] = stats
end

function failure_catalog(ms::MemoryStore)
    return ms.failures
end

"""
compress_memory!(ms; window=10)
Compress repeated episodes into summaries, e.g., coalesce identical successive actions.
"""
function compress_memory!(ms::MemoryStore; window::Int=10)
    if length(ms.episodes) < window
        return
    end
    out = Dict{String,Any}[]
    i = 1
    while i <= length(ms.episodes)
        e = ms.episodes[i]
        j = i+1
        count = 1
        while j <= length(ms.episodes) && ms.episodes[j]["action_id"] == e["action_id"]
            count += 1
            j += 1
        end
        if count > 1
            push!(out, Dict("action_id" => e["action_id"], "runs" => count, "last_cycle" => ms.episodes[j-1]["cycle"]))
        else
            push!(out, e)
        end
        i = j
    end
    ms.episodes = out
    ms.last_compaction = now()
end

"""
get_adjustments(ms, capability_ids)
Return multipliers for planning based on observed statistics.
"""
function get_adjustments(ms::MemoryStore, capability_ids::Vector{String})
    # default multipliers
    cost_mul = 1.0f0
    reward_mul = 1.0f0
    unc_off = 0.0f0
    for id in capability_ids
        stats = get(ms.capability_stats, id, nothing)
        if stats !== nothing && stats["count"] > 0
            avg_err = stats["sum_error"]/stats["count"]
            # If high error, reduce expected reward and increase uncertainty
            if avg_err > 0.5
                reward_mul *= 0.8f0
                unc_off += 0.1f0
            elseif avg_err < 0.1
                reward_mul *= 1.05f0
                unc_off -= 0.02f0
            end
            # If many failures, increase cost multiplier
            if stats["fail"] > stats["success"]
                cost_mul *= 1.2f0
            end
        end
    end
    return Dict(:cost_multiplier => Float32(cost_mul), :reward_multiplier => Float32(reward_mul), :uncertainty_offset => Float32(unc_off))
end

"""
decay_memory!(ms; half_life_cycles=100)
Apply forgetting pressure by decaying counts.
"""
function decay_memory!(ms::MemoryStore; half_life_cycles::Int=100)
    for (k,v) in ms.capability_stats
        v["success"] = max(0, Int(floor(v["success"] * 0.995)))
        v["fail"] = max(0, Int(floor(v["fail"] * 0.995)))
        v["sum_error"] = v["sum_error"] * 0.995
        v["count"] = max(1, Int(floor(v["count"] * 0.995)))
        ms.capability_stats[k] = v
    end
end

end # module
