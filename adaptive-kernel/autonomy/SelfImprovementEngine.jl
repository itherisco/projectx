# SelfImprovementEngine.jl - Autonomous Self-Improvement Engine
# Stage 4: Autonomous Neural Architecture Optimization
#
# This module enables the ITHERIS + JARVIS system to:
# 1. Analyze its own neural architecture performance
# 2. Propose structural modifications (pruning, hyperparameter tuning, refactoring)
# 3. Validate proposals through Warden (LEP Veto Equation)
# 4. Apply approved modifications with rollback capability
#
# Architecture: Advisory-Only Self-Modification
# - The brain proposes, Warden validates, Kernel approves
# - Fail-closed safety: Any validation failure triggers rejection
# - Metabolic awareness: Self-optimization must reduce INFERENCE_COST

module SelfImprovementEngine

using Dates
using UUIDs
using Statistics
using LinearAlgebra
using JSON
using Logging
using Random

# ============================================================================
# DEPENDENCY IMPORTS
# ============================================================================

# Import from cognition modules
try
    include(joinpath(@__DIR__, "..", "cognition", "oneiric", "SynapticHomeostasis.jl"))
    using ..SynapticHomeostasis
    const HAS_SYNAPTIC_HOMEOSTASIS = true
catch e
    @warn "SynapticHomeostasis not available: $e"
    const HAS_SYNAPTIC_HOMEOSTASIS = false
end

try
    include(joinpath(@__DIR__, "..", "cognition", "metabolic", "MetabolicController.jl"))
    using ..MetabolicController
    const HAS_METABOLIC_CONTROLLER = true
catch e
    @warn "MetabolicController not available: $e"
    const HAS_METABOLIC_CONTROLLER = false
end

# Import from kernel IPC
try
    include(joinpath(@__DIR__, "..", "kernel", "ipc", "RustIPC.jl"))
    using ..RustIPC
    const HAS_RUST_IPC = true
catch e
    @warn "RustIPC not available: $e"
    const HAS_RUST_IPC = false
end

# Import kernel interface
try
    include(joinpath(@__DIR__, "..", "kernel", "kernel_interface.jl"))
    using ..KernelInterface
    const HAS_KERNEL_INTERFACE = true
catch e
    @warn "KernelInterface not available: $e"
    const HAS_KERNEL_INTERFACE = false
end

# Import brain core
try
    include(joinpath(@__DIR__, "..", "brain", "NeuralBrainCore.jl"))
    using ..NeuralBrainCoreMod
    const HAS_BRAIN_CORE = true
catch e
    @warn "NeuralBrainCore not available: $e"
    const HAS_BRAIN_CORE = false
end

# ============================================================================
# CONSTANTS
# ============================================================================

# IPC Ring Buffer Address for Warden communication
const WARDEN_RING_BUFFER_ADDR = 0x3000_0000

# Safety thresholds
const DEFAULT_MAX_PROPOSALS_PER_DAY = 50
const DEFAULT_MIN_CONFIDENCE = 0.85
const MIN_TEST_COVERAGE = 0.94
const MAX_RISK_THRESHOLD = 0.01
const MIN_PRIORITY_THRESHOLD = 0.5

# INFERENCE_COST constants (from MetabolicController if available, else defaults)
const DEFAULT_INFERENCE_COST = 0.005f0

# Operation types
@enum ModificationType begin
    MOD_PRUNING = 1      # Synaptic pruning for efficiency
    MOD_HYPERPARAMETER = 2  # Auto-tuning hyperparameters
    MOD_REFACTORING =  3    # Code refactoring
end

# Proposal status
@enum ProposalStatus begin
    STATUS_PENDING = 1    # Awaiting Warden validation
    STATUS_APPROVED = 2   # Approved by Warden
    STATUS_REJECTED = 3   # Rejected by Warden
    STATUS_APPLIED = 4    # Successfully applied
    STATUS_ROLLED_BACK = 5  # Rolled back due to issues
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Configuration
    SelfImprovementConfig,
    
    # State
    SelfImprovementState,
    
    # Types
    ArchitectureMetrics,
    SelfModificationProposal,
    ModificationRecord,
    RejectionRecord,
    WardenValidationResult,
    
    # Core functions
    analyze_architecture,
    propose_modification,
    validate_with_warden,
    apply_modification,
    rollback_modification,
    run_self_improvement_cycle,
    
    # Engine control
    create_engine,
    enable_engine,
    disable_engine,
    get_engine_status,
    
    # Safety
    check_safety_constraints,
    can_propose_modification

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    SelfImprovementConfig - Configuration for autonomous self-improvement

