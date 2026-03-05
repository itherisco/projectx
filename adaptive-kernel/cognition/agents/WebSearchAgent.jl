# cognition/agents/WebSearchAgent.jl - Web Search Agent
# Provides internet retrieval capabilities for the multi-agent hierarchy

module WebSearchAgentModule

using Dates
using UUIDs
using JSON

# Import types (WebSearchAgent is now defined in types.jl)
include("../types.jl")
using ..CognitionTypes

# Import spine
include("../spine/DecisionSpine.jl")
using ..DecisionSpine

# Import safe HTTP capability
include("../../capabilities/safe_http_request.jl")
using ..SafeHTTPRequest

export WebSearchAgent, create_websearch_agent, generate_proposal

# ============================================================================
# WEB SEARCH AGENT TYPE IS NOW DEFINED IN cognition/types.jl
# ============================================================================

# ============================================================================
# FACTORY FUNCTION
# ============================================================================

"""
    create_websearch_agent(id::String = "websearch_001")::WebSearchAgent
    Factory function to create a WebSearchAgent instance
"""
function create_websearch_agent(id::String = "websearch_001")::WebSearchAgent
    return WebSearchAgent(id)
end

# ============================================================================
# MAIN PROPOSAL GENERATION
# ============================================================================

"""
    generate_proposal(agent::WebSearchAgent, perception::Perception, query_context::Dict{String, Any})::AgentProposal
    Analyzes incoming queries for information retrieval needs and generates search strategy proposals
"""
function generate_proposal(
    agent::WebSearchAgent,
    perception::Perception,
    query_context::Dict{String, Any}
)::AgentProposal
    
    # Extract the query from context
    query = get(query_context, "query", "")
    user_intent = get(query_context, "intent", "unknown")
    
    # Analyze query for information retrieval needs
    info_needs = analyze_information_needs(query, user_intent)
    
    # Generate search strategy
    search_strategy = generate_search_strategy(info_needs, query)
    
    # Calculate confidence based on query clarity
    confidence = calculate_search_confidence(query, info_needs)
    
    # Generate evidence URLs
    evidence = generate_evidence_urls(info_needs, query)
    
    # Generate alternative strategies
    alternatives = generate_alternative_strategies(info_needs, query)
    
    # Build reasoning
    reasoning = build_search_reasoning(query, info_needs, confidence)
    
    # Record in search history
    search_record = Dict{String, Any}(
        "query" => query,
        "intent" => user_intent,
        "info_needs" => info_needs,
        "strategy" => search_strategy,
        "timestamp" => string(now())
    )
    push!(agent.search_history, search_record)
    
    return AgentProposal(
        agent.id,
        :websearch,
        search_strategy,
        confidence,
        reasoning = reasoning,
        weight = 0.8,  # Default weight for web search influence
        evidence = evidence,
        alternatives = alternatives
    )
end

# ============================================================================
# QUERY ANALYSIS
# ============================================================================

"""
    analyze_information_needs - Analyze query to determine information retrieval requirements
"""
function analyze_information_needs(query::String, intent::String)::Dict{String, Any}
    info_needs = Dict{String, Any}()
    
    # Check if query actually needs web search
    info_needs["requires_search"] = requires_web_search(query, intent)
    
    # Categorize the type of information needed
    info_needs["info_category"] = categorize_information(query)
    
    # Determine urgency/priority
    info_needs["urgency"] = determine_urgency(query)
    
    # Check for specific URLs or sources mentioned
    info_needs["mentioned_urls"] = extract_mentioned_urls(query)
    
    # Determine required depth (factual, analytical, comprehensive)
    info_needs["depth"] = determine_depth(query)
    
    return info_needs
end

"""
    requires_web_search - Determine if query requires web search
"""
function requires_web_search(query::String, intent::String)::Bool
    # If intent is explicitly about retrieving information
    if intent in ["inform", "research", "lookup", "find", "search"]
        return true
    end
    
    # Check for question patterns that typically need web search
    question_patterns = [
        r"^what (is|are|was|were)",
        r"^how (do|does|did|to)",
        r"^who (is|are|was|were)",
        r"^where (is|are|was|were)",
        r"^when (is|are|was|were)",
        r"^why (is|are|was|were)",
        r"^can (you|i|we)",
        r"search for",
        r"find information",
        r"look up",
        r"latest news",
        r"current.*",
    ]
    
    query_lower = lowercase(query)
    for pattern in question_patterns
        if occursin(pattern, query_lower)
            return true
        end
    end
    
    return false
end

