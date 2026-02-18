module SimulateOutcomes
export meta, execute

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"simulate_outcomes",
        "name"=>"Simulate Outcomes",
        "description"=>"Given a candidate plan (sequence of capability ids), return predicted reward, cost, risk, uncertainty",
        "inputs"=>Dict("plan_steps"=>"array"),
        "outputs"=>Dict("predicted_reward"=>"float","predicted_cost"=>"float","predicted_risk"=>"string","uncertainty"=>"float"),
        "cost"=>0.05,
        "risk"=>"low",
        "reversible"=>true,
        "confidence_model"=>"model_free_sim"
    )
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    steps = get(params, "plan_steps", String[])
    # Heuristic simulation: reward = sum(1 - cost) ; risk = max risk; uncertainty = mean per-step uncertainty
    total_cost = 0.0
    uncertainties = Float32[]
    risk_order = Dict("low"=>1, "medium"=>2, "high"=>3)
    maxrisk = "low"
    for s in steps
        # try to read capability metadata file if present
        mpath = joinpath("capabilities", string(s*".jl"))
        # default heuristics
        c = 0.05
        r = "low"
        u = 0.2
        try
            # If capability is loaded in Main, query its meta
            if isdefined(Main, Symbol(camelcase(s)))
                mod = getfield(Main, Symbol(camelcase(s)))
                meta = mod.meta()
                c = Float32(get(meta, "cost", 0.05))
                r = get(meta, "risk", "low")
                u = Float32(get(meta, "uncertainty", 0.2))
            end
        catch
        end
        total_cost += c
        push!(uncertainties, u)
        if risk_order[r] > risk_order[maxrisk]
            maxrisk = r
        end
    end
    predicted_reward = Float32(max(0.0, length(steps) * 0.9 - total_cost))
    predicted_cost = Float32(total_cost)
    uncertainty = mean(uncertainties)
    return Dict("success"=>true, "effect"=>"simulated", "actual_confidence"=>0.8, "energy_cost"=>0.05, "data"=>Dict("predicted_reward"=>predicted_reward, "predicted_cost"=>predicted_cost, "predicted_risk"=>maxrisk, "uncertainty"=>uncertainty))
end

# helper
function camelcase(s::String)
    parts = split(s, "_")
    return join([uppercase(first(p)) * lowercase(p[2:end]) for p in parts])
end

end