module SummarizeState
export meta, execute

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"summarize_state",
        "name"=>"Summarize State",
        "description"=>"Produce concise summary of world + self state",
        "inputs"=>Dict("world"=>"dict","self_metrics"=>"dict"),
        "outputs"=>Dict("summary"=>"string"),
        "cost"=>0.02,
        "risk"=>"low",
        "reversible"=>true,
        "confidence_model"=>"rule_based"
    )
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    world = get(params, "world", Dict())
    selfm = get(params, "self_metrics", Dict())
    summary = "State summary: " * join([string(k)*":"*string(v) for (k,v) in world], ", ")
    summary *= " | Self: " * join([string(k)*":"*string(v) for (k,v) in selfm], ", ")
    return Dict("success"=>true, "effect"=>"summarized", "actual_confidence"=>0.9, "energy_cost"=>0.02, "data"=>Dict("summary"=>summary))
end

end