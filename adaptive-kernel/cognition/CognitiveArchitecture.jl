# cognition/CognitiveArchitecture.jl - Complete Cognitive Architecture Integration
# Integrates WorkingMemory, ProceduralMemory, SemanticRecall, MemoryStore, GlobalWorkspace, Attention
# Implements OODA-style cognitive processing loop

module CognitiveArchitecture

using Dates
using UUIDs
using Logging

# ============================================================================
# MODULE DEPENDENCIES
# ============================================================================

# Include required submodules
include("../memory/WorkingMemory.jl")
include("../memory/ProceduralMemory.jl")
include("../memory/Memory.jl")
include("GlobalWorkspace.jl")
include("Attention.jl")

# Import types from submodules
using .WorkingMemory
using .ProceduralMemory
using .Memory
using .GlobalWorkspace
using .Attention

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Main Architecture Types
    CognitiveArchitecture,
    CognitiveCycleState,
    CyclePhase,
    
    # Architecture Operations
    create_cognitive_architecture,
    reset_architecture!,
    get_architecture_status,
    
    # Cognitive Cycle Operations
    perceive,
    attend,
    broadcast_to_workspace,
    consolidate_to_memory,
    learn_procedure,
    retrieve_procedures,
    full_cognitive_cycle,
    
    # Memory Integration
    recall_semantic,
    has_experience,
    
    # Status Queries
    get_working_memory_contents,
    get_attended_items,
    get_conscious_content,
    get_procedures_for_capability

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    CyclePhase

Phases of the cognitive processing cycle (OODA loop).
"""
@enum CyclePhase begin
    PHASE_OBSERVE   # Observe - perceiving external/internal stimuli
    PHASE_ORIENT    # Orient - attending and organizing information  
    PHASE_DECIDE    # Decide - broadcasting to workspace for consciousness
    PHASE_ACT       # Act - consolidating to memory and executing
    PHASE_REST      # Rest - idle state
end

"""
    CognitiveCycleState

The current state of the cognitive processing cycle.
Tracks which phase the system is in and what data is being processed.

# Fields
- `phase::CyclePhase`: Current phase of the OODA loop
- `perceived_input::Union{Any, Nothing}`: Input received in observe phase
- `attended_items::Vector{Any}`: Items that passed through attention filter
- `broadcast_content::Union{WorkspaceContent, Nothing}`: Content currently in conscious workspace
- `consolidated_to_memory::Bool`: Whether current cycle completed memory consolidation
- `cycle_count::Int`: Number of completed cognitive cycles
- `last_cycle_timestamp::DateTime`: Timestamp of last cycle completion

# Example
```julia
state = CognitiveCycleState()
state.phase == PHASE_REST  # true initially
```
"""
mutable struct CognitiveCycleState
    phase::CyclePhase
    perceived_input::Union{Any, Nothing}
    attended_items::Vector{Any}
    broadcast_content::Union{GlobalWorkspace.WorkspaceContent, Nothing}
    consolidated_to_memory::Bool
    cycle_count::Int
    last_cycle_timestamp::DateTime
    
    """
        CognitiveCycleState()

    Create a new cognitive cycle state in the resting phase.
    """
    function CognitiveCycleState()
        new(
            PHASE_REST,
            nothing,
            Any[],
            nothing,
            false,
            0,
            now()
        )
    end
end

"""
    CognitiveArchitecture

The complete cognitive architecture integrating all cognitive subsystems.
This is the unified state container for the entire cognitive system.

# Design Principles

This architecture implements a complete cognitive processing loop inspired by:
1. **Baddeley's Working Memory**: Short-term buffer for active processing
2. **Anderson's ACT-R**: Procedural memory for learned skills
3. **Global Workspace Theory**: Consciousness through competitive broadcasting
4. **Posner's Attention Model**: Selective attention and cognitive control
5. **OODA Loop**: Observe-Orient-Decide-Act cycle

# Fields

