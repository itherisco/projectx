# adaptive-kernel/cognition/metacognition/SelfModel.jl
# Component 10: Self-Model/Metacognition - JARVIS Neuro-Symbolic Architecture
# Provides explicit self-representation with capability awareness

module SelfModel

using Statistics

export 
    SelfModel,
    introspect,
    estimate_uncertainty,
    calibrate_confidence!,
    assess_capabilities,
    update_capability!,
    identify_knowledge_boundary,
    update_knowledge!,
    check_cognitive_health,
    should_defer_decision,
    explain_reasoning,
    get_confidence_statement

# ============================================================================
# SELF-MODEL STRUCT
# ============================================================================

"""
    SelfModel - Explicit self-representation with capability awareness

# Fields
- `capabilities::Dict{Symbol, Float32}` - Capability scores (:reasoning, :planning, :learning, :memory)
- `capability_confidence::Dict{Symbol, Float32}` - Confidence in each capability estimate
- `known_domains::Vector{Symbol}` - Domains the system knows about
- `unknown_domains::Vector{Symbol}` - Domains the system doesn't know about  
- `knowledge_confidence::Float32` - Overall confidence in knowledge boundaries
- `cognitive_health::Float32` - Cognitive health (0.0-1.0)
- `resource_health::Float32` - CPU/memory availability (0.0-1.0)
- `error_rate::Float32` - Current error rate
- `recent_accuracy::Float32` - Recent decision accuracy
- `decision_latency_ms::Float32` - Decision latency in milliseconds
- `cycles_since_review::Int` - Cycles since last self-review
- `uncertainty_estimate::Float32` - Current uncertainty in self-assessment
- `calibration_error::Float32` - Difference between confidence and actual accuracy
"""
mutable struct SelfModel
    # Capability awareness
    capabilities::Dict{Symbol, Float32}
    capability_confidence::Dict{Symbol, Float32}
    
    # Knowledge boundaries
    known_domains::Vector{Symbol}
    unknown_domains::Vector{Symbol}
    knowledge_confidence::Float32
    
    # Health state
    cognitive_health::Float32
    resource_health::Float32
    error_rate::Float32
    
    # Performance metrics
    recent_accuracy::Float32
    decision_latency_ms::Float32
    cycles_since_review::Int
    
    # Confidence tracking
    uncertainty_estimate::Float32
    calibration_error::Float32
    
    # Internal tracking for calibration
    _prediction_history::Vector{Float32}
    _outcome_history::Vector{Bool}
    
    function SelfModel()
        new(
            # Capabilities with default values
            Dict{Symbol, Float32}(
                :reasoning => 0.7f0,
                :planning => 0.6f0,
                :learning => 0.5f0,
                :memory => 0.8f0
            ),
            Dict{Symbol, Float32}(
                :reasoning => 0.8f0,
                :planning => 0.7f0,
                :learning => 0.6f0,
                :memory => 0.9f0
            ),
            # Knowledge boundaries
            Symbol[],
            Symbol[],
            0.5f0,
            # Health state
            1.0f0,
            1.0f0,
            0.0f0,
            # Performance metrics
            0.7f0,
            100.0f0,
            0,
            # Confidence tracking
            0.3f0,
            0.1f0,
            # Internal tracking
            Float32[],
            Bool[]
        )
    end
end

# ============================================================================
# INTROSPECTION
# ============================================================================