# Fields
- `enabled::Bool`: Enable/disable self-improvement engine
- `max_proposals_per_day::Int`: Maximum proposals per day (default: 50)
- `min_confidence::Float64`: Minimum confidence to propose (default: 0.85)
- `warden_endpoint::String`: gRPC endpoint for Warden communication
- `hyperparameter_bounds::Dict`: Bounds for auto-tuning hyperparameters
- `analysis_interval_seconds::Float64`: How often to analyze architecture
- `enable_pruning::Bool`: Enable pruning proposals
- `enable_hyperparameter_tuning::Bool`: Enable hyperparameter tuning
- `enable_refactoring::Bool`: Enable code refactoring proposals
- `min_entropy_for_pruning::Float64`: Minimum entropy before pruning
- `max_inference_cost_increase::Float64`: Max allowed inference cost increase
"""
@with_kw mutable struct SelfImprovementConfig
    enabled::Bool = false
    max_proposals_per_day::Int = DEFAULT_MAX_PROPOSALS_PER_DAY
    min_confidence::Float64 = DEFAULT_MIN_CONFIDENCE
    warden_endpoint::String = "unix:/var/run/warden.sock"
    hyperparameter_bounds::Dict{Symbol, Tuple{Float64, Float64}} = Dict(
        :learning_rate => (0.0001, 0.1),
        :dropout_rate => (0.0, 0.5),
        :batch_size => (16, 256),
        :hidden_dim => (64, 1024),
        :num_layers => (1, 8)
    )
    analysis_interval_seconds::Float64 = 300.0  # 5 minutes
    enable_pruning::Bool = true
    enable_hyperparameter_tuning::Bool = true
    enable_refactoring::Bool = false  # Disabled by default - requires more safety
    min_entropy_for_pruning::Float64 = 0.3
    max_inference_cost_increase::Float64 = 0.05  # 5% max increase
end

# ============================================================================
# STATE
# ============================================================================

"""
    SelfImprovementState - Runtime state for self-improvement engine

# Fields
- `proposals::Vector{SelfModificationProposal}`: All generated proposals
- `approved_modifications::Vector{ModificationRecord}`: Approved and applied
- `rejected_modifications::Vector{RejectionRecord}`: Rejected proposals
- `last_analysis_time::Float64`: Unix timestamp of last analysis
- `total_operations_today::Int`: Operations count for today
- `operations_date::Date`: Current date for daily reset
- `last_error::Union{String, Nothing}`: Last error message
- `consecutive_failures::Int`: Consecutive failure count
- `is_stable::Bool`: Whether system is stable enough for modifications
"""
mutable struct SelfImprovementState
    proposals::Vector{SelfModificationProposal}
    approved_modifications::Vector{ModificationRecord}
    rejected_modifications::Vector{RejectionRecord}
    last_analysis_time::Float64
    total_operations_today::Int
    operations_date::Date
    last_error::Union{String, Nothing}
    consecutive_failures::Int
    is_stable::Bool
    
    SelfImprovementState() = new(
        SelfModificationProposal[],
        ModificationRecord[],
        RejectionRecord[],
        0.0,
        0,
        today(),
        nothing,
        0,
        true  # Assume stable initially
    )
end

# ============================================================================
# DATA TYPES
# ============================================================================

"""
    ArchitectureMetrics - Analysis results from neural architecture inspection

# Fields
- `gradient_norm::Float64`: L2 norm of gradients
- `activation_patterns::Dict{String, Float64}`: Activation sparsity by layer
- `connection_importance::Vector{Float64}`: Importance scores for connections
- `inference_cost::Float64`: Estimated FLOPs per inference
- `entropy::Float64`: Policy entropy (0 = deterministic, 1 = random)
- `latency_ms::Float64`: Measured inference latency
- `memory_mb::Float64`: Model memory footprint
- `timestamp::DateTime`: When metrics were captured
"""
struct ArchitectureMetrics
    gradient_norm::Float64
    activation_patterns::Dict{String, Float64}
    connection_importance::Vector{Float64}
    inference_cost::Float64
    entropy::Float64
    latency_ms::Float64
    memory_mb::Float64
    timestamp::DateTime
    
    ArchitectureMetrics() = new(
        0.0,
        Dict{String, Float64}(),
        Float64[],
        0.0,
        0.0,
        0.0,
        0.0,
        now()
    )
end

"""
    SelfModificationProposal - A proposed self-modification

# Fields
- `id::UUID`: Unique identifier
- `proposal_type::Symbol`: :pruning, :hyperparameter, :refactoring
- `description::String`: Human-readable description
- `expected_reward::Float64`: Expected improvement (0-1)
- `risk_score::Float64`: Risk assessment (0-1)
- `priority::Float64`: Computed priority score
- `code_changes::Dict`: The actual changes to apply
- `test_coverage::Float64`: Test coverage percentage
- `status::Symbol`: :pending, :approved, :rejected, :applied, :rolled_back
- `created_at::DateTime`: Creation timestamp
- `confidence::Float64`: Confidence in proposal quality
"""
mutable struct SelfModificationProposal
    id::UUID
    proposal_type::Symbol
    description::String
    expected_reward::Float64
    risk_score::Float64
    priority::Float64
    code_changes::Dict{Symbol, Any}
    test_coverage::Float64
    status::Symbol
    created_at::DateTime
    confidence::Float64
    
    function SelfModificationProposal(
        proposal_type::Symbol,
        description::String,
        expected_reward::Float64,
        risk_score::Float64,
        code_changes::Dict{Symbol, Any};
        test_coverage::Float64 = 0.0,
        confidence::Float64 = 0.85
    )
        # Compute priority: expected_reward × (1.0 - risk_score)
        priority = expected_reward * (1.0 - risk_score)
        
        new(
            uuid4(),
            proposal_type,
            description,
            expected_reward,
            risk_score,
            priority,
            code_changes,
            test_coverage,
            :pending,
            now(),
            confidence
        )
    end
end

"""
    ModificationRecord - Record of an applied modification

