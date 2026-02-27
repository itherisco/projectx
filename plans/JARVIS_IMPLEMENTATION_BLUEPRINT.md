# JARVIS PRODUCTION IMPLEMENTATION BLUEPRINT
## Project JARVIS – Neuro-Symbolic Sovereign AI Assistant

**Generated:** 2026-02-26  
**Status:** EXECUTABLE ARCHITECTURAL SPECIFICATION  
**Classification:** SOVEREIGN AI INFRASTRUCTURE

---

# TABLE OF CONTENTS

1. [Final Target Architecture](#1-final-target-architecture)
2. [Critical Implementation Phases](#2-critical-implementation-phases)
3. [Implementation Sequence Roadmap](#3-implementation-sequence-roadmap)
4. [Production Hardening](#4-production-hardening)
5. [Definition of Done](#5-definition-of-done)

---

# 1. FINAL TARGET ARCHITECTURE

## 1.1 System Architecture Diagram (Text-Based)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              JARVIS PRODUCTION ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                           PERCEPTION LAYER (Input)                               │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │   │
│  │  │    Voice     │  │    Vision    │  │    Text      │  │   System    │    │   │
│  │  │  (Whisper)   │  │   (VLM)      │  │  (REST API)  │  │  Telemetry  │    │   │
│  │  │   [NEW]      │  │   [NEW]      │  │              │  │   [NEW]     │    │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │   │
│  │         │                  │                  │                 │            │   │
│  │         └──────────────────┼──────────────────┼─────────────────┘            │   │
│  │                            ▼                                                         │   │
│  │                   ┌─────────────────┐                                                │   │
│  │                   │ PerceptionVector │ ◄── Unified 12D input format               │   │
│  │                   └────────┬────────┘                                                │   │
│  └────────────────────────────────────────────────────────────────────────────────────┘   │
│                                ▼                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                         COGNITION LAYER (Brain)                                 │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                           ITHERIS BRAIN                                  │   │   │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐     │   │   │
│  │  │  │  Encoder   │  │   Policy   │  │   Value    │  │  Memory   │     │   │   │
│  │  │  │  Network   │──│  Network   │──│  Network   │──│ Embedding │     │   │   │
│  │  │  └────────────┘  └────────────┘  └────────────┘  └────────────┘     │   │   │
│  │  │        │                                     │                       │   │   │
│  │  │        └──────────────┬──────────────────────┘                       │   │   │
│  │  │                       ▼                                                │   │   │
│  │  │              ┌─────────────────┐                                       │   │   │
│  │  │              │   BrainOutput   │ ◄── ADVISORY PROPOSAL (NEVER EXECUTES)│   │   │
│  │  │              └────────┬────────┘                                       │   │   │
│  │  └──────────────────────────────────────────────────────────────────────────┘   │   │
│  │                              │ ADVISORY ONLY                                      │   │
│  │                              ▼                                                  │   │
│  └──────────────────────────────┼──────────────────────────────────────────────────┘   │
│                                 ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                      SOVEREIGNTY LAYER (Kernel)                               │   │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                        ADAPTIVE KERNEL                                   │   │   │
│  │  │                                                                         │   │   │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐      │   │   │
│  │  │  │ WorldState │  │    Goal    │  │ Reflection │  │   Trust   │      │   │   │
│  │  │  │  Observer  │  │  Manager   │  │   Engine   │  │ Classifier │      │   │   │
│  │  │  └─────┬──────┘  └─────┬──────┘  └──────┬─────┘  └─────┬──────┘      │   │   │
│  │  │        │                │                │              │              │   │   │
│  │  │        └────────────────┼────────────────┼──────────────┘              │   │   │
│  │  │                         ▼                                                 │   │   │
│  │  │              ┌─────────────────────┐                                    │   │   │
│  │  │              │  Kernel.approve()   │ ◄── SOVEREIGN DECISION           │   │   │
│  │  │              │  (APPROVE/DENY/STOP) │    NO EXCEPTION - KERNEL STATE   │   │   │
│  │  │              │                      │    MUST NEVER BE `nothing`      │   │   │
│  │  │              └──────────┬──────────┘                                    │   │   │
│  │  └─────────────────────────┼──────────────────────────────────────────────┘   │   │
│  │                            │ APPROVED                                          │   │
│  │                            ▼                                                  │   │
│  └────────────────────────────┼───────────────────────────────────────────────────┘   │
│                               ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                      EXECUTION LAYER (Action)                                 │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐      │   │
│  │  │   OpenClaw   │  │  Capability  │  │   System    │  │   Safety   │      │   │
│  │  │    Tools     │  │   Registry   │  │  Commands   │  │   Guard    │      │   │
│  │  │  [SANDBOXED] │  │   [NEW]      │  │   [NEW]     │  │   [NEW]    │      │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬──────┘      │   │
│  │         │                  │                  │                │             │   │
│  │         └──────────────────┼──────────────────┘                │             │   │
│  │                            ▼                                   │             │   │
│  │                   ┌─────────────────┐                          │             │   │
│  │                   │  ActionResult   │ ◄── Execution outcome  │             │   │
│  │                   └────────┬────────┘                          │             │   │
│  └─────────────────────────────┼───────────────────────────────────┘             │
│                                ▼                                                 │
│                               FEEDBACK                                            │
│                                │                                                 │
│                                ▼                                                 │
│              ┌─────────────────────────────────┐                               │
│              │  Kernel.reflect!(proposal,result)│ ◄── Self-model update        │
│              └─────────────────────────────────┘                               │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────────┐
│                         SUPPORTING INFRASTRUCTURE                                 │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Persistence  │  │   Secrets    │  │Observability│  │  Circuit    │          │
│  │  (SQLite)    │  │   (Vault)    │  │ (Metrics)   │  │  Breakers   │          │
│  │  [NEW]       │  │   [NEW]      │  │   [NEW]     │  │   [NEW]     │          │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## 1.2 Updated Cognitive Loop

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         COMPLETE COGNITIVE LOOP                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│     ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                  │
│     │ PERCEPTION  │ ───► │  COGNITION  │ ───► │ EXECUTION   │                  │
│     └─────────────┘      └─────────────┘      └─────────────┘                  │
│           │                    │                    │                           │
│           │                    │                    │                           │
│           ▼                    ▼                    ▼                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐               │
│  │ 1. Input        │  │ 4. Brain        │  │ 7. Kernel       │               │
│  │    Normalization│  │    Inference    │  │    Approval     │               │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘               │
│           │                    │                    │                           │
│           │                    │                    │                           │
│           ▼                    ▼                    ▼                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐               │
│  │ 2. Entity       │  │ 5. Proposal     │  │ 8. Capability   │               │
│  │    Extraction   │  │    Generation   │  │    Selection    │               │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘               │
│           │                    │                    │                           │
│           │                    │                    │                           │
│           ▼                    ▼                    ▼                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐               │
│  │ 3. Perception   │  │ 6. BrainOutput  │  │ 9. Tool         │               │
│  │    Vector Build │  │    (Advisory)  │  │    Execution    │               │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘               │
│                                                                  │               │
│                                                                  │               │
│     ◄────────────────────────────────────────────────────────────┘               │
│     │                                                                       │
│     │  ┌─────────────────────────────────────────────────────┐               │
│     │  │              REFLECTION LOOP                         │               │
│     │  │  10. Result Collection → 11. Kernel.reflect!()      │               │
│     │  │       → 12. Self-Model Update → 13. Memory Storage │               │
│     │  └─────────────────────────────────────────────────────┘               │
│     │                                                                       │
│     └──────────────────────────────────────────────────── (next cycle)        │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 1.3 Final Data Flow

```
USER INPUT → [PerceptionVector] → [ITHERIS Brain] → [BrainOutput]
                                                       │
                                                       ▼
                                          ┌─────────────────────┐
                                          │  ADVISORY PROPOSAL  │
                                          │  (confidence, value │
                                          │   uncertainty)      │
                                          └──────────┬──────────┘
                                                     │
                                                     ▼
                                       [Kernel.approve()] ──→ SOVEREIGN DECISION
                                                     │
                                  ┌──────────────────┼──────────────────┐
                                  ▼                  ▼                  ▼
                            [APPROVED]          [DENIED]          [STOPPED]
                                  │                  │                   │
                                  ▼                  │                   │
                        [Capability Registry]       │                   │
                                  │                  │                   │
                                  ▼                  │                   │
                          [Tool Execution]         │                   │
                                  │                  │                   │
                                  ▼                  │                   │
                          [ActionResult]            │                   │
                                  │                  │                   │
                                  └──────────────────┴───────────────────┘
                                                     │
                                                     ▼
                                          [Kernel.reflect!]
                                                     │
                                                     ▼
                                          [Self-Model Update]
                                          [Episode Storage]
```

---

# 2. CRITICAL IMPLEMENTATION PHASES

## PHASE 1: Kernel State Initialization (CRITICAL - P0)

### 2.1.1 Architectural Role
The Kernel is the SOVEREIGN authority. All execution flows through `Kernel.approve()`. The kernel state **MUST NEVER BE `nothing`**. This is the most critical invariant in the entire system.

### 2.1.2 Required File Modifications
- **File:** [`adaptive-kernel/kernel/Kernel.jl`](adaptive-kernel/kernel/Kernel.jl:1)
  - Add `approve()` function
  - Add `evaluate()` function  
  - Modify initialization to ensure non-nothing state
  - Add fail-closed validation

### 2.1.3 New Files to Create
- **File:** `adaptive-kernel/kernel/StateValidator.jl`
  - Validates kernel state integrity
  - Ensures non-nothing invariant

### 2.1.4 Data Structures

```julia
# kernel/Kernel.jl - Add these structs

"""
    KernelApproval - Sovereign decision on brain proposal
"""
@enum ApprovalDecision APPROVED DENIED STOPPED

"""
    ApprovalContext - Context for approval decision
"""
struct ApprovalContext
    proposal::IntegrationActionProposal
    risk_level::RiskLevel
    trust_level::TrustLevel
    confirmation_required::Bool
    timestamp::DateTime
end

"""
    ApprovalResult - Result of kernel approval decision
"""
struct ApprovalResult
    decision::ApprovalDecision
    confidence::Float32
    reasoning::String
    requires_confirmation::Bool
    approval_id::UUID
    timestamp::DateTime
end
```

### 2.1.5 Interface Contracts

```julia
# Function signatures for kernel approval

"""
    approve(kernel::KernelState, proposal::IntegrationActionProposal)::ApprovalResult
    
INVARIANT: This function MUST NEVER return without a decision.
Kernel state MUST NEVER be nothing.
"""
function approve(kernel::KernelState, proposal::IntegrationActionProposal)::ApprovalResult

"""
    evaluate(kernel::KernelState, world_state::IntegrationWorldState)::Vector{Float32}
    
Computes priority scores for goals given current world state.
"""
function evaluate(kernel::KernelState, world_state::IntegrationWorldState)::Vector{Float32}
```

### 2.1.6 Integration Points
- **Input:** BrainOutput from ITHERIS Brain
- **Input:** Trust classifier from Trust Module
- **Output:** ApprovalResult to Execution Layer
- **Output:** ReflectionEvent to Memory

### 2.1.7 Failure Modes
| Failure Mode | Detection | Recovery |
|--------------|----------|----------|
| Kernel state is nothing | State validation | Auto-initialize with default goals |
| Approval timeout | Timeout watchdog | Fail-closed: DENY |
| Trust classifier unavailable | Health check | Use cached trust level |
| World state invalid | Validation failure | Use last valid state |

### 2.1.8 Security Risks
- **State Corruption:** Kernel state modified by unauthorized component
  - **Mitigation:** Immutable state, copy-on-write
- **Approval Bypass:** Brain directly executes without kernel
  - **Mitigation:** Boundary invariant enforcement, audit logging

### 2.1.9 Minimal Viable Implementation Code Skeleton (Julia)

```julia
# adaptive-kernel/kernel/Kernel.jl - Add these functions

"""
    approve - SOVEREIGN approval function
    CRITICAL: Must never fail to return a decision
"""
function approve(kernel::KernelState, proposal::IntegrationActionProposal)::ApprovalResult
    # P0: Fail-closed - kernel state must never be nothing
    if kernel === nothing
        @error "KERNEL STATE IS NOTHING - FAILING CLOSED"
        return ApprovalResult(STOPPED, 0.0f0, "Kernel state invalid", true, uuid4(), now())
    end
    
    # P1: Validate proposal
    if !_validate_proposal(proposal)
        return ApprovalResult(DENIED, 0.0f0, "Invalid proposal", false, uuid4(), now())
    end
    
    # P2: Check risk threshold
    risk_level = _classify_risk(proposal)
    
    # P3: Get trust level
    trust_level = _get_current_trust_level(kernel)
    
    # P4: Determine if confirmation required
    confirmation_required = _requires_confirmation(risk_level, trust_level)
    
    # P5: Make sovereign decision
    decision = _make_decision(proposal, risk_level, trust_level)
    
    # P6: Log decision for audit
    _log_approval_decision(proposal, decision)
    
    return ApprovalResult(
        decision,
        proposal.confidence,
        "Approved by kernel sovereignty",
        confirmation_required,
        uuid4(),
        now()
    )
end

"""
    _make_decision - Atomic sovereign decision logic
"""
function _make_decision(
    proposal::IntegrationActionProposal,
    risk_level::RiskLevel,
    trust_level::TrustLevel
)::ApprovalDecision
    # High risk + low trust = STOP
    if risk_level == HIGH_RISK && trust_level < TRUST_FULL
        return STOPPED
    end
    
    # Medium risk + insufficient trust = DENY
    if risk_level == MEDIUM_RISK && trust_level < TRUST_STANDARD
        return DENIED
    end
    
    # Default: approve with confidence weighting
    return APPROVED
end
```

### 2.1.10 Testing Requirements
- **Unit Tests:**
  - `test_kernel_never_nothing`: Verify kernel state is never nothing after init
  - `test_approve_always_returns`: Verify approve() always returns a decision
  - `test_fail_closed`: Verify system fails closed on errors
- **Integration Tests:**
  - `test_brain_kernel_boundary`: Verify brain cannot bypass kernel
  - `test_approval_audit_trail`: Verify all approvals are logged

---

## PHASE 2: ITHERIS Brain Full Integration (CRITICAL - P0)

### 2.2.1 Architectural Role
The Brain is ADVISORY ONLY. It proposes actions but NEVER executes. All brain outputs pass through `Kernel.approve()` before execution.

### 2.2.2 Required File Modifications
- **File:** [`jarvis/src/SystemIntegrator.jl`](jarvis/src/SystemIntegrator.jl:200)
  - Replace fallback heuristic path with neural brain activation
  - Wire training loop into cognitive cycle

### 2.2.3 New Files to Create
- **File:** `adaptive-kernel/brain/NeuralBrain.jl`
  - Full neural network implementation
  - Training loop with experience replay

### 2.2.4 Data Structures

```julia
# adaptive-kernel/brain/NeuralBrain.jl - New file

"""
    NeuralBrainCore - Full neural network brain implementation
"""
mutable struct NeuralBrainCore
    encoder::Chain          # Encoder network
    policy_network::Chain  # Policy network (action selection)
    value_network::Chain   # Value network (reward estimation)
    latent_dim::Int
    
    # Training state
    experience_buffer::ExperienceBuffer
    optimizer::Any
    target_network::Chain
    
    # Uncertainty estimation
    dropout_layers::Vector{Dropout}
    ensemble_models::Vector{Chain}
end

"""
    BrainInferenceResult - Result from brain inference
"""
struct BrainInferenceResult
    proposed_actions::Vector{String}
    confidence::Float32
    value_estimate::Float32
    uncertainty::Float32
    reasoning::String
    latent_features::Vector{Float32}
end
```

### 2.2.5 Interface Contracts

```julia
# Brain interface functions

"""
    infer(brain::JarvisBrain, input::BrainInput)::BrainOutput
    
INVARIANT: Brain output is ALWAYS advisory. Kernel approval required for execution.
"""
function infer(brain::JarvisBrain, input::BrainInput)::BrainOutput

"""
    learnbrain::Jarvis!(Brain, experience::Experience)::LearningResult
    
Update brain based on experience tuple.
"""
function learn!(brain::JarvisBrain, experience::Experience)::LearningResult

"""
    evaluate_value(brain::NeuralBrainCore, perception::Vector{Float32})::Float32
    
Evaluate expected cumulative reward for given perception.
"""
function evaluate_value(brain::NeuralBrainCore, perception::Vector{Float32})::Float32
```

### 2.2.6 Integration Points
- **Input:** BrainInput (perception vector, goal context)
- **Output:** BrainOutput (advisory proposals)
- **Training:** Experience replay from reflection events

### 2.2.7 Failure Modes
| Failure Mode | Detection | Recovery |
|--------------|----------|----------|
| Brain inference fails | Exception caught | Fallback: DENY all proposals |
| Neural network unavailable | Health check | Switch to heuristic mode with warning |
| Training loop crashes | Exception caught | Continue with frozen weights |

### 2.2.8 Security Risks
- **Brain Hijacking:** External component modifies brain state
  - **Mitigation:** Immutable brain after initialization
- **Output Manipulation:** Brain outputs tampered before reaching kernel
  - **Mitigation:** Output validation, cryptographic signing

### 2.2.9 Minimal Viable Implementation Code Skeleton (Julia)

```julia
# adaptive-kernel/brain/NeuralBrain.jl - New file

using Flux
using Statistics

"""
    create_brain(config::BrainConfig)::JarvisBrain
"""
function create_brain(config::BrainConfig=BrainConfig())::JarvisBrain
    brain = JarvisBrain(config)
    
    # Initialize neural networks if not using fallback
    if config.model_path !== nothing
        brain.brain_core = _load_neural_brain(config.model_path)
    else
        # Create new untrained brain with default architecture
        brain.brain_core = _create_default_brain()
    end
    
    brain.initialized = true
    @info "Brain initialized" trained=(config.model_path !== nothing)
    return brain
end

"""
    _create_default_brain - Default architecture when no pretrained model
"""
function _create_default_brain()
    encoder = Chain(
        Dense(12, 64, relu),
        Dense(64, 128, relu),
        Dense(128, 64)
    )
    
    policy_network = Chain(
        Dense(64, 32, relu),
        Dense(32, length(CLAW_TOOLS), softmax)  # Output: action probabilities
    )
    
    value_network = Chain(
        Dense(64, 32, relu),
        Dense(32, 1, sigmoid)  # Output: value estimate [0, 1]
    )
    
    return NeuralBrainCore(
        encoder,
        policy_network,
        value_network,
        64,  # latent_dim
        ExperienceReplayBuffer(10000),
        ADAM(0.001),
        deepcopy(policy_network),  # target network
        [Dropout(0.1)],  # dropout for uncertainty
        []  # ensemble models
    )
end

"""
    infer_brain - Full brain inference with uncertainty estimation
"""
function infer_brain(brain::JarvisBrain, input::BrainInput)::BrainOutput
    # P0: Validate boundary - brain receives COPY, never original state
    perception = copy(input.perception_vector)
    
    # Forward pass through encoder
    latent = brain.brain_core.encoder(perception)
    
    # Policy forward pass - get action logits
    action_logits = brain.brain_core.policy_network(latent)
    
    # Value forward pass - estimate expected reward
    value = brain.brain_core.value_network(latent)[1]
    
    # Uncertainty estimation via dropout sampling
    uncertainty = _estimate_uncertainty(brain.brain_core, perception)
    
    # Get top-k actions
    top_actions = _get_top_actions(action_logits, CLAW_TOOLS)
    
    return BrainOutput(
        top_actions,
        value,
        value,  # value_estimate
        uncertainty,
        "Neural brain inference completed",
        latent
    )
end

"""
    _estimate_uncertainty - Monte Carlo dropout for epistemic uncertainty
"""
function _estimate_uncertainty(brain::NeuralBrainCore, perception::Vector{Float32})::Float32
    n_samples = 10
    values = Float32[]
    
    for _ in 1:n_samples
        # Enable dropout at inference
        latent = brain.encoder(perception)
        v = brain.value_network(latent)[1]
        push!(values, v)
    end
    
    # Variance as uncertainty measure
    return Float32(var(values))
end

"""
    learn! - Update brain from experience
"""
function learn!(brain::JarvisBrain, experience::Experience)::LearningResult
    # Add to experience buffer
    push!(brain.experience_buffer, experience)
    
    # Sample batch if buffer has enough data
    if brain.experience_buffer.size >= 32
        batch = sample(brain.experience_buffer, 32)
        
        # Compute gradients and update
        loss = _train_step!(brain.brain_core, batch)
        
        return LearningResult(true, loss, length(batch))
    end
    
    return LearningResult(false, 0.0f0, 0)
end

"""
    _train_step! - Single training step
"""
function _train_step!(brain::NeuralBrainCore, batch::Vector{Experience})::Float32
    states = [exp.state for exp in batch]
    rewards = Float32[exp.reward for exp in batch]
    
    # Compute loss (simple MSE for value function)
    latent = brain.encoder.(states)
    predictions = brain.value_network.(latent)
    
    loss = mean((predictions .- rewards).^2)
    
    # Backpropagation
    Flux.Optimise.update!(brain.optimizer, params(brain.value_network), 
                          Flux.Zygote.gradient(() -> loss, params(brain.value_network)))
    
    return loss
end
```

### 2.2.10 Testing Requirements
- **Unit Tests:**
  - `test_brain_output_is_advisory`: Verify brain never produces executable actions
  - `test_brain_boundary_invariant`: Verify brain-kernel boundary is maintained
  - `test_uncertainty_estimation`: Verify uncertainty estimation is reasonable
- **Integration Tests:**
  - `test_brain_kernel_integration`: Verify brain output reaches kernel correctly
  - `test_training_loop`: Verify learning from experience

---

## PHASE 3: Type System Unification (CRITICAL - P1)

### 2.3.1 Architectural Role
All modules must share a unified type system. No structural mismatches. No duplicate ActionProposal definitions.

### 2.3.2 Required File Modifications
- **File:** [`adaptive-kernel/types.jl`](adaptive-kernel/types.jl:1)
  - Consolidate IntegrationActionProposal
  - Resolve risk type mismatch (String vs Float32)
- **File:** [`jarvis/src/types.jl`](jarvis/src/types.jl:1)
  - Remove duplicate ActionProposal definitions
  - Use canonical shared types

### 2.3.3 New Files to Create
- **File:** `adaptive-kernel/shared/CanonicalTypes.jl`
  - Single source of truth for all shared types

### 2.3.4 Data Structures

```julia
# adaptive-kernel/shared/CanonicalTypes.jl - New file

module CanonicalTypes

using Dates
using UUIDs

export 
    # Core types
    ActionProposal,
    WorldState,
    RiskLevel,
    TrustLevel,
    
    # Enums
    @enum RiskLevel LOW_RISK MEDIUM_RISK HIGH_RISK CRITICAL_RISK,
    @enum TrustLevel TRUST_BLOCKED TRUST_RESTRICTED TRUST_LIMITED TRUST_STANDARD TRUST_FULL,

# ============================================================================
# CANONICAL ACTION PROPOSAL - Single source of truth
# ============================================================================

"""
    ActionProposal - Unified action proposal across all modules
    Fields CANNOT change without system-wide coordination
"""
struct ActionProposal
    id::UUID
    capability_id::String
    confidence::Float32          # [0, 1]
    predicted_cost::Float32      # [0, 1]
    predicted_reward::Float32    # [0, 1]
    risk::RiskLevel             # Enum, NOT String or Float32
    reasoning::String
    impact_estimate::Float32    # [0, 1]
    timestamp::DateTime
    
    function ActionProposal(
        capability_id::String,
        confidence::Float32,
        cost::Float32,
        reward::Float32,
        risk::RiskLevel;
        reasoning::String = "",
        impact::Float32 = 0.5f0
    )
        new(uuid4(), capability_id, clamp(confidence, 0f0, 1f0), 
            clamp(cost, 0f0, 1f0), clamp(reward, 0f0, 1f0),
            risk, reasoning, clamp(impact, 0f0, 1f0), now())
    end
end

# Risk level functions
parse_risk_level(x::String)::RiskLevel = ...
parse_risk_level(x::Float32)::RiskLevel = ...
risk_to_float(r::RiskLevel)::Float32 = ...
risk_to_string(r::RiskLevel)::String = ...

# ============================================================================
# CANONICAL WORLD STATE - Unified world observation
# ============================================================================

"""
    WorldState - Unified world state representation
"""
struct WorldState
    timestamp::DateTime
    cpu_load::Float32
    memory_usage::Float32
    disk_io::Float32
    network_latency::Float32
    overall_severity::Float32
    threat_count::Int
    trust_level::TrustLevel
    kernel_approvals::Int
    kernel_denials::Int
    available_capabilities::Vector{String}
end

end # CanonicalTypes
```

### 2.3.5 Interface Contracts

```julia
# Type conversion functions

"""
    convert_to_canonical(proposal)::CanonicalTypes.ActionProposal
Convert any proposal format to canonical form.
"""
function convert_to_canonical(proposal)::CanonicalTypes.ActionProposal

"""
    convert_from_canonical(canonical)::ActionProposal
Convert from canonical to module-specific format.
"""
function convert_from_canonical(canonical)::ActionProposal
```

### 2.3.6 Integration Points
- All modules import from CanonicalTypes
- Conversion layer handles legacy types

### 2.3.7 Failure Modes
| Failure Mode | Detection | Recovery |
|--------------|----------|----------|
| Type mismatch | Type check failure | Use conversion layer |
| Missing field | Validation failure | Reject with error |

### 2.3.8 Security Risks
- **Type Confusion:** Attacker exploits type mismatch
  - **Mitigation:** Strict type validation at boundaries

### 2.3.9 Minimal Viable Implementation Code Skeleton

```julia
# adaptive-kernel/shared/CanonicalTypes.jl - New file

@enum RiskLevel LOW_RISK MEDIUM_RISK HIGH_RISK CRITICAL_RISK

# Risk level conversions
function parse_risk_level(s::String)::RiskLevel
    s == "low" && return LOW_RISK
    s == "medium" && return MEDIUM_RISK
    s == "high" && return HIGH_RISK
    s == "critical" && return CRITICAL_RISK
    return LOW_RISK  # Default to safe
end

function parse_risk_level(f::Float32)::RiskLevel
    f < 0.25f0 && return LOW_RISK
    f < 0.5f0 && return MEDIUM_RISK
    f < 0.75f0 && return HIGH_RISK
    return CRITICAL_RISK
end

function risk_to_float(r::RiskLevel)::Float32
    r == LOW_RISK && return 0.1f0
    r == MEDIUM_RISK && return 0.3f0
    r == HIGH_RISK && return 0.7f0
    r == CRITICAL_RISK && return 0.9f0
end
```

### 2.3.10 Testing Requirements
- **Unit Tests:**
  - `test_risk_level_parsing`: Verify risk parsing from String/Float32
  - `test_type_conversions`: Verify bidirectional conversion
- **Integration Tests:**
  - `test_cross_module_types`: Verify all modules use canonical types

---

## PHASE 4: Voice Module (STT/TTS)

### 2.4.1 Architectural Role
Voice module provides speech input (STT) and output (TTS) capabilities for multimodal interaction.

### 2.4.2 Required File Modifications
- **File:** [`jarvis/src/bridge/CommunicationBridge.jl`](jarvis/src/bridge/CommunicationBridge.jl:1)
  - Add STT integration
  - Add TTS integration

### 2.4.3 New Files to Create
- **File:** `jarvis/src/voice/STT.jl`
- **File:** `jarvis/src/voice/TTS.jl`

### 2.4.4 Data Structures

```julia
# jarvis/src/voice/STT.jl

"""
    STTConfig - Speech-to-Text configuration
"""
struct STTConfig
    provider::Symbol  # :openai (whisper), :coqui
    api_key::String
    model::String    # "whisper-1" for OpenAI
    language::String
    sample_rate::Int
end

"""
    STTResult - Result from speech-to-text
"""
struct STTResult
    text::String
    confidence::Float32
    duration::Float32
    language::String
end
```

### 2.4.5 Interface Contracts

```julia
"""
    transcribe(audio_data::Vector{Int16}, config::STTConfig)::STTResult
"""
function transcribe(audio_data::Vector{Int16}, config::STTConfig)::STTResult

"""
    stream_transcribe(audio_stream::Channel, config::STTConfig)::Channel{String}
"""
function stream_transcribe(audio_stream::Channel, config::STTConfig)::Channel{String}
```

### 2.4.6 Integration Points
- **Input:** Audio stream from microphone
- **Output:** Text to NLP pipeline
- **Config:** From config.toml

### 2.4.7 Failure Modes
| Failure Mode | Detection | Recovery |
|--------------|----------|----------|
| API unavailable | HTTP error | Fallback to local Whisper |
| Audio quality poor | Low confidence | Request retry |

### 2.4.8 Security Risks
- **API Key Exposure:** Keys in config files
  - **Mitigation:** Use environment variables

### 2.4.9 Implementation Skeleton

```julia
# jarvis/src/voice/STT.jl

using HTTP
using JSON

"""
    transcribe_with_whisper - OpenAI Whisper integration
"""
function transcribe_with_whisper(audio_data::Vector{Int16}, config::STTConfig)::STTResult
    # Convert audio to base64
    audio_base64 = base64encode(audio_data)
    
    body = Dict(
        "model" => config.model,
        "file" => audio_base64,
        "language" => config.language
    )
    
    headers = [
        "Authorization" => "Bearer $(config.api_key)",
        "Content-Type" => "application/json"
    ]
    
    response = HTTP.post(
        "https://api.openai.com/v1/audio/transcriptions",
        headers=headers,
        JSON.json(body),
        timeout=30
    )
    
    result = JSON.parse(String(response.body))
    
    return STTResult(
        result["text"],
        get(result, "confidence", 0.9f0),
        get(result, "duration", 0.0f0),
        config.language
    )
end
```

---

## PHASE 5: Vision Module (VLM)

### 2.5.1 Architectural Role
Vision module processes image inputs using Vision Language Models for multimodal understanding.

### 2.5.2 Required File Modifications
- **File:** [`jarvis/src/bridge/CommunicationBridge.jl`](jarvis/src/bridge/CommunicationBridge.jl:1)
  - Add VLM integration

### 2.5.3 New Files to Create
- **File:** `jarvis/src/vision/VLM.jl`

### 2.5.4 Data Structures

```julia
# jarvis/src/vision/VLM.jl

"""
    VLMConfig - Vision Language Model configuration
"""
struct VLMConfig
    provider::Symbol  # :openai (gpt-4v), :anthropic (claude-v)
    api_key::String
    model::String
    max_tokens::Int
end

"""
    VLMResult - Result from vision analysis
"""
struct VLMResult
    description::String
    objects::Vector{String}
    text_detected::String
    confidence::Float32
end
```

### 2.5.5 Interface Contracts

```julia
"""
    analyze_image(image_path::String, prompt::String, config::VLMConfig)::VLMResult
"""
function analyze_image(image_path::String, prompt::String, config::VLMConfig)::VLMResult
```

---

## PHASE 6: Real System Observation

### 2.6.1 Architectural Role
Replace mock metrics with real system telemetry for accurate world state observation.

### 2.6.2 Required File Modifications
- **File:** [`adaptive-kernel/kernel/Kernel.jl`](adaptive-kernel/kernel/Kernel.jl:26)
  - Replace Observation struct with real data collectors

### 2.6.3 New Files to Create
- **File:** `adaptive-kernel/observation/SystemObserver.jl`

### 2.6.4 Data Structures

```julia
# adaptive-kernel/observation/SystemObserver.jl

"""
    SystemObserver - Real system telemetry collector
"""
mutable struct SystemObserver
    cpu_monitor::CPUMonitor
    memory_monitor::MemoryMonitor
    disk_monitor::DiskMonitor
    network_monitor::NetworkMonitor
    last_observation::Union{Observation, Nothing}
    observation_interval::Second
end

"""
    collect_observation(observer::SystemObserver)::Observation
"""
function collect_observation(observer::SystemObserver)::Observation
```

---

## PHASE 7: OpenClaw Tool Integration

### 2.7.1 Architectural Role
Execute tools from OpenClaw container with sandboxing and capability-based access control.

### 2.7.2 Required File Modifications
- **File:** [`jarvis/src/bridge/OpenClawBridge.jl`](jarvis/src/bridge/OpenClawBridge.jl:1)
  - Add sandbox execution
  - Add capability-based access control

### 2.7.3 New Files to Create
- **File:** `jarvis/src/sandbox/ToolSandbox.jl`
- **File:** `jarvis/src/security/CapabilityRegistry.jl`

### 2.7.4 Data Structures

```julia
# jarvis/src/sandbox/ToolSandbox.jl

"""
    SandboxConfig - Configuration for tool sandboxing
"""
struct SandboxConfig
    enabled::Bool
    timeout_seconds::Float64
    max_memory_mb::Int
    allowed_categories::Vector{String}
    blocked_tools::Vector{String}
end

"""
    SandboxResult - Result from sandboxed execution
"""
struct SandboxResult
    success::Bool
    output::Any
    error::Union{String, Nothing}
    execution_time_ms::Float64
    memory_used_mb::Int
end
```

---

## PHASE 8: Persistence & Checkpointing

### 2.8.1 Architectural Role
SQLite-backed state persistence with crash recovery and snapshot restore.

### 2.8.2 Required File Modifications
- **File:** [`adaptive-kernel/persistence/Persistence.jl`](adaptive-kernel/persistence/Persistence.jl:1)
  - Add SQLite backend

### 2.8.3 New Files to Create
- **File:** `adaptive-kernel/persistence/SQLiteStore.jl`
- **File:** `adaptive-kernel/persistence/CheckpointManager.jl`

### 2.8.4 Data Structures

```julia
# adaptive-kernel/persistence/SQLiteStore.jl

using SQLite

"""
    SQLiteStore - SQLite-backed persistence
"""
mutable struct SQLiteStore
    db::SQLite.DB
    checkpoint_interval::Second
    last_checkpoint::DateTime
end

# Schema:
# - kernel_state: id, cycle, goals_json, self_metrics_json, timestamp
# - reflection_events: id, cycle, action_id, confidence, reward, timestamp
# - conversation_history: id, role, content, timestamp

"""
    save_checkpoint(store::SQLiteStore, kernel::KernelState)
"""
function save_checkpoint(store::SQLiteStore, kernel::KernelState)

"""
    restore_latest_checkpoint(store::SQLiteStore)::KernelState
"""
function restore_latest_checkpoint(store::SQLiteStore)::KernelState
```

---

## PHASE 9: Configuration & Secrets Management

### 2.9.1 Architectural Role
Environment-based configuration with secure secrets handling.

### 2.9.2 Required File Modifications
- **File:** [`config.toml`](config.toml:1)
  - Document environment variable schema

### 2.9.3 New Files to Create
- **File:** `jarvis/src/config/SecretsManager.jl`

### 2.9.4 Data Structures

```julia
# jarvis/src/config/SecretsManager.jl

"""
    SecretsManager - Secure secrets handling
"""
mutable struct SecretsManager
    vault_enabled::Bool
    env_prefix::String  # "JARVIS_"
end

"""
    get_secret(manager::SecretsManager, key::String)::String
"""
function get_secret(manager::SecretsManager, key::String)::String
    # Priority: Vault > Environment Variable > Config
end
```

---

## PHASE 10: Trust & Confirmation Model

### 2.10.1 Architectural Role
Risk-based confirmation gates with real-time trust adjustment.

### 2.10.2 Required File Modifications
- **File:** [`jarvis/src/types.jl`](jarvis/src/types.jl:49)
  - Implement trust level logic

### 2.10.3 New Files to Create
- **File:** `adaptive-kernel/security/TrustClassifier.jl`
- **File:** `adaptive-kernel/security/ConfirmationGate.jl`

### 2.10.4 Data Structures

```julia
# adaptive-kernel/security/TrustClassifier.jl

"""
    TrustClassifier - Real-time trust level determination
"""
mutable struct TrustClassifier
    current_level::TrustLevel
    history::Vector{TrustEvent}
    decay_factor::Float32
end

"""
    ConfirmationGate - Risk-based confirmation requirement
"""
struct ConfirmationGate
    thresholds::Dict{RiskLevel, TrustLevel}  # Risk -> min trust required
end

"""
    requires_confirmation(gate::ConfirmationGate, risk::RiskLevel, trust::TrustLevel)::Bool
"""
function requires_confirmation(gate::ConfirmationGate, risk::RiskLevel, trust::TrustLevel)::Bool
```

---

# 3. IMPLEMENTATION SEQUENCE ROADMAP

## 3.1 Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            DEPENDENCY GRAPH                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  Phase 1: Kernel State Init                                                     │
│  ├── No dependencies (CRITICAL PATH)                                            │
│  └── Enables: All subsequent phases                                             │
│                                                                                  │
│  Phase 2: Brain Full Integration                                                │
│  ├── Depends on: Phase 1 (Kernel State)                                         │
│  └── Enables: Phase 3                                                           │
│                                                                                  │
│  Phase 3: Type System Unification                                               │
│  ├── Depends on: Phase 1                                                        │
│  └── Enables: All modules                                                       │
│                                                                                  │
│  Phase 4: Voice Module (STT/TTS)                                                │
│  ├── Depends on: Phase 3                                                        │
│  └── Enables: Multimodal interaction                                            │
│                                                                                  │
│  Phase 5: Vision Module (VLM)                                                   │
│  ├── Depends on: Phase 3                                                        │
│  └── Enables: Multimodal interaction                                             │
│                                                                                  │
│  Phase 6: Real System Observation                                               │
│  ├── Depends on: Phase 1, Phase 3                                               │
│  └── Enables: Accurate world state                                              │
│                                                                                  │
│  Phase 7: OpenClaw Integration                                                  │
│  ├── Depends on: Phase 1, Phase 3                                               │
│  └── Enables: Tool execution                                                    │
│                                                                                  │
│  Phase 8: Persistence                                                           │
│  ├── Depends on: Phase 1                                                        │
│  └── Enables: Crash recovery, state restore                                    │
│                                                                                  │
│  Phase 9: Secrets Management                                                    │
│  ├── Depends on: Phase 3                                                        │
│  └── Enables: Secure API key handling                                           │
│                                                                                  │
│  Phase 10: Trust Model                                                          │
│  ├── Depends on: Phase 1, Phase 3, Phase 7                                      │
│  └── Enables: Confirmation gates                                               │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Parallelizable Phases

| Phase | Can Parallelize With |
|-------|---------------------|
| Phase 4 (Voice) | Phase 5 (Vision) |
| Phase 6 (Observation) | Phase 7 (OpenClaw) |
| Phase 8 (Persistence) | Phase 9 (Secrets) |

## 3.3 Critical Path

```
Phase 1 (Kernel State) → Phase 2 (Brain Integration) → Phase 3 (Types)
```

## 3.4 Risk Ranking

| Phase | Risk Level | Reason |
|-------|------------|--------|
| Phase 1: Kernel State | CRITICAL | Foundation - if broken, nothing works |
| Phase 2: Brain Integration | CRITICAL | Core cognitive function |
| Phase 3: Type Unification | HIGH | Breaking change if not done carefully |
| Phase 10: Trust Model | HIGH | Security critical |
| Phase 7: OpenClaw | HIGH | External execution |
| Phase 8: Persistence | MEDIUM | Data integrity |
| Phase 4-6: I/O Modules | MEDIUM | External dependencies |
| Phase 9: Secrets | MEDIUM | Security |

## 3.5 Estimated Complexity

| Phase | Complexity (Story Points) |
|-------|--------------------------|
| Phase 1: Kernel State | 5 |
| Phase 2: Brain Integration | 13 |
| Phase 3: Type Unification | 8 |
| Phase 4: Voice | 5 |
| Phase 5: Vision | 5 |
| Phase 6: Observation | 3 |
| Phase 7: OpenClaw | 8 |
| Phase 8: Persistence | 8 |
| Phase 9: Secrets | 3 |
| Phase 10: Trust | 5 |
| **TOTAL** | **63** |

---

# 4. PRODUCTION HARDENING

## 4.1 Structured Logging Standard

```julia
# Log format: JSON with structured fields
# {
#   "timestamp": "2026-02-26T04:25:40.799Z",
#   "level": "INFO",
#   "component": "kernel",
#   "event": "approve",
#   "proposal_id": "uuid",
#   "decision": "APPROVED",
#   "risk": "LOW",
#   "trace_id": "uuid"
# }
```

## 4.2 Observability Stack

| Component | Implementation |
|-----------|---------------|
| Metrics | Prometheus.jl |
| Tracing | OpenTelemetry.jl |
| Logging | JSON logs to stdout |
| Alerting | PagerDuty webhooks |

## 4.3 Circuit Breaker Design

```julia
mutable struct CircuitBreaker
    state::CircuitState  # CLOSED, OPEN, HALF_OPEN
    failure_count::Int
    success_count::Int
    last_failure_time::DateTime
    threshold::Int  # failures before open
    reset_timeout::Second
end
```

## 4.4 Graceful Degradation Paths

| Component Failure | Degradation Path |
|-------------------|------------------|
| Brain unavailable | Kernel heuristic mode |
| Voice API unavailable | Text-only mode |
| Vision API unavailable | Skip image analysis |
| OpenClaw unavailable | Block tool execution, notify user |
| Persistence unavailable | In-memory mode with warning |

## 4.5 Health Checks

```
GET /health
Response: {
  "status": "healthy",
  "components": {
    "kernel": "healthy",
    "brain": "healthy",
    "persistence": "healthy"
  },
  "uptime_seconds": 3600
}
```

## 4.6 Deployment Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                      DEPLOYMENT TOPOLOGY                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐                                                │
│  │  Load       │                                                │
│  │  Balancer   │                                                │
│  └──────┬──────┘                                                │
│         │                                                        │
│  ┌──────▼──────┐                                                │
│  │  Jarvis     │  ← Container (Docker)                           │
│  │  Service    │                                                │
│  └──────┬──────┘                                                │
│         │                                                        │
│  ┌──────┴──────┐                                                │
│  │             │                                                │
│  │  ┌────────┐ │    ┌─────────┐    ┌─────────────┐             │
│  │  │Kernel  │ │    │  Brain  │    │  OpenClaw  │             │
│  │  │(Julia) │ │    │ (Flux)  │    │  (Docker)  │             │
│  │  └────────┘ │    └─────────┘    └─────────────┘             │
│  │             │                                                │
│  │  ┌────────┐ │    ┌─────────┐    ┌─────────────┐             │
│  │  │Memory  │ │    │Secrets  │    │ Persistence │             │
│  │  │(Redis) │ │    │ (Vault) │    │  (SQLite)  │             │
│  │  └────────┘ │    └─────────┘    └─────────────┘             │
│  │             │                                                │
│  └─────────────┘                                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 4.7 CI/CD Outline

```yaml
# .github/workflows/ci.yml
stages:
  - test:
      - unit tests
      - integration tests
  - security:
      - vulnerability scan
      - secrets detection
  - build:
      - Docker image build
      - artifact upload
  - deploy:
      - staging deployment
      - integration tests
      - production deployment
```

---

# 5. DEFINITION OF DONE

## 5.1 "Kernel Sovereignty Achieved"

| Criterion | Measurement | Threshold |
|-----------|-------------|-----------|
| Kernel state never nothing | Automated test verifies 1000 init cycles | 100% pass |
| approve() always returns | Test timeout injection | <1ms fallback |
| Boundary invariant enforced | Audit log verification | All brain→kernel calls logged |
| Fail-closed on errors | Chaos injection tests | No unapproved execution |

## 5.2 "Brain Fully Integrated"

| Criterion | Measurement | Threshold |
|-----------|-------------|-----------|
| Neural inference active | Log verification | Brain inference in 95%+ cycles |
| Training loop wired | Experience buffer usage | 100+ experiences stored/cycle |
| Fallback disabled | Configuration check | fallback_to_heuristic=false |
| Boundary maintained | Integration test | No direct brain→tool execution |

## 5.3 "Multimodal Complete"

| Criterion | Measurement | Threshold |
|-----------|-------------|-----------|
| Voice STT functional | Test transcription | <5% WER |
| Voice TTS functional | Test synthesis | Latency <500ms |
| Vision VLM functional | Test image analysis | Returns valid description |
| Unified perception | Type check | All modalities use PerceptionVector |

## 5.4 "Persistence Durable"

| Criterion | Measurement | Threshold |
|-----------|-------------|-----------|
| Crash recovery | Kill -9 test | State restored within 5s |
| Checkpoint interval | Log verification | <=60s between checkpoints |
| Data integrity | Checksum verification | 100% consistency |
| Conversation history | Query test | Full history retrievable |

## 5.5 "Production Ready"

| Criterion | Measurement | Threshold |
|-----------|-------------|-----------|
| Uptime | Production monitoring | 99.9% |
| Latency | P95 response time | <500ms |
| Error rate | Production metrics | <1% |
| Security scan | Vulnerability scan | 0 critical findings |
| Documentation | Code coverage | >80% documented |

---

# APPENDIX: FILE MODIFICATION SUMMARY

## Required File Modifications

| File | Change Type | Lines |
|------|-------------|-------|
| adaptive-kernel/kernel/Kernel.jl | Modify | Add approve(), evaluate() |
| adaptive-kernel/types.jl | Modify | Add CanonicalTypes |
| jarvis/src/types.jl | Modify | Remove duplicates |
| jarvis/src/SystemIntegrator.jl | Modify | Wire brain integration |
| jarvis/src/bridge/CommunicationBridge.jl | Modify | Add voice/vision |
| jarvis/src/bridge/OpenClawBridge.jl | Modify | Add sandboxing |
| adaptive-kernel/persistence/Persistence.jl | Modify | Add SQLite |
| config.toml | Modify | Document env vars |

## New Files to Create

| File | Purpose |
|------|---------|
| adaptive-kernel/kernel/StateValidator.jl | State integrity validation |
| adaptive-kernel/brain/NeuralBrain.jl | Full neural brain |
| adaptive-kernel/shared/CanonicalTypes.jl | Unified type system |
| adaptive-kernel/observation/SystemObserver.jl | Real telemetry |
| jarvis/src/voice/STT.jl | Speech-to-text |
| jarvis/src/voice/TTS.jl | Text-to-speech |
| jarvis/src/vision/VLM.jl | Vision language model |
| jarvis/src/sandbox/ToolSandbox.jl | Tool sandboxing |
| jarvis/src/security/CapabilityRegistry.jl | Access control |
| adaptive-kernel/persistence/SQLiteStore.jl | SQLite backend |
| adaptive-kernel/persistence/CheckpointManager.jl | Crash recovery |
| jarvis/src/config/SecretsManager.jl | Secrets handling |
| adaptive-kernel/security/TrustClassifier.jl | Trust levels |
| adaptive-kernel/security/ConfirmationGate.jl | Confirmation gates |

---

**END OF IMPLEMENTATION BLUEPRINT**
