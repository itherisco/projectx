# Jarvis Production Implementation Plan
## Project Jarvis - Sovereign Neuro-Symbolic AI System

**Generated:** 2026-02-26  
**Status:** PRODUCTION IMPLEMENTATION SPECIFICATION  
**Classification:** SOVEREIGN AI INFRASTRUCTURE  

---

## Table of Contents

1. [System Completion Blueprint](#1-system-completion-blueprint)
2. [Critical Gap Implementation Plans](#2-critical-gap-implementation-plans)
   - [A. Full ITHERIS Neural Brain Activation](#a-full-itheris-neural-brain-activation)
   - [B. Adaptive Kernel Sovereignty Enforcement](#b-adaptive-kernel-sovereignty-enforcement)
   - [C. Real System Observation Integration](#c-real-system-observation-integration)
   - [D. Voice Module (STT/TTS)](#d-voice-module-stttts)
   - [E. Vision Module (VLM)](#e-vision-module-vlm)
   - [F. OpenClaw Tooling Integration](#f-openclaw-tooling-integration)
   - [G. Persistence & Checkpointing](#g-persistence--checkpointing)
   - [H. Configuration & Secrets Management](#h-configuration--secrets-management)
   - [I. Trust & Confirmation Model](#i-trust--confirmation-model)
   - [J. Error Handling & Recovery Architecture](#j-error-handling--recovery-architecture)
3. [Integration Sequencing Roadmap](#3-integration-sequencing-roadmap)
4. [Production Hardening Requirements](#4-production-hardening-requirements)
5. [Final State Definition](#5-final-state-definition)

---

## 1. SYSTEM COMPLETION BLUEPRINT

### 1.1 High-Level Final Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        JARVIS PRODUCTION ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                      PERCEPTION LAYER (Input)                            │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │    │
│  │  │  Voice       │  │  Vision      │  │  Text/JSON  │  │   System   │  │    │
│  │  │  (Whisper)   │  │  (GPT-4V)    │  │  (REST API) │  │ Telemetry  │  │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬──────┘  │    │
│  │         │                  │                  │                 │        │    │
│  │         └──────────────────┼──────────────────┼─────────────────┘        │    │
│  │                            ▼                                           │    │
│  │                   ┌─────────────────┐                                 │    │
│  │                   │ PerceptionVector │ ◄── Unified 12D input format │    │
│  │                   └────────┬────────┘                                 │    │
│  └─────────────────────────────┼────────────────────────────────────────────┘    │
│                                ▼                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                      COGNITION LAYER (Brain)                            │    │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │    │
│  │  │                        ITHERIS BRAIN                            │   │    │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌──────────┐ │   │    │
│  │  │  │  Encoder   │  │  Policy    │  │   Value    │  │ Memory   │ │   │    │
│  │  │  │  Network  │──│  Network  │──│  Network   │──│ Embedding│ │   │    │
│  │  │  └────────────┘  └────────────┘  └────────────┘  └──────────┘ │   │    │
│  │  │        │                                     │                  │   │    │
│  │  │        └──────────────┬──────────────────────┘                  │   │    │
│  │  │                       ▼                                           │   │    │
│  │  │              ┌─────────────────┐                                  │   │    │
│  │  │              │  BrainOutput    │ ◄── ADVISORY PROPOSAL         │   │    │
│  │  │              │  (Thought)      │    (confidence, value,        │   │    │
│  │  │              └─────────────────┘     uncertainty)               │   │    │
│  │  └──────────────────────────────────────────────────────────────────┘   │    │
│  │                              │ ADVISORY ONLY                            │    │
│  │                              ▼                                          │    │
│  └──────────────────────────────┼───────────────────────────────────────────┘    │
│                                 ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    SOVEREIGNTY LAYER (Kernel)                          │    │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │    │
│  │  │                     ADAPTIVE KERNEL                              │   │    │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐ │   │    │
│  │  │  │ WorldState │  │   Goal     │  │ Reflection │  │   Trust    │ │   │    │
│  │  │  │  Observer  │  │  Manager   │  │   Engine   │  │  Classifier│ │   │    │
│  │  │  └─────┬──────┘  └──────┬─────┘  └──────┬─────┘  └─────┬──────┘ │   │    │
│  │  │        │                │                │              │        │   │    │
│  │  │        └────────────────┼────────────────┼──────────────┘        │   │    │
│  │  │                         ▼                                     │   │    │
│  │  │              ┌─────────────────────┐                          │   │    │
│  │  │              │  Kernel.approve()  │ ◄── SOVEREIGN DECISION  │   │    │
│  │  │              │  (APPROVE/DENY/STOP)│    NO EXCEPTION        │   │    │
│  │  │              └──────────┬──────────┘                          │   │    │
│  │  └─────────────────────────┼────────────────────────────────────┘   │    │
│  │                            │ APPROVED                                │    │
│  │                            ▼                                         │    │
│  └────────────────────────────┼────────────────────────────────────────┘    │
│                               ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                    EXECUTION LAYER (Action)                             │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │    │
│  │  │  OpenClaw   │  │  Capability  │  │   System     │  │   Safety   │ │    │
│  │  │   Tools     │  │   Registry   │  │  Commands    │  │   Guard    │ │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └─────┬──────┘ │    │
│  │         │                  │                  │                │        │    │
│  │         └──────────────────┼──────────────────┘                │        │    │
│  │                            ▼                                    │        │    │
│  │                   ┌─────────────────┐                         │        │    │
│  │                   │  ActionResult   │ ◄── Execution outcome  │        │    │
│  │                   └────────┬────────┘                         │        │    │
│  └─────────────────────────────┼──────────────────────────────────┘        │
│                                ▼                                             │
│                               FEEDBACK                                        │
│                                │                                              │
│                                ▼                                              │
│              ┌─────────────────────────────────┐                            │
│              │  Kernel.reflect!(proposal,result)│ ◄── Self-model update     │
│              └─────────────────────────────────┘                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                       SUPPORTING INFRASTRUCTURE                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │  Persistence │  │   Secrets    │  │ Observability│  │  Circuit    │        │
│  │   (SQLite)   │  │   (Vault)    │  │  (Metrics)   │  │  Breakers   │        │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘        │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Updated Data Flow Diagram (Text-Based)

```
USER INPUT → [PerceptionVector] → [ITHERIS Brain] → [BrainOutput]
                                                       │
                                                       ▼
                                          ┌─────────────────────┐
                                          │  ADVISORY PROPOSAL  │
                                          │  (confidence, value, │
                                          │   uncertainty)      │
                                          └──────────┬──────────┘
                                                     │
                                                     ▼
                                       [Kernel.approve()] ──→ SOVEREIGN DECISION
                                                     │
                                    ┌────────────────┼────────────────┐
                                    ▼                ▼                ▼
                              [APPROVED]        [DENIED]          [STOPPED]
                                    │                │                 │
                                    ▼                │                 │
                          [Capability Registry]      │                 │
                                    │                │                 │
                                    ▼                │                 │
                            [Tool Execution]         │                 │
                                    │                │                 │
                                    ▼                │                 │
                          [ActionResult]            │                 │
                                    │                │                 │
                                    └────────────────┴────────────────┘
                                                     │
                                                     ▼
                                          [Kernel.reflect!]
                                                     │
                                                     ▼
                                       [Self-Model Update]
                                       [Episode Storage]
```

### 1.3 Revised Sovereignty Enforcement Path

**INVARIANT:** "No action executes without kernel sovereignty approval"

```
┌─────────────────────────────────────────────────────────────────┐
│              SOVEREIGNTY ENFORCEMENT PATH                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. PROPOSAL SUBMISSION                                          │
│     BrainOutput → Kernel.request_approval(proposal)             │
│                                                                  │
│  2. RISK CLASSIFICATION                                          │
│     ├─ capability_id lookup                                      │
│     ├─ risk_level (low/medium/high/critical)                    │
│     ├─ trust_requirement (TRUST_RESTRICTED → TRUST_FULL)        │
│     └─ reversibility assessment                                   │
│                                                                  │
│  3. WORLD STATE VALIDATION                                       │
│     ├─ current_system_health check                              │
│     ├─ goal_alignment verification                              │
│     └─ resource_availability确认                                 │
│                                                                  │
│  4. TRUST CALIBRATION                                            │
│     ├─ user_trust_level retrieval                                │
│     ├─ action_risk vs trust_threshold comparison                 │
│     └─ confirmation_gate evaluation                              │
│                                                                  │
│  5. DECISION (ATOMIC)                                            │
│     APPROVE  → proceed to execution                               │
│     DENY    → log denial, return to cognition                    │
│     STOP    → halt system if critical anomaly                    │
│                                                                  │
│  6. AUDIT TRAIL (NON-NEGOTIABLE)                                 │
│     ├─ timestamp (UTC ISO 8601)                                   │
│     ├─ proposal_hash                                              │
│     ├─ decision + reasoning                                      │
│     ├─ trust_level_at_decision                                    │
│     └─ syscall_context                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.4 Final Perception → Cognition → Execution Loop

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                     COMPLETE COGNITIVE LOOP                                      │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│     ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                │
│     │ PERCEPTION  │ ───► │  COGNITION  │ ───► │ EXECUTION   │                │
│     └─────────────┘      └─────────────┘      └─────────────┘                │
│           │                    │                    │                         │
│           │                    │                    │                         │
│           ▼                    ▼                    ▼                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │ 1. Input        │  │ 4. Brain        │  │ 7. Kernel       │              │
│  │    Normalization│  │    Inference    │  │    Approval     │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│           │                    │                    │                         │
│           │                    │                    │                         │
│           ▼                    ▼                    ▼                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │ 2. Entity       │  │ 5. Proposal     │  │ 8. Capability   │              │
│  │    Extraction   │  │    Generation   │  │    Selection    │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│           │                    │                    │                         │
│           │                    │                    │                         │
│           ▼                    ▼                    ▼                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │ 3. Perception   │  │ 6. BrainOutput │  │ 9. Tool         │              │
│  │    Vector Build │  │    (Advisory)  │  │    Execution    │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│                                                                  │              │
│                                                                  │              │
│     ◄────────────────────────────────────────────────────────────┘              │
│     │                                                                  │
│     │  ┌─────────────────────────────────────────────────────┐                  │
│     │  │              REFLECTION LOOP                         │                  │
│     │  │  10. Result Collection → 11. Kernel.reflect!()       │                  │
│     │  │       → 12. Self-Model Update → 13. Memory Storage  │                  │
│     │  └─────────────────────────────────────────────────────┘                  │
│     │                                                                  │
│     └──────────────────────────────────────────────────── (next cycle)           │
│                                                                                 │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. CRITICAL GAP IMPLEMENTATION PLANS

### A. Full ITHERIS Neural Brain Activation

#### Current State
- [`itheris.jl`](itheris.jl:1) contains neural network definitions using Flux.jl
- BrainCore struct exists with encoder, policy, and value networks
- Training loop stub exists (`train_brain!`) but not wired into cognitive cycle
- Fallback heuristic path used in [`SystemIntegrator`](jarvis/src/SystemIntegrator.jl:200) when brain unavailable

#### Implementation Steps

**A.1 Replace Fallback Heuristic Path**

File: `jarvis/src/SystemIntegrator.jl`

```julia
# BEFORE (fallback heuristic):
function _generate_proposal(state::JarvisState, input::String)::ActionProposal
    # Heuristic fallback - TO BE REMOVED
    confidence = 0.5f0
    # ... simplified logic
end

# AFTER (neural brain activation):
function _generate_proposal(state::JarvisState, input::String)::ActionProposal
    # 1. Encode perception to latent vector
    perception_vec = encode_perception(state.brain_core, input)
    
    # 2. Forward pass through policy network
    action_logits = forward_pass(state.brain_core.policy_network, perception_vec)
    
    # 3. Sample action from policy
    action_id = sample_from_policy(action_logits)
    
    # 4. Evaluate value
    value = forward_pass(state.brain_core.value_network, perception_vec)[1]
    
    # 5. Compute uncertainty (Monte Carlo dropout or ensemble variance)
    uncertainty = compute_uncertainty(state.brain_core, perception_vec)
    
    return ActionProposal(
        capability_id=action_id,
        confidence=value,
        predicted_cost=estimate_cost(action_id),
        predicted_reward=value,
        risk=classify_risk(action_id),
        reasoning="Neural inference: value=$value, uncertainty=$uncertainty"
    )
end
```

**A.2 Integrate Training Loop into Cognitive Cycle**

File: `adaptive-kernel/cognition/Cognition.jl`

```julia
"""
    learn_from_experience!(brain::BrainCore, experience::Experience)
Integrate real-world feedback into neural brain.
"""
function learn_from_experience!(brain::BrainCore, experience::Experience)
    # 1. Compute TD error
    target = experience.reward + γ * brain.value_network(experience.next_state)
    current_value = brain.value_network(experience.state)
    td_error = target - current_value
    
    # 2. Update value network (MSE loss)
    value_loss = Flux.mse(current_value, target)
    Flux.update!(brain.value_optimizer, brain.value_network, value_loss)
    
    # 3. Update policy network (policy gradient with baseline)
    log_prob = brain.policy_network(experience.state)[experience.action]
    policy_loss = -log_prob * td_error  # REINFORCE with baseline
    Flux.update!(brain.policy_optimizer, brain.policy_network, policy_loss)
    
    # 4. Store in experience replay buffer
    push!(brain.replay_buffer, experience)
    
    return Dict("value_loss" => value_loss, "policy_loss" => policy_loss, "td_error" => td_error)
end

# Wire into cognitive cycle:
function run_sovereign_cycle(engine::CognitiveEngine, input::PerceptionVector)
    # ... existing perception and cognition ...
    
    # AFTER execution, integrate feedback:
    result = execute_action(proposal)
    experience = Experience(
        state=perception_vector,
        action=proposal.capability_id,
        reward=compute_reward(result, engine.goal),
        next_state=get_current_world_state()
    )
    learn_from_experience!(engine.brain, experience)
end
```

**A.3 Define Inference Contract**

File: `adaptive-kernel/brain/contracts.jl` (NEW FILE)

```julia
"""
    BrainInferenceContract - Invariant specification for brain-kernel boundary

INVARIANTS:
1. BrainOutput is ALWAYS advisory - kernel maintains sovereignty
2. Brain must produce confidence score in [0, 1]
3. Brain must produce uncertainty estimate for meta-cognition
4. Brain cannot access kernel state directly - receives copy only
"""
struct BrainOutput
    proposed_actions::Vector{String}          # Ranked action candidates
    confidence::Float32                        # [0, 1] confidence in proposal
    value_estimate::Float32                   # Expected cumulative reward
    uncertainty::Float32                       # Epistemic uncertainty [0, 1]
    reasoning::String                          # Natural language explanation
    latent_features::Vector{Float32}          # For memory embedding
end

"""
    BrainInput - Constrained input to brain (copy of relevant state)
"""
struct BrainInput
    perception_vector::Vector{Float32}        # 12D normalized perception
    goal_context::Vector{Float32}             # Goal embedding
    recent_outcomes::Vector{Float32}          # Last N reward signals
    time_constraint::Float32                  # Available thinking time
end
```

**A.4 Define Brain-Kernel Boundary Invariant**

File: `adaptive-kernel/brain/Brain.jl` (NEW FILE)

```julia
"""
    INVARIANT: Brain-Kernel Boundary

The brain and kernel MUST maintain semantic isolation:
- Brain receives: BrainInput (immutable snapshot)
- Brain produces: BrainOutput (advisory only)
- Kernel owns: world_state, goal_states, trust_classifier, approval_logic

No direct brain → kernel state mutation permitted.
All brain outputs pass through kernel.approve() before execution.
"""
const BRAIN_KERNEL_BOUNDARY_INVARIANT = """
BRAIN OUTPUT IS ADVISORY ONLY.
KERNEL SOVEREIGNTY IS ABSOLUTE.
NO EXCEPTION TO APPROVAL GATE.
"""

function validate_boundary_safety(brain_output::BrainOutput)::Bool
    # Validate confidence bounds
    !(0.0f0 <= brain_output.confidence <= 1.0f0) && return false
    !(0.0f0 <= brain_output.uncertainty <= 1.0f0) && return false
    # Validate non-empty proposals
    isempty(brain_output.proposed_actions) && return false
    return true
end
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `jarvis/src/SystemIntegrator.jl` | REPLACE | Replace `_generate_proposal` with neural inference |
| `adaptive-kernel/cognition/Cognition.jl` | EXTEND | Add `learn_from_experience!` integration |
| `adaptive-kernel/brain/contracts.jl` | NEW | Brain inference contract types |
| `adaptive-kernel/brain/Brain.jl` | NEW | Brain module with boundary enforcement |
| `adaptive-kernel/integration/Conversions.jl` | EXTEND | Add BrainOutput ↔ ActionProposal conversion |

#### Testing Strategy

- **Unit Tests:** Forward pass produces valid BrainOutput
- **Integration Tests:** Brain → Kernel → Execution chain
- **Property Tests:** Confidence always in [0,1], uncertainty monotonic with entropy
- **Adversarial Tests:** Inject malformed brain outputs, verify kernel rejection

#### Performance Implications

- Neural inference adds 10-50ms latency (GPU) or 100-500ms (CPU)
- Training batch updates async, doesn't block inference
- Memory: ~100MB for BrainCore with 3-layer networks

---

### B. Adaptive Kernel Sovereignty Enforcement

#### Current State
- [`Kernel.approve()`](adaptive-kernel/kernel/Kernel.jl:300) stub exists
- `reflect!` method exists but not fully wired
- Basic goal management in place
- Missing: audit trail enforcement, formal invariant verification

#### Implementation Steps

**B.1 Complete Kernel.approve() Integration**

File: `adaptive-kernel/kernel/sovereignty/Sovereignty.jl` (NEW FILE)

```julia
"""
    SovereigntyEnforcer - Kernel's sovereign approval gate
"""
struct SovereigntyEnforcer
    audit_log::Channel{AuditEntry}
    trust_classifier::TrustClassifier
    invariant_checker::InvariantChecker
end

"""
    Kernel.approve() - COMPLETE IMPLEMENTATION
"""
function Kernel.approve(
    kernel::KernelState,
    proposal::ActionProposal;
    user_trust_level::TrustLevel = TRUST_STANDARD
)::SovereignDecision
    @sync begin
        # 1. Log proposal receipt (pre-decision)
        audit_entry = AuditEntry(
            timestamp=now(),
            proposal_hash=sha256(proposal),
            phase=:approval_requested,
            decision=nothing
        )
        
        # 2. Validate proposal structure
        !validate_proposal(proposal) && return SovereignDecision(:DENIED, "Invalid proposal structure")
        
        # 3. Lookup capability risk classification
        capability_info = get_capability_registry(proposal.capability_id)
        risk_level = capability_info.risk  # :low, :medium, :high, :critical
        
        # 4. Check trust threshold
        required_trust = trust_threshold_for_risk(risk_level)
        if user_trust_level < required_trust
            log_audit(audit_entry, :denied, "Insufficient trust: $user_trust_level < $required_trust")
            return SovereignDecision(:DENIED, "Trust level too low for $risk_level action")
        end
        
        # 5. Verify system health
        if !is_system_healthy(kernel.world.observations)
            log_audit(audit_entry, :stopped, "System health check failed")
            return SovereignDecision(:STOPPED, "System unhealthy - refusing all actions")
        end
        
        # 6. Check goal alignment
        if !is_goal_aligned(proposal, kernel.active_goal_id)
            log_audit(audit_entry, :denied, "Action not aligned with active goal")
            return SovereignDecision(:DENIED, "Goal misalignment")
        end
        
        # 7. Confirmation gate for high-risk actions
        if risk_level == :critical && !user_confirmed(proposal)
            log_audit(audit_entry, :pending_confirmation, "Awaiting user confirmation")
            return SovereignDecision(:PENDING_CONFIRMATION, "Critical action requires confirmation")
        end
        
        # 8. APPROVE or DENY
        decision = (risk_level == :critical) ? SovereignDecision(:APPROVED, "Critical approved with audit") :
                   SovereignDecision(:APPROVED, "Approved")
        
        log_audit(audit_entry, decision.decision, "Approved")
        return decision
    end
end

# FAILURE MODE: If kernel crashes during approval, default to DENY (fail-closed)
```

**B.2 Wire reflect! Feedback Loop**

File: `adaptive-kernel/kernel/Kernel.jl`

```julia
"""
    reflect! - Self-model update based on action outcomes
    COMPLETE IMPLEMENTATION with formal invariant enforcement
"""
function reflect!(
    kernel::KernelState,
    proposal::ActionProposal,
    result::ActionResult
)::ReflectionEvent
    # 1. Compute prediction error
    prediction_error = abs(result.actual_reward - proposal.predicted_reward)
    
    # 2. Update self-metrics based on outcome
    if result.success
        kernel.self_metrics["confidence"] = min(1.0f0, kernel.self_metrics["confidence"] + 0.05f0)
        kernel.self_metrics["energy"] = max(0.0f0, kernel.self_metrics["energy"] - result.energy_cost)
    else
        kernel.self_metrics["confidence"] = max(0.1f0, kernel.self_metrics["confidence"] - 0.1f0)
    end
    
    # 3. Record reflection event
    event = ReflectionEvent(
        timestamp=now(),
        proposal_sha256=sha256(proposal),
        outcome=result.success ? :success : :failure,
        prediction_error=prediction_error,
        goal_id=kernel.active_goal_id
    )
    
    # 4. Update goal progress
    if result.success
        update_goal_progress!(kernel.goal_states[kernel.active_goal_id], result.progress)
    else
        fail_goal!(kernel.goal_states[kernel.active_goal_id])
    end
    
    # 5. Store in episodic memory (bounded)
    push!(kernel.episodic_memory, event)
    if length(kernel) > MAX_EPISODES
        popfirst!(kernel.episodic_memory)
    end
    
    # 6. Update IntentVector for strategic inertia (Phase 3)
    update_alignment!(kernel.intent_vector, proposal, result)
    
    return event
end

# VERIFY INVARIANT: No action executes without kernel approval
# This is enforced by:
# 1. Kernel.approve() is the ONLY gateway to execution
# 2. Execution layer rejects any non-approved proposals
# 3. Audit log records every approval/denial
```

**B.3 Formal Invariant Implementation**

File: `adaptive-kernel/kernel/sovereignty/invariants.jl` (NEW FILE)

```julia
"""
    FORMAL INVARIANT: "No action executes without kernel sovereignty approval"

This invariant is enforced through:
1. SYNCHRONOUS approval gate (no bypass)
2. AUDIT trail (non-negotiable)
3. FAIL-CLOSED default (deny on error)
4. STATELESS verification (no cached approvals)
"""
const SOVEREIGNTY_INVARIANT = """
INVARIANT: Every action MUST pass through Kernel.approve()
- No exceptions for "trusted" components
- No cached approvals across cycles
- No direct brain → execution path
- Deny on any error condition
"""

function verify_sovereignty_invariant(execution_log::Vector{ExecutionRecord})::Bool
    for record in execution_log
        # Every record must have a corresponding approval
        record.approval_timestamp === nothing && return false
        # Approval must be BEFORE execution
        record.approval_timestamp >= record.execution_timestamp && return false
    end
    return true
end

# Audit trail enforcement - non-negotiable
function log_sovereign_event(event::SovereignEvent)
    # Append to append-only audit log
    # Encrypt sensitive fields
    # Queue for external audit sink
    open("sovereignty_audit.log", "a") do io
        println(io, JSON.json(Dict(
            "timestamp" => now(),
            "event_type" => event.type,
            "proposal_hash" => event.proposal_hash,
            "decision" => event.decision,
            "kernel_version" => KERNEL_VERSION
        )))
    end
end
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `adaptive-kernel/kernel/sovereignty/Sovereignty.jl` | NEW | Complete approval gate implementation |
| `adaptive-kernel/kernel/sovereignty/invariants.jl` | NEW | Formal invariant definitions |
| `adaptive-kernel/kernel/Kernel.jl` | EXTEND | Complete `reflect!` implementation |
| `adaptive-kernel/kernel/audit/Audit.jl` | NEW | Audit trail subsystem |

#### Testing Strategy

- **Invariant Tests:** Verify every execution has prior approval
- **Fail-Closed Tests:** On kernel error, actions must be denied
- **Audit Tests:** Verify all decisions logged with full context
- **Concurrency Tests:** Multiple approval requests don't race

#### Performance Implications

- Approval gate adds ~1-5ms synchronous latency
- Audit logging async, doesn't block execution
- Memory: ~10MB for audit buffer

---

### C. Real System Observation Integration

#### Current State
- [`observe_cpu.jl`](adaptive-kernel/capabilities/observe_cpu.jl:1) reads from `/proc` - PARTIAL REAL
- Other observation capabilities are stubs
- No unified observation aggregation
- Kernel receives mock metrics in tests

#### Implementation Steps

**C.1 Replace Mock Metrics with Real Telemetry**

File: `adaptive-kernel/kernel/observability/SystemObserver.jl` (NEW FILE)

```julia
"""
    SystemObserver - Real-time system telemetry aggregation
"""
mutable struct SystemObserver
    observation_interval::Float64  # seconds
    last_observation::Union{Observation, Nothing}
    observation_history::CircularBuffer{Observation}
    
    function SystemObserver(interval::Float64=1.0)
        new(interval, nothing, CircularBuffer{Observation}(100))
    end
end

"""
    collect_real_observation()::Observation
Collect real system metrics from /proc (Linux) or WMI (Windows)
"""
function collect_real_observation()::Observation
    cpu = _read_cpu_load()
    mem = _read_memory_usage()
    disk = _read_disk_io()
    net = _read_network_latency()
    files = _count_filesystem_objects()
    procs = _count_processes()
    
    return Observation(cpu, mem, disk, net, files, procs)
end

function _read_cpu_load()::Float32
    if isfile("/proc/loadavg")
        load = parse(Float64, split(readlines("/proc/loadavg")[1])[1])
        return Float32(clamp(load / Sys.CPU_THREADS, 0.0, 1.0))
    elseif Sys.iswindows()
        # WMI query for CPU usage
        return _windows_cpu_usage()
    else
        return 0.1f0  # Safe default
    end
end

function _read_memory_usage()::Float32
    if isfile("/proc/meminfo")
        data = _parse_meminfo()
        total = get(data, "MemTotal", 0) / 1024 / 1024  # GB
        avail = get(data, "MemAvailable", 0) / 1024 / 1024
        used = total - avail
        return Float32(used / total)
    elseif Sys.iswindows()
        return _windows_memory_usage()
    else
        return 0.5f0
    end
end

function _read_network_latency()::Float32
    # Measure latency to known hosts
    latencies = Float32[]
    for host in ["8.8.8.8", "1.1.1.1"]
        t = @elapsed ping_result = run(`ping -c 1 -W 1 $host`)
        push!(latencies, Float32(t * 1000))  # ms
    end
    return isempty(latencies) ? 1000.0f0 : median(latencies) / 1000.0f0
end
```

**C.2 Define Capability-Based Observation Layer**

File: `adaptive-kernel/kernel/observability/ObservationCapabilities.jl` (NEW FILE)

```julia
"""
    ObservationCapability - System capability abstraction
Each capability returns typed Observation data
"""
abstract type ObservationCapability end

struct CPUMonitor <: ObservationCapability end
struct MemoryMonitor <: ObservationCapability end  
struct DiskMonitor <: ObservationCapability end
struct NetworkMonitor <: ObservationCapability end
struct ProcessMonitor <: ObservationCapability end
struct FilesystemMonitor <: ObservationCapability end

function execute(cap::CPUMonitor)::Observation
    # Platform-specific implementation
end

"""
    UnifiedObservation - Aggregated system state
"""
struct UnifiedObservation
    timestamp::DateTime
    cpu::CPUObservation
    memory::MemoryObservation
    disk::DiskObservation
    network::NetworkObservation
    custom::Dict{String, Any}
end

"""
    get_system_capabilities()::Vector{String}
Return list of available observation capabilities
"""
function get_system_capabilities()::Vector{String}
    caps = String[]
    Sys.islinux() && push!(caps, "linux_proc")
    Sys.iswindows() && push!(caps, "windows_wmi")
    push!(caps, "generic")  # Always available fallback
    return caps
end
```

**C.3 Implement Secure Monitoring**

File: `adaptive-kernel/kernel/observability/SecureObserver.jl` (NEW FILE)

```julia
"""
    SecureObservation - Prevent observation privilege escalation

SECURITY: Observation capabilities must NOT:
1. Execute arbitrary code
2. Access files outside /proc, /sys (Linux)
3. Leak sensitive system information
4. Provide timing channels for attack
"""
function validate_observation_safety(obs::Observation)::Bool
    # All values must be in valid ranges
    !(0.0f0 <= obs.cpu_load <= 1.0f0) && return false
    !(0.0f0 <= obs.memory_usage <= 1.0f0) && return false
    obs.file_count < 0 && return false
    obs.process_count < 0 && return false
    return true
end

# Rate limiting to prevent observation DoS
const OBSERVATION_RATE_LIMIT = 100  # per minute
const _observation_counter = Ref(0)

function rate_limit_observation()::Bool
    # Reset counter every minute
    now().second % 60 == 0 && (_observation_counter[] = 0)
    _observation_counter[] += 1
    return _observation_counter[] <= OBSERVATION_RATE_LIMIT
end
```

**C.4 Wire Observation into Kernel**

File: `adaptive-kernel/kernel/Kernel.jl`

```julia
function update_world_state!(kernel::KernelState)
    # Replace mock with real observation
    real_observation = collect_real_observation()
    
    # Validate before update
    if validate_observation_safety(real_observation)
        kernel.world = WorldState(
            now(),
            real_observation,
            kernel.world.facts
        )
    else
        @warn "Invalid observation received, using previous state"
    end
end
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `adaptive-kernel/kernel/observability/SystemObserver.jl` | NEW | Real telemetry collection |
| `adaptive-kernel/kernel/observability/ObservationCapabilities.jl` | NEW | Capability abstraction |
| `adaptive-kernel/kernel/observability/SecureObserver.jl` | NEW | Security for observation |
| `adaptive-kernel/kernel/Kernel.jl` | EXTEND | Wire real observations |
| `adaptive-kernel/capabilities/observe_*.jl` | EXTEND | Add Windows/macOS support |

#### Testing Strategy

- **Platform Tests:** Verify readings on Linux/Windows/macOS
- **Accuracy Tests:** Compare against htop, top, Activity Monitor
- **Security Tests:** Attempt injection via observation channel

---

### D. Voice Module (STT/TTS)

#### Current State
- [`config.toml`](config.toml:8) contains STT/TTS provider configuration
- `stt_provider = "openai"` and `tts_provider = "elevenlabs"` configured
- No actual implementation in codebase

#### Implementation Steps

**D.1 Whisper Integration Architecture**

File: `jarvis/src/voice/WhisperSTT.jl` (NEW FILE)

```julia
"""
    WhisperSTT - OpenAI Whisper integration for Speech-to-Text
"""
struct WhisperSTT
    api_key::String
    model::String  # "whisper-1" 
    language::Union{String, Nothing}  # "en" for English, nothing for auto
    client::HTTP.Client
    
    function WhisperSTT(;api_key::String=get(ENV, "JARVIS_WHISPER_API_KEY", ""),
                        model::String="whisper-1",
                        language::Union{String, Nothing}=nothing)
        isempty(api_key) && error("Whisper API key required")
        new(api_key, model, language, HTTP.Client())
    end
end

"""
    transcribe(audio_data::Vector{UInt8}, stt::WhisperSTT)::String
Transcribe audio bytes to text using Whisper API
"""
function transcribe(audio_data::Vector{UInt8}, stt::WhisperSTT)::String
    # Create multipart form
    body = HTTP.Multipart(
        "audio.wav", audio_data, "audio/wav";
        ...
    )
    
    headers = [
        "Authorization" => "Bearer $(stt.api_key)",
        "Content-Type" => "multipart/form-data"
    ]
    
    response = HTTP.post(
        "https://api.openai.com/v1/audio/transcriptions",
        headers=headers,
        body=body,
        timeout=30
    )
    
    result = JSON.parse(String(response.body))
    return result["text"]
end

"""
    stream_transcribe(audio_stream::IO, stt::WhisperSTT)::String
Streaming transcription for real-time processing
"""
function stream_transcribe(audio_stream::IO, stt::WhisperSTT)::String
    # Buffer audio chunks, send every 5 seconds
    buffer = Vector{UInt8}()
    results = String[]
    
    while !eof(audio_stream)
        chunk = read(audio_stream, 4096)
        append!(buffer, chunk)
        
        if length(buffer) > 5 * 16000 * 2  # 5 seconds of audio
            push!(results, transcribe(buffer, stt))
            empty!(buffer)
        end
    end
    
    # Process remaining
    !isempty(buffer) && push!(results, transcribe(buffer, stt))
    
    return join(results, " ")
end
```

**D.2 ElevenLabs TTS Integration**

File: `jarvis/src/voice/ElevenLabsTTS.jl` (NEW FILE)

```julia
"""
    ElevenLabsTTS - ElevenLabs integration for Text-to-Speech
"""
struct ElevenLabsTTS
    api_key::String
    voice_id::String
    model::String  # "eleven_monolingual_v1"
    stability::Float32  # [0, 1] - higher = more consistent
    similarity_boost::Float32  # [0, 1]
    
    function ElevenLabsTTS(;
        api_key::String=get(ENV, "JARVIS_ELEVENLABS_API_KEY", ""),
        voice_id::String="21m00Tcm4TlvDq8ikWAM",
        model::String="eleven_monolingual_v1",
        stability::Float32=0.5f0,
        similarity_boost::Float32=0.75f0)
        isempty(api_key) && error("ElevenLabs API key required")
        new(api_key, voice_id, model, stability, similarity_boost)
    end
end

"""
    speak(text::String, tts::ElevenLabsTTS)::Vector{UInt8}
Convert text to speech audio bytes
"""
function speak(text::String, tts::ElevenLabsTTS)::Vector{UInt8}
    headers = [
        "Accept" => "audio/mpeg",
        "xi-api-key" => tts.api_key
    ]
    
    body = JSON.json(Dict(
        "text" => text,
        "voice_settings" => Dict(
            "stability" => tts.stability,
            "similarity_boost" => tts.similarity_boost
        )
    ))
    
    response = HTTP.post(
        "https://api.elevenlabs.io/v1/text-to-speech/$(tts.voice_id)",
        headers=headers,
        body=body,
        timeout=30
    )
    
    return Vector{UInt8}(response.body)
end
```

**D.3 Streaming vs Batch Design**

File: `jarvis/src/voice/VoicePipeline.jl` (NEW FILE)

```julia
"""
    VoicePipeline - Coordinates STT → Cognition → TTS flow

MODE: STREAMING (low latency)
- Continuous audio capture
- Chunk-based Whisper transcription
- Real-time text streaming to brain

MODE: BATCH (high accuracy)
- Full audio segment transcription
- Better context understanding
- Higher latency (~1-2s)
"""
@enum VoiceMode STREAMING BATCH

mutable struct VoicePipeline
    stt::WhisperSTT
    tts::ElevenLabsTTS
    mode::VoiceMode
    audio_buffer::Vector{UInt8}
    sample_rate::Int
    
    function VoicePipeline(;mode::VoiceMode=STREAMING)
        stt = WhisperSTT()
        tts = ElevenLabsTTS()
        new(stt, tts, mode, Vector{UInt8}(), 16000)
    end
end

# STREAMING MODE
function process_audio_chunk(pipeline::VoicePipeline, chunk::Vector{UInt8})
    # Real-time transcription with overlap
    text = transcribe_with_overlap(chunk, pipeline.stt)
    return text
end

# BATCH MODE  
function process_audio_segment(pipeline::VoicePipeline, segment::Vector{UInt8})
    # Full context transcription
    text = transcribe(segment, pipeline.stt)
    return text
end

# TTS output
function synthesize_speech(pipeline::VoicePipeline, text::String)::Vector{UInt8}
    return speak(text, pipeline.tts)
end
```

**D.4 Secure API Key Management**

```julia
# API keys MUST come from environment variables, never hardcoded
# Configuration loads from ENV, not config.toml for secrets

function load_voice_config()::VoiceConfig
    return VoiceConfig(
        whisper_key = get(ENV, "JARVIS_WHISPER_API_KEY", "") |> 
            isempty ? error("JARVIS_WHISPER_API_KEY required") : identity,
        elevenlabs_key = get(ENV, "JARVIS_ELEVENLABS_API_KEY", "") |>
            isempty ? error("JARVIS_ELEVENLABS_API_KEY required") : identity,
        # Non-sensitive config from TOML
        provider = config["communication"]["stt_provider"]
    )
end
```

**D.5 Latency Mitigation Strategy**

| Strategy | Implementation | Latency Impact |
|----------|---------------|----------------|
| Streaming chunks | 1-2s audio windows | 500ms |
| Prefetch TTS | Pre-generate common responses | 0ms for cached |
| Edge TTS | Local small model for simple phrases | 100ms |
| Pipeline parallel | STT/TTS parallel to cognition | Hide latency |

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `jarvis/src/voice/WhisperSTT.jl` | NEW | Whisper API integration |
| `jarvis/src/voice/ElevenLabsTTS.jl` | NEW | ElevenLabs API integration |
| `jarvis/src/voice/VoicePipeline.jl` | NEW | Orchestration layer |
| `jarvis/src/voice/AudioCapture.jl` | NEW | Audio device handling |
| `jarvis/src/SystemIntegrator.jl` | EXTEND | Wire voice pipeline |

#### Testing Strategy

- **Integration Tests:** End-to-end STT → TTS with real audio
- **Latency Tests:** Verify <2s total latency target
- **Fallback Tests:** Graceful degradation on API failure

---

### E. Vision Module (VLM)

#### Current State
- [`config.toml`](config.toml:18) contains VLM configuration
- `vlm_provider = "openai"` configured
- No actual implementation

#### Implementation Steps

**E.1 GPT-4V / Claude Vision Integration**

File: `jarvis/src/vision/VisionLanguageModel.jl` (NEW FILE)

```julia
"""
    VLMClient - Vision Language Model abstraction
Supports: GPT-4V, Claude Vision, LLaVA
"""
abstract type VLMClient end

struct GPT4VClient <: VLMClient
    api_key::String
    model::String
    max_tokens::Int
    
    function GPT4VClient(;api_key::String=get(ENV, "JARVIS_OPENAI_API_KEY", ""),
                         model::String="gpt-4-vision-preview")
        new(api_key, model, 2048)
    end
end

struct ClaudeVisionClient <: VLMClient
    api_key::String
    model::String
    
    function ClaudeVisionClient(;api_key::String=get(ENV, "JARVIS_ANTHROPIC_API_KEY", ""),
                               model::String="claude-3-opus-20240229")
        new(api_key, model)
    end
end

"""
    analyze_image(client::VLMClient, image_data::Vector{UInt8}, prompt::String)::VisionResult
Send image to VLM and get structured analysis
"""
function analyze_image(client::GPT4VClient, image_data::Vector{UInt8}, prompt::String)::VisionResult
    # Convert image to base64
    image_b64 = base64encode(image_data)
    
    body = JSON.json(Dict(
        "model" => client.model,
        "messages" => [
            Dict(
                "role" => "user",
                "content" => [
                    Dict("type" => "text", "text" => prompt),
                    Dict(
                        "type" => "image_url",
                        "image_url" => Dict("url" => "data:image/jpeg;base64,$image_b64")
                    )
                ]
            )
        ],
        "max_tokens" => client.max_tokens
    ))
    
    headers = [
        "Authorization" => "Bearer $(client.api_key)",
        "Content-Type" => "application/json"
    ]
    
    response = HTTP.post("https://api.openai.com/v1/chat/completions",
                         headers=headers, body=body, timeout=60)
    
    result = JSON.parse(String(response.body))
    
    return VisionResult(
        description=result["choices"][1]["message"]["content"],
        objects=extract_objects(result),
        text_detected=extract_text(result),
        confidence=result["usage"]["total_tokens"] / client.max_tokens
    )
end
```

**E.2 Image Ingestion Pipeline**

File: `jarvis/src/vision/ImagePipeline.jl` (NEW FILE)

```julia
"""
    ImagePipeline - From camera/file to VLM analysis
"""
struct ImagePipeline
    vlm::VLMClient
    preprocessor::ImagePreprocessor
    risk_filter::VisionRiskFilter
    
    ImagePipeline(;vlm::VLMClient) = new(vlm, ImagePreprocessor(), VisionRiskFilter())
end

"""
    preprocess_image(image::Matrix)::Matrix
Resize, normalize, and prepare image for VLM
"""
function preprocess_image(image::Matrix)::Matrix
    # Resize to VLM max (2048x2048 for GPT-4V)
    resized = imresize(image, (1024, 1024))
    # Convert to RGB if grayscale
    if size(resized, 3) == 1
        resized = cat(resized, resized, resized, dims=3)
    end
    return resized
end

"""
    VisionRiskFilter - Block sensitive content before VLM
"""
struct VisionRiskFilter
    blocked_patterns::Vector{Regex}
    
    function VisionRiskFilter()
        # Block obvious sensitive content patterns
        new([
            r"credit_card",
            r"ssn|social.security",
            r"password",
            # Add more patterns
        ])
    end
end

function filter_risky_content(image::Matrix, filter::VisionRiskFilter)::Bool
    # OCR first to check for sensitive text
    text = extract_text_from_image(image)
    for pattern in filter.blocked_patterns
        occursin(pattern, text) && return false
    end
    return true
end
```

**E.3 Memory Embedding Integration**

```julia
"""
    Embed vision observations into memory
"""
function embed_vision_memory(pipeline::ImagePipeline, result::VisionResult)::Vector{Float32}
    # Create embedding from vision result
    combined = "$(result.description) $(join(result.objects, ", "))"
    embedding = text_to_embedding(combined)  # Use existing VectorMemory
    return embedding
end

# Store in semantic memory
function store_vision_memory(pipeline::ImagePipeline, result::VisionResult, context::Dict)
    embedding = embed_vision_memory(pipeline, result)
    entry = SemanticEntry(
        content=result.description,
        embedding=embedding,
        timestamp=now(),
        source=:vision,
        metadata=Dict("objects" => result.objects, "context" => context)
    )
    VectorMemory.store(entry)
end
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `jarvis/src/vision/VisionLanguageModel.jl` | NEW | VLM API clients |
| `jarvis/src/vision/ImagePipeline.jl` | NEW | Image processing |
| `jarvis/src/vision/VisionRiskFilter.jl` | NEW | Content filtering |
| `jarvis/src/memory/VectorMemory.jl` | EXTEND | Vision embeddings |

---

### F. OpenClaw Tooling Integration

#### Current State
- [`OpenClawBridge.jl`](jarvis/src/bridge/OpenClawBridge.jl:1) exists
- Configuration in `config.toml` points to `http://localhost:3000`
- Not fully integrated with capability registry

#### Implementation Steps

**F.1 Proper Include and Registration**

File: `adaptive-kernel/registry/ToolRegistry.jl` (NEW FILE)

```julia
"""
    ToolRegistry - Central registry for all executable tools
Binds OpenClaw tools + native capabilities
"""
mutable struct ToolRegistry
    openclaw_endpoint::String
    native_capabilities::Dict{String, Capability}
    tool_metadata::Dict{String, ToolMetadata}
    
    function ToolRegistry(endpoint::String="http://localhost:3000")
        new(endpoint, Dict{String, Capability}(), Dict{String, ToolMetadata}())
    end
end

"""
    register_capability!(registry::ToolRegistry, cap::Capability)
Register a native Julia capability
"""
function register_capability!(registry::ToolRegistry, cap::Capability)
    registry.native_capabilities[cap.id] = cap
    registry.tool_metadata[cap.id] = ToolMetadata(
        id=cap.id,
        name=cap.name,
        source=:native,
        risk_level=cap.risk,
        execution_mode=:julia
    )
end

"""
    register_openclaw_tool!(registry::ToolRegistry, tool::OpenClawTool)
Register a Docker-based OpenClaw tool
"""
function register_openclaw_tool!(registry::ToolRegistry, tool::OpenClawTool)
    registry.tool_metadata[tool.id] = ToolMetadata(
        id=tool.id,
        name=tool.name,
        source=:openclaw,
        risk_level=tool.risk,
        execution_mode=:docker,
        endpoint="$(registry.openclaw_endpoint)/tools/$(tool.id)"
    )
end
```

**F.2 Execution Sandbox**

File: `adaptive-kernel/sandbox/ExecutionSandbox.jl` (NEW FILE)

```julia
"""
    ExecutionSandbox - Isolated tool execution environment
"""
abstract type SandboxMode end
struct DockerSandbox <: SandboxMode end
struct ProcessSandbox <: SandboxMode end

"""
    execute_in_sandbox(tool_id::String, params::Dict, mode::SandboxMode)::ExecutionResult
"""
function execute_in_sandbox(
    tool_id::String,
    params::Dict,
    mode::DockerSandbox,
    registry::ToolRegistry
)::ExecutionResult
    tool_meta = registry.tool_metadata[tool_id]
    
    # Validate tool exists and is allowed
    !haskey(registry.tool_metadata, tool_id) && 
        return ExecutionResult(success=false, error="Tool not found")
    
    # Build execution request
    request = Dict(
        "tool_id" => tool_id,
        "params" => params,
        "timeout" => get(params, "timeout", 30),
        "memory_limit" => "512MB",
        "cpu_limit" => "1.0"
    )
    
    # Execute via OpenClaw API
    response = HTTP.post(
        "$(registry.openclaw_endpoint)/execute",
        headers=["Content-Type" => "application/json"],
        body=JSON.json(request),
        timeout=request["timeout"] + 5
    )
    
    return parse_execution_response(response.body)
end
```

**F.3 Capability Risk Classification**

File: `adaptive-kernel/registry/RiskClassifier.jl` (NEW FILE)

```julia
"""
    RiskClassifier - Classify tool risk levels
"""
@enum RiskLevel READ_ONLY LOW MEDIUM HIGH CRITICAL

"""
    classify_tool_risk(tool_id::String, params::Dict)::RiskLevel
"""
function classify_tool_risk(tool_id::String, params::Dict)::RiskLevel
    registry_entry = get_capability_registry(tool_id)
    
    # Base risk from registry
    base_risk = registry_entry.risk
    
    # Parameter modifiers
    param_risk = _assess_parameter_risk(tool_id, params)
    
    # Context modifiers (system state)
    context_risk = _assess_context_risk()
    
    return max(base_risk, param_risk, context_risk)
end

function _assess_parameter_risk(tool_id::String, params::Dict)::RiskLevel
    dangerous_params = ["path", "command", "url", "exec"]
    
    for param in dangerous_params
        if haskey(params, param)
            value = params[param]
            # Check for path traversal
            occursin("..", value) && return HIGH
            occursin("/", value) && value ∉ SAFE_PATHS && return MEDIUM
        end
    end
    return READ_ONLY
end
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `adaptive-kernel/registry/ToolRegistry.jl` | NEW | Central tool registry |
| `adaptive-kernel/sandbox/ExecutionSandbox.jl` | NEW | Sandboxed execution |
| `adaptive-kernel/registry/RiskClassifier.jl` | NEW | Risk classification |
| `jarvis/src/bridge/OpenClawBridge.jl` | REFACTOR | Align with registry |

---

### G. Persistence & Checkpointing

#### Current State
- [`Persistence.jl`](adaptive-kernel/persistence/Persistence.jl:1) has basic event log
- JSONL format append-only log
- No state checkpointing
- No vector store persistence

#### Implementation Steps

**G.1 Durable Memory Serialization**

File: `adaptive-kernel/persistence/Checkpointer.jl` (NEW FILE)

```julia
"""
    CheckpointManager - Durable state snapshots
"""
struct CheckpointManager
    checkpoint_dir::String
    max_checkpoints::Int
    checkpoint_interval::Int  # seconds
    
    function CheckpointManager(dir::String="./checkpoints"; 
                               max_checkpoints::Int=10,
                               interval::Int=300)
        mkpath(dir)
        new(dir, max_checkpoints, interval)
    end
end

"""
    save_checkpoint(manager::CheckpointManager, state::KernelState)
Serialize kernel state to durable storage
"""
function save_checkpoint(manager::CheckpointManager, state::KernelState)
    checkpoint = Dict(
        "version" => KERNEL_VERSION,
        "timestamp" => string(now()),
        "cycle" => state.cycle[],
        "goals" => [goal_to_dict(g) for g in state.goals],
        "goal_states" => goalstate_to_dict.(values(state.goal_states)),
        "episodic_memory" => [event_to_dict(e) for e in state.episodic_memory],
        "self_metrics" => state.self_metrics
    )
    
    filename = joinpath(manager.checkpoint_dir, 
                        "checkpoint_$(state.cycle[])_$(unix_timestamp()).json")
    
    # Write atomically via temp file
    temp_file = filename * ".tmp"
    open(temp_file, "w") do io
        JSON3.pretty(io, checkpoint)
    end
    mv(temp_file, filename; force=true)
    
    # Cleanup old checkpoints
    _cleanup_old_checkpoints(manager)
end
```

**G.2 Vector Store Persistence**

File: `jarvis/src/memory/VectorStore.jl` (NEW FILE)

```julia
"""
    VectorStore - Persistent vector embeddings using SQLite + FAISS-style index
"""
struct VectorStore
    db_path::String
    index_path::String
    embeddings::Vector{Matrix{Float32}}  # In-memory index
    
    function VectorStore(path::String="./vector_store")
        mkpath(path)
        db_path = joinpath(path, "vectors.db")
        index_path = joinpath(path, "index.bin")
        
        # Initialize SQLite schema
        DBInterface.connect(SQLite.DB(db_path)) do db
            SQLite.execute(db, """
                CREATE TABLE IF NOT EXISTS embeddings (
                    id TEXT PRIMARY KEY,
                    content TEXT,
                    embedding BLOB,
                    timestamp TEXT,
                    source TEXT
                )
            """)
        end
        
        new(db_path, index_path, Vector{Matrix{Float32}}())
    end
end

"""
    persist(store::VectorStore, entries::Vector{SemanticEntry})
Store embeddings to durable SQLite
"""
function persist(store::VectorStore, entries::Vector{SemanticEntry})
    DBInterface.connect(SQLite.DB(store.db_path)) do db
        for entry in entries
            embedding_bytes = reinterpret(UInt8, vec(entry.embedding))
            SQLite.execute(db, """
                INSERT OR REPLACE INTO embeddings (id, content, embedding, timestamp, source)
                VALUES (?, ?, ?, ?, ?)
            """, [entry.id, entry.content, embedding_bytes, string(entry.timestamp), entry.source])
        end
    end
end
```

**G.3 Snapshot + Restore Lifecycle**

```julia
"""
    Full system snapshot for disaster recovery
"""
struct SystemSnapshot
    checkpoint::Dict
    vector_store::Vector{String}  # Paths
    audit_log::String  # Path
    timestamp::DateTime
end

function create_snapshot(manager::CheckpointManager, store::VectorStore)::SystemSnapshot
    # 1. Checkpoint kernel state
    save_checkpoint(manager, get_current_kernel_state())
    
    # 2. Persist vector store
    persist(store, get_all_entries())
    
    # 3. Archive audit log
    archive_path = "./archives/audit_$(unix_timestamp()).log.gz"
    compress("sovereignty_audit.log", archive_path)
    
    return SystemSnapshot(
        checkpoint=get_latest_checkpoint_path(),
        vector_store=[store.db_path, store.index_path],
        audit_log=archive_path,
        timestamp=now()
    )
end

function restore_from_snapshot(snapshot::SystemSnapshot)::KernelState
    # 1. Load kernel checkpoint
    state = load_checkpoint(snapshot.checkpoint)
    
    # 2. Restore vector store
    load_embeddings(snapshot.vector_store)
    
    # 3. Verify audit log integrity
    verify_audit_log(snapshot.audit_log)
    
    return state
end
```

**G.4 Crash Recovery Strategy**

```julia
"""
    CrashRecovery - Automatic recovery from failure
"""
function recover_from_crash(manager::CheckpointManager, store::VectorStore)::Union{KernelState, Nothing}
    # 1. Find latest checkpoint
    checkpoints = readdir(manager.checkpoint_dir, join=true)
    isempty(checkpoints) && return nothing
    
    latest = sort(checkpoints, by=mtime, rev=true)[1]
    
    # 2. Verify checkpoint integrity
    checkpoint_data = load_checkpoint(latest)
    !verify_checkpoint_integrity(checkpoint_data) && return nothing
    
    # 3. Replay audit log since checkpoint
    replay_audit_log(latest)
    
    return checkpoint_data
end
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `adaptive-kernel/persistence/Checkpointer.jl` | NEW | State checkpointing |
| `jarvis/src/memory/VectorStore.jl` | NEW | Persistent embeddings |
| `adaptive-kernel/persistence/CrashRecovery.jl` | NEW | Recovery logic |
| `adaptive-kernel/persistence/Persistence.jl` | EXTEND | Add archive support |

---

### H. Configuration & Secrets Management

#### Current State
- [`config.toml`](config.toml:1) has all configuration
- API keys stored in config file (INSECURE)
- No environment-based secrets
- No multi-environment support

#### Implementation Steps

**H.1 Environment Variable Schema**

File: `config/env_schema.yaml` (NEW FILE)

```yaml
# Jarvis Environment Variable Schema
# All secrets MUST come from environment variables

environment_variables:
  # LLM Configuration
  JARVIS_LLM_API_KEY:
    required: true
    description: "OpenAI or Anthropic API key for LLM"
    pattern: "^sk-[a-zA-Z0-9]+$"
  
  JARVIS_WHISPER_API_KEY:
    required: false
    description: "OpenAI API key for Whisper STT"
    pattern: "^sk-[a-zA-Z0-9]+$"
  
  JARVIS_ELEVENLABS_API_KEY:
    required: false
    description: "ElevenLabs API key for TTS"
    pattern: "^[a-zA-Z0-9]+$"
  
  # OpenClaw
  JARVIS_OPENCLAW_ENDPOINT:
    required: false
    default: "http://localhost:3000"
  
  # Secrets (vault)
  JARVIS_VAULT_ADDR:
    required: false
    description: "HashiCorp Vault address"
  
  JARVIS_VAULT_TOKEN:
    required: false
    description: "Vault authentication token"

# Non-sensitive config (can be in TOML)
config_files:
  - config.toml
  - adaptive-kernel/registry/capability_registry.json
```

**H.2 Secure Secrets Vault Strategy**

File: `jarvis/src/config/SecretsManager.jl` (NEW FILE)

```julia
"""
    SecretsManager - Secure secrets loading from Vault or ENV
"""
struct SecretsManager
    vault_addr::Union{String, Nothing}
    vault_token::Union{String, Nothing}
    cache::Dict{String, String}
    
    function SecretsManager()
        vault_addr = get(ENV, "JARVIS_VAULT_ADDR", nothing)
        vault_token = get(ENV, "JARVIS_VAULT_TOKEN", nothing)
        
        new(vault_addr, vault_token, Dict{String, String}())
    end
end

"""
    get_secret(manager::SecretsManager, key::String)::String
Load secret from Vault or fall back to ENV
"""
function get_secret(manager::SecretsManager, key::String)::String
    # Check cache first
    haskey(manager.cache, key) && return manager.cache[key]
    
    # Try Vault first
    if manager.vault_addr !== nothing
        secret = _load_from_vault(manager, key)
        secret !== nothing && (manager.cache[key] = secret; return secret)
    end
    
    # Fall back to environment variable
    env_key = "JARVIS_$(uppercase(key))"
    secret = get(ENV, env_key, "")
    
    isempty(secret) && error("Secret $key not found in Vault or ENV")
    
    manager.cache[key] = secret
    return secret
end
```

**H.3 Multi-Environment Config Model**

File: `config/environments/` (NEW DIRECTORY)

```
config/
├── base.toml           # Shared config
├── development.toml    # Dev overrides
├── staging.toml       # Staging overrides
└── production.toml   # Production overrides
```

```toml
# config/environments/production.toml
[system]
log_level = "warn"  # Override base

[kernel]
default_goal_priority = 0.9

[security]
require_confirmation_threshold = "TRUST_LIMITED"  # Stricter in prod
audit_export_enabled = true
```

**H.4 Dev vs Production Isolation**

```julia
"""
    ConfigLoader - Environment-aware configuration
"""
function load_config(env::String="development")::Config
    # Load base config
    base = TOML.parsefile("config/base.toml")
    
    # Load environment overrides
    env_file = "config/environments/$(env).toml"
    if isfile(env_file)
        overrides = TOML.parsefile(env_file)
        merge!(base, overrides)
    end
    
    # Validate required secrets
    _validate_secrets(base)
    
    return Config(base)
end

function _validate_secrets(config::Dict)
    required_secrets = ["JARVIS_LLM_API_KEY"]
    for secret in required_secrets
        get(ENV, secret, "") |> isempty && 
            error("$secret required for $(config["environment"]) environment")
    end
end
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `config/env_schema.yaml` | NEW | Environment schema |
| `jarvis/src/config/SecretsManager.jl` | NEW | Secrets loading |
| `jarvis/src/config/ConfigLoader.jl` | NEW | Multi-env config |
| `config/environments/*.toml` | NEW | Environment configs |
| `config.toml` | REFACTOR | Remove secrets |

---

### I. Trust & Confirmation Model

#### Current State
- [`TrustLevel`](jarvis/src/types.jl:49) enum exists
- Basic trust levels defined (TRUST_BLOCKED to TRUST_FULL)
- Not fully wired into kernel approval

#### Implementation Steps

**I.1 Risk Classification Engine**

File: `adaptive-kernel/kernel/trust/RiskClassifier.jl` (NEW FILE)

```julia
"""
    TrustClassifier - Dynamic risk classification for actions
"""
struct TrustClassifier
    risk_thresholds::Dict{RiskLevel, TrustLevel}
    history::CircularBuffer{TrustEvent}
    
    TrustClassifier() = new(
        Dict(
            READ_ONLY => TRUST_RESTRICTED,
            LOW => TRUST_LIMITED,
            MEDIUM => TRUST_STANDARD,
            HIGH => TRUST_FULL,
            CRITICAL => TRUST_FULL
        ),
        CircularBuffer{TrustEvent}(1000)
    )
end

"""
    classify_action_risk(proposal::ActionProposal, context::ActionContext)::RiskLevel
"""
function classify_action_risk(
    proposal::ActionProposal,
    context::ActionContext,
    classifier::TrustClassifier
)::RiskLevel
    # Base risk from capability registry
    base_risk = get_capability_risk(proposal.capability_id)
    
    # Context modifiers
    modifier = 0
    
    # File path risk
    if occursin("..", get(proposal.params, "path", ""))
        modifier += 1
    end
    
    # Shell command risk
    if haskey(proposal.params, "command")
        modifier += 2
    end
    
    # HTTP request risk
    if haskey(proposal.params, "url")
        url = proposal.params["url"]
        !startswith(url, "https://") && (modifier += 1)
        url in ALLOWED_HOSTS || (modifier += 1)
    end
    
    # Compute final risk
    final_risk = RiskLevel(min(Int(base_risk) + modifier, Int(CRITICAL)))
    
    # Record for learning
    push!(classifier.history, TrustEvent(proposal, final_risk, now()))
    
    return final_risk
end
```

**I.2 User Confirmation Gate**

File: `adaptive-kernel/kernel/trust/ConfirmationGate.jl` (NEW FILE)

```
"""
    ConfirmationGate - User confirmation for high-risk actions
"""
struct ConfirmationGate
    pending_confirmations::Dict{UUID, PendingAction}
    timeout::Int  # seconds
    
    function ConfirmationGate(timeout::Int=30)
        new(Dict{UUID, PendingAction}(), timeout)
    end
end

"""
    require_confirmation(gate::ConfirmationGate, proposal::ActionProposal)::UUID
Queue action for user confirmation, return confirmation ID
"""
function require_confirmation(gate::ConfirmationGate, proposal::ActionProposal)::UUID
    confirmation_id = uuid4()
    
    pending = PendingAction(
        id=confirmation_id,
        proposal=proposal,
        requested_at=now(),
        timeout=gate.timeout
    )
    
    gate.pending_confirmations[confirmation_id] = pending
    
    # Emit confirmation request event
    emit_confirmation_request(pending)
    
    return confirmation_id
end

"""
    confirm_action(gate::ConfirmationGate, confirmation_id::UUID)::Bool
User confirms action
"""
function confirm_action(gate::ConfirmationGate, confirmation_id::UUID)::Bool
    pending = get(gate.pending_confirmations, confirmation_id, nothing)
    pending === nothing && return false
    
    # Check timeout
    elapsed = (now() - pending.requested_at).value / 1000
    elapsed > pending.timeout && return false
    
    delete!(gate.pending_confirmations, confirmation_id)
    return true
end
```

**I.3 Real-Time Trust Recalibration**

```julia
"""
    recalibrate_trust!(classifier::TrustClassifier, outcome::ActionResult)
Adjust trust thresholds based on outcomes
"""
function recalibrate_trust!(classifier::TrustClassifier, outcome::ActionResult)
    # Track success/failure rates per action type
    # If failure rate too high, increase required trust level
    
    recent_events = filter(e -> 
        (now() - e.timestamp) < Hour(1), 
        classifier.history
    )
    
    failure_rate = count(!e.success for e in recent_events) / length(recent_events)
    
    if failure_rate > 0.3
        # High failure rate - increase caution
        _increase_trust_thresholds(classifier)
    elseif failure_rate < 0.05
        # Very reliable - can relax slightly
        _decrease_trust_thresholds(classifier)
    end
end
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `adaptive-kernel/kernel/trust/RiskClassifier.jl` | NEW | Risk classification |
| `adaptive-kernel/kernel/trust/ConfirmationGate.jl` | NEW | User confirmation |
| `adaptive-kernel/kernel/trust/TrustCalibrator.jl` | NEW | Dynamic calibration |
| `adaptive-kernel/kernel/Kernel.jl` | EXTEND | Wire trust into approval |

---

### J. Error Handling & Recovery Architecture

#### Current State
- Basic error handling in capabilities
- No circuit breaker
- No component health monitoring
- No graceful degradation

#### Implementation Steps

**J.1 Circuit Breaker Design**

File: `adaptive-kernel/resilience/CircuitBreaker.jl` (NEW FILE)

```julia
"""
    CircuitBreaker - Prevent cascading failures
"""
mutable struct CircuitBreaker
    name::String
    state::CircuitState  # :closed, :open, :half_open
    failure_count::Int
    success_count::Int
    last_failure::Union{DateTime, Nothing}
    threshold::Int  # failures before opening
    timeout::Int     # seconds before half-open
    
    CircuitBreaker(name::String; threshold::Int=5, timeout::Int=60) = 
        new(name, :closed, 0, 0, nothing, threshold, timeout)
end

@enum CircuitState CLOSED OPEN HALF_OPEN

"""
    call(breaker::CircuitBreaker, f::Function)
Execute function through circuit breaker
"""
function call(breaker::CircuitBreaker, f::Function)
    # Check state
    if breaker.state == OPEN
        # Check if timeout elapsed
        if breaker.last_failure !== nothing && 
           (now() - breaker.last_failure).value / 1000 > breaker.timeout
            breaker.state = HALF_OPEN
        else
            throw(CircuitBreakerOpenException(breaker.name))
        end
    end
    
    # Execute
    try
        result = f()
        _on_success(breaker)
        return result
    catch e
        _on_failure(breaker)
        rethrow()
    end
end

function _on_success(breaker::CircuitBreaker)
    breaker.success_count += 1
    breaker.failure_count = 0
    if breaker.state == HALF_OPEN && breaker.success_count >= 3
        breaker.state = CLOSED
    end
end

function _on_failure(breaker::CircuitBreaker)
    breaker.failure_count += 1
    breaker.last_failure = now()
    if breaker.failure_count >= breaker.threshold
        breaker.state = OPEN
    end
end
```

** Health Monitoring**

File: `adaptive-kJ.2 Componenternel/resilience/HealthMonitor.jl` (NEW FILE)

```julia
"""
    HealthMonitor - Track component health for degradation decisions
"""
struct ComponentHealth
    name::String
    status::HealthStatus
    last_check::DateTime
    failure_count::Int
    latency_p99::Float64  # milliseconds
    
    ComponentHealth(name::String) = new(name, :healthy, now(), 0, 0.0)
end

@enum HealthStatus HEALTHY DEGRADED UNHEALTHY UNKNOWN

"""
    HealthMonitor - System-wide health tracking
"""
mutable struct HealthMonitor
    components::Dict{String, ComponentHealth}
    check_interval::Int
    
    HealthMonitor(interval::Int=10) = new(Dict{String, ComponentHealth}(), interval)
end

function check_health(monitor::HealthMonitor, component::String)::HealthStatus
    comp = get(monitor.components, component, nothing)
    comp === nothing && return UNKNOWN
    
    # Determine status from metrics
    if comp.failure_count > 10
        return UNHEALTHY
    elseif comp.failure_count > 3 || comp.latency_p99 > 1000
        return DEGRADED
    else
        return HEALTHY
    end
end
```

**J.3 Graceful Degradation Modes**

```julia
"""
    DegradationMode - System operates at reduced capability
"""
@enum DegradationMode NOMINAL DEGRADED MINIMAL EMERGENCY

function determine_degradation_mode(monitor::HealthMonitor)::DegradationMode
    health_states = values(monitor.components) .|> .status
    
    if any(s == UNHEALTHY for s in health_states)
        return EMERGENCY
    elseif any(s == DEGRADED for s in health_states)
        return DEGRADED
    elseif all(s == HEALTHY for s in health_states)
        return NOMINAL
    else
        return MINIMAL
    end
end

# Apply degradation policies
function apply_degradation_policy(mode::DegradationMode)
    if mode == EMERGENCY
        # Only allow READ_ONLY actions
        set_capability_whitelist!(READ_ONLY_ACTIONS_ONLY)
        disable_llm_brain!()  # Use fallback
        increase_audit_logging()
    elseif mode == DEGRADED
        # Disable high-risk capabilities
        disable_capabilities!(HIGH_RISK_ACTIONS)
    end
end
```

**J.4 Autonomous Self-Healing Behaviors**

```julia
"""
    SelfHealer - Autonomous recovery from failures
"""
struct SelfHealer
    recovery_strategies::Dict{String, RecoveryStrategy}
end

"""
    attempt_recovery(healer::SelfHealer, component::String, error::Exception)
"""
function attempt_recovery(healer::SelfHealer, component::String, error::Exception)
    strategy = get(healer.recovery_strategies, component, nothing)
    strategy === nothing && return false
    
    # Execute recovery strategy
    try
        strategy.recovery_fn(error)
        return true
    catch
        return false
    end
end

# Example recovery strategies
recovery_strategies = Dict(
    "llm" => RecoveryStrategy(
        name="LLM Recovery",
        recovery_fn=() -> switch_to_fallback_model()
    ),
    "memory" => RecoveryStrategy(
        name="Memory Recovery", 
        recovery_fn=() -> compact_vector_store()
    ),
    "kernel" => RecoveryStrategy(
        name="Kernel Recovery",
        recovery_fn=() -> restore_from_checkpoint()
    )
)
```

#### Required File Modifications

| File | Modification Type | Description |
|------|------------------|-------------|
| `adaptive-kernel/resilience/CircuitBreaker.jl` | NEW | Circuit breaker |
| `adaptive-kernel/resilience/HealthMonitor.jl` | NEW | Health tracking |
| `adaptive-kernel/resilience/DegradationManager.jl` | NEW | Graceful degradation |
| `adaptive-kernel/resilience/SelfHealer.jl` | NEW | Self-healing |

---

## 3. INTEGRATION SEQUENCING ROADMAP

### Phase Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DEPENDENCY GRAPH                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  PHASE 0: Foundation (Weeks 1-2)                                                │
│  ├── H. Configuration & Secrets Management                                       │
│  │   └── H.1 → H.2 → H.3 → H.4                                                  │
│  └── G. Persistence & Checkpointing                                             │
│      └── G.1 → G.2 → G.3 → G.4                                                  │
│                                                                                  │
│  PHASE 1: Core Infrastructure (Weeks 3-4)                                       │
│  ├── B. Adaptive Kernel Sovereignty                                             │
│  │   └── B.1 → B.2 → B.3                                                        │
│  ├── C. Real System Observation                                                 │
│  │   └── C.1 → C.2 → C.3 → C.4                                                  │
│  └── I. Trust & Confirmation Model                                              │
│      └── I.1 → I.2 → I.3                                                        │
│                                                                                  │
│  PHASE 2: Brain Integration (Weeks 5-6)                                         │
│  └── A. ITHERIS Neural Brain Activation                                          │
│      └── A.1 → A.2 → A.3 → A.4                                                  │
│                                                                                  │
│  PHASE 3: Perception Modules (Weeks 7-8)                                        │
│  ├── D. Voice Module (STT/TTS)                                                  │
│  │   └── D.1 → D.2 → D.3 → D.4 → D.5                                           │
│  └── E. Vision Module (VLM)                                                     │
│      └── E.1 → E.2 → E.3                                                        │
│                                                                                  │
│  PHASE 4: Execution Layer (Weeks 9-10)                                          │
│  ├── F. OpenClaw Tooling Integration                                            │
│  │   └── F.1 → F.2 → F.3                                                        │
│  └── J. Error Handling & Recovery                                               │
│      └── J.1 → J.2 → J.3 → J.4                                                  │
│                                                                                  │
│  PHASE 5: Production Hardening (Weeks 11-12)                                   │
│  └── Integration + Testing + Deployment                                         │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Phased Implementation Order

| Phase | Module | Duration | Dependencies | Risk |
|-------|--------|----------|--------------|------|
| 0 | H. Config & Secrets | 1 week | None | LOW |
| 0 | G. Persistence | 1 week | H | MEDIUM |
| 1 | B. Kernel Sovereignty | 1 week | G | HIGH |
| 1 | C. Observation | 1 week | G | MEDIUM |
| 1 | I. Trust Model | 1 week | B | HIGH |
| 2 | A. Brain Activation | 2 weeks | B, I | CRITICAL |
| 3 | D. Voice Module | 1.5 weeks | H | MEDIUM |
| 3 | E. Vision Module | 1.5 weeks | H | MEDIUM |
| 4 | F. OpenClaw | 1 week | B, C | HIGH |
| 4 | J. Error Handling | 1 week | All | MEDIUM |
| 5 | Integration | 2 weeks | All | CRITICAL |

### Parallelizable Workstreams

| Workstream A | Workstream B | Can Run Parallel |
|--------------|--------------|------------------|
| H. Config | G. Persistence | YES |
| C. Observation | I. Trust Model | YES |
| D. Voice | E. Vision | YES |
| F. OpenClaw | J. Error Handling | YES |

### Risk Ranking

| Rank | Module | Risk Level | Mitigation |
|------|--------|-------------|------------|
| 1 | A. Brain Activation | CRITICAL | Extensive testing, fallback to heuristic |
| 2 | B. Kernel Sovereignty | CRITICAL | Fail-closed, audit trail |
| 3 | I. Trust Model | HIGH | Gradual rollout, user confirmation |
| 4 | F. OpenClaw | HIGH | Sandbox, rate limiting |
| 5 | C. Observation | MEDIUM | Fallback to mock |
| 6 | J. Error Handling | MEDIUM | Circuit breaker |
| 7 | D. Voice | MEDIUM | Demo mode |
| 8 | E. Vision | MEDIUM | Content filtering |
| 9 | G. Persistence | MEDIUM | Backup strategies |
| 10 | H. Config | LOW | Validation |

---

## 4. PRODUCTION HARDENING REQUIREMENTS

### 4.1 Observability Stack

```yaml
# metrics.yaml
metrics:
  prometheus:
    enabled: true
    port: 9090
    scrape_interval: 15s
  
  # Custom metrics
  - name: kernel_approvals_total
    type: counter
    labels: [decision, capability_id]
    
  - name: brain_inference_latency_ms
    type: histogram
    buckets: [10, 50, 100, 500, 1000]
    
  - name: action_execution_duration_ms
    type: histogram
    
  - name: trust_level_current
    type: gauge
    
  - name: circuit_breaker_state
    type: gauge
    labels: [component]
```

### 4.2 Structured Logging Standard

```julia
# Logging format (JSON)
# {
#   "timestamp": "2026-02-26T03:38:05.877Z",
#   "level": "INFO",
#   "component": "kernel.approve",
#   "message": "Action approved",
#   "trace_id": "uuid",
#   "context": {
#     "proposal_id": "uuid",
#     "capability_id": "safe_shell",
#     "risk_level": "medium",
#     "decision": "APPROVED"
#   }
# }
```

### 4.3 Metrics Dashboard Model

| Dashboard | Metrics | Alerts |
|-----------|---------|--------|
| System Health | CPU, Memory, Disk, Network | >80% usage |
| Kernel | Approvals/sec, Denials, Latency p99 | >100ms latency |
| Brain | Inference time, Confidence, Training loss | Confidence <0.5 |
| Actions | Execution count, Success rate, Errors | Failure >5% |
| Trust | Current level, Confirmations, Recalibrations | Trust drift >10% |

### 4.4 Chaos Testing Plan

| Scenario | Target | Expected Behavior |
|----------|--------|------------------|
| LLM API failure | Brain | Fallback to heuristic, log error |
| Network partition | Observation | Use cached values, degrade |
| High load | All | Circuit breakers, queueing |
| Memory exhaustion | Vector store | Stop ingestion, compact |
| Invalid input | Kernel | Fail-closed, reject |

### 4.5 Load Testing Targets

| Metric | Target | Peak |
|--------|--------|------|
| Concurrent users | 10 | 100 |
| Requests/second | 50 | 500 |
| Latency p99 | <500ms | <2s |
| Brain inference | <100ms | <500ms |
| Kernel approval | <10ms | <50ms |

### 4.6 Security Audit Checklist

- [ ] All API keys in Vault/ENV, not in code
- [ ] Kernel sovereignty invariant verified
- [ ] Audit log non-negotiable
- [ ] Input sanitization on all capabilities
- [ ] Rate limiting on external APIs
- [ ] SQL injection prevention
- [ ] Command injection prevention
- [ ] Path traversal prevention
- [ ] TLS for all external communication
- [ ] Regular secrets rotation

### 4.7 Secrets Rotation Plan

```yaml
rotation:
  schedule:
    api_keys: 90_days
    database: 180_days
    certificates: 365_days
    
  process:
    1. Generate new secret
    2. Update in Vault
    3. Deploy to secret consumer
    4. Verify
    5. Revoke old
```

### 4.8 CI/CD Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CI/CD PIPELINE                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐   │
│  │  Build  │───▶│  Test   │───▶│  Scan   │───▶│ Deploy  │   │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘   │
│      │              │              │              │          │
│      ▼              ▼              ▼              ▼          │
│  Compile        Unit Tests    SAST Scan      Staging       │
│  Lint          Integration    Dependency     Production     │
│  Format        Property       Secrets        Canary         │
│                                                  Rollback      │
└─────────────────────────────────────────────────────────────────┘
```

### 4.9 Deployment Topology

| Environment | Topology | Use |
|-------------|----------|-----|
| Development | Local Julia | Feature development |
| Staging | Single node | Integration testing |
| Production | Multi-node (3+) | HA, load balancing |

---

## 5. FINAL STATE DEFINITION

### 5.1 "Production Ready" Criteria

| Criterion | Metric | Threshold |
|-----------|--------|-----------|
| Test Coverage | Line coverage | >80% |
| Performance | Latency p99 | <500ms |
| Reliability | Uptime | >99.9% |
| Security | Vulnerabilities | 0 Critical |
| Documentation | API docs | 100% |

### 5.2 "Sovereign Safe" Criteria

| Criterion | Verification | Method |
|-----------|--------------|--------|
| No bypass of approval | Audit log 100% coverage | Automated check |
| Fail-closed | On error, default DENY | Chaos testing |
| Immutable decisions | Audit log append-only | Crypto hash |
| Trust calibration | Dynamic adjustment | A/B testing |

### 5.3 "Cognitively Integrated" Criteria

| Criterion | Metric | Threshold |
|-----------|--------|-----------|
| Brain activation | Neural inference active | >90% of cycles |
| Training loop | Backprop on feedback | Every 10 cycles |
| Memory integration | Embeddings stored | 100% of inputs |
| Uncertainty aware | Epistemic uncertainty | Computed per inference |

### 5.4 "Operationally Resilient" Criteria

| Criterion | Metric | Threshold |
|-----------|--------|-----------|
| Circuit breakers | Active | All external deps |
| Graceful degradation | Degradation modes | 4 modes implemented |
| Self-healing | Recovery automation | >80% auto-recovery |
| Observability | Metrics exported | 100% components |
| Recovery time | MTTR | <5 minutes |

---

## IMPLEMENTATION PRIORITY MATRIX

| Priority | Module | Files to Create/Modify | Effort |
|----------|--------|----------------------|--------|
| P0 | H. Config & Secrets | `jarvis/src/config/*.jl`, `config/env_schema.yaml` | 1 week |
| P0 | G. Persistence | `adaptive-kernel/persistence/*.jl` | 1 week |
| P1 | B. Kernel Sovereignty | `adaptive-kernel/kernel/sovereignty/*.jl` | 1 week |
| P1 | A. Brain Activation | `adaptive-kernel/brain/*.jl`, modify `SystemIntegrator.jl` | 2 weeks |
| P1 | I. Trust Model | `adaptive-kernel/kernel/trust/*.jl` | 1 week |
| P2 | C. Observation | `adaptive-kernel/kernel/observability/*.jl` | 1 week |
| P2 | D. Voice | `jarvis/src/voice/*.jl` | 1.5 weeks |
| P2 | E. Vision | `jarvis/src/vision/*.jl` | 1.5 weeks |
| P3 | F. OpenClaw | `adaptive-kernel/registry/*.jl`, `adaptive-kernel/sandbox/*.jl` | 1 week |
| P3 | J. Error Handling | `adaptive-kernel/resilience/*.jl` | 1 week |

---

**END OF IMPLEMENTATION PLAN**