- `working_memory::WorkingMemory`: Short-term buffer for current context
- `procedural_memory::ProceduralMemory`: Long-term storage for skills/procedures
- `episodic_store::Memory.MemoryStore`: Episodic memory for experiences
- `semantic_recall::Memory.SemanticRecall`: Semantic memory for knowledge recall
- `global_workspace::GlobalWorkspace`: Consciousness/broadcasting system
- `attention_system::Attention.AttentionSystem`: Attentional control
- `cycle_state::CognitiveCycleState`: Current processing state
- `config::Dict{String, Any}`: Configuration parameters

# Cognitive Processing Flow

```
External Input → Perceive → Working Memory → Attend → Global Workspace 
                                                        ↓
                                              (Conscious Processing)
                                                        ↓
Memory ← Consolidate ← Decision ← Broadcast ← Attention Filter
  ↑
Procedural Memory ← Learn Procedure
```

# Example
```julia
arch = create_cognitive_architecture()

# Run a cognitive cycle
result = full_cognitive_cycle(arch, Dict("task" => "analyze_data"))
```
"""
mutable struct CognitiveArchitecture
    # Core Memory Systems
    working_memory::WorkingMemory
    procedural_memory::ProceduralMemory
    episodic_store::Memory.MemoryStore
    semantic_recall::Memory.SemanticRecall
    
    # Processing Systems
    global_workspace::GlobalWorkspace
    attention_system::Attention.AttentionSystem
    
    # State Management
    cycle_state::CognitiveCycleState
    
    # Configuration
    config::Dict{String, Any}
    
    # Metadata
    id::UUID
    created_at::DateTime
    last_update::DateTime
    
    """
        CognitiveArchitecture(;
            working_memory_capacity=7,
            procedural_memory_max_history=20,
            attention_budget=1.0,
            workspace_max_history=100
        )

    Create a new cognitive architecture with all subsystems.
    """
    function CognitiveArchitecture(;
        working_memory_capacity::Int=7,
        working_memory_decay::Float64=0.1,
        procedural_memory_max_history::Int=20,
        procedural_decay_rate::Float64=0.05,
        attention_budget::Float64=1.0,
        attention_alertness::Float64=0.8,
        attention_orienting::Float64=0.9,
        workspace_competition_threshold::Float64=0.3,
        workspace_attention_decay::Float64=0.1,
        workspace_max_history::Int=100,
        semantic_enabled::Bool=false
    )
        # Initialize all subsystems
        wm = WorkingMemory(capacity=working_memory_capacity, decay_rate=working_memory_decay)
        pm = ProceduralMemory(max_history=procedural_memory_max_history, decay_rate=procedural_decay_rate)
        ms = Memory.MemoryStore()
        
        # Semantic recall (optional - may fail if VectorStore unavailable)
        sr = try
            Memory.SemanticRecall(enabled=semantic_enabled)
        catch e
            @warn "Failed to initialize semantic recall: $e"
            Memory.SemanticRecall(enabled=false)
        end
        
        # Global workspace for consciousness
        gw = GlobalWorkspace(
            competition_threshold=workspace_competition_threshold,
            attention_decay=workspace_attention_decay,
            max_history=workspace_max_history
        )
        
        # Attention system for cognitive control
        att = Attention.AttentionSystem(
            attention_budget=attention_budget,
            alerting_level=attention_alertness,
            orienting_speed=attention_orienting,
            executive_capacity=attention_orienting
        )
        
        # Configuration
        config = Dict{String, Any}(
            "working_memory_capacity" => working_memory_capacity,
            "working_memory_decay" => working_memory_decay,
            "procedural_memory_max_history" => procedural_memory_max_history,
            "procedural_decay_rate" => procedural_decay_rate,
            "attention_budget" => attention_budget,
            "attention_alertness" => attention_alertness,
            "workspace_competition_threshold" => workspace_competition_threshold,
            "semantic_enabled" => semantic_enabled
        )
        
        new(
            wm,
            pm,
            ms,
            sr,
            gw,
            att,
            CognitiveCycleState(),
            config,
            uuid4(),
            now(),
            now()
        )
    end
end

# ============================================================================
# ARCHITECTURE CREATION
# ============================================================================

"""
    create_cognitive_architecture(;kwargs...) -> CognitiveArchitecture

