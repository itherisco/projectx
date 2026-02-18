module GitReadonly
export meta, execute

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"git_readonly",
        "name"=>"Git Readonly",
        "description"=>"Read contents of a git repo (no network writes)",
        "inputs"=>Dict("repo_path"=>"string","ref"=>"string"),
        "outputs"=>Dict("files"=>"array"),
        "cost"=>0.04,
        "risk"=>"medium",
        "reversible"=>true,
        "confidence_model"=>"empirical"
    )
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    repo = get(params, "repo_path", ".")
    ref = get(params, "ref", "HEAD")
    files = String[]
    try
        out = read(`git -C $repo ls-tree -r --name-only $ref`, String)
        files = split(strip(out), '\n')
    catch
    end
    return Dict("success"=>true, "effect"=>"git listed", "actual_confidence"=>0.85, "energy_cost"=>0.04, "data"=>Dict("files"=>files))
end

end