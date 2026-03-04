using Random, Flux, JSON, Dates, UUIDs, Statistics, Sockets, Logging
using LinearAlgebra, BSON, StatsBase
using Base.Threads

# ============================================================
# IPC MESSAGE (CONTRACT COMPLIANT)
# ============================================================

const IPC_VERSION = "1.0"

struct IPCMessage
    version::String
    msg_id::String
    timestamp::String
    sender::String
    type::String
    payload::Dict{String, Any}
end

function new_msg(sender, type, payload)
    IPCMessage(
        IPC_VERSION,
        string(uuid4()),
        string(now()),
        sender,
        type,
        payload
    )
end

# ============================================================
# CORE STRUCTURES
# ============================================================

mutable struct Memory
    embedding::Vector{Float32}
    timestamp::DateTime
    note::String
end

struct Transition
    state::Vector{Float32}
    action::Int
    reward::Float32
end

mutable struct Agent
    id::String
    age::Int
    energy::Dict{String, Float32}
    genes::Dict{String, Float32}
    brain::Chain
    buffer::Vector{Transition}
    knowledge::Dict{String, Any}
    opt::Flux.Optimise.AbstractOptimiser
    inbox_lock::SpinLock
end

mutable struct World
    cycle_count::Int
    agent::Agent
end

# ============================================================
# BRAIN
# ============================================================

function create_brain()
    Chain(
        Dense(18, 16, relu),
        Dense(16, 8, relu),
        Dense(8, 4),
        softmax
    )
end

function init_agent()
    Agent(
        string(uuid4()),
        0,
        Dict("available"=>50f0, "core"=>50f0, "memory"=>50f0),
        Dict(
            "resilience"=>rand(Float32),
            "innovation"=>rand(Float32),
            "strategy"=>rand(Float32),
            "intellect"=>rand(Float32)
        ),
        create_brain(),
        Transition[],
        Dict(
            "memories"=>Memory[],
            "inbox"=>Any[],
            "pending_transitions"=>Dict{String, Any}(),
            "world_tick"=>0
        ),
        Flux.Optimise.Adam(0.001f0),
        SpinLock()
    )
end

# ============================================================
# SAVE / LOAD
# ============================================================

function save_brain(agent::Agent, path="itheris_state.bson")
    BSON.@save path agent
end

function load_brain!(agent::Agent, path="itheris_state.bson")
    isfile(path) || return
    data = BSON.load(path)
    saved = data[:agent]
    agent.brain = saved.brain
    agent.opt = saved.opt
    agent.age = saved.age
    agent.energy = saved.energy
    agent.genes = saved.genes
    agent.buffer = saved.buffer
    agent.knowledge = saved.knowledge
end

# ============================================================
# IPC SEND
# ============================================================

function send_ipc(msg::IPCMessage; host="127.0.0.1", port=9003)
    try
        sock = connect(host, port)
        println(sock, JSON.json(Dict(
            "version"=>msg.version,
            "msg_id"=>msg.msg_id,
            "timestamp"=>msg.timestamp,
            "sender"=>msg.sender,
            "type"=>msg.type,
            "payload"=>msg.payload
        )))
        close(sock)
    catch
        @debug "IPC send failed"
    end
end

# ============================================================
# PERCEPTION
# ============================================================

function cosine_similarity(a::Vector{Float32}, b::Vector{Float32})
    dot(a, b) / (norm(a)*norm(b) + 1f-6)
end

function build_input(agent::Agent)
    vitals = Float32[
        agent.energy["available"]/100f0,
        min(agent.age/200f0, 1f0),
        agent.genes["intellect"],
        agent.genes["innovation"],
        agent.genes["strategy"],
        agent.energy["core"]/max(agent.energy["memory"], 1f0)
    ]

    mem_ctx = zeros(Float32, 12)
    mems = agent.knowledge["memories"]

    if !isempty(mems)
        sims = [cosine_similarity(vitals, m.embedding) for m in mems]
        idx = sortperm(sims, rev=true)[1:min(2, length(sims))]
        flat = vcat([mems[i].embedding for i in idx]...)
        mem_ctx[1:min(12, length(flat))] .= flat[1:min(12, length(flat))]
    end

    vcat(vitals, mem_ctx)
