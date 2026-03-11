# jarvis/src/nlp/NLPGateway.jl - NLP Gateway for ITHERIS Brain Integration
# Provides feature encoding and goal construction for semantic memory integration

module NLPGateway

using Dates
using UUIDs
using JSON
using Logging
using SHA

# This module returns Dict with symbol-based priority/trust values
# Caller converts symbols to JarvisTypes enums when creating JarvisGoal
export 
    # Feature encoding
    generate_feature_vector,
    FeatureVector,
    
    # Goal construction
    construct_goal,
    GoalContext,
    
    # Doctrine types
    DoctrineConstraint,
    
    # NLP utilities
    extract_keywords,
    detect_urgency,
    classify_intent

# ============================================================================
# FEATURE VECTOR TYPES
# ============================================================================

"""
    FeatureVector - 12-Dimensional intent feature vector for ITHERIS brain
    
    Categories (indices):
    1.  Urgency      - How time-critical is the request?
    2.  Social       - Does it involve social interactions?
    3.  Technical    - Is it technical in nature?
    4.  Financial    - Does it involve financial matters?
    5.  Security     - Is security-related?
    6.  System       - Does it involve system operations?
    7.  Personal     - Is it personal in nature?
    8.  Research     - Is it a research/information request?
    9.  Creative     - Does it require creative output?
    10. Risk         - What's the risk level?
    11. Reward       - What's the potential reward?
    12. Complexity   - How complex is the task?
"""
struct FeatureVector
    urgency::Float32
    social::Float32
    technical::Float32
    financial::Float32
    security::Float32
    system::Float32
    personal::Float32
    research::Float32
    creative::Float32
    risk::Float32
    reward::Float32
    complexity::Float32
    
    function FeatureVector(
        urgency::Float32, social::Float32, technical::Float32,
        financial::Float32, security::Float32, system::Float32,
        personal::Float32, research::Float32, creative::Float32,
        risk::Float32, reward::Float32, complexity::Float32
    )
        new(
            clamp(urgency, 0f0, 1f0),
            clamp(social, 0f0, 1f0),
            clamp(technical, 0f0, 1f0),
            clamp(financial, 0f0, 1f0),
            clamp(security, 0f0, 1f0),
            clamp(system, 0f0, 1f0),
            clamp(personal, 0f0, 1f0),
            clamp(research, 0f0, 1f0),
            clamp(creative, 0f0, 1f0),
            clamp(risk, 0f0, 1f0),
            clamp(reward, 0f0, 1f0),
            clamp(complexity, 0f0, 1f0)
        )
    end
end

# Convert to Vector for neural network
Base.Vector(fv::FeatureVector) = Float32[
    fv.urgency, fv.social, fv.technical, fv.financial,
    fv.security, fv.system, fv.personal, fv.research,
    fv.creative, fv.risk, fv.reward, fv.complexity
]

# ============================================================================
# DOCTRINE CONSTRAINT TYPES
# ============================================================================

"""
    DoctrineConstraint - A constraint retrieved from semantic memory
    Represents user preferences and operational constraints
"""
struct DoctrineConstraint
    id::UUID
    category::Symbol        # :privacy, :safety, :behavior, :interface, :custom
    description::String
    priority::Int           # 1-10, higher = more important
    enforce::Bool           # Whether this is a hard constraint
    source::String          # Where this constraint came from
    
    function DoctrineConstraint(
        category::Symbol,
        description::String;
        priority::Int = 5,
        enforce::Bool = true,
        source::String = "user_preference"
    )
        new(uuid4(), category, description, priority, enforce, source)
    end
end

"""
    GoalContext - Context for goal construction
    Contains the user input and retrieved memories
"""
struct GoalContext
    user_input::String
    feature_vector::FeatureVector
    retrieved_memories::Vector{Tuple{String, Float32}}  # (content, similarity)
    constraints::Vector{DoctrineConstraint}
    timestamp::DateTime
    
    function GoalContext(
        user_input::String,
        feature_vector::FeatureVector,
        retrieved_memories::Vector{Tuple{String, Float32}};
        constraints::Vector{DoctrineConstraint} = DoctrineConstraint[]
    )
        new(user_input, feature_vector, retrieved_memories, constraints, now())
    end
end

# ============================================================================
# FEATURE VECTOR GENERATION - Keyword dictionaries for classification
# ============================================================================

#
const URGENCY_KEYWORDS = [
    "urgent", "asap", "immediately", "now", "emergency", "critical",
    "deadline", "fast", "quick", "rush", "hurry", "pressing", "crucial"
]