"""
    introspect(self_model::SelfModel; deep::Bool=false)::Dict{Symbol, Any}
    
Perform self-examination and return comprehensive self-assessment.

# Arguments
- `self_model::SelfModel` - The self-model to introspect
- `deep::Bool=false` - Whether to perform deep introspection

# Returns
- `Dict{Symbol, Any}` - Comprehensive self-assessment including capabilities, health, and boundaries
"""
function introspect(
    self_model::SelfModel;
    deep::Bool=false
)::Dict{Symbol, Any}
    # Evaluate overall cognitive health
    health = check_cognitive_health(self_model)
    
    # Build introspection result
    result = Dict{Symbol, Any}(
        :timestamp => time(),
        :health => health,
        :capabilities => deepcopy(self_model.capabilities),
        :knowledge_boundaries => Dict(
            :known => deepcopy(self_model.known_domains),
            :unknown => deepcopy(self_model.unknown_domains),
            :confidence => self_model.knowledge_confidence
        ),
        :performance => Dict(
            :recent_accuracy => self_model.recent_accuracy,
            :latency_ms => self_model.decision_latency_ms,
            :error_rate => self_model.error_rate
        ),
        :confidence => Dict(
            :uncertainty => self_model.uncertainty_estimate,
            :calibration_error => self_model.calibration_error
        )
    )
    
    if deep
        # Deep introspection includes capability confidence and recommendations
        result[:capability_confidence] = deepcopy(self_model.capability_confidence)
        result[:resource_health] = self_model.resource_health
        
        # Generate recommendations based on state
        recommendations = String[]
        
        if health < 0.5
            push!(recommendations, "Low cognitive health - consider deferring complex decisions")
        end
        
        if self_model.uncertainty_estimate > 0.6
            push!(recommendations, "High uncertainty - recommend human consultation")
        end
        
        if self_model.calibration_error > 0.2
            push!(recommendations, "Poor confidence calibration -需要进行重新校准")
        end
        
        if self_model.cycles_since_review > 100
            push!(recommendations, "Self-review overdue - schedule introspection")
        end
        
        result[:recommendations] = recommendations
        result[:cycles_since_review] = self_model.cycles_since_review
    end
    
    # Increment cycles since review
    self_model.cycles_since_review += 1
    
    return result
end

# ============================================================================
# UNCERTAINTY ESTIMATION
# ============================================================================

"""
    estimate_uncertainty(self_model::SelfModel, decision::Dict)::Float32

Estimate uncertainty in a decision based on knowledge boundaries and capabilities.

# Arguments
- `self_model::SelfModel` - The self-model
- `decision::Dict` - The decision to evaluate (should contain :context, :domain, :required_capabilities)

# Returns
- `Float32` - Uncertainty estimate between 0.0 (certain) and 1.0 (uncertain)
"""
function estimate_uncertainty(
    self_model::SelfModel,
    decision::Dict
)::Float32
    uncertainty = 0.0f0
    
    # Check domain knowledge
    if haskey(decision, :domain)
        domain = decision[:domain]
        if domain in self_model.unknown_domains
            uncertainty += 0.4f0
        elseif domain in self_model.known_domains
            uncertainty -= 0.1f0
        else
            uncertainty += 0.2f0  # Unknown if known or not
        end
    end
    
    # Check required capabilities
    if haskey(decision, :required_capabilities)
        for cap in decision[:required_capabilities]
            if cap in keys(self_model.capabilities)
                cap_uncertainty = 1.0f0 - self_model.capabilities[cap]
                uncertainty += cap_uncertainty * 0.15f0
            else
                uncertainty += 0.3f0  # Unknown capability
            end
        end
    end
    
    # Factor in current uncertainty estimate (autocorrelation)
    uncertainty += self_model.uncertainty_estimate * 0.1f0
    
    # Factor in calibration error
    uncertainty += self_model.calibration_error * 0.2f0
    
    # Clamp to [0, 1]
    return clamp(uncertainty, 0.0f0, 1.0f0)
end

"""
    calibrate_confidence!(self_model::SelfModel, predictions::Vector, outcomes::Vector)

Update confidence calibration based on prediction accuracy.

# Arguments
- `self_model::SelfModel` - The self-model to update
- `predictions::Vector` - Vector of predicted probabilities
- `outcome::Vector` - Vector of actual outcomes (true/false)
"""
function calibrate_confidence!(
    self_model::SelfModel,
    predictions::Vector,
    outcomes::Vector
)
    n = min(length(predictions), length(outcomes))
    n == 0 && return
    
    # Add to history
    append!(self_model._prediction_history, predictions[1:n])
    append!(self_model._outcome_history, outcomes[1:n])
    
    # Keep only recent history (last 100)
    if length(self_model._prediction_history) > 100
        self_model._prediction_history = self_model._prediction_history[end-99:end]
        self_model._outcome_history = self_model._outcome_history[end-99:end]
    end
    
    # Calculate calibration error
    # Compare predicted confidence to actual accuracy
    if length(self_model._prediction_history) >= 10
        total_error = 0.0f0
        count = 0
        
        for (pred, outcome) in zip(self_model._prediction_history, self_model._outcome_history)
            actual = outcome ? 1.0f0 : 0.0f0
            total_error += abs(pred - actual)
            count += 1
        end
        
        self_model.calibration_error = total_error / count
        
        # Update uncertainty estimate based on calibration
        self_model.uncertainty_estimate = self_model.calibration_error + 
            (1.0f0 - self_model.cognitive_health) * 0.1f0
    end
