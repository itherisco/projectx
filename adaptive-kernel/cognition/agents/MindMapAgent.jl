# cognition/agents/MindMapAgent.jl - MindMap Agent
# Knowledge graph-based reasoning coherence tracker
# Prevents logical fragmentation in long reasoning chains

module MindMapAgent

using Dates
using UUIDs

# Import types
include("../types.jl")
using ..CognitionTypes

# Import spine for AgentProposal
include("../spine/DecisionSpine.jl")
using ..DecisionSpine

# Export all public functions
export 
    MindMapAgent,
    create_mindmap_agent,
    generate_proposal,
    add_reasoning_node,
    add_reasoning_edge,
    query_knowledge_graph,
    detect_coherence_breaks,
    validate_chain_consistency,
    check_hallucination,
    get_chain_confidence,
    backtrack_to_state,
    KnowledgeNode,
    KnowledgeEdge,
    ReasoningChain

# ============================================================================
# KNOWLEDGE GRAPH TYPES
# ============================================================================

"""
    RelationType - Types of logical relationships in the knowledge graph
"""
@enum RelationType begin
    causal        # A causes B
    sequential    # A precedes B in reasoning
    contradictory # A contradicts B
    supportive    # A supports B
    equivalent    # A is equivalent to B
    refines       # A refines B
    supersedes    # A supersedes B
end

"""
    KnowledgeNode - Node in the knowledge graph representing a concept or fact
"""
mutable struct KnowledgeNode
    id::String
    chain_id::String         # Reasoning chain this node belongs to
    concept::String          # The actual concept/fact
    confidence::Float64      # [0, 1] confidence score
    source::String           # Source attribution
    created_at::DateTime
    metadata::Dict{String, Any}
    
    function KnowledgeNode(
        chain_id::String,
        concept::String,
        confidence::Float64;
        source::String = "unknown",
        metadata::Dict{String, Any} = Dict{String, Any}()
    )
        return new(
            "node_" * string(uuid4()),
            chain_id,
            concept,
            clamp(confidence, 0.0, 1.0),
            source,
            now(),
            metadata
        )
    end
end

"""
    KnowledgeEdge - Edge in the knowledge graph representing a logical relationship
"""
mutable struct KnowledgeEdge
    id::String
    chain_id::String      # Reasoning chain this edge belongs to
    from_node::String     # Source node ID
    to_node::String      # Target node ID
    relation_type::RelationType
    confidence::Float64   # [0, 1] confidence in this relationship
    created_at::DateTime
    metadata::Dict{String, Any}
    
    function KnowledgeEdge(
        chain_id::String,
        from_node::String,
        to_node::String,
        relation_type::RelationType;
        confidence::Float64 = 1.0,
        metadata::Dict{String, Any} = Dict{String, Any}()
    )
        return new(
            "edge_" * string(uuid4()),
            chain_id,
            from_node,
            to_node,
            relation_type,
            clamp(confidence, 0.0, 1.0),
            now(),
            metadata
        )
    end
end

"""
    ReasoningChain - A complete reasoning chain with nodes and edges
"""
mutable struct ReasoningChain
    id::String
    name::String
    nodes::Vector{KnowledgeNode}
    edges::Vector{KnowledgeEdge}
    created_at::DateTime
    last_updated::DateTime
    is_active::Bool
    metadata::Dict{String, Any}
    
    function ReasoningChain(
        id::String,
        name::String = "unnamed_chain"
    )
        return new(
            id,
            name,
            KnowledgeNode[],
            KnowledgeEdge[],
            now(),
            now(),
            true,
            Dict{String, Any}()
        )
    end
end

# ============================================================================
# MINDMAP AGENT STRUCT
# ============================================================================

