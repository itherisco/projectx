module FileDiff
export meta, execute

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"file_diff",
        "name"=>"File Diff",
        "description"=>"Compute simple line diff between two sandbox files",
        "inputs"=>Dict("a"=>"string","b"=>"string"),
        "outputs"=>Dict("diff_lines"=>"int","summary"=>"string"),
        "cost"=>0.02,
        "risk"=>"low",
        "reversible"=>true,
        "confidence_model"=>"deterministic"
    )
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    a = get(params, "a", "sandbox/output.txt")
    b = get(params, "b", "sandbox/output.txt")
    la = isfile(a) ? readlines(a) : String[]
    lb = isfile(b) ? readlines(b) : String[]
    diff = 0
    for i in 1:max(length(la), length(lb))
        if i > length(la) || i > length(lb) || la[i] != lb[i]
            diff += 1
        end
    end
    summary = "diff_lines=$diff"
    return Dict("success"=>true, "effect"=>"diffed", "actual_confidence"=>0.95, "energy_cost"=>0.02, "data"=>Dict("diff_lines"=>diff, "summary"=>summary))
end

end