Create and initialize a complete cognitive architecture with all subsystems.

# Arguments (all keyword)
- `working_memory_capacity::Int`: Max items in working memory (default: 7)
- `working_memory_decay::Float64`: Decay rate for working memory (default: 0.1)
- `procedural_memory_max_history::Int`: Max history per procedure (default: 20)
- `procedural_decay_rate::Float64`: Decay rate for unused procedures (default: 0.05)
- `attention_budget::Float64`: Total attention capacity (default: 1.0)
- `attention_alertness::Float64`: Initial alertness level (default: 0.8)
- `attention_orienting::Float64`: Speed of attentional shifts (default: 0.9)
- `workspace_competition_threshold::Float64`: Min importance for broadcasting (default: 0.3)
- `workspace_attention_decay::Float64`: Attention shift delay (default: 0.1)
- `workspace_max_history::Int`: Max broadcast history (default: 100)
- `semantic_enabled::Bool`: Enable semantic memory (default: false)

# Returns
- `CognitiveArchitecture`: Fully initialized cognitive architecture

# Example
```julia
# Create with defaults
arch = create_cognitive_architecture()

# Create with custom configuration
arch = create_cognitive_architecture(
    working_memory_capacity=5,
    attention_alertness=0.9,
    semantic_enabled=true
)
```
"""
function create_cognitive_architecture(;
    working_memory_capacity::Int=7,
    working_memory_decay::Float64=0.1,
    procedural_memory_max_history::Int=20,
    procedural_decay_rate::Float64=0.05,
    attention_budget::Float64=1.0,
    attention_alertness::Float64=0.8,
    attention_orienting::Float64=0.9,
    workspace_competition_threshold::Float64=0.3,
    workspace_attention_decay::Float64=0.1,
    workspace_max_history::Int=100,
    semantic_enabled::Bool=false
)::CognitiveArchitecture
    
    @info "Creating cognitive architecture with all subsystems"
    
    arch = CognitiveArchitecture(
        working_memory_capacity,
        working_memory_decay=working_memory_decay,
        procedural_memory_max_history=procedural_memory_max_history,
        procedural_decay_rate=procedural_decay_rate,
        attention_budget=attention_budget,
        attention_alertness=attention_alertness,
        attention_orienting=attention_orienting,
        workspace_competition_threshold=workspace_competition_threshold,
        workspace_attention_decay=workspace_attention_decay,
        workspace_max_history=workspace_max_history,
        semantic_enabled=semantic_enabled
    )
    
    # Subscribe attention system to workspace for feedback
    GlobalWorkspace.subscribe!(
        arch.global_workspace, 
        "AttentionSystem";
        priority=GlobalWorkspace.PRIORITY_HIGH
    )
    
    @info "Cognitive architecture initialized" 
          working_memory_capacity=working_memory_capacity
          procedural_memory_max_history=procedural_memory_max_history
          semantic_enabled=semantic_enabled
    
    return arch
end

"""
    reset_architecture!(arch::CognitiveArchitecture)

Reset the cognitive architecture to initial state while preserving learned procedures.
"""
function reset_architecture!(arch::CognitiveArchitecture)
    # Clear working memory
    WorkingMemory.clear_working_memory!(arch.working_memory)
    
    # Reset attention system
    arch.attention_system = Attention.AttentionSystem(
        attention_budget=arch.config["attention_budget"],
        alerting_level=arch.config["attention_alertness"],
        orienting_speed=0.9,
        executive_capacity=0.9
    )
    
    # Clear workspace
    GlobalWorkspace.clear_workspace(arch.global_workspace)
    
    # Reset cycle state
    arch.cycle_state = CognitiveCycleState()
    arch.last_update = now()
    
    @info "Cognitive architecture reset"
end

"""
    get_architecture_status(arch::CognitiveArchitecture) -> Dict