"""
    MindMapAgent - Knowledge graph-based reasoning coherence agent
    Tracks logical relationships and prevents reasoning fragmentation
"""
struct MindMapAgent <: CognitiveAgent
    id::String
    name::String
    capabilities::Vector{String}
    state::AgentState
    historical_accuracy::Float64
    
    # Knowledge graph storage
    knowledge_graph::Dict{String, KnowledgeNode}      # node_id -> node
    edges::Vector{KnowledgeEdge}                     # All edges in the graph
    chains::Dict{String, ReasoningChain}             # chain_id -> chain
    
    # Hallucination prevention
    verified_facts::Set{String}                      # Facts that have been cross-referenced
    contradicted_pairs::Set{Tuple{String, String}}   # Pairs of contradictory nodes
    
    # Snapshots for backtracking
    chain_snapshots::Dict{String, Vector{Dict}}      # chain_id -> list of snapshots
    
    MindMapAgent(id::String = "mindmap_001") = new(
        id,
        "MindMap",
        [
            "add",
            "add_edge",
            "query_graph",
            "detect_breaks",
            "validate_consistency",
            "check_hallucination",
            "backtrack"
        ],
        AgentState(AGENT_IDLE),
        0.85,  # High accuracy - logical validation is reliable
        Dict{String, KnowledgeNode}(),
        KnowledgeEdge[],
        Dict{String, ReasoningChain}(),
        Set{String}(),
        Set{Tuple{String, String}}(),
        Dict{String, Vector{Dict}}()
    )
end

# ============================================================================
# FACTORY FUNCTION
# ============================================================================

"""
    create_mindmap_agent - Create a MindMapAgent instance
"""
function create_mindmap_agent(id::String = "mindmap_001")::MindMapAgent
    return MindMapAgent(id)
end

# ============================================================================
# NODE MANAGEMENT
# ============================================================================

"""
    add_reasoning_node - Add a node to the knowledge graph
    Returns the node_id
"""
function add_reasoning_node(
    agent::MindMapAgent,
    chain_id::String,
    concept::String,
    confidence::Float64;
    source::String = "unknown",
    metadata::Dict{String, Any} = Dict{String, Any}()
)::String
    
    # Create or get the chain
    if !haskey(agent.chains, chain_id)
        agent.chains[chain_id] = ReasoningChain(chain_id, "chain_$chain_id")
    end
    
    # Create the node
    node = KnowledgeNode(chain_id, concept, confidence; source=source, metadata=metadata)
    
    # Add to knowledge graph
    agent.knowledge_graph[node.id] = node
    
    # Add to chain
    push!(agent.chains[chain_id].nodes, node)
    agent.chains[chain_id].last_updated = now()
    
    return node.id
end

"""
    add_reasoning_edge - Add an edge (logical relationship) to the knowledge graph
"""
function add_reasoning_edge(
    agent::MindMapAgent,
    chain_id::String,
    from_node::String,
    to_node::String,
    relation_type::Symbol;
    confidence::Float64 = 1.0,
    metadata::Dict{String, Any} = Dict{String, Any}()
)::String
    
    # Validate nodes exist
    if !haskey(agent.knowledge_graph, from_node)
        error("Source node $from_node does not exist")
    end
    if !haskey(agent.knowledge_graph, to_node)
        error("Target node $to_node does not exist")
    end
    
    # Convert symbol to RelationType
    rel_type = RelationType(relation_type)
    
    # Create the edge
    edge = KnowledgeEdge(
        chain_id,
        from_node,
        to_node,
        rel_type;
        confidence=confidence,
        metadata=metadata
    )
    
    # Add to edges list
    push!(agent.edges, edge)
    
    # Add to chain
    if haskey(agent.chains, chain_id)
        push!(agent.chains[chain_id].edges, edge)
        agent.chains[chain_id].last_updated = now()
    end
    
    # Track contradictory relationships
    if relation_type == :contradictory
        pair = (from_node, to_node)
        push!(agent.contradicted_pairs, pair)
    end
    
    return edge.id
end

# ============================================================================
# KNOWLEDGE GRAPH QUERYING
# ============================================================================