end

# ============================================================================
# CAPABILITY AWARENESS
# ============================================================================

"""
    assess_capabilities(self_model::SelfModel, task_context::Dict)::Dict{Symbol, Float32}

Assess current capabilities for a specific task context.

# Arguments
- `self_model::SelfModel` - The self-model
- `task_context::Dict` - Task context containing :task_type, :complexity, :required_capabilities

# Returns
- `Dict{Symbol, Float32}` - Capability scores for the task
"""
function assess_capabilities(
    self_model::SelfModel,
    task_context::Dict
)::Dict{Symbol, Float32}
    scores = Dict{Symbol, Float32}()
    
    # Determine which capabilities are needed
    required = get(task_context, :required_capabilities, [:reasoning, :planning])
    complexity = get(task_context, :complexity, 0.5f0)
    
    for cap in required
        if cap in keys(self_model.capabilities)
            base_score = self_model.capabilities[cap]
            conf = get(self_model.capability_confidence, cap, 0.5f0)
            
            # Adjust for complexity (higher complexity reduces effective capability)
            complexity_factor = 1.0f0 - (complexity * 0.3f0)
            
            # Adjust for confidence (low confidence reduces reliability)
            reliability_factor = 0.5f0 + (conf * 0.5f0)
            
            scores[cap] = base_score * complexity_factor * reliability_factor
        else
            scores[cap] = 0.0f0  # Unknown capability
        end
    end
    
    return scores
end

"""
    update_capability!(self_model::SelfModel, capability::Symbol, performance::Float32)

Update capability estimate based on recent performance.

# Arguments
- `self_model::SelfModel` - The self-model to update
- `capability::Symbol` - The capability to update (:reasoning, :planning, :learning, :memory)
- `performance::Float32` - Recent performance metric (0.0-1.0)
"""
function update_capability!(
    self_model::SelfModel,
    capability::Symbol,
    performance::Float32
)
    if capability in keys(self_model.capabilities)
        # Smooth update using exponential moving average
        # Learning rate depends on how certain we are
        learning_rate = 0.2f0
        
        old_value = self_model.capabilities[capability]
        new_value = old_value + learning_rate * (performance - old_value)
        
        self_model.capabilities[capability] = clamp(new_value, 0.0f0, 1.0f0)
        
        # Update capability confidence based on consistency
        # (simplified - in reality would track variance)
        current_conf = get(self_model.capability_confidence, capability, 0.5f0)
        consistency = 1.0f0 - abs(performance - old_value)
        new_conf = current_conf + 0.1f0 * (consistency - current_conf)
        self_model.capability_confidence[capability] = clamp(new_conf, 0.0f0, 1.0f0)
    end
end

# ============================================================================
# KNOWLEDGE BOUNDARIES
# ============================================================================

"""
    identify_knowledge_boundary(self_model::SelfModel, query::String)::Bool

Check if a query falls outside known knowledge boundaries.

# Arguments
- `self_model::SelfModel` - The self-model
- `query::String` - The query to check

# Returns
- `Bool` - true if the query is in an unknown domain, false otherwise
"""
function identify_knowledge_boundary(
    self_model::SelfModel,
    query::String
)::Bool
    # Simple heuristic: check if query contains keywords from unknown domains
    # In a real implementation, this would use embeddings or a classifier
    
    query_lower = lowercase(query)
    
    # Check against unknown domains
    for domain in self_model.unknown_domains
        domain_keywords = get_domain_keywords(domain)
        for keyword in domain_keywords
            if occursin(keyword, query_lower)
                return true  # Query is in unknown domain
            end
        end
    end
    
    # Also check for completely unfamiliar terms
    unfamiliar_indicators = ["quantum", "relativistic", "biochemical", "philosophical"]
    for indicator in unfamiliar_indicators
        if occursin(indicator, query_lower)
            # Check if we've learned about this
            if !in(Symbol(indicator), self_model.known_domains)
                return true
            end
        end
    end
    
    return false
end

"""
    get_domain_keywords(domain::Symbol)::Vector{String}

Get keywords associated with a domain for boundary detection.
"""
function get_domain_keywords(domain::Symbol)::Vector{String}
    keywords = Dict(
        :programming => ["code", "function", "variable", "algorithm", "debug"],
        :mathematics => ["equation", "derivative", "integral", "matrix", "vector"],
        :science => ["hypothesis", "experiment", "theory", "observation"],
        :language => ["grammar", "syntax", "semantic", "phoneme", "morphology"],
        :history => ["century", "era", "civilization", "dynasty", "war"],
        :arts => ["composition", "technique", "medium", "genre", "movement"]
    )
    return get(keywords, domain, String[])