const SOCIAL_KEYWORDS = [
    "talk", "chat", "discuss", "share", "friend", "team", "collaborate",
    "meeting", "communicate", "message", "email", "social", "community"
]

const TECHNICAL_KEYWORDS = [
    "code", "debug", "implement", "api", "function", "class", "algorithm",
    "software", "programming", "developer", "engineer", "technical", "system",
    "architecture", "database", "server", "deploy", "build", "compile"
]

const FINANCIAL_KEYWORDS = [
    "money", "cost", "price", "budget", "invoice", "payment", "financial",
    "investment", "stock", "trading", "bank", "transaction", "revenue",
    "profit", "expense", "finance", "dollar", "bitcoin", "crypto"
]

const SECURITY_KEYWORDS = [
    "security", "password", "encrypt", "auth", "permission", "access",
    "firewall", "vulnerability", "threat", "attack", "protect", "secure",
    "privacy", "token", "credential", "cert", "ssl", "tls", "safe"
]

const SYSTEM_KEYWORDS = [
    "system", "monitor", "process", "cpu", "memory", "disk", "network",
    "server", "config", "setup", "install", "update", "upgrade", "restart",
    "service", "daemon", "cron", "schedule", "automate"
]

const PERSONAL_KEYWORDS = [
    "personal", "private", "my", "mine", "i", "me", "my", "home",
    "family", "life", "reminder", "note", "calendar", "appointment"
]

const RESEARCH_KEYWORDS = [
    "research", "find", "search", "lookup", "information", "learn",
    "explain", "what", "how", "why", "when", "where", "who", "understand",
    "document", "article", "paper", "study", "analysis", "compare"
]

const CREATIVE_KEYWORDS = [
    "create", "write", "design", "art", "creative", "generate", "compose",
    "poem", "story", "blog", "content", "video", "image", "music", "song",
    "brainstorm", "idea", "innovate", "novel", "original"
]

const RISK_KEYWORDS = [
    "risk", "danger", "harmful", "dangerous", "unsafe", "warning", "caution",
    "careful", "carefully", "might", "could", "possibly", "probably",
    "uncertain", "doubtful", "concern", "worry", "problem", "issue"
]

const REWARD_KEYWORDS = [
    "benefit", "advantage", "help", "useful", "value", "important",
    "improve", "better", "best", "great", "excellent", "amazing", "wonderful",
    "success", "achieve", "goal", "objective", "outcome", "result"
]

const COMPLEXITY_KEYWORDS = [
    "complex", "complicated", "difficult", "hard", "simple", "easy",
    "straightforward", "challenging", "advanced", "basic", "detailed",
    "comprehensive", "thorough", "in-depth", "quick", "brief", "summary"
]

"""
    _count_matches - Count keyword matches in text
"""
function _count_matches(text::String, keywords::Vector{String})::Int
    text_lower = lowercase(text)
    count = 0
    for kw in keywords
        if occursin(kw, text_lower)
            count += 1
        end
    end
    return count
end

"""
    _calculate_score - Calculate a normalized score from keyword matches
"""
function _calculate_score(text::String, keywords::Vector{String})::Float32
    matches = _count_matches(text, keywords)
    # Normalize based on expected match count (1-3 is typical)
    score = min(1.0f0, matches / 2.0f0)
    return score
end