Get a comprehensive status report of the cognitive architecture.
"""
function get_architecture_status(arch::CognitiveArchitecture)::Dict{String, Any}
    return Dict{String, Any}(
        "id" => string(arch.id),
        "created_at" => string(arch.created_at),
        "last_update" => string(arch.last_update),
        "cycle" => Dict(
            "phase" => string(arch.cycle_state.phase),
            "count" => arch.cycle_state.cycle_count,
            "last_timestamp" => string(arch.cycle_state.last_cycle_timestamp)
        ),
        "working_memory" => Dict(
            "capacity" => arch.working_memory.capacity,
            "current_items" => length(arch.working_memory),
            "decay_rate" => arch.working_memory.decay_rate
        ),
        "procedural_memory" => Dict(
            "procedure_count" => length(arch.procedural_memory.procedures),
            "capabilities" => collect(keys(arch.procedural_memory.capability_index))
        ),
        "episodic_store" => Dict(
            "episode_count" => length(arch.episodic_store.episodes),
            "failure_count" => length(arch.episodic_store.failures)
        ),
        "semantic_recall" => Dict(
            "enabled" => arch.semantic_recall.enabled
        ),
        "global_workspace" => Dict(
            "subscribers" => length(arch.global_workspace.subscribers),
            "broadcast_count" => arch.global_workspace.broadcast_count,
            "current_conscious" => arch.global_workspace.current_conscious_content !== nothing
        ),
        "attention" => Dict(
            "budget" => arch.attention_system.attention_budget,
            "allocated" => arch.attention_system.allocated_budget,
            "alerting_level" => arch.attention_system.alerting_level,
            "current_focus" => arch.attention_system.current_focus !== nothing
        )
    )
end

# ============================================================================
# COGNITIVE CYCLE OPERATIONS
# ============================================================================

"""
    perceive(arch::CognitiveArchitecture, input) -> Any

Process external or internal input into working memory (Observe phase).

This implements the first phase of the OODA loop:
- Receive raw input from sensors or internal processes
- Store in working memory with attention tagging
- Return the perceived content

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `input`: The input to perceive (can be any Julia object)

# Returns
- The input that was stored in working memory

# Example
```julia
arch = create_cognitive_architecture()

# Perceive external observation
perceive(arch, Dict("type" => "vision", "data" => frame_data))

# Perceive internal thought
perceive(arch, "Need to analyze the user's request")
```
"""
function perceive(arch::CognitiveArchitecture, input)::Any
    arch.cycle_state.phase = PHASE_OBSERVE
    
    # Push to working memory with attention tagging
    result = WorkingMemory.push_to_working_memory!(arch.working_memory, input)
    
    # Update architecture timestamp
    arch.last_update = now()
    arch.cycle_state.perceived_input = input
    
    @debug "Perceived input" input_type=typeof(input)
    
    return result
end

"""
    attend(arch::CognitiveArchitecture; threshold::Float64=0.3) -> Vector{Any}

Filter working memory through attention system (Orient phase).

This implements the second phase of the OODA loop:
- Apply attention filter to working memory contents
- Return items that pass the attention threshold
- Update attention system state

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `threshold::Float64`: Minimum attention weight (default: 0.3)

# Returns
- Vector of items that passed the attention filter