end

"""
    update_knowledge!(self_model::SelfModel, domain::Symbol, known::Bool)

Update knowledge boundaries when a domain is learned or identified as unknown.

# Arguments
- `self_model::SelfModel` - The self-model to update
- `domain::Symbol` - The domain to update
- `known::Bool` - true if domain is now known, false if unknown
"""
function update_knowledge!(
    self_model::SelfModel,
    domain::Symbol,
    known::Bool
)
    if known
        # Add to known, remove from unknown
        if domain in self_model.unknown_domains
            filter!(d -> d != domain, self_model.unknown_domains)
        end
        if !(domain in self_model.known_domains)
            push!(self_model.known_domains, domain)
        end
        # Increase knowledge confidence
        self_model.knowledge_confidence = min(1.0f0, self_model.knowledge_confidence + 0.1f0)
    else
        # Add to unknown, remove from known
        if domain in self_model.known_domains
            filter!(d -> d != domain, self_model.known_domains)
        end
        if !(domain in self_model.unknown_domains)
            push!(self_model.unknown_domains, domain)
        end
        # Decrease knowledge confidence
        self_model.knowledge_confidence = max(0.0f0, self_model.knowledge_confidence - 0.1f0)
    end
end

# ============================================================================
# HEALTH MONITORING
# ============================================================================

"""
    check_cognitive_health(self_model::SelfModel)::Float32

Evaluate cognitive health based on error rate, latency, and resource availability.

# Arguments
- `self_model::SelfModel` - The self-model to evaluate

# Returns
- `Float32` - Health score between 0.0 (unhealthy) and 1.0 (healthy)
"""
function check_cognitive_health(
    self_model::SelfModel
)::Float32
    # Weight factors for health components
    error_weight = 0.4f0
    latency_weight = 0.3f0
    resource_weight = 0.3f0
    
    # Error rate contribution (lower is better)
    error_health = 1.0f0 - self_model.error_rate
    error_health = clamp(error_health, 0.0f0, 1.0f0)
    
    # Latency contribution (assuming 100ms is baseline acceptable)
    baseline_latency = 100.0f0
    latency_ratio = baseline_latency / max(self_model.decision_latency_ms, 1.0f0)
    latency_health = clamp(latency_ratio, 0.0f0, 1.0f0)
    
    # Resource health is direct
    resource_health = self_model.resource_health
    
    # Combine weighted components
    health = (error_health * error_weight + 
              latency_health * latency_weight + 
              resource_health * resource_weight)
    
    # Update stored cognitive health
    self_model.cognitive_health = health
    
    return health
end

"""
    should_defer_decision(self_model::SelfModel)::Bool

Check if the system should defer a decision to a human based on low confidence or health.

# Arguments
- `self_model::SelfModel` - The self-model to evaluate

# Returns
- `Bool` - true if should defer to human, false otherwise
"""
function should_defer_decision(
    self_model::SelfModel
)::Bool
    # Check cognitive health
    health = check_cognitive_health(self_model)
    if health < 0.3
        return true
    end
    
    # Check uncertainty
    if self_model.uncertainty_estimate > 0.7
        return true
    end
    
    # Check calibration
    if self_model.calibration_error > 0.3
        return true
    end
    
    # Check for high error rate
    if self_model.error_rate > 0.3
        return true
    end
    
    # Check for very low recent accuracy
    if self_model.recent_accuracy < 0.5
        return true
    end
    
    return false
end

# ============================================================================
# TRANSPARENCY LAYER
# ============================================================================