"""
    categorize_information - Categorize what type of information is needed
"""
function categorize_information(query::String)::String
    query_lower = lowercase(query)
    
    # Factual/Definition queries
    if any(occursin(p, query_lower) for p in ["what is", "what are", "definition", "meaning of"])
        return "factual"
    end
    
    # How-to / Tutorial queries
    if any(occursin(p, query_lower) for p in ["how to", "how do", "guide", "tutorial", "steps"])
        return "procedural"
    end
    
    # News / Current events
    if any(occursin(p, query_lower) for p in ["news", "latest", "recent", "current", "update"])
        return "news"
    end
    
    # Technical / API documentation
    if any(occursin(p, query_lower) for p in ["api", "documentation", "spec", "reference", "function"])
        return "technical"
    end
    
    # Research / Analysis
    if any(occursin(p, query_lower) for p in ["research", "analysis", "compare", "vs", "difference"])
        return "research"
    end
    
    return "general"
end

"""
    determine_urgency - Determine how urgent the information need is
"""
function determine_urgency(query::String)::String
    query_lower = lowercase(query)
    
    if any(occursin(p, query_lower) for p in ["urgent", "asap", "immediately", "emergency"])
        return "high"
    elseif any(occursin(p, query_lower) for p in ["soon", "quickly", "today"])
        return "medium"
    end
    
    return "low"
end

"""
    extract_mentioned_urls - Extract any URLs mentioned in the query
"""
function extract_mentioned_urls(query::String)::Vector{String}
    urls = String[]
    url_pattern = r"https?://[^\s\)]+"
    
    for match in eachmatch(url_pattern, query)
        push!(urls, match.match)
    end
    
    return urls
end

"""
    determine_depth - Determine how comprehensive the search needs to be
"""
function determine_depth(query::String)::String
    query_lower = lowercase(query)
    
    if any(occursin(p, query_lower) for p in ["detailed", "comprehensive", "in-depth", "thorough", "complete guide"])
        return "comprehensive"
    elseif any(occursin(p, query_lower) for p in ["brief", "short", "quick", "summary", "overview"])
        return "brief"
    end
    
    return "standard"
end

# ============================================================================
# SEARCH STRATEGY GENERATION
# ============================================================================

"""
    generate_search_strategy - Generate the actual search query/action
"""
function generate_search_strategy(info_needs::Dict{String, Any}, query::String)::String
    # If specific URLs are mentioned, try to retrieve them
    mentioned_urls = get(info_needs, "mentioned_urls", String[])
    if !isempty(mentioned_urls)
        return "retrieve_urls:$(join(mentioned_urls, ","))"
    end
    
    # Determine category and urgency
    category = get(info_needs, "info_category", "general")
    urgency = get(info_needs, "urgency", "low")
    depth = get(info_needs, "depth", "standard")
    
    # Generate search query
    sanitized_query = sanitize_search_query(query)
    
    # Build strategy string
    strategy = "search:$sanitized_query| urgency:$urgency | depth:$depth | category:$category"
    
    return strategy
end

"""
    sanitize_search_query - Sanitize query for safe search
"""
function sanitize_search_query(query::String)::String
    # Remove potentially dangerous characters
    # Keep alphanumeric, spaces, and common punctuation
    sanitized = replace(query, r"[^\w\s\-\.\,\?\!]" => "")
    
    # Limit length
    if length(sanitized) > 200
        sanitized = sanitized[1:200]
    end
    
    return strip(sanitized)
end

"""
    calculate_search_confidence - Calculate confidence based on query clarity
"""
function calculate_search_confidence(query::String, info_needs::Dict{String, Any})::Float64
    base_confidence = 0.5
    
    # Clear, specific queries get higher confidence
    if length(query) > 10 && length(query) < 500
        base_confidence += 0.1
    end
    
    # Question format typically indicates clearer intent
    if occursin(r"\?", query)
        base_confidence += 0.1
    end
    
    # If URLs are mentioned, we know exactly what to retrieve
    mentioned_urls = get(info_needs, "mentioned_urls", String[])
    if !isempty(mentioned_urls)
        base_confidence += 0.25
    end
    
    # Clear category identification
    category = get(info_needs, "info_category", "general")
    if category != "general"
        base_confidence += 0.1
    end
    
    return clamp(base_confidence, 0.0, 1.0)
end

# ============================================================================
# EVIDENCE AND ALTERNATIVES
# ============================================================================

