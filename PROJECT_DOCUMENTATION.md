# ProjectX Jarvis - Complete System Documentation

> **⚠️ System Status: PROTOTYPE / EXPERIMENTAL**
> This system is a research prototype. It is NOT production-ready.
> - Security Score: 12/100 (CRITICAL)
> - Cognitive Completeness: 47/100 (Partial)
> - Personal Assistant Readiness: 42/100 (Not production-ready)

> ⚠️ **IMPORTANT:** For the authoritative and current feature maturity status, always refer to [STATUS.md](STATUS.md).

**Version:** 1.0.0  
**Last Updated:** 2026-02-28  
**Julia Version:** 1.8+  
**Status:** Experimental Prototype

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Architecture](#2-system-architecture)
3. [Core Components](#3-core-components)
4. [Cognitive Systems](#4-cognitive-systems)
5. [Security Framework](#5-security-framework)
6. [Testing Strategy](#6-testing-strategy)
7. [API Reference](#7-api-reference)
8. [Configuration Guide](#8-configuration-guide)
9. [Troubleshooting](#9-troubleshooting)
10. [Development Roadmap](#10-development-roadmap)

---

## 1. Executive Summary

### Project Overview

**ProjectX Jarvis** is a cutting-edge Neuro-Symbolic Autonomous System that merges high-level LLM reasoning with low-level deterministic safety. It evolves the existing ProjectX codebase into a fully integrated, proactive personal assistant.

### System Philosophy

The system is built on five fundamental principles:

1. **Brain is advisory. Kernel is sovereign.** — All brain outputs must pass through `Kernel.approve()` before execution. No exceptions.

2. **Continuous perception must not bypass kernel risk evaluation.** — All sensory streams feed into the kernel's approval pipeline.

3. **Learning must be sandboxed and reversible.** — All model updates occur in isolated environments with checkpoint rollback capability.

4. **Emotions modulate value signals but do not override safety.** — Emotional states affect value weighting in brain inference but cannot bypass kernel veto.

5. **All subsystems must expose clear interface contracts.** — Every module must define input/output types and document pre/post conditions.

### Key Metrics

| Metric | Value |
|--------|-------|
| Kernel Size | 1790 lines |
| Decision Latency | See benchmark results |
| Dependencies | Minimal (JSON only) |
| Test Coverage | Unit + Integration |
| Trust Levels | 5 (BLOCKED → FULL) |
| Memory Capacity | 1000 events (MAX_EPISODIC_MEMORY) |

---

## 2. System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PROJECT JARVIS ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     CEREBRAL CORTEX (LLM Layer)                     │   │
│  │                                                                       │   │
│  │  ┌─────────────┐  ┌──────────────────┐  ┌─────────────────────────┐  │   │
│  │  │  GPT-4o    │  │  Claude 3.5       │  │  Natural Language       │  │   │
│  │  │  Bridge    │  │  Bridge           │  │  Parser                 │  │   │
│  │  └──────┬──────┘  └────────┬─────────┘  └───────────┬─────────────┘  │   │
│  │         │                  │                       │                  │   │
│  │         └──────────────────┼───────────────────────┘                  │   │
│  │                            │                                          │   │
│  │                    ┌──────▼──────┐                                    │   │
│  │                    │   LLMBridge │  ◄─── Async LLM Communication     │   │
│  │                    └──────┬──────┘                                    │   │
│  └───────────────────────────┼────────────────────────────────────────────┘   │
│                              │                                                 │
│                              ▼                                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                  ITHERIS REINFORCEMENT BRAIN                         │   │
│  │                                                                       │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │                    BrainCore (itheris.jl)                      │ │   │
│  │  │                                                                  │ │   │
│  │  │   12-Dimensional Feature Vector ──► Neural Network ──► Actions │ │   │
│  │  │                                                                  │ │   │
│  │  │   • Episodic Learning      • Dream/Imagination                  │ │   │
│  │  │   • Action Proposals       • Value Estimation                   │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  └───────────────────────────┬────────────────────────────────────────────┘   │
│                              │                                                 │
│                              ▼                                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    ADAPTIVE KERNEL (Safety Valve)                   │   │
│  │                                                                       │   │
│  │   ┌───────────────────────────────────────────────────────────────┐  │   │
│  │   │              Deterministic Formula                             │  │   │
│  │   │        score = priority × (reward − risk)                     │  │   │
│  │   └───────────────────────────────────────────────────────────────┘  │   │
│  │                                                                       │   │
│  │   ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐    │   │
│  │   │  Whitelist   │  │  Audit Log   │  │  Trust Level          │    │   │
│  │   │  Enforcement │  │  (events.log)│  │  (TRUST_BLOCKED→FULL)│    │   │
│  │   └──────────────┘  └──────────────┘  └────────────────────────┘    │   │
│  │                                                                       │   │
│  │   Capabilities: Shell, HTTP, IoT, File Operations                    │   │
│  └───────────────────────────┬────────────────────────────────────────────┘   │
│                              │                                                 │
│                              ▼                                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    SEMANTIC MEMORY (Long-Term)                      │   │
│  │                                                                       │   │
│  │   ┌───────────────┐  ┌───────────────┐  ┌───────────────────────┐   │   │
│  │   │  Vector DB   │  │  RAG Engine  │  │  Memory Collections  │   │   │
│  │   │  (Qdrant/   │  │  (Retrieval  │  │  • User Preferences  │   │   │
│  │   │   HNSW)     │  │   Augmented  │  │  • Conversations     │   │   │
│  │   │             │  │   Generation) │  │  • Project Knowledge │   │   │
│  │   └───────────────┘  └───────────────┘  └───────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                 PROACTIVE PLANNING (TaskOrchestrator)               │   │
│  │                                                                       │   │
│  │   • Periodic WorldState Scanning                                     │   │
│  │   • Optimization Suggestions ("CPU high, throttle tasks?")          │   │
│  │   • Safety Alerts                                                   │   │
│  │   • Automation Recommendations                                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    SYSTEM INTEGRATOR                                  │   │
│  │              (Central Nervous System)                                │   │
│  │                                                                       │   │
│  │   ┌───────────────────────────────────────────────────────────────┐  │   │
│  │   │                    run_cycle()                                 │  │   │
│  │   │   1. Observe → 2. Perceive → 3. Infer → 4. Approve          │  │   │
│  │   │   5. Execute → 6. Learn  → 7. Suggest                      │  │   │
│  │   └───────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Three-Subsystem Model

| Subsystem | Purpose | Authority |
|-----------|---------|-----------|
| **ITHERIS Brain** | Neural decision making, action proposals | Advisory only |
| **Adaptive Kernel** | Deterministic safety validation | Sovereign authority |
| **Cerebral Cortex** | Natural language understanding | Input processing |

---

## 3. Core Components

### 3.1 JARVIS Components

```
jarvis/
├── Project.toml                    # Julia package manifest
├── README.md                       # Project overview
├── DOCUMENTATION.md                # Comprehensive documentation
└── src/
    ├── Jarvis.jl                   # Main entry point
    ├── SystemIntegrator.jl         # Central Nervous System (82,851 bytes)
    ├── types.jl                    # Core type definitions
    ├── llm/
    │   └── LLMBridge.jl            # LLM communication (GPT-4o, Claude)
    ├── memory/
    │   ├── VectorMemory.jl         # Semantic storage + RAG
    │   └── SemanticMemory.jl       # Action outcome memory
    ├── orchestration/
    │   └── TaskOrchestrator.jl     # Proactive planning
    ├── bridge/
    │   ├── CommunicationBridge.jl   # Voice/Vision
    │   └── OpenClawBridge.jl      # Tool container interface
    ├── brain/
    │   └── BrainTrainer.jl         # Neural training
    ├── auth/
    │   └── JWTAuth.jl              # Authentication
    └── config/
        ├── ConfigLoader.jl         # Configuration loading
        └── SecretsManager.jl       # Secrets management
```

### 3.2 Adaptive Kernel Components

```
adaptive-kernel/
├── kernel/
│   ├── Kernel.jl                   # Core kernel (278 lines)
│   └── trust/
│       ├── Trust.jl                # Trust management
│       ├── RiskClassifier.jl       # Risk classification
│       └── ConfirmationGate.jl    # Confirmation handling
├── cognition/
│   ├── Cognition.jl               # Main cognition engine
│   ├── spine/
│   │   ├── DecisionSpine.jl        # Decision coordination
│   │   └── ConflictResolution.jl   # Agent conflict resolution
│   ├── agents/
│   │   ├── ExecutorAgent.jl        # Action execution
│   │   ├── StrategistAgent.jl      # Strategic planning
│   │   ├── AuditorAgent.jl         # Safety auditing
│   │   └── EvolutionEngine.jl     # Strategy evolution
│   ├── goals/
│   │   └── GoalSystem.jl           # Goal management
│   ├── worldmodel/
│   │   └── WorldModel.jl           # World state modeling
│   ├── security/
│   │   └── InputSanitizer.jl      # Input sanitization
│   └── feedback/
│       └── Emotions.jl             # Emotional state
├── capabilities/
│   ├── observe_cpu.jl             # CPU monitoring
│   ├── observe_filesystem.jl      # File system monitoring
│   ├── safe_shell.jl              # Safe shell execution
│   └── analyze_logs.jl            # Log analysis
├── brain/
│   ├── Brain.jl                   # Neural brain
│   └── NeuralBrainCore.jl         # Brain implementation
├── sensory/
│   └── SensoryProcessing.jl       # Sensory processing
└── tests/
    ├── unit_kernel_test.jl        # Kernel unit tests
    └── integration_test.jl        # Integration tests
```

---

## 4. Cognitive Systems

### 4.1 Cognitive Cycle

The cognitive cycle follows a 7-stage process:

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         COGNITIVE CYCLE DATA FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  1. PERCEIVE()                                                                       │
│     ├── ContinuousSensoryBuffer ←──── Visual Stream                                  │
│     ├── ContinuousSensoryBuffer ←──── Auditory Stream                               │
│     ├── ContinuousSensoryBuffer ←──── System Telemetry                              │
│     └── Returns: SensorySnapshot                                                     │
│                                                                                      │
│  2. ATTEND()                                                                         │
│     ├── SensorySnapshot → SalienceScorer                                            │
│     ├── NoveltyDetector                                                              │
│     └── Returns: AttendedPercept (bounded compute)                                  │
│                                                                                      │
│  3. UPDATE_WORLD_MODEL()                                                             │
│     ├── AttendedPercept → WorldModel.predict_next()                                 │
│     ├── CounterfactualGenerator                                                     │
│     └── Returns: UpdatedWorldState, RiskPrediction                                   │
│                                                                                      │
│  4. GENERATE_GOALS()                                                                 │
│     ├── WorldState → AutonomousGoalGenerator                                        │
│     ├── CuriosityRewardComputer                                                     │
│     └── Kernel.approve(new_goals) ← CRITICAL SOVEREIGNTY CHECK                      │
│                                                                                      │
│  5. INFER_ACTIONS()                                                                  │
│     ├── AttendedPercept + Goals + Emotions → ITHERIS.infer()                        │
│     ├── BrainOutput (advisory)                                                       │
│     └── Returns: BrainOutput                                                         │
│                                                                                      │
│  6. KERNEL_APPROVAL()                                                                │
│     ├── BrainOutput.proposed_actions → Kernel.approve()                              │
│     ├── Kernel evaluates: risk, energy, confidence, goal alignment                 │
│     └── Returns: Decision {APPROVED, DENIED, STOPPED}                               │
│                                                                                      │
│  7. EXECUTE()                                                                        │
│     ├── If APPROVED: Execute action via CapabilityRegistry                           │
│     ├── Observe outcome                                                             │
│     └── Returns: ExecutionResult                                                     │
│                                                                                      │
│  8. REFLECT()                                                                        │
│     ├── ExecutionResult → ReflectionEngine                                          │
│     ├── Update SelfModel (confidence, energy)                                       │
│     ├── Update GoalState                                                             │
│     └── Returns: ReflectionEvent                                                     │
│                                                                                      │
│  9. LEARN()                                                                          │
│     ├── ReflectionEvent → ExperienceReplayBuffer                                     │
│     ├── ITHERIS.learn!() (sandboxed, reversible)                                    │
│     └── MetaLearning.update()                                                       │
│                                                                                      │
│  10. SLEEP_IF_NEEDED()                                                               │
│      ├── Check: cycle_count % sleep_threshold == 0                                  │
│      ├── sleep_cycle!():                                                             │
│      │    ├── consolidate_memory!(): Episodic → Semantic                            │
│      │    └── dream!(): Counterfactual exploration                                  │
│      └── Returns: UpdatedMemory                                                      │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Multi-Agent System

The cognition system employs four specialized agents:

| Agent | Role | Function |
|-------|------|----------|
| **Executor** | Action execution | Translates decisions into capability calls |
| **Strategist** | Long-horizon planning | Plans multi-step goal achievement |
| **Auditor** | Safety constraint enforcement | Validates safety and policy compliance |
| **Evolution** | Strategy adaptation | Evolves doctrine based on outcomes |

### 4.3 World Model

The World Model provides predictive capabilities:

- **State Prediction**: Predicts next system state given actions
- **Reward Prediction**: Estimates expected reward for actions
- **Risk Prediction**: Assesses potential risks
- **Counterfactual Simulation**: Explores alternative action sequences

---

## 5. Security Framework

### 5.1 Trust Levels

The system implements a five-level trust model:

```julia
@enum TrustLevel begin
    TRUST_BLOCKED = 0      # No actions allowed
    TRUST_RESTRICTED = 1   # Only read-only actions
    TRUST_LIMITED = 2      # Non-destructive actions only  
    TRUST_STANDARD = 3      # Most actions allowed
    TRUST_FULL = 4          # All actions allowed (with audit)
end
```

| Level | Value | Allowed Actions |
|-------|-------|----------------|
| `TRUST_BLOCKED` | 0 | None |
| `TRUST_RESTRICTED` | 1 | Read-only |
| `TRUST_LIMITED` | 2 | Non-destructive |
| `TRUST_STANDARD` | 3 | Most actions |
| `TRUST_FULL` | 4 | All (with audit) |

### 5.2 Input Sanitization

The [`InputSanitizer`](adaptive-kernel/cognition/security/InputSanitizer.jl) module implements multi-layered security:

**Threats Detected:**
- Prompt injection attempts
- Tool injection attempts
- Hidden XML/HTML tags
- Role override attempts
- LLM jailbreak attempts
- Base64-encoded payloads
- Unicode obfuscation
- Shell injection fragments
- JSON schema spoofing

**Sanitization Levels:**
- `CLEAN` - Input passes all checks
- `SUSPICIOUS` - Requires manual review
- `MALICIOUS` - Blocked immediately

### 5.3 Kernel Sovereignty

The Adaptive Kernel enforces deterministic safety:

```
score = priority × (reward − risk)
```

**Safety Guarantees:**
1. All actions pass through `Kernel.approve()`
2. Fail-closed behavior on errors
3. Append-only audit trail
4. Deterministic decision logic (no randomness)
5. Type-stable code (no `Any` in critical paths)

---

## 6. Testing Strategy

### 6.1 Test Architecture

The system follows a comprehensive 5-phase testing approach:

```
PHASE 0: STATIC ANALYSIS (No Execution)
├── SA-01: Dependency Graph Validation
├── SA-02: Type Stability Analysis
├── SA-03: Circular Dependency Detection
└── SA-04: Security Boundary Analysis

PHASE 1: UNIT ISOLATION (Mocked External)
├── U-01: Kernel State Machine Tests
├── U-02: Type Constructor Tests
├── U-03: Decision Spine Tests
├── U-04: Agent Proposal Generation Tests
├── U-05: Capability Filter Tests
└── U-06: Conversion Function Tests

PHASE 2: INTEGRATION (Internal Only)
├── I-01: Kernel ↔ Cognition Integration
├── I-02: Decision Spine ↔ Agents Integration
├── I-03: Memory Persistence Tests
├── I-04: Jarvis ↔ Kernel Bridge Tests
└── I-05: Type Conversion Round-trip Tests

PHASE 3: SYSTEM INTEGRATION (Real Components)
├── S-01: Full Cognitive Cycle Tests
├── S-02: LLM Bridge Integration Tests
├── S-03: Orchestration Flow Tests
├── S-04: End-to-End Scenario Tests
└── S-05: UI Backend Integration Tests

PHASE 4: ADVERSARIAL & STRESS
├── A-01: Capability Bypass Attempts
├── A-02: Cognitive Cycle Injection Tests
├── A-03: Memory Corruption Tests
├── A-04: Concurrency Stress Tests
└── A-05: Chaos Engineering Tests

PHASE 5: REGRESSION & REPRODUCIBILITY
├── R-01: Manifest.toml Reproducibility
├── R-02: Deterministic Cycle Tests
├── R-03: Cross-Version Compatibility
└── R-04: Performance Baseline Comparison
```

### 6.2 Running Tests

```bash
# Unit tests
cd adaptive-kernel
julia --project=. -e 'include("tests/unit_kernel_test.jl")'

# Integration tests
julia --project=. -e 'include("tests/integration_simulation_test.jl")'

# Full test suite
julia --project=. -e 'using Pkg; Pkg.test()'
```

---

## 7. API Reference

### 7.1 System Integrator

| Function | Description |
|----------|-------------|
| [`initialize_jarvis()`](jarvis/src/SystemIntegrator.jl:240) | Initialize the complete Jarvis system |
| [`run_cycle()`](jarvis/src/SystemIntegrator.jl:515) | Execute one complete cognitive cycle |
| [`process_user_request()`](jarvis/src/SystemIntegrator.jl) | Process natural language user request |
| [`get_system_status()`](jarvis/src/SystemIntegrator.jl) | Get current system status |
| [`shutdown()`](jarvis/src/SystemIntegrator.jl) | Graceful shutdown |

### 7.2 Kernel

| Function | Description |
|----------|-------------|
| [`init_kernel()`](adaptive-kernel/kernel/Kernel.jl) | Initialize kernel state |
| [`step_once()`](adaptive-kernel/kernel/Kernel.jl) | Execute one kernel cycle |
| [`evaluate_world()`](adaptive-kernel/kernel/Kernel.jl) | Compute goal priorities |
| [`request_action()`](adaptive-kernel/kernel/Kernel.jl) | Request action approval |
| [`reflect()`](adaptive-kernel/kernel/Kernel.jl) | Reflect on action outcome |

### 7.3 Cognition

| Function | Description |
|----------|-------------|
| [`run_sovereign_cycle()`](adaptive-kernel/cognition/Cognition.jl:167) | Run complete cognition cycle |
| [`generate_goals()`](adaptive-kernel/cognition/goals/GoalSystem.jl) | Generate goals from perception |
| [`predict_next_state()`](adaptive-kernel/cognition/worldmodel/WorldModel.jl) | Predict next world state |

### 7.4 Security

| Function | Description |
|----------|-------------|
| [`sanitize_input()`](adaptive-kernel/cognition/security/InputSanitizer.jl) | Sanitize user input |
| [`classify_action_risk()`](adaptive-kernel/kernel/trust/RiskClassifier.jl) | Classify action risk |
| [`require_confirmation()`](adaptive-kernel/kernel/trust/ConfirmationGate.jl) | Require user confirmation |

---

## 8. Configuration Guide

### 8.1 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `JULIA_PROJECT` | Julia project path | `./` |
| `JARVIS_CONFIG_PATH` | Configuration file path | `./config.toml` |
| `EVENTS_LOG_PATH` | Events log location | `./events.log` |
| `TRUST_LEVEL` | Initial trust level | `TRUST_STANDARD` |

### 8.2 Configuration File

```toml
[julius]
version = "1.0"
julia_version = "1.8+"

[llm]
provider = "openai"
model = "gpt-4o"
max_tokens = 2048
temperature = 0.7

[security]
require_confirmation_threshold = "TRUST_STANDARD"
audit_enabled = true

[proactive]
scan_interval_seconds = 30
```

---

## 9. Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Kernel initialization fails | Check `config.toml` syntax |
| LLM requests timeout | Verify API keys in secrets manager |
| Memory exhaustion | Reduce episodic memory capacity |
| Trust level too low | Adjust trust thresholds in configuration |

### Debug Mode

```bash
# Enable debug output
JULIA_DEBUG=all julia --project=. harness/run.jl
```

### Log Inspection

```bash
# Inspect event log
julia tools/inspect_log.jl

# Custom log file
julia tools/inspect_log.jl my_events.log
```

---

## 10. Development Roadmap

### Current Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ COMPLETE | ITHERIS Brain Integration |
| Phase 2 | ✅ COMPLETE | Kernel Sovereignty Enforcement |
| Phase 3 | ✅ COMPLETE | SystemIntegrator Integration |
| Phase 4 | ✅ COMPLETE | Testing (55 tests passing) |

### Milestones

See [`adaptive-kernel/MILESTONES.md`](adaptive-kernel/MILESTONES.md) for detailed roadmap:

- **Milestone 1**: Foundation (Kernel + Registry + Capabilities)
- **Milestone 2**: Real OS Perception
- **Milestone 3**: Safe Shell & OS Integration
- **Milestone 4**: Threat Modeling & High-Risk Actions
- **Milestone 5**: Procedural Memory & Learning
- **Milestone 6**: Distributed & Multi-Agent
- **Milestone 7**: Production Hardening & Ops
- **Milestone 8**: Field Deployment & Certification

---

## Additional Documentation

| Document | Description |
|----------|-------------|
| [`jarvis/README.md`](jarvis/README.md) | JARVIS quick start |
| [`jarvis/DOCUMENTATION.md`](jarvis/DOCUMENTATION.md) | Comprehensive JARVIS docs |
| [`adaptive-kernel/README.md`](adaptive-kernel/README.md) | Adaptive Kernel overview |
| [`adaptive-kernel/START_HERE.md`](adaptive-kernel/START_HERE.md) | Getting started guide |
| [`adaptive-kernel/DESIGN.md`](adaptive-kernel/DESIGN.md) | Design rationale |
| [`TEST_STRATEGY.md`](TEST_STRATEGY.md) | Testing methodology |
| [`Manifest.md`](Manifest.md) | Architecture manifest |
| [`plans/JARVIS_NEUROSYMBOLIC_ARCHITECTURE.md`](plans/JARVIS_NEUROSYMBOLIC_ARCHITECTURE.md) | Detailed architecture |

---

*Last Updated: 2026-02-28*