end

# ============================================================
# SAFETY GOVERNOR (LOCAL ONLY)
# ============================================================

function safety_governor(agent::Agent, action::Int)
    agent.energy["available"] > 1f0
end

# ============================================================
# LEARNING
# ============================================================

function update_brain!(agent::Agent, batch=32)
    length(agent.buffer) < batch && return
    idxs = sample(1:length(agent.buffer), batch, replace=false)
    batchset = agent.buffer[idxs]

    states = hcat([t.state for t in batchset]...)
    actions = [t.action for t in batchset]
    rewards = [t.reward for t in batchset]

    ps = Flux.params(agent.brain)
    grads = Flux.gradient(ps) do
        probs = agent.brain(states)
        loss = 0f0
        for i in 1:batch
            loss += -rewards[i]*log(probs[actions[i], i] + 1f-6)
        end
        loss / batch
    end

    Flux.Optimise.update!(agent.opt, ps, grads)
end

# ============================================================
# PROPOSAL
# ============================================================

function propose_action(agent, action, confidence)
    new_msg(
        "julia_cortex",
        "proposal",
        Dict(
            "agent_id"=>agent.id,
            "action"=>action,
            "confidence"=>confidence,
            "energy"=>agent.energy["available"],
            "world_tick"=>agent.knowledge["world_tick"]
        )
    )
end

# ============================================================
# INBOX PROCESSING (STRICT CONTRACT)
# ============================================================

function process_inbox!(agent::Agent)
    lock(agent.inbox_lock)
    try
        while !isempty(agent.knowledge["inbox"])
            msg = popfirst!(agent.knowledge["inbox"])
            t = msg["type"]
            payload = msg["payload"]

            if t == "verdict"
                pid = payload["proposal_id"]
                if haskey(agent.knowledge["pending_transitions"], pid)
                    tr = agent.knowledge["pending_transitions"][pid]
                    r = Float32(payload["reward"])
                    push!(agent.buffer, Transition(tr.state, tr.action, r))
                    delete!(agent.knowledge["pending_transitions"], pid)
                end

            elseif t == "world_state"
                agent.knowledge["world_tick"] = payload["world_tick"]

            elseif t == "command"
                @info "USER COMMAND" payload
            end
        end
    finally
        unlock(agent.inbox_lock)
    end
end

# ============================================================
# ASYNC LISTENER
# ============================================================

function start_listener(agent::Agent; port=9002)
    @async begin
        server = listen(port)
        while true
            sock = accept(server)
            @async begin
                try
                    line = readline(sock)
                    !isempty(line) && push!(agent.knowledge["inbox"], JSON.parse(line))
                catch
                end
                close(sock)
            end
        end
    end
end

# ============================================================
# SMART STEP
# ============================================================

function smart_step!(world::World; ε=0.1f0)
    agent = world.agent
    world.cycle_count += 1
    agent.energy["available"] = max(0f0, agent.energy["available"] - 0.1f0)

    input = build_input(agent)
    probs = agent.brain(input)

    action = rand() < ε ? rand(1:4) : argmax(probs)
    conf = probs[action]

    if !safety_governor(agent, action)
        push!(agent.buffer, Transition(input, action, -1f0))
        return
    end

    msg = propose_action(agent, action, conf)
    agent.knowledge["pending_transitions"][msg.msg_id] =
        (state=copy(input), action=action, time=now())

    send_ipc(msg)
    update_brain!(agent)

    for (k,v) in collect(agent.knowledge["pending_transitions"])
        now() - v.time > Second(30) && delete!(agent.knowledge["pending_transitions"], k)
    end

    push!(agent.knowledge["memories"], Memory(input[1:6], now(), "cycle"))
    length(agent.knowledge["memories"]) > 500 && deleteat!(agent.knowledge["memories"], 1)

    agent.age += 1
    world.cycle_count % 100 == 0 && save_brain(agent)
end

# ============================================================
# MAIN
# ============================================================

function main()
    println("🧠 ITHERIS JULIA CORTEX ONLINE")
    agent = init_agent()
    load_brain!(agent)
    world = World(0, agent)
    start_listener(agent)

    while true
        process_inbox!(agent)
        smart_step!(world)
        sleep(1.0)
    end
end

 main()
