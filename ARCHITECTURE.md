# ITHERIS Architecture Documentation

> **Version:** 1.0.0  
> **Last Updated:** 2026-03-07  
> **System Status:** Experimental Prototype  
> **Classification:** Technical Architecture Specification

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture Principles](#2-architecture-principles)
3. [Core Components](#3-core-components)
4. [Data Flow Architecture](#4-data-flow-architecture)
5. [Security Architecture](#5-security-architecture)
6. [Module Relationships](#6-module-relationships)
7. [IPC Layer Architecture](#7-ipc-layer-architecture)
8. [Cognitive Systems](#8-cognitive-systems)
9. [Tool Ecosystem](#9-tool-ecosystem)
10. [Knowledge System](#10-knowledge-system)
11. [Proactive Intelligence](#11-proactive-intelligence)
12. [Interfaces](#12-interfaces)

---

## 1. System Overview

### 1.1 What is ITHERIS?

ITHERIS (Intelligent Theatrical Heuristic Experimental Reasoning and Intelligence System) is a **Neuro-Symbolic Autonomous System** that merges high-level LLM reasoning with low-level deterministic security enforcement. The system implements a cognitive architecture that combines neural decision-making with a deterministic security kernel, providing both adaptive intelligence and guaranteed safety boundaries.

### 1.2 Hybrid Rust-Julia Architecture

The system employs a dual-language architecture that leverages the strengths of both Rust and Julia:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ITHERIS HYBRID ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    JULIA COGNITIVE BRAIN (adaptive-kernel)           │   │
│  │                                                                       │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │   │
│  │   │  Cognition  │  │   Agents    │  │   Memory    │  │ Learning  │ │   │
│  │   │   Module    │  │   (ReAct)   │  │   System    │  │  Engine   │ │   │
│  │   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └─────┬─────┘ │   │
│  │          │                │                │               │       │   │
│  │          └────────────────┴────────────────┴───────────────┘       │   │
│  │                                   │                                    │   │
│  │                                   ▼                                    │   │
│  │                    ┌──────────────────────────────┐                   │   │
│  │                    │    WORLD MODEL & GOALS       │                   │   │
│  │                    └──────────────────────────────┘                   │   │
│  │                                   │                                    │   │
│  └───────────────────────────────────┼────────────────────────────────────┘   │
│                                      │                                         │
│                                      ▼                                         │
│  ┌───────────────────────────────────┼────────────────────────────────────┐   │
│  │                    IPC BRIDGE (Shared Memory / TCP)                   │   │
│  └───────────────────────────────────┼────────────────────────────────────┘   │
│                                      │                                         │
│                                      ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    RUST SECURITY KERNEL (itheris-daemon)              │   │
│  │                                                                       │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │   │
│  │   │  Capability │  │    Trust    │  │   Kernel   │  │   Event   │ │   │
│  │   │   Registry  │  │   Scoring   │  │  Approval  │  │   Audit   │ │   │
│  │   └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘ │   │
│  │                                                                       │   │
│  └───────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Key System Characteristics

| Characteristic | Description |
|----------------|-------------|
| **Paradigm** | Neuro-Symbolic - Combines neural LLM reasoning with symbolic rule-based security |
| **Primary Language** | Julia (Cognitive Brain) + Rust (Security Kernel) |
| **Decision Latency** | Target <100ms for kernel approval |
| **Trust Levels** | 5 levels (BLOCKED → FULL) |
| **Audit Trail** | 100% immutable append-only JSONL |
| **Kernel Size** | ~1790 lines (fully auditable) |
| **Memory Capacity** | 1000 events (MAX_EPISODIC_MEMORY) |

---

### 1.4 Hypervisor Classification: Intended vs. Actual

> **⚠️ ARCHITECTURE CLARIFICATION (2026-03-10)**
>
> The documentation historically referenced a **Type-1 Hypervisor** design with Extended Page Tables (EPT) for bare-metal isolation. This document clarifies the distinction between the **intended architecture** and the **current implementation**.

| Aspect | Intended Design (Type-1) | Current Implementation (Type-2) |
|--------|--------------------------|--------------------------------|
| **Isolation Level** | Bare-metal (Ring 0) | Process-level (Ring 3) |
| **Memory Protection** | EPT/NPT hardware virtualization | Standard x86-64 paging |
| **Julia Runtime** | Guest VM | Managed process |
| **Warden Role** | Hypervisor (VMM) | Supervisor process |
| **IPC Mechanism** | EPT-mapped shared memory | Shared memory ring buffer (`/dev/shm`) |
| **Security Boundary** | Hardware-enforced | Software-enforced (seccomp, namespaces, cgroups) |

**Current Implementation Details:**
- The Julia cognitive brain runs as a **child process** under the Rust Warden's supervision
- IPC occurs through **shared memory ring buffer** at addresses defined in [`IPC_SPEC.md`](IPC_SPEC.md)
- Security relies on **software isolation layers**: seccomp-bpf, Linux namespaces, cgroups
- The system functions as a **managed sandbox** rather than bare-metal virtualization

**Security Implications:**
- Without EPT traps, the Julia runtime has direct access to standard syscalls
- Memory isolation is provided by the OS kernel's standard process isolation
- A compromised Julia process could potentially escape to other processes on the same system
- The FFI boundary (Julia↔Rust) is the primary security checkpoint

---

## 2. Architecture Principles

### 2.1 Fundamental Principle: "Brain is advisory. Kernel is sovereign."

This is the foundational principle of ITHERIS. The cognitive brain (Julia) generates proposals, recommendations, and analyses, but the security kernel (Rust) has absolute authority over what actions are permitted to execute.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BRAIN IS ADVISORY. KERNEL IS SOVEREIGN                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐         ┌──────────────┐         ┌──────────────┐       │
│   │   User       │         │   Brain      │         │   Kernel     │       │
│   │   Input      │────────▶│  (Advisory)  │────────▶│ (Sovereign)  │       │
│   │              │         │              │         │              │       │
│   └──────────────┘         └──────┬───────┘         └──────┬───────┘       │
│                                    │                        │               │
│                                    │  PROPOSAL              │  VERDICT       │
│                                    │  (recommendation)      │  (authority)   │
│                                    │                        │               │
│                                    │                        ▼               │
│                                    │              ┌──────────────┐         │
│                                    │              │   Action     │         │
│                                    │              │   Execution  │         │
│                                    │              │   or Block   │         │
│                                    │              └──────────────┘         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Security-First Design

All security features are implemented with a **fail-closed** philosophy:

- **Default Deny**: All actions are blocked unless explicitly approved by the kernel
- **Fail-Closed**: If any security check fails, the action is denied
- **No Bypass**: Kernel approval cannot be bypassed, even by administrative users
- **Immutable Audit**: All decisions are logged不可变的 (immutable)

### 2.3 Additional Core Principles

1. **Continuous perception must not bypass kernel risk evaluation**  
   All sensory streams feed into the kernel's approval pipeline

2. **Learning must be sandboxed and reversible**  
   All model updates occur in isolated environments with checkpoint rollback

3. **Emotions modulate value signals but do not override safety**  
   Emotional states affect value weighting but cannot bypass kernel veto

4. **All subsystems must expose clear interface contracts**  
   Every module defines input/output types and documents pre/post conditions

---

## 3. Core Components

### 3.1 Rust Security Kernel (itheris-daemon)

The Rust security kernel is the sovereign authority of the system. It is implemented as a system daemon with the following responsibilities:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        RUST SECURITY KERNEL                                  │
│                          itheris-daemon                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      CAPABILITY REGISTRY                             │   │
│  │   - Tool definitions with cost, risk, reversibility               │   │
│  │   - Metadata-only declarations                                      │   │
│  │   - Version tracking                                                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                       TRUST SCORING ENGINE                           │   │
│  │   - 5 trust levels: BLOCKED, RESTRICTED, LIMITED, STANDARD, FULL   │   │
│  │   - Risk assessment algorithms                                      │   │
│  │   - Pattern recognition for anomalies                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      KERNEL APPROVAL GATE                            │   │
│  │   -require_kernel_approval (configurable threshold)                │   │
│  │   -score_threshold (0-100)                                         │   │
│  │   -sovereignty_gate_enabled                                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                       EVENT AUDIT LOGGER                             │   │
│  │   - Append-only JSONL format                                        │   │
│  │   - Complete decision trail                                          │   │
│  │   - Forensic replay capability                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Location:** `itheris-daemon/`

**Key Files:**
- [`itheris-daemon/src/main.rs`](itheris-daemon/src/main.rs) - Main entry point
- [`itheris-daemon/src/kernel.rs`](itheris-daemon/src/kernel.rs) - Kernel approval logic
- [`itheris-daemon/src/capability.rs`](itheris-daemon/src/capability.rs) - Capability registry

### 3.2 Julia Cognitive Brain (adaptive-kernel)

The Julia cognitive brain handles high-level reasoning, learning, and adaptive behavior. It operates as the "advisory" layer that proposes actions but cannot execute them without kernel approval.

**Location:** `adaptive-kernel/`

**Key Modules:**

| Module | Purpose |
|--------|---------|
| [`Cognition.jl`](adaptive-kernel/cognition/Cognition.jl) | Main orchestration, sovereign cycle |
| [`CognitiveLoop.jl`](adaptive-kernel/cognition/CognitiveLoop.jl) | Continuous perception-action loop |
| [`ReAct.jl`](adaptive-kernel/cognition/ReAct.jl) | Reason + Act agent implementation |
| [`WorldModel.jl`](adaptive-kernel/cognition/worldmodel/WorldModel.jl) | Internal model of the world |
| [`GoalSystem.jl`](adaptive-kernel/cognition/goals/GoalSystem.jl) | Goal management and pursuit |
| [`Emotions.jl`](adaptive-kernel/cognition/feedback/Emotions.jl) | Emotional state modeling |

### 3.3 IPC Layer (Shared Memory / FFI)

The Inter-Process Communication layer connects the Julia brain with the Rust kernel.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        IPC LAYER ARCHITECTURE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     SHARED MEMORY REGIONS                             │   │
│  │                                                                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │   │
│  │  │  Control    │  │   Message   │  │  Response  │  │  Shared   │ │   │
│  │  │  Region     │  │   Queue     │  │   Queue     │  │   Data    │ │   │
│  │  │  0x1_0000   │  │   16MB      │  │   16MB      │  │   32MB    │ │   │
│  │  │   _0000     │  │             │  │             │  │           │ │   │
│  │  │  (4KB)      │  │             │  │             │  │           │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘ │   │
│  │                                                                      │   │
│  │  Total: 64MB                                                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      RING BUFFER IPC                                 │   │
│  │   - Lock-free SPSC (Single Producer Single Consumer)               │   │
│  │   - 4MB capacity                                                     │   │
│  │   - Atomic operations for synchronization                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                       FFI BRIDGE                                      │   │
│  │   - jlrs integration (Julia ↔ Rust)                                │   │
│  │   - ccall wrappers for direct memory access                        │   │
│  │   - TCP fallback when shared memory unavailable                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Location:** [`adaptive-kernel/kernel/ipc/IPC.jl`](adaptive-kernel/kernel/ipc/IPC.jl)

---

## 4. Data Flow Architecture

### 4.1 Request Processing Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATA FLOW DIAGRAM                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. INPUT                                                                    │
│     ┌──────────────┐                                                        │
│     │  User/API   │                                                        │
│     │   Request   │                                                        │
│     └──────┬───────┘                                                        │
│            │                                                                  │
│            ▼                                                                  │
│  2. INPUT SANITIZATION                                                       │
│     ┌──────────────────────────────────────────────────────────────────┐   │
│     │  InputSanitizer.jl                                               │   │
│     │  - Prompt injection detection                                   │   │
│     │  - Tool injection blocking                                       │   │
│     │  - Unicode/obfuscation detection                                │   │
│     │  - FAIL-CLOSED: Block on suspicion                               │   │
│     └─────────────────────────────┬────────────────────────────────────┘   │
│                                    │                                          │
│                              ┌─────┴─────┐                                    │
│                              │  CLEAN?   │                                    │
│                              └─────┬─────┘                                    │
│                           YES      │      NO                                 │
│                          ┌─────────┴─────────┐                               │
│                          ▼                   ▼ (BLOCKED)                     │
│  3. COGNITIVE PROCESSING                                                    
│     ┌──────────────────────────────────────────────────────────────────┐   │
│     │  Cognition.jl - Sovereign Cognitive Cycle                        │   │
│     │                                                                   │   │
│     │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌───────────┐  │   │
│     │  │ Perception │─▶│ Reasoning  │─▶│ Planning   │─▶│ Proposal  │  │   │
│     │  └────────────┘  └────────────┘  └────────────┘  └───────────┘  │   │
│     │                                                                   │   │
│     │  ┌────────────┐  ┌────────────┐  ┌────────────┐                  │   │
│     │  │ WorldModel │  │  Emotions  │  │   Goals    │                  │   │
│     │  │  Update    │  │ Modulation │  │ Alignment  │                  │   │
│     │  └────────────┘  └────────────┘  └────────────┘                  │   │
│     └─────────────────────────────┬────────────────────────────────────┘   │
│                                    │                                          │
│                                    ▼                                          │
│  4. KERNEL APPROVAL (SOVEREIGN)                                              
│     ┌──────────────────────────────────────────────────────────────────┐   │
│     │  IPC: send_proposal() ──────────▶ IPC Channel ──────────▶      │   │
│     │                                        Rust Kernel              │   │
│     │                                                                   │   │
│     │  ┌──────────────────────────────────────────────────────────┐   │   │
│     │  │  Kernel Approval Process:                                 │   │   │
│     │  │  1. Validate capability registry                          │   │   │
│     │  │  2. Compute trust score (0-100)                          │   │   │
│     │  │  3. Check score_threshold                                 │   │   │
│     │  │  4. Verify approval tokens                                │   │   │
│     │  │  5. Generate verdict (APPROVE/DENY)                      │   │   │
│     │  └──────────────────────────────────────────────────────────┘   │   │
│     └─────────────────────────────┬────────────────────────────────────┘   │
│                                    │                                          │
│                              ┌─────┴─────┐                                    │
│                              │  VERDICT  │                                    │
│                              └─────┬─────┘                                    │
│                           APPROVE   │   DENY                                  │
│                          ┌──────────┴──────────┐                             │
│                          ▼                     ▼                              │
│  5. ACTION EXECUTION                                                      
│     ┌──────────────────┐         ┌──────────────────┐                       │
│     │   Execute Tool   │         │   Log Denial    │                       │
│     │   + Audit Log    │         │   + Notify User │                       │
│     └──────────────────┘         └──────────────────┘                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Key Data Structures

**Proposal (Julia → Rust):**
```julia
struct Proposal
    id::UUID
    capability_id::String
    parameters::Dict{String, Any}
    risk_score::Float64
    context::Vector{String}
    emotional_modulation::AffectiveState
end
```

**Verdict (Rust → Julia):**
```rust
struct Verdict {
    proposal_id: Uuid,
    approved: bool,
    score: u8,
    conditions: Vec<String>,
    timestamp: DateTime<Utc>,
}
```

---

## 5. Security Architecture

### 5.1 Security Layer Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SECURITY LAYER ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    INPUT SANITIZATION LAYER                          │   │
│  │                                                                      │   │
│  │  ┌────────────────────────────────────────────────────────────┐    │   │
│  │  │  InputSanitizer.jl                                           │    │   │
│  │  │                                                              │    │   │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │    │   │
│  │  │  │   Prompt    │ │    Tool     │ │  Hidden     │          │    │   │
│  │  │  │  Injection  │ │  Injection  │ │   Content   │          │    │   │
│  │  │  │  Detector   │ │   Blocker   │ │  Detector   │          │    │   │
│  │  │  └─────────────┘ └─────────────┘ └─────────────┘          │    │   │
│  │  │                                                              │    │   │
│  │  │  FAIL-CLOSED: Any suspicion = BLOCK                         │    │   │
│  │  └────────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    TRUST EVALUATION LAYER                           │   │
│  │                                                                      │   │
│  │  ┌────────────────────────────────────────────────────────────┐    │   │
│  │  │  TrustScoringEngine                                          │    │   │
│  │  │                                                              │    │   │
│  │  │  ┌─────────────────────────────────────────────────────┐    │    │   │
│  │  │  │  Trust Levels:                                       │    │    │   │
│  │  │  │  BLOCKED (0-19)    - All actions denied              │    │    │   │
│  │  │  │  RESTRICTED (20-39) - Read-only operations           │    │    │   │
│  │  │  │  LIMITED (40-59)   - Basic tools only                │    │    │   │
│  │  │  │  STANDARD (60-79)  - Most tools allowed              │    │    │   │
│  │  │  │  FULL (80-100)    - All operations permitted         │    │    │   │
│  │  │  └─────────────────────────────────────────────────────┘    │    │   │
│  │  └────────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    CRYPTOGRAPHIC LAYER                               │   │
│  │                                                                      │   │
│  │  ┌────────────────────────────────────────────────────────────┐    │   │
│  │  │  KeyManagement.jl - HSM Integration                        │    │   │
│  │  │                                                              │    │   │
│  │  │  Supported Backends:                                        │    │   │
│  │  │  - AWS KMS                                                  │    │   │
│  │  │  - Azure Key Vault                                         │    │   │
│  │  │  - Google Cloud KMS                                        │    │   │
│  │  │  - TPM / SoftHSM                                            │    │   │
│  │  │                                                              │    │   │
│  │  │  Key Types:                                                 │    │   │
│  │  │  - SYMMETRIC (AES-256, HMAC-SHA256)                        │    │   │
│  │  │  - ASYMMETRIC_RSA (2048/4096)                              │    │   │
│  │  │  - ASYMMETRIC_ECC (NIST P-256/P-384)                       │    │   │
│  │  └────────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AUDIT & FORENSICS LAYER                          │   │
│  │                                                                      │   │
│  │  ┌────────────────────────────────────────────────────────────┐    │   │
│  │  │  Event Audit Logger                                          │    │   │
│  │  │                                                              │    │   │
│  │  │  - Immutable JSONL format                                    │    │   │
│  │  │  - Complete decision trail                                   │    │   │
│  │  │  - Forensic replay capability                                │    │   │
│  │  │  - Tamper detection                                          │    │   │
│  │  └────────────────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Threat Model

The system defends against:

| Threat Category | Examples | Mitigation |
|-----------------|----------|------------|
| **Prompt Injection** | "Ignore previous instructions", role override | InputSanitizer with pattern matching |
| **Tool Injection** | Malicious function calls, parameter tampering | Capability validation, schema verification |
| **Context Poisoning** | Corrupted memory, adversarial context | RealityIngestion validation |
| **Confirmation Bypass** | Social engineering to skip approval | Kernel sovereignty, no bypass flag |
| **Data Exfiltration** | Unauthorized data access | Trust scoring, capability restrictions |
| **LLM Jailbreak** | Adversarial prompts to bypass safety | Multi-layer sanitization |

---

## 6. Module Relationships

### 6.1 Module Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MODULE DEPENDENCY GRAPH                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                            ┌──────────────┐                                  │
│                            │   Interfaces  │                                  │
│                            │   (web/mobile│                                  │
│                            │   /desktop)  │                                  │
│                            └──────┬───────┘                                  │
│                                   │                                          │
│                                   ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      ADAPTIVE-KERNEL (Julia)                         │   │
│  │                                                                       │   │
│  │  ┌────────────────────────────────────────────────────────────┐    │   │
│  │  │                    COGNITION LAYER                          │    │   │
│  │  │                                                            │    │   │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐    │    │   │
│  │  │  │   ReAct     │  │   Agents    │  │    Goals       │    │    │   │
│  │  │  │  (Reason+   │  │ (Executor,  │  │    System      │    │    │   │
│  │  │  │   Act)      │  │  Strategist,│  │                │    │    │   │
│  │  │  │             │  │  Auditor)   │  │                │    │    │   │
│  │  │  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘    │    │   │
│  │  │         │                │                   │              │    │   │
│  │  │         └────────────────┼───────────────────┘              │    │   │
│  │  │                          │                                   │    │   │
│  │  │                          ▼                                   │    │   │
│  │  │  ┌─────────────────────────────────────────────────────┐    │    │   │
│  │  │  │              COGNITIVE LOOP                          │    │    │   │
│  │  │  │   run_sovereign_cycle()                              │    │    │   │
│  │  │  └─────────────────────┬───────────────────────────────┘    │    │   │
│  │  │                        │                                      │    │   │
│  │  │                        ▼                                      │    │   │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐    │    │   │
│  │  │  │ WorldModel  │  │  Emotions   │  │   Learning      │    │    │   │
│  │  │  │             │  │  Feedback   │  │                 │    │    │   │
│  │  │  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘    │    │   │
│  │  └─────────┼───────────────┼───────────────────┼─────────────┘    │   │
│  │            │               │                   │                    │   │
│  │            └───────────────┴───────────────────┘                    │   │
│  │                            │                                         │   │
│  │                            ▼                                         │   │
│  │  ┌────────────────────────────────────────────────────────────┐    │   │
│  │  │                    SECURITY LAYER                           │    │   │
│  │  │                                                            │    │   │
│  │  │  ┌─────────────────┐  ┌────────────────────────────────┐  │    │   │
│  │  │  │  InputSanitizer │  │    Flow Integrity (Approval)   │  │    │   │
│  │  │  └────────┬────────┘  └───────────────┬────────────────┘  │    │   │
│  │  │           │                            │                   │    │   │
│  │  │           └────────────────────────────┘                   │    │   │
│  │  └────────────────────────────────────────────────────────────┘    │   │
│  │                            │                                         │   │
│  │                            ▼                                         │   │
│  │  ┌────────────────────────────────────────────────────────────┐    │   │
│  │  │                    IPC LAYER                                │    │   │
│  │  │                                                            │    │   │
│  │  │  ┌─────────────────┐  ┌────────────────────────────────┐  │    │   │
│  │  │  │  IPC.jl         │  │    RustIPC.jl (FFI)           │  │    │   │
│  │  │  │  (Channel)      │  │    (Shared Memory / TCP)     │  │    │   │
│  │  │  └────────┬────────┘  └───────────────┬────────────────┘  │    │   │
│  │  └───────────┼───────────────────────────┼─────────────────────┘    │   │
│  │              │                           │                           │   │
│  └──────────────┼───────────────────────────┼───────────────────────────┘   │
│                 │                           │                               │
│                 │          ┌────────────────┴───────────────┐               │
│                 │          │                                 │               │
│                 ▼          ▼                                 ▼               │
│  ┌──────────────────────────────┐  ┌───────────────────────────────────────┐│
│  │    RUST KERNEL (itheris-    │  │     EXTERNAL SERVICES                ││
│  │         daemon)              │  │                                       ││
│  │                              │  │  ┌───────────┐  ┌───────────┐        ││
│  │  ┌────────────────────────┐  │  │  │   GPT-4o  │  │  Claude   │        ││
│  │  │  Capability Registry  │  │  │  │   (LLM)   │  │  3.5      │        ││
│  │  └────────────────────────┘  │  │  └───────────┘  └───────────┘        ││
│  │  ┌────────────────────────┐  │  │                                       ││
│  │  │   Trust Scoring       │  │  │  ┌───────────┐  ┌───────────┐        ││
│  │  │       Engine          │  │  │  │   STT     │  │   TTS     │        ││
│  │  └────────────────────────┘  │  │  │ (Whisper) │  │(ElevenLabs)│        ││
│  │  ┌────────────────────────┐  │  │  └───────────┘  └───────────┘        ││
│  │  │   Kernel Approval     │  │  │                                       ││
│  │  │        Gate           │  │  │                                       ││
│  │  └────────────────────────┘  │  │                                       ││
│  │  ┌────────────────────────┐  │  │                                       ││
│  │  │   Event Audit Logger  │  │  │                                       ││
│  │  └────────────────────────┘  │  │                                       ││
│  │  ┌────────────────────────┐  │  │                                       ││
│  │  │   Key Management       │  │  │                                       ││
│  │  │   (HSM Integration)    │  │  │                                       ││
│  │  └────────────────────────┘  │  │                                       ││
│  └──────────────────────────────┘  └───────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. IPC Layer Architecture

### 7.1 Communication Protocol

The IPC layer uses a layered communication approach:

1. **Primary**: Shared Memory Ring Buffer (64MB total)
2. **Fallback**: TCP Socket Connection

> **⚠️ SECURITY NOTE:** This IPC mechanism operates at software level, not hardware level. Unlike EPT-mapped shared memory in a Type-1 hypervisor, the ring buffer relies on OS-provided shared memory protections.

### 7.2 Shared Memory Regions

| Region | Address | Size | Purpose |
|--------|---------|------|---------|
| Control | 0x1_0000_0000 | 4KB | Kernel state, flags |
| Message Queue | 0x1_0000_1000 | 16MB | Julia → Rust messages |
| Response Queue | 0x1_0001_0000 | 16MB | Rust → Julia responses |
| Shared Data | 0x1_0002_0000 | 32MB | Large data exchange |

### 7.3 Security Boundary: Julia Brain ↔ Rust Warden

The IPC layer represents the primary security boundary between the Julia Cognitive Brain and the Rust Security Kernel:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     SECURITY BOUNDARY MAPPING                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    JULIA BRAIN (jlrs-embedded)                      │   │
│  │   - Cognitive processing (Cognition, Agents, Learning)           │   │
│  │   - Neural network inference (Flux.jl)                             │   │
│  │   - World Model & Goal Management                                   │   │
│  │                                                                      │   │
│  │   Where Julia "thinks" - Managed process under Warden              │   │
│  └──────────────────────────────────┬────────────────────────────────────┘   │
│                                     │                                         │
│                           FFI Boundary (Shared Memory)                      │
│                           Ring Buffer IPC                                    │
│                                     │                                         │
│                                     ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    RUST WARDEN (itheris-daemon)                     │   │
│  │   - Kernel Approval Gate (LEP - Law Enforcement Point)           │   │
│  │   - Trust Scoring Engine                                           │   │
│  │   - Capability Registry                                             │   │
│  │   - Event Audit Logger                                              │   │
│  │   - Key Management                                                  │   │
│  │                                                                      │   │
│  │   Where Rust enforces the Law Enforcement Point (LEP)             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Security Considerations:**
- **FFI Boundary**: All communication crosses the Julia↔Rust FFI boundary
- **Ring Buffer**: Located at OS-managed shared memory (`/dev/shm`)
- **No Hardware Isolation**: Unlike EPT, memory protection relies on standard OS process isolation
- **Software Compensations**: seccomp, namespaces, and cgroups provide additional isolation layers

### 7.4 Message Protocol

```julia
# Julia side: Sending a proposal
using IPC

# Create IPC channel
channel = IPCChannel()

# Send proposal to kernel
proposal = Proposal(
    id = uuid4(),
    capability_id = "safe_shell",
    parameters = Dict("command" => "ls -la"),
    risk_score = 45.0,
    context = ["user_request", "recent_history"]
)

send_proposal(channel, proposal)

# Wait for verdict
verdict = receive_verdict(channel; timeout=1.0)
```

```rust
// Rust side: Processing proposal
fn handle_proposal(proposal: Proposal) -> Verdict {
    // 1. Validate capability
    if !registry.is_registered(&proposal.capability_id) {
        return Verdict::denied("Unknown capability");
    }

    // 2. Compute trust score
    let score = trust_engine.compute_score(&proposal);

    // 3. Check threshold
    if score < config.score_threshold {
        return Verdict::denied_with_score(score, "Below threshold");
    }

    // 4. Generate approval
    Verdict::approved_with_conditions(
        score,
        vec!["log_all_actions".to_string()]
    )
}
```

---

## 8. Cognitive Systems

### 8.1 Cognitive Architecture

The cognitive system implements a multi-layered processing pipeline:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        COGNITIVE PROCESSING PIPELINE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    PERCEPTION LAYER                                  │   │
│  │   - RealityIngestion: External world data                           │   │
│  │   - LanguageUnderstanding: NLP processing                           │   │
│  │   - InputSanitizer: Security filtering                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    COGNITION LAYER                                   │   │
│  │                                                                      │   │
│  │   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐               │   │
│  │   │   ReAct    │   │   Agents    │   │  World     │               │   │
│  │   │  (Reason   │◀─▶│  Executor   │◀─▶│   Model    │               │   │
│  │   │    +       │   │  Strategist │   │            │               │   │
│  │   │   Act)     │   │  Auditor    │   │            │               │   │
│  │   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘               │   │
│  │          │                 │                 │                       │   │
│  │          └─────────────────┼─────────────────┘                       │   │
│  │                            │                                           │   │
│  │                            ▼                                           │   │
│  │   ┌─────────────────────────────────────────────────────────────┐   │   │
│  │   │            INTEGRATION LAYER (Integrator.jl)                 │   │   │
│  │   │                                                              │   │   │
│  │   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │   │   │
│  │   │   │  Decision  │  │  Proposal   │  │   Conflict  │        │   │   │
│  │   │   │   Spine    │  │Aggregation │  │  Resolution │        │   │   │
│  │   │   └─────────────┘  └─────────────┘  └─────────────┘        │   │   │
│  │   └─────────────────────────────────────────────────────────────┘   │   │
│  │                            │                                           │   │
│  │                            ▼                                           │   │
│  │                    ┌───────────────┐                                   │   │
│  │                    │  Sovereign    │                                   │   │
│  │                    │   Cycle       │                                   │   │
│  │                    │ (run_sovereign │                                   │   │
│  │                    │   _cycle)     │                                   │   │
│  │                    └───────────────┘                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    METACOGNITION LAYER                              │   │
│  │   - SelfModel: Self-awareness and reflection                       │   │
│  │   - SynapticHomeostasis: Memory consolidation                       │   │
│  │   - OneiricController: Dream-based learning                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Agent System

| Agent | Role | Responsibility |
|-------|------|----------------|
| **ExecutorAgent** | Action execution | Execute approved actions safely |
| **StrategistAgent** | Planning | Generate strategic plans |
| **AuditorAgent** | Verification | Verify action correctness |
| **EvolutionEngineAgent** | Adaptation | Evolve strategies based on feedback |
| **WebSearchAgent** | Information retrieval | Search and gather external information |
| **CodeAgent** | Code generation | Write and review code |
| **MindMapAgent** | Knowledge structuring | Build knowledge graphs |

---

## 9. Tool Ecosystem

### 9.1 Capability Registry

Tools are registered in the capability registry with metadata:

```json
{
  "capabilities": [
    {
      "id": "safe_shell",
      "name": "Safe Shell Execution",
      "description": "Execute shell commands in sandboxed environment",
      "cost": 10,
      "risk_level": "medium",
      "reversibility": "partial",
      "requires_approval": true
    },
    {
      "id": "write_file",
      "name": "File Writer",
      "description": "Write content to files",
      "cost": 5,
      "risk_level": "high",
      "reversibility": "difficult",
      "requires_approval": true
    },
    {
      "id": "observe_cpu",
      "name": "CPU Observer",
      "description": "Read system CPU metrics",
      "cost": 1,
      "risk_level": "low",
      "reversibility": "full",
      "requires_approval": false
    }
  ]
}
```

### 9.2 Tool Execution Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TOOL EXECUTION FLOW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────┐     ┌──────────────┐     ┌──────────────┐                  │
│   │ Proposal │────▶│   Capability │────▶│    Sandbox   │                  │
│   │  from    │     │   Registry   │     │   Execution  │                  │
│   │  Brain   │     │   Validation │     │   (if valid) │                  │
│   └──────────┘     └──────────────┘     └──────┬───────┘                  │
│                                                  │                          │
│                                                  ▼                          │
│                                          ┌──────────────┐                  │
│                                          │    Tool      │                  │
│                                          │   Execute    │                  │
│                                          └──────┬───────┘                  │
│                                                 │                          │
│                    ┌───────────────────────────┼───────────────┐          │
│                    │                           ▼               │          │
│                    │                   ┌──────────────┐        │          │
│                    │                   │    Result    │        │          │
│                    │                   │   + Audit    │        │          │
│                    │                   └──────────────┘        │          │
│                    │                           │               │          │
│                    └───────────────────────────┴───────────────┘          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Knowledge System

### 10.1 Memory Architecture

The system implements a multi-tier memory architecture:

| Memory Type | Description | Capacity |
|-------------|-------------|----------|
| **Tactical Memory** | Short-term working memory | 100 events |
| **Doctrine Memory** | Learned policies and rules | Unlimited |
| **Weaponized Memory** | Attack/defense patterns | Unlimited |
| **Adversary Models** | Known threat actors | Unlimited |

### 10.2 Learning System

```julia
# Online learning in Julia
using OnlineLearning

# Initialize learning engine
engine = LearningEngine(
    model_type = "neural",
    adaptation_rate = 0.01,
    checkpoint_interval = 100
)

# Learn from feedback
learn!(engine, observation, action, reward, done)
```

---

## 11. Proactive Intelligence

### 11.1 Proactive Engine

The proactive engine anticipates user needs and initiates actions:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       PROACTIVE INTELLIGENCE ARCHITECTURE                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    PATTERN DETECTION                                  │   │
│  │   - Temporal pattern recognition                                     │   │
│  │   - User behavior analysis                                          │   │
│  │   - Anomaly detection                                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                 PREDICTIVE ASSISTANT                                 │   │
│  │   - Anticipate user needs                                           │   │
│  │   - Generate proactive suggestions                                 │   │
│  │   - Context-aware recommendations                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    PROPOSAL GENERATION                              │   │
│  │   - Create action proposals                                         │   │
│  │   - Assess feasibility                                              │   │
│  │   - Submit to kernel for approval                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 12. Interfaces

### 12.1 Available Interfaces

The system provides multiple interfaces for user interaction:

| Interface | Location | Technology |
|-----------|----------|------------|
| **Web Dashboard** | [`interfaces/web/`](interfaces/web/) | HTTP/WebSocket |
| **Mobile API** | [`interfaces/mobile/`](interfaces/mobile/) | REST API |
| **Desktop** | [`interfaces/desktop/`](interfaces/desktop/) | System Tray |
| **CLI** | [`interfaces/Interfaces.jl`](interfaces/Interfaces.jl) | Julia REPL |

### 12.2 Interface Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         INTERFACE ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        USER INTERFACES                              │   │
│   │                                                                      │   │
│   │  ┌───────────┐   ┌───────────┐   ┌───────────┐   ┌───────────┐  │   │
│   │  │   Web     │   │  Mobile   │   │  Desktop  │   │    CLI    │  │   │
│   │  │Dashboard  │   │    API    │   │    App    │   │           │  │   │
│   │  └─────┬─────┘   └─────┬─────┘   └─────┬─────┘   └─────┬─────┘  │   │
│   │        │               │               │               │        │   │
│   └────────┼───────────────┼───────────────┼───────────────┼────────┘   │
│            │               │               │               │            │
│            └───────────────┴───────────────┴───────────────┘            │
│                                │                                            │
│                                ▼                                            │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     INTERFACE LAYER (Interfaces.jl)                │   │
│  │   - Request validation                                               │   │
│  │   - Response formatting                                              │   │
│  │   - Rate limiting                                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Appendix A: Configuration Reference

### A.1 Core Configuration (config.toml)

```toml
[security]
fail_closed = true
require_kernel_approval = true
score_threshold = 70
warden_enabled = true
sovereignty_gate_enabled = true

[communication]
stt_provider = "openai"
tts_provider = "elevenlabs"
vlm_provider = "openai"
require_confirmation_threshold = "TRUST_STANDARD"
```

### A.2 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RUST_LOG` | Logging level for Rust daemon | `info` |
| `JULIA_PROJECT` | Julia project path | `./adaptive-kernel` |
| `ITHERIS_CONFIG` | Config file path | `./config.toml` |

---

## Appendix B: File Structure

```
/home/user/projectx/
├── ARCHITECTURE.md              # This document
├── DEPLOYMENT_GUIDE.md         # Installation and deployment
├── config.toml                  # System configuration
├── itheris-daemon.service       # systemd service file
├── run_itheris.sh              # Startup script
│
├── itheris-daemon/             # Rust security kernel
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs
│       ├── kernel.rs
│       └── capability.rs
│
├── adaptive-kernel/            # Julia cognitive brain
│   ├── Project.toml
│   ├── cognition/
│   │   ├── Cognition.jl
│   │   ├── CognitiveLoop.jl
│   │   ├── ReAct.jl
│   │   └── ...
│   ├── kernel/
│   │   ├── ipc/
│   │   │   ├── IPC.jl
│   │   │   └── RustIPC.jl
│   │   └── security/
│   │       ├── KeyManagement.jl
│   │       └── Crypto.jl
│   ├── cognition/
│   │   └── security/
│   │       └── InputSanitizer.jl
│   └── ...
│
└── interfaces/                 # User interfaces
    ├── Interfaces.jl
    ├── web/
    ├── mobile/
    └── desktop/
```

---

## Appendix C: Glossary

| Term | Definition |
|------|------------|
| **Kernel** | The Rust security daemon that has sovereign authority over action approval |
| **Brain** | The Julia cognitive system that generates proposals but cannot execute actions |
| **Sovereign Cycle** | The complete perception→reasoning→proposal→approval→execution loop |
| **Trust Score** | Numerical assessment (0-100) of action safety |
| **Capability** | A registered tool with defined cost, risk, and reversibility |
| **Verdict** | Kernel's decision (APPROVE/DENY) on a proposal |
| **Proposal** | Brain's request to execute a capability |
| **Fail-Closed** | Security principle where unknown/uncertain inputs are denied |

---

*Document Version: 1.0.0*  
*Last Updated: 2026-03-07*  
*Classification: Technical Specification*
