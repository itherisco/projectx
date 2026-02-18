# capabilities/analyze_logs.jl - Parse and summarize logs

module AnalyzeLogs

export meta, execute

function meta()::Dict{String, Any}
    return Dict(
        "id" => "analyze_logs",
        "name" => "Analyze Logs",
        "description" => "Parse and summarize content from a provided log file",
        "inputs" => Dict("file_path" => "string"),
        "outputs" => Dict("lines" => "int", "keywords_found" => "int", "summary" => "string"),
        "cost" => 0.05,
        "risk" => "low",
        "reversible" => true
    )
end

function execute(params::Dict)::Dict{String, Any}
    file_path = get(params, "file_path", "events.log")
    
    # Safe: only read from events.log or sandbox
    if !occursin("events.log", file_path) && !occursin("sandbox", file_path)
        return Dict(
            "success" => false,
            "effect" => "File path restricted",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0
        )
    end
    
    # Deterministic log analysis: read file if present and compute keyword counts
    lines_count = 0
    keyword_count = 0
    keywords = ["error", "warning", "info", "debug"]

    if isfile(file_path)
        lines = readlines(file_path)
        lines_count = length(lines)
        for line in lines
            for kw in keywords
                if occursin(kw, lowercase(line))
                    keyword_count += 1
                end
            end
        end
    end
    
    return Dict(
        "success" => true,
        "effect" => "Log analyzed: $lines_count lines",
        "actual_confidence" => 0.9,
        "energy_cost" => 0.05,
        "data" => Dict(
            "lines" => lines_count,
            "keywords_found" => keyword_count,
            "summary" => "Processed $lines_count log entries"
        )
    )
end

end  # module