"""
    query_knowledge_graph - Query the knowledge graph for relevant nodes/edges
"""
function query_knowledge_graph(
    agent::MindMapAgent,
    query::String;
    chain_id::Union{String, Nothing} = nothing
)::Vector{Dict{String, Any}}
    
    results = Dict{String, Any}[]
    query_lower = lowercase(query)
    
    # Determine which chains to search
    chains_to_search = if chain_id !== nothing && haskey(agent.chains, chain_id)
        [chain_id]
    elseif chain_id !== nothing
        String[]  # Chain doesn't exist
    else
        collect(keys(agent.chains))
    end
    
    for cid in chains_to_search
        chain = agent.chains[cid]
        
        # Search nodes
        for node in chain.nodes
            # Check if query matches concept or metadata
            if occursin(query_lower, lowercase(node.concept))
                push!(results, Dict{String, Any}(
                    "type" => "node",
                    "id" => node.id,
                    "chain_id" => node.chain_id,
                    "concept" => node.concept,
                    "confidence" => node.confidence,
                    "source" => node.source,
                    "created_at" => string(node.created_at)
                ))
            end
        end
        
        # Search edges
        for edge in chain.edges
            # Check relation type matches query
            relation_str = string(edge.relation_type)
            if occursin(query_lower, relation_str)
                from_concept = agent.knowledge_graph[edge.from_node].concept
                to_concept = agent.knowledge_graph[edge.to_node].concept
                
                push!(results, Dict{String, Any}(
                    "type" => "edge",
                    "id" => edge.id,
                    "chain_id" => edge.chain_id,
                    "from_node" => edge.from_node,
                    "to_node" => edge.to_node,
                    "from_concept" => from_concept,
                    "to_concept" => to_concept,
                    "relation_type" => relation_str,
                    "confidence" => edge.confidence,
                    "created_at" => string(edge.created_at)
                ))
            end
        end
    end
    
    return results
end

# ============================================================================
# COHERENCE DETECTION
# ============================================================================

"""
    detect_coherence_breaks - Detect logical gaps in a reasoning chain
"""
function detect_coherence_breaks(
    agent::MindMapAgent,
    chain_id::String
)::Vector{Dict{String, Any}}
    
    breaks = Dict{String, Any}[]
    
    # Check chain exists
    if !haskey(agent.chains, chain_id)
        push!(breaks, Dict{String, Any}(
            "type" => "chain_not_found",
            "chain_id" => chain_id,
            "severity" => "critical",
            "message" => "Reasoning chain $chain_id does not exist"
        ))
        return breaks
    end
    
    chain = agent.chains[chain_id]
    
    # Check 1: Empty chain
    if isempty(chain.nodes)
        push!(breaks, Dict{String, Any}(
            "type" => "empty_chain",
            "chain_id" => chain_id,
            "severity" => "critical",
            "message" => "Reasoning chain is empty - no starting point"
        ))
        return breaks
    end
    
    # Check 2: Orphan nodes (nodes without incoming or outgoing edges)
    connected_nodes = Set{String}()
    for edge in chain.edges
        push!(connected_nodes, edge.from_node)
        push!(connected_nodes, edge.to_node)
    end
    
    for node in chain.nodes
        if !(node.id in connected_nodes)
            push!(breaks, Dict{String, Any}(
                "type" => "orphan_node",
                "node_id" => node.id,
                "concept" => node.concept,
                "chain_id" => chain_id,
                "severity" => "high",
                "message" => "Node '$(node.concept)' has no connections - may be disconnected reasoning"
            ))
        end
    end
    
    # Check 3: Missing sequential connections
    # A reasoning chain should have some sequential or causal connections
    has_flow = any(e -> e.relation_type in [:sequential, :causal], chain.edges)
    if has_flow == false && length(chain.nodes) > 1
        push!(breaks, Dict{String, Any}(
            "type" => "no_flow",
            "chain_id" => chain_id,
            "severity" => "medium",
            "message" => "Chain has multiple nodes but no sequential/causal flow - reasoning may be disconnected"
        ))
    end
    
    # Check 4: Low confidence nodes
    for node in chain.nodes
        if node.confidence < 0.3
            push!(breaks, Dict{String, Any}(
                "type" => "low_confidence_node",
                "node_id" => node.id,
                "concept" => node.concept,
                "confidence" => node.confidence,
                "chain_id" => chain_id,
                "severity" => "medium",
                "message" => "Low confidence ($(node.confidence)) in node '$(node.concept)'"
            ))
        end
    end
    
    # Check 5: Contradictory relationships without resolution
    contradictions = filter(e -> e.relation_type == :contradictory, chain.edges)
    if !isempty(contradictions)
        # Check if there's a resolution (supportive edge resolving the contradiction)
        for contr in contradictions
            has_resolution = any(e -> 
                e.relation_type == :supportive && 
                (e.from_node == contr.from_node || e.to_node == contr.to_node),
                chain.edges
            )
            if !has_resolution
                from_concept = agent.knowledge_graph[contr.from_node].concept
                to_concept = agent.knowledge_graph[contr.to_node].concept
                push!(breaks, Dict{String, Any}(
                    "type" => "unresolved_contradiction",
                    "edge_id" => contr.id,
                    "from_concept" => from_concept,
                    "to_concept" => to_concept,
                    "chain_id" => chain_id,
                    "severity" => "high",
                    "message" => "Contradiction between '$from_concept' and '$to_concept' has no resolution"
                ))
            end
        end
    end
    
    return breaks