# Example
```julia
arch = create_cognitive_architecture()
perceive(arch, "important_task")
perceive(arch, "background_noise")

# Get attended items (those above attention threshold)
attended = attend(arch, threshold=0.5)
```
"""
function attend(arch::CognitiveArchitecture; threshold::Float64=0.3)::Vector{Any}
    arch.cycle_state.phase = PHASE_ORIENT
    
    # Get items from working memory above threshold
    attended = WorkingMemory.get_attended_items(arch.working_memory; threshold=threshold)
    
    # Update attention system with attended items
    for item in attended
        att_item = Attention.AttentionItem(
            item;
            source=Attention.SOURCE_INTERNAL,
            priority=Attention.PRIORITY_NORMAL,
            salience=0.5
        )
        Attention.allocate_attention!(arch.attention_system, att_item)
    end
    
    # Store attended items in cycle state
    arch.cycle_state.attended_items = attended
    
    arch.last_update = now()
    
    @debug "Attended items" count=length(attended)
    
    return attended
end

"""
    broadcast_to_workspace(arch::CognitiveArchitecture, content::Any; 
                          importance::Float64=0.5, source::String="CognitiveArchitecture") 
                          -> Union{GlobalWorkspace.WorkspaceContent, Nothing}

Send attended content to global workspace for consciousness (Decide phase).

This implements the third phase of the OODA loop:
- Content competes for the "spotlight" of consciousness
- Winner is broadcast to all subscribers
- Represents conscious awareness

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `content::Any`: Content to broadcast
- `importance::Float64`: Importance score 0-1 (default: 0.5)
- `source::String`: Source module name (default: "CognitiveArchitecture")

# Returns
- The broadcast content if it won the competition, nothing otherwise

# Example
```julia
arch = create_cognitive_architecture()
attend(arch)

# Broadcast the decision to consciousness
result = broadcast_to_workspace(arch, "Execute the planned action"; importance=0.8)
```
"""
function broadcast_to_workspace(
    arch::CognitiveArchitecture, 
    content::Any; 
    importance::Float64=0.5, 
    source::String="CognitiveArchitecture"
)::Union{GlobalWorkspace.WorkspaceContent, Nothing}
    
    arch.cycle_state.phase = PHASE_DECIDE
    
    # Broadcast through global workspace
    result = GlobalWorkspace.broadcast_content(
        arch.global_workspace,
        content,
        source;
        importance=importance,
        context=Dict("cycle_phase" => string(PHASE_DECIDE))
    )
    
    arch.cycle_state.broadcast_content = result
    arch.last_update = now()
    
    if result !== nothing
        @debug "Content broadcast to workspace" source=source importance=importance
    end
    
    return result
end

"""
    consolidate_to_memory(arch::CognitiveArchitecture, content::Any;
                         is_episodic::Bool=true, metadata::Dict=Dict()) -> Bool

Consolidate important information to episodic and semantic memory (Act phase).

This implements memory consolidation:
- Episodic: Stores the experience in the memory store
- Semantic: Optionally stores for knowledge retrieval

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `content::Any`: Content to consolidate
- `is_episodic::Bool`: Whether to store as episodic memory (default: true)
- `metadata::Dict`: Additional metadata for the memory

# Returns
- `true` if consolidation was successful

# Example
```julia
arch = create_cognitive_architecture()

# Consolidate an experience to memory
consolidate_to_memory(
    arch, 
    "Successfully completed analysis task";
    is_episodic=true,
    metadata=Dict("outcome" => "success", "task_type" => "analysis")
)
```
"""
function consolidate_to_memory(
    arch::CognitiveArchitecture, 
    content::Any;
    is_episodic::Bool=true,
    metadata::Dict{String, Any}=Dict{String, Any}()
)::Bool
    
    arch.cycle_state.phase = PHASE_ACT
    arch.cycle_state.consolidated_to_memory = true
    
    success = true
    
    # Consolidate to episodic memory
    if is_episodic
        episode = Dict{String, Any}(
            "content" => content,
            "timestamp" => now(),
            "cycle" => arch.cycle_state.cycle_count,
            "metadata" => metadata
        )
        Memory.ingest_episode!(arch.episodic_store, episode)
    end
    
    # Consolidate to semantic memory if enabled
    if arch.semantic_recall.enabled && isa(content, String)
        try
            Memory.integrate_semantic_memory(
                arch.episodic_store,
                arch.semantic_recall,
                content,
                metadata
            )
        catch e
            @warn "Failed to consolidate to semantic memory" error=string(e)
        end
    end
    
    arch.last_update = now()
    
    @debug "Consolidated to memory" is_episodic=is_episodic
    
    return success
end

# ============================================================================
# PROCEDURAL MEMORY OPERATIONS
# ============================================================================

"""
    learn_procedure(arch::CognitiveArchitecture, name::String, capability_id::String;
                   parameters::Dict=Dict()) -> ProceduralMemory.Procedure