"""
    generate_evidence_urls - Generate URLs to retrieve as evidence
"""
function generate_evidence_urls(info_needs::Dict{String, Any}, query::String)::Vector{String}
    evidence = String[]
    
    # Add any explicitly mentioned URLs
    mentioned_urls = get(info_needs, "mentioned_urls", String[])
    for url in mentioned_urls
        # Validate URL before adding to evidence
        allowed, _ = is_url_allowed(url)
        if allowed
            push!(evidence, url)
        end
    end
    
    # If no explicit URLs, suggest potential sources based on category
    if isempty(evidence)
        category = get(info_needs, "info_category", "general")
        suggested = suggest_sources(category, query)
        append!(evidence, suggested)
    end
    
    return evidence
end

"""
    suggest_sources - Suggest relevant sources based on information category
"""
function suggest_sources(category::String, query::String)::Vector{String}
    sources = String[]
    
    # Note: These are placeholder suggestions - actual implementation would
    # use a more sophisticated source selection algorithm
    
    if category == "factual"
        push!(sources, "https://en.wikipedia.org/wiki/")
    elseif category == "news"
        # Would add news APIs in production
        push!(sources, "https://httpbin.org/json")
    elseif category == "technical"
        push!(sources, "https://api.github.com")
    end
    
    return sources
end

"""
    generate_alternative_strategies - Generate alternative search strategies
"""
function generate_alternative_strategies(info_needs::Dict{String, Any}, query::String)::Vector{String}
    alternatives = String[]
    
    # Alternative 1: Broader search terms
    broader = "search:$(query) $(extract_keywords(query, 2))"
    push!(alternatives, broader)
    
    # Alternative 2: More specific search
    specific = "search:$(query) -tutorial -guide"
    push!(alternatives, specific)
    
    # Alternative 3: Different category
    category = get(info_needs, "info_category", "general")
    if category != "general"
        alt_category = category == "factual" ? "technical" : "factual"
        alt = "search:$query (category:$alt_category)"
        push!(alternatives, alt)
    end
    
    return alternatives
end

"""
    extract_keywords - Extract key terms from query for alternatives
"""
function extract_keywords(query::String, count::Int)::String
    # Simple keyword extraction - split on spaces and take significant words
    words = split(query)
    keywords = String[]
    
    # Filter out common stop words
    stop_words = ["the", "a", "an", "is", "are", "was", "were", "to", "for", "of", "in", "on", "how", "what", "why", "when", "where", "who"]
    
    for word in words
        word_lower = lowercase(word)
        if word_lower ∉ stop_words && length(word) > 3
            push!(keywords, word)
        end
    end
    
    return join(keywords[1:min(count, length(keywords))], " ")
end

"""
    build_search_reasoning - Build human-readable reasoning for the proposal
"""
function build_search_reasoning(query::String, info_needs::Dict{String, Any}, confidence::Float64)::String
    requires_search = get(info_needs, "requires_search", false)
    category = get(info_needs, "info_category", "unknown")
    urgency = get(info_needs, "urgency", "low")
    depth = get(info_needs, "depth", "standard")
    
    if !requires_search
        return "Query does not require web search - direct answer possible"
    end
    
    reasoning_parts = String[]
    push!(reasoning_parts, "Information retrieval needed")
    push!(reasoning_parts, "Category: $category")
    push!(reasoning_parts, "Urgency: $urgency")
    push!(reasoning_parts, "Depth: $depth")
    push!(reasoning_parts, "Confidence: $(round(confidence * 100))%")
    
    return join(reasoning_parts, ". ") * "."
end

# ============================================================================
# HTTP RETRIEVAL (using safe_http_request)
# ============================================================================

"""
    retrieve_url_safely - Safely retrieve content from a URL using safe_http_request
"""
function retrieve_url_safely(agent::WebSearchAgent, url::String)::Dict{String, Any}
    # Use the safe HTTP request capability
    params = Dict{String, Any}(
        "url" => url,
        "max_response_size" => 1024,  # 1KB limit for snippets
        "timeout" => 3
    )
    
    result = execute(params)
    
    # Track success/failure
    if get(result, "success", false)
        agent.successful_retrievals += 1
    else
        agent.failed_retrievals += 1
    end
    
    return result
end

# ============================================================================
# METRICS AND TRACKING
# ============================================================================

"""
    get_retrieval_accuracy - Calculate the agent's retrieval accuracy
"""
function get_retrieval_accuracy(agent::WebSearchAgent)::Float64
    total = agent.successful_retrievals + agent.failed_retrievals
    if total == 0
        return 0.0
    end
    return agent.successful_retrievals / total
end

end # module WebSearchAgentModule