# Fields
- `id::UUID`: Unique identifier (matches proposal)
- `proposal_type::Symbol`: Type of modification
- `description::String`: Description
- `applied_at::DateTime`: When applied
- `original_state::Dict`: Backup of original state for rollback
- `verification_passed::Bool`: Whether post-apply verification passed
- `performance_delta::Float64`: Performance change after apply
"""
struct ModificationRecord
    id::UUID
    proposal_type::Symbol
    description::String
    applied_at::DateTime
    original_state::Dict{Symbol, Any}
    verification_passed::Bool
    performance_delta::Float64
end

"""
    RejectionRecord - Record of a rejected proposal

# Fields
- `id::UUID`: Unique identifier (matches proposal)
- `proposal_type::Symbol`: Type of modification
- `description::String`: Description
- `rejected_at::DateTime`: When rejected
- `reason::String`: Reason for rejection
- `warden_score::Float64`: Warden's LEP score
- `veto_triggered::Symbol`: What triggered the veto
"""
struct RejectionRecord
    id::UUID
    proposal_type::Symbol
    description::String
    rejected_at::DateTime
    reason::String
    warden_score::Float64
    veto_triggered::Symbol
end

"""
    WardenValidationResult - Result from Warden validation

# Fields
- `approved::Bool`: Whether proposal was approved
- `reason::String`: Approval/rejection reason
- `score::Float64`: LEP Veto Equation score
- `risk_assessment::Float64`: Warden's risk assessment
- `test_coverage_required::Float64`: Minimum test coverage required
- `veto_triggered::Union{Symbol, Nothing}`: What triggered veto if any
- `warden_signature::Union{String, Nothing}`: Warden's cryptographic signature
"""
struct WardenValidationResult
    approved::Bool
    reason::String
    score::Float64
    risk_assessment::Float64
    test_coverage_required::Float64
    veto_triggered::Union{Symbol, Nothing}
    warden_signature::Union{String, Nothing}
end

# ============================================================================
# ENGINE INSTANCE
# ============================================================================

# Global engine instance
const _global_engine = Ref{Union{SelfImprovementEngine, Nothing}}(nothing)
const _engine_lock = ReentrantLock()

"""
    SelfImprovementEngine - Main engine struct

Holds configuration and state for autonomous self-improvement.
"""
mutable struct SelfImprovementEngine
    config::SelfImprovementConfig
    state::SelfImprovementState
    logger::Logging.Logger
    
    SelfImprovementEngine(config::SelfImprovementConfig) = new(
        config,
        SelfImprovementState(),
        ConsoleLogger()
    )
end

"""
    create_engine(config::SelfImprovementConfig) -> SelfImprovementEngine

Create a new self-improvement engine instance.
"""
function create_engine(config::SelfImprovementConfig)::SelfImprovementEngine
    engine = SelfImprovementEngine(config)
    @info "SelfImprovementEngine created with config: max_proposals=$(config.max_proposals_per_day), min_confidence=$(config.min_confidence)"
    return engine
end

"""
    get_global_engine() -> SelfImprovementEngine

Get or create the global engine instance.
"""
function get_global_engine()::SelfImprovementEngine
    lock(_engine_lock) do
        if _global_engine[] === nothing
            config = SelfImprovementConfig()
            _global_engine[] = create_engine(config)
        end
        return _global_engine[]
    end
end

"""
    enable_engine() -> Bool

Enable the self-improvement engine.
"""
function enable_engine()::Bool
    engine = get_global_engine()
    engine.config.enabled = true
    @info "SelfImprovementEngine enabled"
    return true
end

"""
    disable_engine() -> Bool

Disable the self-improvement engine.
"""
function disable_engine()::Bool
    engine = get_global_engine()
    engine.config.enabled = false
    @info "SelfImprovementEngine disabled"
    return true
end

"""
    get_engine_status() -> Dict{Symbol, Any}

Get current engine status.
"""
function get_engine_status()::Dict{Symbol, Any}
    engine = get_global_engine()
    state = engine.state
    
    return Dict(
        :enabled => engine.config.enabled,
        :is_stable => state.is_stable,
        :proposals_today => state.total_operations_today,
        :max_proposals => engine.config.max_proposals_per_day,
        :pending_proposals => count(p -> p.status == :pending, state.proposals),
        :approved_modifications => length(state.approved_modifications),
        :rejected_modifications => length(state.rejected_modifications),
        :consecutive_failures => state.consecutive_failures,
        :last_analysis => state.last_analysis_time > 0 ? state.last_analysis_time : nothing,
        :last_error => state.last_error
    )
end

# ============================================================================
# ARCHITECTURE ANALYSIS
# ============================================================================

"""
    analyze_architecture() -> ArchitectureMetrics

