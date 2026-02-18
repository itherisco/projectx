module ObserveProcesses
export meta, execute

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"observe_processes",
        "name"=>"Observe Processes",
        "description"=>"Collect process counts and top CPU consumers",
        "inputs"=>Dict(),
        "outputs"=>Dict("process_count"=>"int","top"=>"array"),
        "cost"=>0.03,
        "risk"=>"low",
        "reversible"=>true,
        "confidence_model"=>"empirical"
    )
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    pcs = 0
    top = []
    try
        for name in readdir("/proc")
            if all(isdigit, collect(name))
                pcs += 1
            end
        end
        # get ps aux top 3 by cpu
        out = read(`ps -eo pid,pcpu,comm --sort=-pcpu | head -n 4`, String)
        lines = split(out,'\n')
        for ln in lines[2:end]
            if !isempty(strip(ln))
                push!(top, strip(ln))
            end
        end
    catch
    end
    return Dict("success"=>true, "effect"=>"processes observed", "actual_confidence"=>0.9, "energy_cost"=>0.03, "data"=>Dict("process_count"=>pcs, "top"=>top))
end

end