module EstimateRisk
export meta, execute

function meta()::Dict{String,Any}
    return Dict("id"=>"estimate_risk","name"=>"Estimate Risk","description"=>"Estimate risk of given plan steps","inputs"=>Dict("plan_steps"=>"array"),"outputs"=>Dict("risk_score"=>"float","risk_level"=>"string"),"cost"=>0.02,"risk"=>"low","reversible"=>true,"confidence_model"=>"model_free")
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    steps = get(params, "plan_steps", String[])
    score = 0.0
    for s in steps
        if occursin("safe", s) || occursin("observe", s)
            score += 0.01
        elseif occursin("http", s) || occursin("git", s)
            score += 0.2
        else
            score += 0.05
        end
    end
    level = score > 0.3 ? "high" : (score > 0.1 ? "medium" : "low")
    return Dict("success"=>true, "effect"=>"risked", "actual_confidence"=>0.8, "energy_cost"=>0.02, "data"=>Dict("risk_score"=>Float32(score), "risk_level"=>level))
end

end