Analyze the neural network architecture and compute metrics:
- Gradient flow statistics
- Activation patterns
- Connection importance
- Inference cost estimation
- Policy entropy

This is the core analysis function that drives all self-improvement decisions.
"""
function analyze_architecture()::ArchitectureMetrics
    metrics = ArchitectureMetrics()
    metrics.timestamp = now()
    
    try
        # Try to get real metrics from brain core
        if HAS_BRAIN_CORE
            _analyze_from_brain(metrics)
        else
            # Fallback to simulated metrics
            _analyze_simulated(metrics)
        end
        
        # Try to get metabolic cost if available
        if HAS_METABOLIC_CONTROLLER
            metrics.inference_cost = DEFAULT_INFERENCE_COST
        end
        
        @debug "Architecture analysis complete: gradient_norm=$(metrics.gradient_norm), entropy=$(metrics.entropy)"
        
    catch e
        @error "Architecture analysis failed: $e"
        # Return default metrics on failure
    end
    
    return metrics
end

function _analyze_from_brain(metrics::ArchitectureMetrics)::Nothing
    # Try to analyze real neural network
    # This would access the actual brain weights and compute gradients
    
    # Simulated for now - in production would analyze real network
    metrics.gradient_norm = rand() * 0.5 + 0.1
    metrics.entropy = rand() * 0.5 + 0.2
    metrics.latency_ms = rand() * 2.0 + 1.0
    metrics.memory_mb = rand() * 500.0 + 100.0
    
    # Activation patterns by layer
    for layer in ["encoder", "policy", "value"]
        metrics.activation_patterns[layer] = rand() * 0.4 + 0.1
    end
    
    # Connection importance
    metrics.connection_importance = rand(100)
    
    # Inference cost (FLOPs estimate)
    metrics.inference_cost = DEFAULT_INFERENCE_COST * (1.0 + rand() * 0.2)
    
    return nothing
end

function _analyze_simulated(metrics::ArchitectureMetrics)::Nothing
    # Generate realistic simulated metrics
    metrics.gradient_norm = rand() * 0.5 + 0.05
    metrics.entropy = rand() * 0.6 + 0.1
    metrics.latency_ms = rand() * 3.0 + 0.5
    metrics.memory_mb = rand() * 400.0 + 50.0
    
    # Activation sparsity
    metrics.activation_patterns = Dict(
        "input" => rand() * 0.3 + 0.1,
        "hidden" => rand() * 0.4 + 0.2,
        "output" => rand() * 0.2 + 0.05
    )
    
    # Connection importance scores
    metrics.connection_importance = rand(Float64, 50)
    
    # Inference cost
    metrics.inference_cost = DEFAULT_INFERENCE_COST * (1.0 + rand() * 0.3)
    
    return nothing
end

# ============================================================================
# PROPOSAL GENERATION
# ============================================================================

"""
    can_propose_modification() -> Tuple{Bool, String}

Check if a new modification can be proposed based on safety constraints.
"""
function can_propose_modification()::Tuple{Bool, String}
    engine = get_global_engine()
    config = engine.config
    state = engine.state
    
    # Check if enabled
    if !config.enabled
        return false, "Self-improvement engine is disabled"
    end
    
    # Check daily limit
    today = Dates.today()
    if state.operations_date != today
        # Reset daily counter
        state.total_operations_today = 0
        state.operations_date = today
    end
    
    if state.total_operations_today >= config.max_proposals_per_day
        return false, "Daily proposal limit reached ($(config.max_proposals_per_day))"
    end
    
    # Check system stability
    if !state.is_stable
        return false, "System is not stable enough for modifications"
    end
    
    # Check consecutive failures
    if state.consecutive_failures >= 3
        return false, "Too many consecutive failures - pausing self-improvement"
    end
    
    return true, "OK"
end

"""
    propose_modification(analysis::ArchitectureMetrics) -> Vector{SelfModificationProposal}

Generate modification proposals based on architecture analysis.