end

# ============================================================================
# CONSISTENCY VALIDATION
# ============================================================================

"""
    validate_chain_consistency - Validate logical consistency of a chain
"""
function validate_chain_consistency(
    agent::MindMapAgent,
    chain_id::String
)::Dict{String, Any}
    
    result = Dict{String, Any}(
        "is_consistent" => true,
        "chain_id" => chain_id,
        "issues" => String[],
        "warnings" => String[]
    )
    
    # Get chain
    if !haskey(agent.chains, chain_id)
        result["is_consistent"] = false
        push!(result["issues"], "Chain does not exist")
        return result
    end
    
    chain = agent.chains[chain_id]
    
    # Check for circular dependencies (self-referential edges)
    for edge in chain.edges
        if edge.from_node == edge.to_node
            result["is_consistent"] = false
            push!(result["issues"], "Self-referential edge detected: $(edge.id)")
        end
    end
    
    # Check for contradictory chains (multiple contradictory edges without resolution)
    contraditions = filter(e -> e.relation_type == :contradictory, chain.edges)
    if length(contraditions) > 1
        # Multiple contradictions might indicate inconsistent reasoning
        push!(result["warnings"], "Multiple contradictory relationships detected")
    end
    
    # Check confidence consistency
    avg_confidence = mean([n.confidence for n in chain.nodes])
    if avg_confidence < 0.5
        push!(result["warnings"], "Overall chain confidence is low: $avg_confidence")
    end
    
    return result
end

# ============================================================================
# HALLUCINATION PREVENTION
# ============================================================================

"""
    check_hallucination - Check if a new claim might be hallucinated
    Cross-references with existing knowledge graph
"""
function check_hallucination(
    agent::MindMapAgent,
    claim::String;
    chain_id::Union{String, Nothing} = nothing
)::Dict{String, Any}
    
    result = Dict{String, Any}(
        "is_hallucination" => false,
        "claim" => claim,
        "risk_level" => "low",
        "contradictions" => String[],
        "supporting_evidence" => String[],
        "verification_needed" => false
    )
    
    claim_lower = lowercase(claim)
    
    # Search for existing related concepts
    related_nodes = KnowledgeNode[]
    for (id, node) in agent.knowledge_graph
        # Check for concept similarity
        if occursin(claim_lower, lowercase(node.concept)) || 
           occursin(lowercase(node.concept), claim_lower)
            push!(related_nodes, node)
        end
    end
    
    # Check for contradictions with existing facts
    for node in related_nodes
        # Check if this claim contradicts existing node
        for (node1, node2) in agent.contradicted_pairs
            if node.id == node1 || node.id == node2
                other_id = node.id == node1 ? node2 : node1
                if haskey(agent.knowledge_graph, other_id)
                    other_node = agent.knowledge_graph[other_id]
                    # Check if claim is similar to the contradicting node
                    if occursin(claim_lower, lowercase(other_node.concept))
                        push!(result["contradictions"], 
                            "Claim contradicts established fact: '$(other_node.concept)'")
                        result["is_hallucination"] = true
                        result["risk_level"] = "high"
                    end
                end
            end
        end
    end
    
    # Check source attribution
    if isempty(related_nodes)
        result["verification_needed"] = true
        result["risk_level"] = "medium"
        push!(result["supporting_evidence"], 
            "No existing knowledge graph entries match - verification recommended")
    end
    
    # Check if any related nodes have been verified
    for node in related_nodes
        if node.source in agent.verified_facts
            push!(result["supporting_evidence"], 
                "Supported by verified source: $(node.source)")
        end
    end
    
    # If no evidence and no contradictions, mark for verification
    if isempty(result["supporting_evidence"]) && isempty(result["contradictions"])
        result["verification_needed"] = true
        result["risk_level"] = "medium"
    end
    
    return result
end

# ============================================================================
# CONFIDENCE CALCULATION
# ============================================================================

