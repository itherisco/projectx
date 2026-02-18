module ObserveNetwork
export meta, execute

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"observe_network",
        "name"=>"Observe Network",
        "description"=>"Collect simple network stats (connectivity, latency)",
        "inputs"=>Dict("host"=>"string"),
        "outputs"=>Dict("rtt_ms"=>"float","reachable"=>"bool"),
        "cost"=>0.02,
        "risk"=>"low",
        "reversible"=>true,
        "confidence_model"=>"empirical"
    )
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    host = get(params, "host", "8.8.8.8")
    rtt = 0.0
    reachable = false
    try
        # perform a single ICMP ping via system ping if available
        cmd = `ping -c 1 -W 1 $host`
        out = read(cmd, String)
        m = match(r"time=(\d+\.\d+) ms", out)
        if m !== nothing
            rtt = parse(Float32, m.captures[1])
            reachable = true
        end
    catch
        reachable = false
        rtt = 0.0
    end
    return Dict("success"=>true, "effect"=>"net observed", "actual_confidence"=>0.85, "energy_cost"=>0.02, "data"=>Dict("rtt_ms"=>rtt, "reachable"=>reachable))
end

end