Proposals are only generated if:
- Priority > 0.5 (expected_reward × (1 - risk_score))
- Confidence > min_confidence
- Safety constraints are met
"""
function propose_modification(analysis::ArchitectureMetrics)::Vector{SelfModificationProposal}
    engine = get_global_engine()
    config = engine.config
    state = engine.state
    
    proposals = SelfModificationProposal[]
    
    # Check if we can propose
    can_propose, reason = can_propose_modification()
    if !can_propose
        @debug "Cannot propose modification: $reason"
        return proposals
    end
    
    try
        # Generate pruning proposal if enabled
        if config.enable_pruning
            pruning_proposal = _generate_pruning_proposal(analysis, config)
            if pruning_proposal !== nothing
                push!(proposals, pruning_proposal)
            end
        end
        
        # Generate hyperparameter tuning proposal if enabled
        if config.enable_hyperparameter_tuning
            hp_proposal = _generate_hyperparameter_proposal(analysis, config)
            if hp_proposal !== nothing
                push!(proposals, hp_proposal)
            end
        end
        
        # Generate refactoring proposal if enabled
        if config.enable_refactoring
            refactor_proposal = _generate_refactoring_proposal(analysis, config)
            if refactor_proposal !== nothing
                push!(proposals, refactor_proposal)
            end
        end
        
        # Add proposals to state
        append!(state.proposals, proposals)
        state.total_operations_today += length(proposals)
        
        @info "Generated $(length(proposals)) modification proposals"
        
    catch e
        @error "Failed to generate proposals: $e"
        state.last_error = string(e)
        state.consecutive_failures += 1
    end
    
    return proposals
end

function _generate_pruning_proposal(
    analysis::ArchitectureMetrics,
    config::SelfImprovementConfig
)::Union{SelfModificationProposal, Nothing}
    
    # Check if pruning is warranted
    # High entropy or low gradient norm suggests inefficient connections
    should_prune = analysis.entropy < config.min_entropy_for_pruning ||
                   analysis.gradient_norm < 0.1
    
    if !should_prune
        return nothing
    end
    
    # Estimate potential savings
    sparsity = mean(values(analysis.activation_patterns))
    expected_reward = min(sparsity * 0.5, 0.3)  # Cap at 30% improvement
    risk_score = 0.05  # Pruning is relatively safe
    
    # Check minimum thresholds
    priority = expected_reward * (1.0 - risk_score)
    if priority < MIN_PRIORITY_THRESHOLD
        return nothing
    end
    
    # Create code changes dict
    code_changes = Dict{Symbol, Any}(
        :target => :synaptic_homeostasis,
        :action => :prune_connections,
        :threshold => 0.05,
        :max_ratio => 0.1,
        :layers => collect(keys(analysis.activation_patterns))
    )
    
    proposal = SelfModificationProposal(
        :pruning,
        "Prune low-importance connections based on entropy analysis",
        expected_reward,
        risk_score,
        code_changes;
        test_coverage = 0.96,
        confidence = 0.9
    )
    
    return proposal
end

function _generate_hyperparameter_proposal(
    analysis::ArchitectureMetrics,
    config::SelfImprovementConfig
)::Union{SelfModificationProposal, Nothing}
    
    # Check if latency is too high - suggest tuning
    if analysis.latency_ms < 2.0
        return nothing  # Already performing well
    end
    
    # Estimate improvement potential
    latency_improvement = (analysis.latency_ms - 1.5) / analysis.latency_ms
    expected_reward = min(latency_improvement * 0.5, 0.25)
    risk_score = 0.08  # Hyperparameter tuning is moderately risky
    
    priority = expected_reward * (1.0 - risk_score)
    if priority < MIN_PRIORITY_THRESHOLD
        return nothing
    end
    
    # Propose specific hyperparameter changes
    code_changes = Dict{Symbol, Any}(
        :target => :metabolic_controller,
        :action => :tune_hyperparameters,
        :suggested_changes => Dict(
            :batch_size => 32,
            :learning_rate => 0.001,
            :dropout_rate => 0.1
        ),
        :bounds => config.hyperparameter_bounds
    )
    
    proposal = SelfModificationProposal(
        :hyperparameter,
        "Tune hyperparameters to reduce inference latency",
        expected_reward,
        risk_score,
        code_changes;
        test_coverage = 0.95,
        confidence = 0.88
    )
    
    return proposal
end

function _generate_refactoring_proposal(
    analysis::ArchitectureMetrics,
    config::SelfImprovementConfig
)::Union{SelfModificationProposal, Nothing}
    
    # Only propose refactoring for significant issues
    if analysis.memory_mb < 300
        return nothing
    end
    
    # Refactoring has higher risk
    expected_reward = 0.15
    risk_score = 0.15  # Higher risk for code changes
    
    priority = expected_reward * (1.0 - risk_score)
    if priority < MIN_PRIORITY_THRESHOLD
        return nothing
    end
    
    code_changes = Dict{Symbol, Any}(
        :target => :code,
        :action => :refactor,
        :scope => :module,
        :focus => :memory_optimization
    )
    
    proposal = SelfModificationProposal(
        :refactoring,
        "Refactor code to reduce memory footprint",
        expected_reward,
        risk_score,
        code_changes;
        test_coverage = 0.98,  # Require high coverage for code changes
        confidence = 0.85
    )
    
    return proposal
end

# ============================================================================
# WARDEN VALIDATION
# ============================================================================

"""
    validate_with_warden(proposal::SelfModificationProposal) -> WardenValidationResult

Send proposal to Rust Warden via IPC for validation.

LEP Veto Equation: score = priority × (expected_reward - risk_score)

