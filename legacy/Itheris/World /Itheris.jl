# Itheris.jl - Neural-Spatial AI Agent System
# Fully upgraded version: Merges simulation, neuro-evolution, spatial grid, energy management, and logging

using JSON
using Random
using Dates
using Flux

# ============================================================================
# MODULE 1: AGENT DEFINITION
# ============================================================================

mutable struct Agent
    id::String
    genes::Dict{String, Float64}        # intellect, resilience, innovation, strategy
    energy::Dict{String, Float64}       # available, memory, archive, core
    thoughts::Dict{String, Float64}     # wisdom, creativity, strategy, philosophy
    status::String
    age::Int
    generation::Int
    x::Int                               # grid x position
    y::Int                               # grid y position
    brain::Chain                         # neural network for decision making
    knowledge::Dict{String,Any}          # local knowledge graph
end

# Helper: create neural brain
function create_brain(input_dim::Int=6, hidden_dim::Int=16, output_dim::Int=4)
    return Chain(
        Dense(input_dim, hidden_dim, relu),
        Dense(hidden_dim, hidden_dim, relu),
        Dense(hidden_dim, output_dim),
        softmax
    )
end

function create_agent(id::String; parent_genes=nothing, generation=1, grid_size=(10,10), parent_brain=nothing)
    # Genes
    genes = parent_genes === nothing ? Dict(
        "intellect"=>rand(0.1:0.01:1.0),
        "resilience"=>rand(0.1:0.01:1.0),
        "innovation"=>rand(0.1:0.01:1.0),
        "strategy"=>rand(0.1:0.01:1.0)
    ) : Dict(k=>clamp(parent_genes[k]+randn()*0.05,0.1,1.0) for k in keys(parent_genes))

    # Energy
    energy = Dict("available"=>100.0, "memory"=>50.0, "archive"=>0.0, "core"=>20.0)

    # Thoughts
    thoughts = Dict(
        "wisdom"=>genes["intellect"]*0.5,
        "creativity"=>genes["innovation"]*0.5,
        "strategy"=>genes["strategy"]*0.7,
        "philosophy"=>genes["strategy"]*0.3
    )

    # Position in grid
    x = rand(1:grid_size[1])
    y = rand(1:grid_size[2])

    # Brain
    brain = parent_brain === nothing ? create_brain() : copy_and_mutate_brain(parent_brain)

    knowledge = Dict{String,Any}()

    return Agent(id, genes, energy, thoughts, "primitive", 0, generation, x, y, brain, knowledge)
end

# ============================================================================
# MODULE 2: WORLD DEFINITION
# ============================================================================

mutable struct World
    agents::Dict{String, Agent}
    grid_size::Tuple{Int,Int}
    cycle_count::Int
    interaction_log::Vector{Dict{String,Any}}
    error_log::Vector{Dict{String,Any}}
    world_status::String
    library::Dict{String, Float64}  # global metrics
end

function create_world(initial_population::Int=10, grid_size=(10,10))
    agents = Dict{String,Agent}()
    for i in 1:initial_population
        id = "agent_$(uuid4())"
        agents[id] = create_agent(id, grid_size=grid_size)
    end

    library = Dict("knowledge"=>0.0,"confidence"=>0.5,"creativity"=>0.3,"novelty"=>0.1)
    return World(agents, grid_size, 0, [], [], "primitive", library)
end

# ============================================================================
# MODULE 3: ENERGY & AGENT ACTIONS
# ============================================================================

# Gain energy per cycle
function agent_gain_energy!(agent::Agent)
    gain = 5.0 + agent.genes["resilience"]*5.0
    agent.energy["available"] = min(agent.energy["available"]+gain,100.0)
end

# Agent decision using neural network
function agent_decide!(agent::Agent, world::World)
    # Input vector: Energy, Age, Genes, neighbor density
    neighbors = count_neighbors(agent, world)
    input_vec = [agent.energy["available"]/100,
                 agent.age/200,
                 agent.genes["intellect"],
                 agent.genes["innovation"],
                 agent.genes["strategy"],
                 neighbors/8]
    output = agent.brain(input_vec)
    choice = argmax(output)  # 1:think, 2:communicate,3:reproduce,4:move

    if choice==1
        agent_think!(agent, world)
    elseif choice==2
        neighbor = random_neighbor(agent, world)
        if neighbor!==nothing
            agent_communicate!(agent, neighbor, world)
        end
    elseif choice==3
        mate = random_neighbor(agent, world)
        if mate!==nothing
            agent_reproduce!(agent, mate, world)
        end
    elseif choice==4
        move_agent!(agent, world)
    end
end

# ============================================================================
# MODULE 4: SPATIAL / NEIGHBOR FUNCTIONS
# ============================================================================

function count_neighbors(agent::Agent, world::World)
    count=0
    for other in values(world.agents)
        if other.id!=agent.id && abs(other.x-agent.x)<=1 && abs(other.y-agent.y)<=1
            count+=1
        end
    end
    return count
end

function random_neighbor(agent::Agent, world::World)
    neighbors = [a for a in values(world.agents) if a.id!=agent.id && abs(a.x-agent.x)<=1 && abs(a.y-agent.y)<=1]
    return isempty(neighbors) ? nothing : rand(neighbors)
end

function move_agent!(agent::Agent, world::World)
    agent.x = clamp(agent.x+rand(-1:1),1,world.grid_size[1])
    agent.y = clamp(agent.y+rand(-1:1),1,world.grid_size[2])
    agent.energy["available"] -= 1.0
