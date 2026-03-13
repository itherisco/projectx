module CompareStrategies
export meta, execute

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"compare_strategies",
        "name"=>"Compare Strategies",
        "description"=>"Compare two plans and return a preference score",
        "inputs"=>Dict("plan_a"=>"array","plan_b"=>"array"),
        "outputs"=>Dict("preferred"=>"string","score_diff"=>"float"),
        "cost"=>0.03,
        "risk"=>"low",
        "reversible"=>true,
        "confidence_model"=>"rule_based"
    )
end

function evaluate_plan_simple(plan)
    # simple evaluation: reward - cost
    r = 0.0
    c = 0.0
    for s in plan
        c += 0.05
        r += 0.9 - 0.05
    end
    return r - c
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    a = get(params, "plan_a", String[])
    b = get(params, "plan_b", String[])
    sa = evaluate_plan_simple(a)
    sb = evaluate_plan_simple(b)
    pref = sa >= sb ? "a" : "b"
    return Dict("success"=>true, "effect"=>"compared", "actual_confidence"=>0.8, "energy_cost"=>0.03, "data"=>Dict("preferred"=>pref, "score_diff"=>abs(sa-sb)))
end

end