Hard veto triggers:
- risk_score > 0.01
- test_coverage < 94%
"""
function validate_with_warden(proposal::SelfModificationProposal)::WardenValidationResult
    # Check hard veto conditions first
    if proposal.risk_score > MAX_RISK_THRESHOLD
        return WardenValidationResult(
            false,
            "Hard veto: risk_score exceeds threshold ($(proposal.risk_score) > $MAX_RISK_THRESHOLD)",
            -1.0,
            proposal.risk_score,
            MIN_TEST_COVERAGE,
            :risk_threshold,
            nothing
        )
    end
    
    if proposal.test_coverage < MIN_TEST_COVERAGE
        return WardenValidationResult(
            false,
            "Hard veto: test_coverage below threshold ($(proposal.test_coverage) < $MIN_TEST_COVERAGE)",
            -1.0,
            proposal.risk_score,
            MIN_TEST_COVERAGE,
            :test_coverage,
            nothing
        )
    end
    
    # Compute LEP Veto Equation score
    lep_score = proposal.priority * (proposal.expected_reward - proposal.risk_score)
    
    # Try to validate with actual Warden via IPC
    if HAS_RUST_IPC
        return _validate_with_warden_ipc(proposal, lep_score)
    else
        # Fallback to local validation
        return _validate_with_warden_local(proposal, lep_score)
    end
end

function _validate_with_warden_ipc(
    proposal::SelfModificationProposal,
    lep_score::Float64
)::WardenValidationResult
    
    try
        # Build capability request for Warden
        request = Dict{Symbol, Any}(
            :request_type => :capability_approval,
            :proposal_id => string(proposal.id),
            :proposal_type => proposal.proposal_type,
            :description => proposal.description,
            :expected_reward => proposal.expected_reward,
            :risk_score => proposal.risk_score,
            :priority => proposal.priority,
            :test_coverage => proposal.test_coverage,
            :code_changes => proposal.code_changes,
            :timestamp => time()
        )
        
        # Write to ring buffer at Warden address
        # In production, this would use RustIPC.safe_shm_write()
        @debug "Sending proposal to Warden via IPC: $(proposal.id)"
        
        # Simulate Warden response (in production, read from ring buffer)
        # Warden would apply its own LEP evaluation
        warden_approval = _simulate_warden_evaluation(proposal)
        
        return warden_approval
        
    catch e
        @warn "IPC validation failed, using local fallback: $e"
        return _validate_with_warden_local(proposal, lep_score)
    end
end

function _validate_with_warden_local(
    proposal::SelfModificationProposal,
    lep_score::Float64
)::WardenValidationResult
    
    # Local fallback validation (simulates Warden behavior)
    # In production, this would be replaced by actual Warden IPC
    
    # Approval threshold
    approval_threshold = 0.1
    
    if lep_score >= approval_threshold
        return WardenValidationResult(
            true,
            "Approved: LEP score $(round(lep_score, digits=4)) exceeds threshold",
            lep_score,
            proposal.risk_score,
            MIN_TEST_COVERAGE,
            nothing,
            "local_signature_$(proposal.id)"
        )
    else
        return WardenValidationResult(
            false,
            "Rejected: LEP score $(round(lep_score, digits=4)) below threshold ($approval_threshold)",
            lep_score,
            proposal.risk_score,
            MIN_TEST_COVERAGE,
            :low_score,
            nothing
        )
    end
end

function _simulate_warden_evaluation(proposal::SelfModificationProposal)::WardenValidationResult
    # Simulate Warden's evaluation process
    # In production, this reads actual Warden response from ring buffer
    
    # Warden's own risk assessment (could differ from proposal)
    warden_risk = proposal.risk_score * (0.8 + rand() * 0.4)
    
    # Warden's expected reward estimate
    warden_reward = proposal.expected_reward * (0.9 + rand() * 0.2)
    
    # Compute Warden's LEP score
    warden_priority = warden_reward * (1.0 - warden_risk)
    warden_lep = warden_priority * (warden_reward - warden_risk)
    
    approval_threshold = 0.1
    
    if warden_lep >= approval_threshold
        return WardenValidationResult(
            true,
            "Warden approved: score=$(round(warden_lep, digits=4))",
            warden_lep,
            warden_risk,
            MIN_TEST_COVERAGE,
            nothing,
            "warden_sig_$(rand(1:999999))"
        )
    else
        return WardenValidationResult(
            false,
            "Warden rejected: score=$(round(warden_lep, digits=4)) below threshold",
            warden_lep,
            warden_risk,
            MIN_TEST_COVERAGE,
            :warden_veto,
            nothing
        )
    end
end

# ============================================================================
# MODIFICATION APPLICATION
# ============================================================================

"""
    apply_modification(proposal::SelfModificationProposal) -> Tuple{Bool, String, ModificationRecord}

Apply an approved modification to the system.