end

# ============================================================================
# MODULE 5: THINK / COMMUNICATE / REPRODUCE
# ============================================================================

function agent_think!(agent::Agent, world::World)
    agent.energy["available"] -= 2.0
    insight = agent.genes["intellect"]*agent.genes["innovation"]
    agent.thoughts["wisdom"] += insight*0.05
    world.library["knowledge"] += insight*0.1
end

function agent_communicate!(a1::Agent,a2::Agent,world::World)
    if a1.energy["available"]<3.0 || a2.energy["available"]<3.0
        return
    end
    a1.energy["available"]-=3.0
    a2.energy["available"]-=3.0

    # Merge local knowledge
    for (k,v) in a2.knowledge
        a1.knowledge[k] = v
    end
    for (k,v) in a1.knowledge
        a2.knowledge[k] = v
    end

    # Update thoughts
    avg_wisdom=(a1.thoughts["wisdom"]+a2.thoughts["wisdom"])/2
    a1.thoughts["wisdom"]=avg_wisdom
    a2.thoughts["wisdom"]=avg_wisdom

    push!(world.interaction_log, Dict("timestamp"=>string(now()),"agent_id"=>a1.id,
                                     "signal_type"=>"communication","resulting_wisdom"=>avg_wisdom))
end

function copy_and_mutate_brain(parent_chain::Chain, mutation_rate=0.05)
    new_layers=[]
    for layer in parent_chain
        if layer isa Dense
            W=layer.weight
            b=layer.bias
            new_W=W .+ (randn(size(W)).*mutation_rate)
            new_b=b .+ (randn(size(b)).*mutation_rate)
            push!(new_layers,Dense(new_W,new_b,layer.σ))
        else
            push!(new_layers,layer)
        end
    end
    return Chain(new_layers...)
end

function agent_reproduce!(agent::Agent, mate::Agent, world::World)
    if agent.energy["available"]<30.0 || mate.energy["available"]<30.0
        return
    end
    agent.energy["available"]-=30.0
    mate.energy["available"]-=30.0

    new_genes=Dict(k=>clamp((agent.genes[k]+mate.genes[k])/2+randn()*0.05,0.1,1.0) for k in keys(agent.genes))
    new_id="agent_$(uuid4())"
    child=create_agent(new_id, parent_genes=new_genes, generation=max(agent.generation,mate.generation)+1,
                       grid_size=world.grid_size, parent_brain=agent.brain)
    world.agents[new_id]=child
end

# ============================================================================
# MODULE 6: AGING AND DEATH
# ============================================================================

function agent_age!(agent::Agent, world::World)
    agent.age+=1
    agent.energy["available"] -= 1.0*(1.0/agent.genes["resilience"])
    if agent.age>50
        transfer=min(agent.energy["available"]*0.1,5.0)
        agent.energy["available"]-=transfer
        agent.energy["archive"]+=transfer
    end
    if agent.energy["available"]<=0.0 || agent.age>200
        world.library["knowledge"] += agent.energy["archive"]*0.01
        delete!(world.agents, agent.id)
    end
end

# ============================================================================
# MODULE 7: WORLD STATUS AND CYCLE
# ============================================================================

function update_world_status!(world::World)
    if length(world.agents)==0
        world.world_status="extinct"
        return
    end
    avg_intellect=mean([a.genes["intellect"] for a in values(world.agents)])
    avg_innovation=mean([a.genes["innovation"] for a in values(world.agents)])
    total_knowledge=world.library["knowledge"]

    if total_knowledge>100.0 && avg_intellect>0.7 && avg_innovation>0.7
        world.world_status="advanced"
    elseif total_knowledge>50.0 && avg_innovation>0.5
        world.world_status="creative"
    elseif total_knowledge>20.0 && avg_intellect>0.4
        world.world_status="adaptive"
    else
        world.world_status="primitive"
    end
end

function simulate_cycle!(world::World)
    world.cycle_count+=1
    for agent in values(world.agents)
        agent_gain_energy!(agent)
        agent_decide!(agent,world)
        agent_age!(agent,world)
    end
    update_world_status!(world)
end

# ============================================================================
# MODULE 8: DATA EXPORT
# ============================================================================

function export_world_json(world::World, filename="tmp/world_metrics.json")
    data=Dict(
        "cycle"=>world.cycle_count,
        "population"=>length(world.agents),
        "world_status"=>world.world_status,
        "library"=>world.library,
        "agents"=>[Dict("id"=>a.id,"x"=>a.x,"y"=>a.y,"energy"=>a.energy,"genes"=>a.genes,"age"=>a.age,"knowledge"=>a.knowledge) for a in values(world.agents)]
    )
    open(filename,"w") do f
        JSON.print(f,data,2)
    end
end

# ============================================================================
# MODULE 9: MAIN EXECUTION
# ============================================================================

function main()
    println("Initializing Itheris World...")
    world=create_world(20,(10,10))

    for cycle in 1:50
        simulate_cycle!(world)
        if cycle%10==0
            println("Cycle $cycle: Population=$(length(world.agents)), Status=$(world.world_status), Knowledge=$(round(world.library["knowledge"],digits=2))")
        end
        export_world_json(world)
    end
    println("Simulation Complete. Final Population=$(length(world.agents))")
end

# Helper
mean(x)=sum(x)/length(x)
uuid4()=string(rand(UInt128),base=16)

# Execute if run directly
if abspath(PROGRAM_FILE)==@__FILE__
    main()
end