"""
    explain_reasoning(self_model::SelfModel, decision::Dict)::String

Generate a human-readable explanation for a decision.

# Arguments
- `self_model::SelfModel` - The self-model
- `decision::Dict` - The decision to explain

# Returns
- `String` - Human-readable explanation
"""
function explain_reasoning(
    self_model::SelfModel,
    decision::Dict
)::String
    parts = String[]
    
    # Explain based on decision type
    decision_type = get(decision, :type, "unknown")
    push!(parts, "Decision type: $decision_type")
    
    # Explain confidence factors
    push!(parts, "\nConfidence factors:")
    
    # Capability factors
    if haskey(decision, :required_capabilities)
        caps = decision[:required_capabilities]
        for cap in caps
            if cap in keys(self_model.capabilities)
                score = self_model.capabilities[cap]
                conf = get(self_model.capability_confidence, cap, 0.5f0)
                push!(parts, "  - $cap: score=$(round(score, digits=2)), confidence=$(round(conf, digits=2))")
            end
        end
    end
    
    # Domain knowledge
    if haskey(decision, :domain)
        domain = decision[:domain]
        if domain in self_model.known_domains
            push!(parts, "  - Domain '$domain': Known (confidence: $(round(self_model.knowledge_confidence, digits=2)))")
        elseif domain in self_model.unknown_domains
            push!(parts, "  - Domain '$domain': Unknown - high uncertainty")
        else
            push!(parts, "  - Domain '$domain': Uncertain familiarity")
        end
    end
    
    # Health status
    health = check_cognitive_health(self_model)
    push!(parts, "\nSystem health: $(round(health, digits=2))")
    
    # Uncertainty
    push!(parts, "Uncertainty estimate: $(round(self_model.uncertainty_estimate, digits=2))")
    
    # Defer recommendation
    if should_defer_decision(self_model)
        push!(parts, "\n⚠️ Recommendation: Defer to human operator")
    else
        push!(parts, "\n✓ Recommendation: Proceed with decision")
    end
    
    return join(parts, "\n")
end

"""
    get_confidence_statement(self_model::SelfModel)::String

Generate a confidence statement for user communication.

# Arguments
- `self_model::SelfModel` - The self-model

# Returns
- `String` - Confidence statement
"""
function get_confidence_statement(
    self_model::SelfModel
)::String
    health = check_cognitive_health(self_model)
    
    # Determine overall confidence level
    if health > 0.8 && self_model.uncertainty_estimate < 0.3
        level = "high"
        emoji = "✅"
    elseif health > 0.5 && self_model.uncertainty_estimate < 0.5
        level = "moderate"
        emoji = "⚠️"
    else
        level = "low"
        emoji = "❌"
    end
    
    # Build statement
    statement = "$emoji Confidence level: $level\n"
    statement *= "  - Cognitive health: $(round(health * 100, digits=1))%\n"
    statement *= "  - Uncertainty: $(round(self_model.uncertainty_estimate * 100, digits=1))%\n"
    statement *= "  - Recent accuracy: $(round(self_model.recent_accuracy * 100, digits=1))%\n"
    statement *= "  - Calibration error: $(round(self_model.calibration_error * 100, digits=1))%"
    
    # Add defer recommendation if needed
    if should_defer_decision(self_model)
        statement *= "\n⚠️ System recommends deferring to human operator for this decision."
    end
    
    return statement
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    update_performance!(self_model::SelfModel, accuracy::Float32, latency_ms::Float32)

Update performance metrics.

# Arguments
- `self_model::SelfModel` - The self-model to update
- `accuracy::Float32` - Recent accuracy (0.0-1.0)
- `latency_ms::Float32` - Decision latency in milliseconds
"""
function update_performance!(
    self_model::SelfModel,
    accuracy::Float32,
    latency_ms::Float32
)
    # Exponential moving average update
    alpha = 0.3f0
    
    self_model.recent_accuracy = self_model.recent_accuracy * (1 - alpha) + accuracy * alpha
    self_model.decision_latency_ms = self_model.decision_latency_ms * (1 - alpha) + latency_ms * alpha
    
    # Update error rate
    self_model.error_rate = 1.0f0 - self_model.recent_accuracy
end

"""
    update_resource_health!(self_model::SelfModel, cpu_usage::Float32, memory_usage::Float32)

Update resource health based on system metrics.

# Arguments
- `self_model::SelfModel` - The self-model to update
- `cpu_usage::Float32` - CPU usage (0.0-1.0)
- `memory_usage::Float32` - Memory usage (0.0-1.0)
"""
function update_resource_health!(
    self_model::SelfModel,
    cpu_usage::Float32,
    memory_usage::Float32
)
    # Resource health is inverse of usage (high usage = low health)
    # Weight CPU more heavily as it affects decision quality
    resource_usage = cpu_usage * 0.6f0 + memory_usage * 0.4f0
    self_model.resource_health = 1.0f0 - resource_usage
end

end # module SelfModel