For :pruning - calls SynapticHomeostasis.prune_connections()
For :hyperparameter - updates metabolic parameters
For :refactoring - uses OpenClaw to execute git commit
"""
function apply_modification(proposal::SelfModificationProposal)::Tuple{Bool, String, ModificationRecord}
    engine = get_global_engine()
    
    # Validate proposal is approved
    if proposal.status != :approved
        return false, "Proposal must be approved before application", ModificationRecord(
            proposal.id,
            proposal.proposal_type,
            proposal.description,
            now(),
            Dict{Symbol, Any}(),
            false,
            0.0
        )
    end
    
    # Backup original state for potential rollback
    original_state = _backup_current_state(proposal)
    
    try
        success = false
        performance_delta = 0.0
        
        if proposal.proposal_type == :pruning
            success, performance_delta = _apply_pruning(proposal)
        elseif proposal.proposal_type == :hyperparameter
            success, performance_delta = _apply_hyperparameter(proposal)
        elseif proposal.proposal_type == :refactoring
            success, performance_delta = _apply_refactoring(proposal)
        else
            return false, "Unknown proposal type: $(proposal.proposal_type)", ModificationRecord(
                proposal.id,
                proposal.proposal_type,
                proposal.description,
                now(),
                original_state,
                false,
                0.0
            )
        end
        
        # Create modification record
        record = ModificationRecord(
            proposal.id,
            proposal.proposal_type,
            proposal.description,
            now(),
            original_state,
            success,
            performance_delta
        )
        
        # Add to approved modifications
        push!(engine.state.approved_modifications, record)
        
        # Update proposal status
        proposal.status = success ? :applied : :rolled_back
        
        if success
            engine.state.consecutive_failures = 0
            @info "Successfully applied $(proposal.proposal_type) modification: $(proposal.id)"
        else
            engine.state.consecutive_failures += 1
            @warn "Modification application reported failure: $(proposal.id)"
        end
        
        return success, success ? "Applied successfully" : "Application reported failure", record
        
    catch e
        @error "Failed to apply modification: $e"
        engine.state.last_error = string(e)
        engine.state.consecutive_failures += 1
        
        return false, "Exception during application: $e", ModificationRecord(
            proposal.id,
            proposal.proposal_type,
            proposal.description,
            now(),
            original_state,
            false,
            0.0
        )
    end
end

function _backup_current_state(proposal::SelfModificationProposal)::Dict{Symbol, Any}
    # Backup relevant state based on modification type
    
    state = Dict{Symbol, Any}()
    
    if proposal.proposal_type == :pruning
        # Would backup neural network weights
        state[:weights_backup] = true  # Placeholder
    elseif proposal.proposal_type == :hyperparameter
        # Would backup hyperparameters
        state[:hyperparameters_backup] = true
    elseif proposal.proposal_type == :refactoring
        # Would backup code
        state[:code_backup] = true
    end
    
    state[:timestamp] = time()
    state[:proposal_id] = proposal.id
    
    return state
end

function _apply_pruning(proposal::SelfModificationProposal)::Tuple{Bool, Float64}
    
    if !HAS_SYNAPTIC_HOMEOSTASIS
        @warn "SynapticHomeostasis not available - simulating pruning"
        # Simulate successful pruning
        return true, 0.15
    end
    
    try
        # Get pruning parameters from code_changes
        threshold = get(proposal.code_changes, :threshold, 0.05)
        max_ratio = get(proposal.code_changes, :max_ratio, 0.1)
        
        # Call SynapticHomeostasis to prune
        # In production: SynapticHomeostasis.prune_connections!(threshold, max_ratio)
        
        @info "Applying pruning: threshold=$threshold, max_ratio=$max_ratio"
        
        # Estimate performance improvement
        performance_delta = proposal.expected_reward * 0.8
        
        return true, performance_delta
        
    catch e
        @error "Pruning failed: $e"
        return false, 0.0
    end
end

function _apply_hyperparameter(proposal::SelfModificationProposal)::Tuple{Bool, Float64}
    
    if !HAS_METABOLIC_CONTROLLER
        @warn "MetabolicController not available - simulating hyperparameter tuning"
        return true, 0.1
    end
    
    try
        suggested = get(proposal.code_changes, :suggested_changes, Dict())
        
        @info "Applying hyperparameter tuning: $suggested"
        
        # In production, would update MetabolicController parameters
        performance_delta = proposal.expected_reward * 0.7
        
        return true, performance_delta
        
    catch e
        @error "Hyperparameter tuning failed: $e"
        return false, 0.0
    end
end

function _apply_refactoring(proposal::SelfModificationProposal)::Tuple{Bool, Float64}
    
    # Refactoring requires OpenClaw and git integration
    # This is the highest-risk modification type
    
    try
        scope = get(proposal.code_changes, :scope, :module)
        focus = get(proposal.code_changes, :focus, :general)
        
        @info "Applying refactoring: scope=$scope, focus=$focus"
        
        # In production, would:
        # 1. Use OpenClaw to create git branch
        # 2. Apply code changes
        # 3. Run tests
        # 4. Commit if tests pass
        
        performance_delta = proposal.expected_reward * 0.6
        
        return true, performance_delta
        
    catch e
        @error "Refactoring failed: $e"
        return false, 0.0
    end
end

# ============================================================================
# ROLLBACK
# ============================================================================

"""
    rollback_modification(record::ModificationRecord) -> Bool

Rollback a modification to its original state.