"""
    get_chain_confidence - Calculate overall confidence for a reasoning chain
"""
function get_chain_confidence(
    agent::MindMapAgent,
    chain_id::String
)::Float64
    
    if !haskey(agent.chains, chain_id)
        return 0.0
    end
    
    chain = agent.chains[chain_id]
    
    if isempty(chain.nodes)
        return 0.0
    end
    
    # Base confidence from node confidences
    node_confidences = [n.confidence for n in chain.nodes]
    avg_node_conf = mean(node_confidences)
    
    # Adjust for edge density (more connections = more coherent)
    expected_edges = length(chain.nodes) - 1
    actual_edges = length(chain.edges)
    edge_ratio = min(1.0, actual_edges / max(1, expected_edges))
    
    # Adjust for breaks
    breaks = detect_coherence_breaks(agent, chain_id)
    break_penalty = 0.1 * length(breaks)
    
    # Calculate final confidence
    confidence = (avg_node_conf * 0.6 + edge_ratio * 0.4) - break_penalty
    
    return clamp(confidence, 0.0, 1.0)
end

# ============================================================================
# BACKTRACKING
# ============================================================================

"""
    backtrack_to_state - Revert to a previous reasoning state
"""
function backtrack_to_state(
    agent::MindMapAgent,
    chain_id::String,
    snapshot_index::Int
)::Bool
    
    if !haskey(agent.chain_snapshots, chain_id)
        return false
    end
    
    snapshots = agent.chain_snapshots[chain_id]
    if snapshot_index < 1 || snapshot_index > length(snapshots)
        return false
    end
    
    snapshot = snapshots[snapshot_index]
    
    # Restore nodes
    agent.knowledge_graph = merge(agent.knowledge_graph, 
        Dict{String, KnowledgeNode}(snapshot["nodes"]))
    
    # Restore chain
    if haskey(agent.chains, chain_id)
        agent.chains[chain_id] = snapshot["chain"]
    end
    
    return true
end

"""
    save_chain_snapshot - Save current chain state for potential backtracking
"""
function save_chain_snapshot!(
    agent::MindMapAgent,
    chain_id::String
)
    if !haskey(agent.chains, chain_id)
        return
    end
    
    if !haskey(agent.chain_snapshots, chain_id)
        agent.chain_snapshots[chain_id] = Dict[]
    end
    
    # Create snapshot
    snapshot = Dict{String, Any}(
        "timestamp" => now(),
        "chain" => agent.chains[chain_id],
        "nodes" => Dict(agent.knowledge_graph)
    )
    
    push!(agent.chain_snapshots[chain_id], snapshot)
    
    # Limit snapshots to 10 per chain
    if length(agent.chain_snapshots[chain_id]) > 10
        popfirst!(agent.chain_snapshots[chain_id])
    end
end

# ============================================================================
# PROPOSAL GENERATION
# ============================================================================