Store a new skill or procedure in procedural memory.

This allows the system to learn new capabilities through practice:
- Creates a new procedure with initial effectiveness
- Associates it with a capability domain
- Can be retrieved and executed later

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `name::String`: Human-readable name for the procedure
- `capability_id::String`: The capability this procedure implements
- `parameters::Dict`: Configuration parameters (default: empty Dict)

# Returns
- The newly created `Procedure`

# Example
```julia
arch = create_cognitive_architecture()

# Learn a new procedure
proc = learn_procedure(
    arch,
    "fast_csv_analysis",
    "data_analysis";
    parameters=Dict("method" => "streaming", "delimiter" => ",")
)
```
"""
function learn_procedure(
    arch::CognitiveArchitecture, 
    name::String, 
    capability_id::String;
    parameters::Dict{String, Any}=Dict{String, Any}()
)::ProceduralMemory.Procedure
    
    proc = ProceduralMemory.create_procedure!(
        arch.procedural_memory,
        name,
        capability_id;
        parameters=parameters
    )
    
    @info "Learned new procedure" name=name capability_id=capability_id
    
    return proc
end

"""
    retrieve_procedures(arch::CognitiveArchitecture, capability_id::String;
                       min_effectiveness::Float64=0.0) -> Vector{ProceduralMemory.Procedure}

Retrieve relevant skills from procedural memory.

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `capability_id::String`: The capability to retrieve procedures for
- `min_effectiveness::Float64`: Minimum effectiveness threshold (default: 0.0)

# Returns
- Vector of matching `Procedure` objects

# Example
```julia
arch = create_cognitive_architecture()

# Learn some procedures first
learn_procedure(arch, "method_a", "data_analysis")
learn_procedure(arch, "method_b", "data_analysis")

# Retrieve all procedures for data analysis
procedures = retrieve_procedures(arch, "data_analysis")

# Get the best one
best = ProceduralMemory.get_best_procedure(arch.procedural_memory, "data_analysis")
```
"""
function retrieve_procedures(
    arch::CognitiveArchitecture, 
    capability_id::String;
    min_effectiveness::Float64=0.0
)::Vector{ProceduralMemory.Procedure}
    
    return ProceduralMemory.get_procedures_by_capability(
        arch.procedural_memory,
        capability_id;
        min_effectiveness=min_effectiveness
    )
end

"""
    get_procedures_for_capability(arch::CognitiveArchitecture, capability_id::String) 
                                  -> Union{ProceduralMemory.Procedure, Nothing}

Get the most effective procedure for a capability (convenience function).
"""
function get_procedures_for_capability(
    arch::CognitiveArchitecture, 
    capability_id::String
)::Union{ProceduralMemory.Procedure, Nothing}
    
    return ProceduralMemory.get_best_procedure(arch.procedural_memory, capability_id)
end

# ============================================================================
# SEMANTIC RECALL OPERATIONS
# ============================================================================

"""
    recall_semantic(arch::CognitiveArchitecture, query::String;
                   top_k::Int=5, min_similarity::Float32=0.3f0) -> Vector{Dict{String, Any}}

Query semantic memory for relevant past experiences.

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `query::String`: The search query
- `top_k::Int`: Number of results to return (default: 5)
- `min_similarity::Float32`: Minimum similarity threshold (default: 0.3)

