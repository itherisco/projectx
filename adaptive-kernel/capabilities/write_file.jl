# capabilities/write_file.jl - Write to sandbox
# FAIL-CLOSED: Requires Rust kernel approval before file writes

module WriteFile

export meta, execute

# Import RustIPC for fail-closed brain availability check
using ..RustIPC

function meta()::Dict{String, Any}
    return Dict(
        "id" => "write_file",
        "name" => "Write File",
        "description" => "Write data to a sandbox file (sandbox/output.txt)",
        "inputs" => Dict("content" => "string"),
        "outputs" => Dict("success" => "bool", "file_path" => "string"),
        "cost" => 0.08,
        "risk" => "medium",
        "reversible" => false
    )
end

function execute(params::Dict)::Dict{String, Any}
    # MANDATORY: Fail-closed - require Warden approval before any file write
    require_rust_brain("write_file")
    
    content = get(params, "content", "Logged output")
    
    # Safety: all writes confined to sandbox/
    sandbox_dir = "sandbox"
    mkpath(sandbox_dir)
    file_path = joinpath(sandbox_dir, "output.txt")
    
    try
        open(file_path, "a") do io  # append-only
            println(io, content)
        end
        
        return Dict(
            "success" => true,
            "effect" => "Wrote to $file_path",
            "actual_confidence" => 0.9,
            "energy_cost" => 0.08,
            "data" => Dict(
                "file_path" => file_path,
                "bytes_written" => length(content)
            )
        )
    catch e
        return Dict(
            "success" => false,
            "effect" => "Write failed: $(string(e))",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0
        )
    end
end

end  # module
