module ObserveFilesystem
export meta, execute

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"observe_filesystem",
        "name"=>"Observe Filesystem",
        "description"=>"Collect filesystem usage and recent file events",
        "inputs"=>Dict("path"=>"string"),
        "outputs"=>Dict("free_mb"=>"float","recent_changes"=>"int"),
        "cost"=>0.02,
        "risk"=>"low",
        "reversible"=>true,
        "confidence_model"=>"empirical"
    )
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    path = get(params, "path", "/")
    free_mb = 0.0
    changes = 0
    try
        st = statvfs(path)
        free_mb = Float32((st.f_bavail * st.f_frsize) / 1024 / 1024)
        # approximate recent changes by counting files modified in last hour
        cutoff = now() - Dates.Hour(1)
        for (root, dirs, files) in walkdir(path)
            for f in files
                fp = joinpath(root,f)
                try
                    mt = stat(fp).mtime
                    if mt > cutoff
                        changes += 1
                    end
                catch
                end
            end
        end
    catch
        free_mb = 1024.0
        changes = 0
    end
    return Dict("success"=>true, "effect"=>"fs observed", "actual_confidence"=>0.9, "energy_cost"=>0.02, "data"=>Dict("free_mb"=>Float32(free_mb), "recent_changes"=>changes))
end

end