"""
    generate_proposal - MindMapAgent generates coherence validation proposal
"""
function generate_proposal(
    agent::MindMapAgent,
    perception::Perception,
    reasoning_context::Dict{String, Any}
)::AgentProposal
    
    # Extract context information
    action = get(reasoning_context, "action", "validate")
    chain_id = get(reasoning_context, "chain_id", "default_chain")
    
    # Update agent state
    agent.state.status = AGENT_THINKING
    agent.state.processing_since = now()
    
    decision = ""
    reasoning_parts = String[]
    evidence = String[]
    
    try
        if action == "validate"
            # Validate chain consistency
            consistency = validate_chain_consistency(agent, chain_id)
            
            if consistency["is_consistent"]
                decision = "chain_valid"
                push!(reasoning_parts, "Chain $chain_id is logically consistent")
            else
                decision = "chain_invalid"
                push!(reasoning_parts, string("Chain ", chain_id, " has inconsistencies: ", join(get(consistency, "issues", String[]), ", ")))
            end
            
            # Get coherence breaks
            breaks = detect_coherence_breaks(agent, chain_id)
            if !isempty(breaks)
                decision = "coherence_breaks_detected"
                push!(reasoning_parts, "Found $(length(breaks)) coherence issues")
                for brk in breaks
                    push!(evidence, string(get(brk, "type", "unknown"), ": ", get(brk, "message", "")))
                end
            end
            
        elseif action == "add_node"
            # Add a new reasoning node
            concept = get(reasoning_context, "concept", "")
            confidence = get(reasoning_context, "confidence", 0.5)
            source = get(reasoning_context, "source", "reasoning")
            
            if isempty(concept)
                decision = "error"
                push!(reasoning_parts, "No concept provided for node")
            else
                # Check for hallucination first
                hallucination_check = check_hallucination(agent, concept)
                
                if hallucination_check["risk_level"] == "high"
                    decision = "hallucination_detected"
                    push!(reasoning_parts, "Hallucination risk detected for: $concept")
                    for contr in hallucination_check["contradictions"]
                        push!(evidence, contr)
                    end
                else
                    # Save snapshot before adding
                    save_chain_snapshot!(agent, chain_id)
                    
                    node_id = add_reasoning_node(agent, chain_id, concept, confidence; source=source)
                    decision = "node_added"
                    push!(reasoning_parts, "Added node '$concept' to chain $chain_id")
                    push!(evidence, "node_id: $node_id")
                    
                    if hallucination_check["verification_needed"]
                        push!(reasoning_parts, "Note: Claim requires verification")
                    end
                end
            end
            
        elseif action == "add_edge"
            # Add a logical relationship
            from_node = get(reasoning_context, "from_node", "")
            to_node = get(reasoning_context, "to_node", "")
            relation = get(reasoning_context, "relation_type", :sequential)
            confidence = get(reasoning_context, "confidence", 1.0)
            
            if isempty(from_node) || isempty(to_node)
                decision = "error"
                push!(reasoning_parts, "Missing node references for edge")
            else
                edge_id = add_reasoning_edge(agent, chain_id, from_node, to_node, relation; confidence=confidence)
                decision = "edge_added"
                push!(reasoning_parts, "Added $(relation) relationship between nodes")
                push!(evidence, "edge_id: $edge_id")
            end
            
        elseif action == "query"
            # Query the knowledge graph
            query = get(reasoning_context, "query", "")
            results = query_knowledge_graph(agent, query; chain_id=chain_id)
            
            decision = "query_results"
            push!(reasoning_parts, "Found $(length(results)) matching entries for: $query")
            for r in results
                r_type = get(r, "type", "unknown")
                r_val = get(r, "concept", get(r, "relation_type", "unknown"))
                push!(evidence, "$r_type: $r_val")
            end
            
        elseif action == "detect_breaks"
            # Detect coherence breaks
            breaks = detect_coherence_breaks(agent, chain_id)
            
            if isempty(breaks)
                decision = "no_breaks"
                push!(reasoning_parts, "No coherence breaks detected in chain $chain_id")
            else
                decision = "breaks_found"
                push!(reasoning_parts, "Detected $(length(breaks)) coherence breaks")
                for brk in breaks
                    push!(evidence, string(get(brk, "type", "unknown"), ": ", get(brk, "message", "")))
                end
            end
            
        elseif action == "check_hallucination"
            # Check for hallucination
            claim = get(reasoning_context, "claim", "")
            check_result = check_hallucination(agent, claim; chain_id=chain_id)
            
            if check_result["is_hallucination"]
                decision = "hallucination_detected"
                push!(reasoning_parts, "High risk of hallucination for: $claim")
            elseif check_result["verification_needed"]
                decision = "verification_needed"
                push!(reasoning_parts, "Claim requires verification: $claim")
            else
                decision = "claim_verified"
                push!(reasoning_parts, "Claim appears valid: $claim")
            end
            
            for e in check_result["supporting_evidence"]
                push!(evidence, e)
            end
            for c in check_result["contradictions"]
                push!(evidence, c)
            end
            
        else
            decision = "unknown_action"
            push!(reasoning_parts, "Unknown action: $action")
        end
        
        # Calculate confidence
        confidence = get_chain_confidence(agent, chain_id)
        
        # Add chain confidence to reasoning if not already
        if !isempty(decision) && decision != "error"
            push!(reasoning_parts, "Chain confidence: $(round(confidence, digits=2))")
        end
        
        # Reset agent state
        agent.state.status = AGENT_IDLE
        agent.state.processing_since = nothing
        
        return AgentProposal(
            agent.id,
            :mindmap,
            decision,
            confidence;
            reasoning = join(reasoning_parts, ". "),
            weight = 0.9,  # High weight for logical validation
            evidence = evidence,
            alternatives = String[]
        )
        
    catch e
        agent.state.status = AGENT_ERROR
        agent.state.error_message = string(e)
        
        return AgentProposal(
            agent.id,
            :mindmap,
            "error",
            0.0;
            reasoning = "Error in MindMapAgent: $(string(e))",
            weight = 0.0,
            evidence = String[],
            alternatives = String[]
        )
    end
end

end # module MindMapAgent