"""
    generate_feature_vector - Map text intent to 12-dimensional feature vector
    
    This function analyzes the user's natural language input and maps it
    to a 12-dimensional vector that aligns with the ITHERIS Brain's 
    input requirements.
    
    # Arguments
    - `input::String`: The natural language user input
    
    # Returns
    - `FeatureVector`: A 12-dimensional feature vector with values in [0, 1]
    
    # Example
    ```julia
    fv = generate_feature_vector("I need to urgently fix a security vulnerability in my API")
    # Returns FeatureVector with high urgency and security scores
    ```
"""
function generate_feature_vector(input::String)::FeatureVector
    # Calculate each dimension based on keyword matching
    urgency = _calculate_score(input, URGENCY_KEYWORDS)
    social = _calculate_score(input, SOCIAL_KEYWORDS)
    technical = _calculate_score(input, TECHNICAL_KEYWORDS)
    financial = _calculate_score(input, FINANCIAL_KEYWORDS)
    security = _calculate_score(input, SECURITY_KEYWORDS)
    system = _calculate_score(input, SYSTEM_KEYWORDS)
    personal = _calculate_score(input, PERSONAL_KEYWORDS)
    research = _calculate_score(input, RESEARCH_KEYWORDS)
    creative = _calculate_score(input, CREATIVE_KEYWORDS)
    risk = _calculate_score(input, RISK_KEYWORDS)
    reward = _calculate_score(input, REWARD_KEYWORDS)
    complexity = _calculate_score(input, COMPLEXITY_KEYWORDS)
    
    # Apply heuristics for better classification
    # Increase urgency for time-related patterns
    if occursin(r"\d+\s*(hour|minute|second|day|week)", lowercase(input))
        urgency = min(1.0f0, urgency + 0.3f0)
    end
    
    # Increase technical for code-like patterns
    if occursin(r"(function|class|def|var|let|const|import|export)", lowercase(input))
        technical = min(1.0f0, technical + 0.3f0)
    end
    
    # Increase financial for numbers with currency
    if occursin(r"(\$|€|£|usd|eur|gbp|\d+\s*(dollar|euro|pound))", lowercase(input))
        financial = min(1.0f0, financial + 0.3f0)
    end
    
    # Complexity inference from request length and structure
    word_count = length(split(input))
    if word_count > 50
        complexity = min(1.0f0, complexity + 0.2f0)
    elseif word_count < 10
        complexity = max(0.0f0, complexity - 0.2f0)
    end
    
    # Risk/reward balance inference
    if risk > 0.3f0 && reward < 0.3f0
        # High risk, low reward - adjust towards caution
        risk = min(1.0f0, risk + 0.1f0)
    elseif reward > 0.3f0 && risk < 0.3f0
        # High reward, low risk - adjust positively
        reward = min(1.0f0, reward + 0.1f0)
    end
    
    return FeatureVector(
        urgency, social, technical, financial,
        security, system, personal, research,
        creative, risk, reward, complexity
    )
end

"""
    extract_keywords - Extract important keywords from input
"""
function extract_keywords(input::String; top_n::Int = 5)::Vector{String}
    # Simple keyword extraction based on word frequency
    # In production, would use NLP techniques like TF-IDF
    words = split(lowercase(input))
    
    # Filter out common stop words
    stop_words = Set(["the", "a", "an", "is", "are", "was", "were", "be", 
                      "been", "being", "have", "has", "had", "do", "does",
                      "did", "will", "would", "could", "should", "may", "might",
                      "must", "shall", "can", "need", "to", "of", "in", "for",
                      "on", "with", "at", "by", "from", "as", "into", "through",
                      "that", "this", "these", "those", "i", "you", "he", "she",
                      "it", "we", "they", "what", "which", "who", "whom", "how",
                      "and", "or", "but", "if", "then", "else", "when", "where",
                      "why", "all", "each", "every", "both", "few", "more", "most",
                      "other", "some", "such", "no", "not", "only", "same", "so",
                      "than", "too", "very", "just", "also", "now", "here", "there"])
    
    filtered = [w for w in words if w ∉ stop_words && length(w) > 2]
    
    # Return top N
    return filtered[1:min(top_n, length(filtered))]
end

"""
    detect_urgency - Detect urgency level from input
"""
function detect_urgency(input::String)::Float32
    return generate_feature_vector(input).urgency
end

"""
    classify_intent - Classify the primary intent of the input
"""
function classify_intent(input::String)::Symbol
    fv = generate_feature_vector(input)
    vec = Vector(fv)
    
    # Find the highest scoring dimension
    categories = [:urgency, :social, :technical, :financial, :security,
                  :system, :personal, :research, :creative, :risk, 
                  :reward, :complexity]
    
    max_idx = argmax(vec)
    return categories[max_idx]
end

# ============================================================================
# GOAL CONSTRUCTION
# ============================================================================

"""
    _extract_doctrine_constraints - Extract doctrine constraints from retrieved memories
"""
function _extract_doctrine_constraints(
    memories::Vector{Tuple{String, Float32}}
)::Vector{DoctrineConstraint}
    
    constraints = DoctrineConstraint[]
    
    for (content, similarity) in memories
        # Check for preference-like content
        if similarity > 0.7
            # High relevance - extract as potential constraint
            if occursin("prefer", lowercase(content)) || 
               occursin("always", lowercase(content)) ||
               occursin("never", lowercase(content))
                
                push!(DoctrineConstraint(
                    :preference,
                    content;
                    priority = round(Int, similarity * 10),
                    enforce = similarity > 0.85,
                    source = "semantic_memory"
                ))
            end
        end
    end
    
    return constraints
end