# Returns
- Vector of matching experiences with similarity scores

# Example
```julia
arch = create_cognitive_architecture(semantic_enabled=true)

# Query past experiences
results = recall_semantic(arch, "data analysis failures"; top_k=3)
```
"""
function recall_semantic(
    arch::CognitiveArchitecture, 
    query::String;
    top_k::Int=5,
    min_similarity::Float32=0.3f0
)::Vector{Dict{String, Any}}
    
    return Memory.recall_experience(
        arch.semantic_recall,
        query;
        top_k=top_k,
        min_similarity=min_similarity
    )
end

"""
    has_experience(arch::CognitiveArchitecture, query::String;
                   threshold::Float32=0.5f0) -> Bool

Quick check if the system has relevant past experience.

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `query::String`: The query to check
- `threshold::Float32`: Minimum similarity threshold (default: 0.5)

# Returns
- `true` if relevant experience exists
"""
function has_experience(
    arch::CognitiveArchitecture, 
    query::String;
    threshold::Float32=0.5f0
)::Bool
    
    return Memory.has_experience_with(
        arch.semantic_recall,
        query;
        threshold=threshold
    )
end

# ============================================================================
# STATUS QUERY FUNCTIONS
# ============================================================================

"""
    get_working_memory_contents(arch::CognitiveArchitecture) -> Vector{Any}

Get all items currently in working memory.
"""
function get_working_memory_contents(arch::CognitiveArchitecture)::Vector{Any}
    return [entry["content"] for entry in arch.working_memory.buffer]
end

"""
    get_attended_items(arch::CognitiveArchitecture; threshold::Float64=0.3) -> Vector{Any}

Get items in working memory above attention threshold.
"""
function get_attended_items(arch::CognitiveArchitecture; threshold::Float64=0.3)::Vector{Any}
    return WorkingMemory.get_attended_items(arch.working_memory; threshold=threshold)
end

"""
    get_conscious_content(arch::CognitiveArchitecture) -> Union{Any, Nothing}

Get the currently conscious content from the global workspace.
"""
function get_conscious_content(arch::CognitiveArchitecture)::Union{Any, Nothing}
    content = GlobalWorkspace.get_conscious_content(arch.global_workspace)
    return content !== nothing ? content.content : nothing
end

# ============================================================================
# FULL COGNITIVE CYCLE (OODA LOOP)
# ============================================================================

"""
    full_cognitive_cycle(arch::CognitiveArchitecture, input::Any;
                        auto_consolidate::Bool=true) -> Dict{String, Any}

Execute a complete OODA-style cognitive processing cycle.

This is the main entry point for cognitive processing:
1. **Observe**: Perceive input into working memory
2. **Orient**: Filter through attention system
3. **Decide**: Broadcast to global workspace for consciousness
4. **Act**: Consolidate important info to memory

# Arguments
- `arch::CognitiveArchitecture`: The cognitive architecture
- `input::Any`: Input to process (sensory data, thought, etc.)
- `auto_consolidate::Bool`: Whether to automatically consolidate to memory (default: true)

# Returns
- `Dict` containing:
  - `input`: The original input
  - `attended`: Items that passed attention filter
  - `broadcast`: Content that reached consciousness (if any)
  - `consolidated`: Whether content was consolidated to memory
  - `cycle_number`: The current cycle number