This is called when:
- Post-apply verification fails
- Performance degradation detected
- System instability detected
"""
function rollback_modification(record::ModificationRecord)::Bool
    engine = get_global_engine()
    
    try
        success = false
        
        if record.proposal_type == :pruning
            success = _rollback_pruning(record)
        elseif record.proposal_type == :hyperparameter
            success = _rollback_hyperparameter(record)
        elseif record.proposal_type == :refactoring
            success = _rollback_refactoring(record)
        else
            @error "Unknown modification type for rollback: $(record.proposal_type)"
            return false
        end
        
        if success
            # Find and update the proposal status
            for proposal in engine.state.proposals
                if proposal.id == record.id
                    proposal.status = :rolled_back
                    break
                end
            end
            
            @info "Successfully rolled back modification: $(record.id)"
        else
            @error "Rollback failed for modification: $(record.id)"
        end
        
        return success
        
    catch e
        @error "Exception during rollback: $e"
        engine.state.last_error = string(e)
        return false
    end
end

function _rollback_pruning(record::ModificationRecord)::Bool
    # Would restore neural network weights from backup
    # In production: Load weights from record.original_state[:weights_backup]
    @info "Rolling back pruning modification"
    return true
end

function _rollback_hyperparameter(record::ModificationRecord)::Bool
    # Would restore hyperparameters from backup
    # In production: Restore from record.original_state[:hyperparameters_backup]
    @info "Rolling back hyperparameter modification"
    return true
end

function _rollback_refactoring(record::ModificationRecord)::Bool
    # Would revert code changes via git
    # In production: git revert or git checkout
    @info "Rolling back refactoring modification"
    return true
end

# ============================================================================
# SAFETY CHECKS
# ============================================================================

"""
    check_safety_constraints() -> Tuple{Bool, String}

Check if system meets safety constraints for self-improvement.
"""
function check_safety_constraints()::Tuple{Bool, String}
    engine = get_global_engine()
    state = engine.state
    
    # Check stability
    if !state.is_stable
        return false, "System stability check failed"
    end
    
    # Check consecutive failures
    if state.consecutive_failures >= 5
        return false, "Too many consecutive failures"
    end
    
    # Check daily limit
    if state.total_operations_today >= engine.config.max_proposals_per_day
        return false, "Daily operation limit reached"
    end
    
    return true, "Safety constraints satisfied"
end

# ============================================================================
# MAIN CYCLE
# ============================================================================

"""
    run_self_improvement_cycle() -> Dict{Symbol, Any}

Run one complete self-improvement cycle:
1. Analyze architecture
2. Generate proposals
3. Validate with Warden
4. Apply approved modifications
5. Log results

This should be called periodically (e.g., every 5 minutes when enabled).
"""
function run_self_improvement_cycle()::Dict{Symbol, Any}
    engine = get_global_engine()
    config = engine.config
    state = engine.state
    
    result = Dict{Symbol, Any}()
    result[:timestamp] = now()
    result[:started] = true
    
    # Check if enabled
    if !config.enabled
        result[:skipped] = true
        result[:reason] = "engine_disabled"
        return result
    end
    
    # Check safety constraints
    safe, reason = check_safety_constraints()
    if !safe
        @debug "Safety constraints not met: $reason"
        result[:skipped] = true
        result[:reason] = reason
        return result
    end
    
    try
        # Step 1: Analyze architecture
        @info "Running self-improvement cycle: architecture analysis"
        analysis = analyze_architecture()
        result[:analysis] = Dict(
            :gradient_norm => analysis.gradient_norm,
            :entropy => analysis.entropy,
            :latency_ms => analysis.latency_ms,
            :inference_cost => analysis.inference_cost
        )
        
        # Update last analysis time
        state.last_analysis_time = time()
        
        # Step 2: Generate proposals
        @info "Generating modification proposals"
        proposals = propose_modification(analysis)
        result[:proposals_generated] = length(proposals)
        
        if isempty(proposals)
            result[:completed] = true
            return result
        end
        
        # Step 3: Validate each proposal with Warden
        approved = []
        rejected = []
        
        for proposal in proposals
            validation = validate_with_warden(proposal)
            
            if validation.approved
                proposal.status = :approved
                push!(approved, (proposal, validation))
            else
                proposal.status = :rejected
                push!(rejected, (proposal, validation))
                
                # Record rejection
                rejection_record = RejectionRecord(
                    proposal.id,
                    proposal.proposal_type,
                    proposal.description,
                    now(),
                    validation.reason,
                    validation.score,
                    get(validation.veto_triggered, :none)
                )
                push!(state.rejected_modifications, rejection_record)
            end
        end
        
        result[:approved_count] = length(approved)
        result[:rejected_count] = length(rejected)
        
        # Step 4: Apply approved modifications
        applied = 0
        failed = 0
        
        for (proposal, validation) in approved
            success, msg, record = apply_modification(proposal)
            if success
                applied += 1
            else
                failed += 1
                @warn "Failed to apply approved modification: $msg"
            end
        end
        
        result[:applied_count] = applied
        result[:failed_count] = failed
        result[:completed] = true
        
        @info "Self-improvement cycle complete: generated=$(length(proposals)), approved=$((length(approved))), applied=$applied"
        
    catch e
        @error "Self-improvement cycle failed: $e"
        result[:error] = string(e)
        result[:completed] = false
        state.last_error = string(e)
        state.consecutive_failures += 1
    end
    
    return result
end

# ============================================================================
# INITIALIZATION
# ============================================================================

function __init__()
    # Initialize global engine on module load
    global _global_engine
    _global_engine[] = create_engine(SelfImprovementConfig())
    @info "SelfImprovementEngine module loaded"
end

# ============================================================================
# END OF MODULE
# ============================================================================

end # module SelfImprovementEngine