"""
    _generate_success_condition - Generate a success condition from input
"""
function _generate_success_condition(
    input::String,
    context::Vector{Tuple{String, Float32}}
)::String
    
    # Build success condition based on input and context
    keywords = extract_keywords(input)
    
    if isempty(context)
        return "Successfully process user request: '$input'"
    else
        # Include relevant context
        relevant = join([c[1] for c in context[1:min(2, length(context))]], "; ")
        return "Complete user request '$input' while respecting context: $relevant"
    end
end

"""
    construct_goal - Construct a Goal object from NLP input and context vectors
    
    This function takes the current user input AND the Top-3 retrieved memories
    from the vector store and produces a Goal object that includes:
    1. A clear success condition
    2. A list of Doctrine Constraints (retrieved from memory preferences)
    
    # Arguments
    - `nlp_input::String`: The natural language user input
    - `context_vectors::Vector{Tuple{String, Float32}}`: Retrieved memories as (content, similarity) tuples
    
    # Returns
    - `JarvisGoal`: A fully constructed goal with success condition and constraints
    
    # Example
    ```julia
    memories = [("User prefers detailed explanations", 0.85), ("User is a developer", 0.72)]
    goal = construct_goal("How does the API work?", memories)
    # Returns JarvisGoal with success condition and extracted constraints
    ```
"""
function construct_goal(
    nlp_input::String,
    context_vectors::Vector{Tuple{String, Float32}}
)::JarvisGoal
    
    # Generate feature vector from input
    feature_vec = generate_feature_vector(nlp_input)
    
    # Get top 3 most relevant memories (already sorted by similarity)
    top_memories = context_vectors[1:min(3, length(context_vectors))]
    
    # Extract doctrine constraints from memories
    constraints = _extract_doctrine_constraints(top_memories)
    
    # Generate success condition
    success_condition = _generate_success_condition(nlp_input, top_memories)
    
    # Determine priority based on urgency (symbols to avoid enum dependency)
    urgency = feature_vec.urgency
    priority_sym = if urgency > 0.7
        :critical
    elseif urgency > 0.5
        :high
    elseif urgency > 0.3
        :medium
    elseif urgency > 0.1
        :low
    else
        :background
    end
    
    # Determine required trust based on security dimension (symbols)
    trust_sym = if feature_vec.security > 0.7
        :full
    elseif feature_vec.security > 0.4
        :standard
    elseif feature_vec.financial > 0.5
        :limited
    else
        :restricted
    end
    
    # Calculate deadline based on urgency
    deadline = if urgency > 0.7
        now() + Minute(5)
    elseif urgency > 0.5
        now() + Minute(30)
    elseif urgency > 0.3
        now() + Hour(1)
    elseif urgency > 0.1
        now() + Hour(4)
    else
        now() + Hour(24)
    end
    
    # Create GoalContext with symbol-based values (caller will convert to JarvisGoal)
    target_vector = Vector(feature_vec)
    
    # Return a dict with all the info needed to create JarvisGoal
    goal_data = Dict(
        "description" => success_condition,
        "target_vector" => target_vector,
        "priority_symbol" => priority_sym,
        "trust_symbol" => trust_sym,
        "deadline" => deadline
    )
    
    return goal_data
end

# ============================================================================
# SERIALIZATION
# ============================================================================

"""
    to_dict - Convert FeatureVector to Dict
"""
function to_dict(fv::FeatureVector)::Dict{String, Any}
    return Dict(
        "urgency" => fv.urgency,
        "social" => fv.social,
        "technical" => fv.technical,
        "financial" => fv.financial,
        "security" => fv.security,
        "system" => fv.system,
        "personal" => fv.personal,
        "research" => fv.research,
        "creative" => fv.creative,
        "risk" => fv.risk,
        "reward" => fv.reward,
        "complexity" => fv.complexity
    )
end

"""
    to_dict - Convert DoctrineConstraint to Dict
"""
function to_dict(dc::DoctrineConstraint)::Dict{String, Any}
    return Dict(
        "id" => string(dc.id),
        "category" => string(dc.category),
        "description" => dc.description,
        "priority" => dc.priority,
        "enforce" => dc.enforce,
        "source" => dc.source
    )
end

"""
    to_dict - Convert GoalContext to Dict
"""
function to_dict(gc::GoalContext)::Dict{String, Any}
    return Dict(
        "user_input" => gc.user_input,
        "feature_vector" => to_dict(gc.feature_vector),
        "retrieved_memories" => [
            Dict("content" => m[1], "similarity" => m[2]) 
            for m in gc.retrieved_memories
        ],
        "constraints" => [to_dict(c) for c in gc.constraints],
        "timestamp" => string(gc.timestamp)
    )
end

end # module NLPGateway
