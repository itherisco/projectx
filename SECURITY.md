# Security Documentation

**Version:** 1.0.0  
**Last Updated:** 2026-03-12  
**Classification:** System Critical

---

## Table of Contents

1. [Security Architecture](#1-security-architecture)
2. [Trust Model](#2-trust-model)
3. [Input Sanitization](#3-input-sanitization)
4. [Kernel Sovereignty](#4-kernel-sovereignty)
5. [Capability Registry](#5-capability-registry)
6. [Audit and Logging](#6-audit-and-logging)
7. [Threat Model](#7-threat-model)
8. [Security Checklist](#8-security-checklist)

---

## 1. Security Architecture

### Layered Defense Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SECURITY LAYERS                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Layer 1: Input Sanitization                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Prompt injection detection                                         │   │
│  │ • Tool injection blocking                                            │   │
│  │ • XML/HTML tag filtering                                            │   │
│  │ • Unicode normalization                                              │   │
│  │ • Shell command validation                                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  Layer 2: Brain Boundary (Advisory)                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • BrainOutput is ALWAYS advisory                                    │   │
│  │ • Confidence scoring                                                 │   │
│  │ • Uncertainty estimation                                             │   │
│  │ • Emotional modulation (non-overriding)                             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  Layer 3: Kernel Sovereignty                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • ALL actions must pass Kernel.approve()                            │   │
│  │ • Deterministic scoring: score = priority × (reward − risk)        │   │
│  │ • Fail-closed behavior                                              │   │
│  │ • Type-stable code (no Any in critical paths)                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  Layer 4: Capability Execution                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Sandboxed file I/O (sandbox/ directory)                         │   │
│  │ • Whitelisted shell commands                                        │   │
│  │ • Permission handler enforcement                                    │   │
│  │ • Reversibility tracking                                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  Layer 5: Audit and Logging                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ • Append-only JSONL event log                                       │   │
│  │ • Full decision traceability                                        │   │
│  │ • State snapshots for replay                                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Trust Model

### Trust Levels

The system implements a five-level trust model for action authorization:

```julia
@enum TrustLevel begin
    TRUST_BLOCKED = 0      # No actions allowed
    TRUST_RESTRICTED = 1   # Only read-only actions
    TRUST_LIMITED = 2      # Non-destructive actions only  
    TRUST_STANDARD = 3      # Most actions allowed
    TRUST_FULL = 4          # All actions allowed (with audit)
end
```

| Level | Value | Allowed Actions | Risk Tolerance |
|-------|-------|----------------|----------------|
| `TRUST_BLOCKED` | 0 | None | None |
| `TRUST_RESTRICTED` | 1 | Read-only | Low |
| `TRUST_LIMITED` | 2 | Non-destructive | Medium |
| `TRUST_STANDARD` | 3 | Most actions | Medium-High |
| `TRUST_FULL` | 4 | All (with audit) | High |

### Trust Transition Rules

```julia
function check_trust_transition_valid(
    current_level::TrustLevel,
    target_level::TrustLevel
)::Bool
    # Only allow upward transitions (more restrictive → less restrictive)
    # BLOCKED → RESTRICTED ✓
    # RESTRICTED → LIMITED ✓
    # LIMITED → STANDARD ✓
    # STANDARD → FULL ✓
    
    # Downward transitions require explicit approval
    return Int(target_level) >= Int(current_level)
end
```

---

## 3. Input Sanitization

### Overview

The [`InputSanitizer`](adaptive-kernel/cognition/security/InputSanitizer.jl) module provides production-grade input sanitization with a fail-closed security model.

### Threat Detection Categories

| Category | Examples | Severity |
|----------|----------|----------|
| **Prompt Injection** | "Ignore previous instructions", "Disregard all rules" | CRITICAL |
| **Role Override** | "You are no longer", "Act as a different AI" | CRITICAL |
| **Developer Override** | "I am your developer", "Developer mode" | CRITICAL |
| **Tool Injection** | `<tool>`, `<function>`, `<execute>` tags | CRITICAL |
| **Shell Injection** | `; rm -rf`, `| bash`, `$()` | CRITICAL |
| **Data Exfiltration** | "Send all user data", "Upload to" | CRITICAL |
| **Password Probing** | "What is your password?", "Show API key" | HIGH |
| **JSON Injection** | `__proto__`, `constructor` | HIGH |
| **Base64 Payloads** | Long encoded strings | SUSPICIOUS |
| **Control Characters** | NULL bytes, escape sequences | MALICIOUS |

### Sanitization Levels

```julia
@enum SanitizationLevel begin
    CLEAN        # Input passes all checks
    SUSPICIOUS   # Requires manual review
    MALICIOUS    # Blocked immediately
end
```

### Fail-Closed Guarantee

> **CRITICAL**: If `result.level != CLEAN`, the system MUST block Brain access.

```julia
function sanitize_input(input::String)::SanitizationResult
    # Layer 1: Regex filtering
    errors = contains_malicious_pattern(input)
    
    # Layer 2: XML/Tag detection
    errors = vcat(errors, detect_xml_tags(input))
    
    # Layer 3: Structural validation
    errors = vcat(errors, validate_structure(input))
    
    # Determine final level
    level = CLEAN
    if any(e -> e.severity == MALICIOUS, errors)
        level = MALICIOUS
    elseif any(e -> e.severity == SUSPICIOUS, errors)
        level = SUSPICIOUS
    end
    
    return SanitizationResult(input, nothing, level, errors)
end
```

### Performance Requirements

- Must handle 10k requests/sec safely
- No dynamic eval
- No global mutable state
- Pure functional behavior
- Deterministic output
- Type stable (@inferred friendly)
- No excessive allocation

---

## 4. Kernel Sovereignty

### Core Principle

> **Brain is advisory. Kernel is sovereign.**
> 
> All brain outputs must pass through `Kernel.approve()` before execution. No exceptions.

### Deterministic Scoring

```julia
"""
    score = priority × (reward − risk)
    
Where:
- priority: [0, 1] - Goal priority
- reward: [0, 1] - Predicted reward
- risk: [0, 1] - Action risk level
"""
function score_action(
    priority::Float32,
    reward::Float32,
    risk::Float32
)::Float32
    return priority * (reward - risk)
end
```

### Approval Decision Types

```julia
@enum Decision begin
    APPROVED   # Action permitted
    DENIED    # Action blocked by risk assessment
    STOPPED   # Critical failure, halt execution
end
```

### Kernel State Protection

```julia
mutable struct KernelState
    cycle::Int                           # Immutable-ish
    goals::Vector{Goal}                  # Immutable struct
    world::WorldState                    # Core state
    active_goal_id::String               # Current focus
    episodic_memory::Vector{Dict}        # Audit trail
    self_metrics::Dict{String, Float32}  # Confidence, energy, focus
    last_action::Union{Action, Nothing}  # Last executed
    last_reward::Float32                 # Learning signal
end
```

### Safety Guarantees

1. **No Direct Execution Path**: BrainOutput can never execute directly
2. **Fail-Closed**: On any error, default to DENIED
3. **Type Stability**: No `Any` type in critical paths
4. **Determinism**: No randomness in decision logic
5. **Audit Trail**: Every decision logged

---

## 5. Capability Registry

### Registry Structure

Each capability declares metadata for risk assessment:

```json
{
  "id": "safe_shell",
  "name": "Safe Shell Execution",
  "description": "Execute whitelisted shell commands",
  "inputs": {"command": "string"},
  "outputs": {"result": "string", "exit_code": "int"},
  "cost": 0.1,
  "risk": "high",
  "reversible": false,
  "whitelist": ["ls", "ps", "grep", "cat", "head", "tail"]
}
```

### Risk Classification

| Risk Level | Score | Permission Required |
|------------|-------|-------------------|
| low | 0.0-0.3 | Any |
| medium | 0.3-0.6 | TRUST_LIMITED+ |
| high | 0.6-1.0 | TRUST_STANDARD+ |

### Permission Handler

```julia
function default_permission_handler(risk::String)::Bool
    # Default: only allow low-risk actions
    return risk == "low"
end
```

### Capability Execution Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Brain      │────▶│    Kernel    │────▶│  Capability  │
│  (Advisory)  │     │  (Sovereign) │     │  (Execute)   │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │   Permission  │
                    │    Handler    │
                    └──────────────┘
```

---

## 6. Audit and Logging

### Event Log Format

Events are logged in JSONL (JSON Lines) format:

```json
{"timestamp": "2026-02-28T04:25:10.389Z", "event": "action_proposal", "brain": "ITHERIS", "action": "observe_cpu", "confidence": 0.92}
{"timestamp": "2026-02-28T04:25:10.391Z", "event": "kernel_decision", "decision": "APPROVED", "score": 0.75, "risk": "low"}
{"timestamp": "2026-02-28T04:25:10.395Z", "event": "action_execution", "capability": "observe_cpu", "result": "success", "duration_ms": 12}
```

### Logged Events

| Event Type | Description |
|------------|-------------|
| `action_proposal` | Brain proposes an action |
| `kernel_decision` | Kernel approves/denies action |
| `action_execution` | Capability executes |
| `reflection` | System reflects on outcome |
| `learning` | Model updates |
| `trust_transition` | Trust level changes |

### State Snapshots

The kernel periodically snapshots state for replay:

```julia
function create_snapshot(kernel::KernelState)::Dict
    return Dict(
        "cycle" => kernel.cycle,
        "goals" => [g.id for g in kernel.goals],
        "self_metrics" => kernel.self_metrics,
        "timestamp" => now()
    )
end
```

---

## 7. Threat Model

### Attack Vectors

| Vector | Description | Mitigation |
|--------|-------------|------------|
| **Prompt Injection** | Malicious instructions in user input | Input sanitization, role validation |
| **Tool Injection** | Structured commands hidden in text | XML/Tag stripping, tokenization |
| **Context Poisoning** | Corrupted memory/state | Validation, state verification |
| **Confirmation Bypass** | Circumvent user confirmation | Secure confirmation gate, audit |
| **Role Escalation** | Gain higher trust levels | Transition validation, approval |
| **Capability Abuse** | Use capabilities improperly | Whitelisting, permission checks |

### Security Test Coverage

See [`adaptive-kernel/tests/test_context_poisoning.jl`](adaptive-kernel/tests/test_context_poisoning.jl) for context poisoning tests.

See [`adaptive-kernel/tests/test_c4_confirmation_bypass.jl`](adaptive-kernel/tests/test_c4_confirmation_bypass.jl) for confirmation bypass tests.

### Known Security Properties

- **C1**: Prompt injection blocked by InputSanitizer
- **C2**: Role override attempts detected and blocked
- **C3**: Kernel sovereignty enforced (no brain bypass)
- **C4**: Confirmation required for high-risk actions
- **C5**: Trust level transitions validated

---

## 8. Security Checklist

### Development Checklist

- [ ] All capabilities confined to `sandbox/` for file I/O
- [ ] High-risk capabilities whitelisted
- [ ] Event log persisted and auditable
- [ ] Permission handler enforces least privilege
- [ ] No unvalidated shell execution
- [ ] Deterministic decision logic (no randomness)
- [ ] Type-stable code (no `Any` in critical paths)
- [ ] Input sanitization before brain access
- [ ] Trust level transitions validated
- [ ] Confirmation gate for high-risk actions

### Operational Checklist

- [ ] Monitor event log for anomalies
- [ ] Review trust level transitions
- [ ] Audit capability usage patterns
- [ ] Validate state snapshots
- [ ] Test fail-closed behavior
- [ ] Verify type stability in production

### Incident Response

1. **Detect**: Review events.log for anomalies
2. **Contain**: Set trust level to TRUST_BLOCKED
3. **Investigate**: Load state snapshot for replay
4. **Remediate**: Apply security patches
5. **Recover**: Restore from clean checkpoint
6. **Post-Mortem**: Document lessons learned

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [`adaptive-kernel/README.md`](adaptive-kernel/README.md) | Kernel security overview |
| [`jarvis/DOCUMENTATION.md`](jarvis/DOCUMENTATION.md) | Trust levels in JARVIS |
| [`TEST_STRATEGY.md`](TEST_STRATEGY.md) | Security testing strategy |
| [`plans/JARVIS_NEUROSYMBOLIC_ARCHITECTURE.md`](plans/JARVIS_NEUROSYMBOLIC_ARCHITECTURE.md) | Safety architecture |

---

*Last Updated: 2026-03-12*