# Example
```julia
arch = create_cognitive_architecture()

# Run a complete cognitive cycle
result = full_cognitive_architecture(arch, Dict("task" => "analyze_data"))

# Check results
println("Cycle $(result["cycle_number"]): $(result["broadcast"])")
```
"""
function full_cognitive_cycle(
    arch::CognitiveArchitecture, 
    input::Any;
    auto_consolidate::Bool=true
)::Dict{String, Any}
    
    @debug "Starting full cognitive cycle" input_type=typeof(input)
    
    # Phase 1: Observe - Perceive input into working memory
    perceived = perceive(arch, input)
    
    # Phase 2: Orient - Attend to relevant items
    attended = attend(arch)
    
    # Phase 3: Decide - Broadcast to global workspace
    # Determine importance based on attention weight
    importance = isempty(attended) ? 0.5 : 0.7
    broadcast = broadcast_to_workspace(arch, perceived; importance=importance)
    
    # Phase 4: Act - Consolidate to memory
    consolidated = false
    if auto_consolidate
        consolidated = consolidate_to_memory(
            arch, 
            perceived;
            is_episodic=true,
            metadata=Dict("cycle" => arch.cycle_state.cycle_count + 1)
        )
    end
    
    # Update cycle state
    arch.cycle_state.cycle_count += 1
    arch.cycle_state.last_cycle_timestamp = now()
    arch.cycle_state.phase = PHASE_REST
    
    result = Dict{String, Any}(
        "input" => perceived,
        "attended" => attended,
        "broadcast" => broadcast !== nothing ? broadcast.content : nothing,
        "consolidated" => consolidated,
        "cycle_number" => arch.cycle_state.cycle_count,
        "phase" => string(PHASE_REST)
    )
    
    @debug "Completed cognitive cycle" 
           cycle_number=arch.cycle_state.cycle_count
           attended_count=length(attended)
           was_broadcast=broadcast !== nothing
    
    return result
end

# ============================================================================
# DOCSTRING: COMPLETE COGNITIVE LOOP EXPLANATION
# ============================================================================

"""
# Complete Cognitive Processing Loop

This module implements an integrated cognitive architecture inspired by 
multiple cognitive science theories:

## Theoretical Foundation

### 1. Baddeley's Working Memory (Short-term)
- **Phonological Loop**: Verbal information storage
- **Visuospatial Sketchpad**: Visual/spatial information
- **Episodic Buffer**: Integration of multimodal information
- **Central Executive**: Attention control

Implemented in: [`WorkingMemory`](@ref)

### 2. Anderson's ACT-R Procedural Memory (Skills)
- Production rules for skill execution
- Effectiveness tracking through reinforcement
- Pattern matching for retrieval
- Decay of unused procedures

Implemented in: [`ProceduralMemory`](@ref)

### 3. Semantic Recall (Long-term Knowledge)
- Vector-based similarity search
- RAG-style experience retrieval
- Links episodic experiences to knowledge

Implemented in: [`Memory.SemanticRecall`](@ref)

### 4. Global Workspace Theory (Consciousness)
- "Theatre" metaphor for consciousness
- Competitive broadcasting to all modules
- "Spotlight" of attention
- Integration of parallel processing

Implemented in: [`GlobalWorkspace`](@ref)

### 5. Posner's Attention Model (Control)
- **Alerting**: Maintaining vigilance
- **Orienting**: Selective attention
- **Executive Control**: Conflict resolution

Implemented in: [`Attention`](@ref)

### 6. OODA Loop (Processing Cycle)
- **Observe**: Perceive input
- **Orient**: Organize and filter
- **Decide**: Make conscious choice
- **Act**: Execute and consolidate

## Usage Pattern

```julia
# Create the architecture
arch = create_cognitive_architecture()

# Learn some procedures
learn_procedure(arch, "fast_analyzer", "data_analysis"; 
               parameters=Dict("method" => "fast"))

# Run cognitive cycles
result1 = full_cognitive_architecture(arch, "User wants data analysis")
result2 = full_cognitive_architecture(arch, "Error occurred")

# Query memory
procedures = retrieve_procedures(arch, "data_analysis")

# Check consciousness
conscious = get_conscious_content(arch)
```

## Integration Points

The architecture integrates with:
- `WorkingMemory.jl`: Short-term buffer
- `ProceduralMemory.jl`: Skill storage
- `Memory.jl`: Episodic and semantic memory
- `GlobalWorkspace.jl`: Consciousness system
- `Attention.jl`: Cognitive control
"""

end # module CognitiveArchitecture
