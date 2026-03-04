# Design Rationale: Adaptive Cognitive Kernel

## Why Keep the Kernel Minimal?

The adaptive kernel is intentionally designed with 1790 lines: maintain world state, self metrics (confidence, energy, focus), priority-weighted goal scoring, and deterministic action selection via a simple heuristic (priority - cost * risk_penalty). This design is intentional for comprehensive functionality.

### 1. **Auditability & Governance**

A 400-line kernel is fully reviewable by a single engineer in one afternoon. Every decision path is traceable. No hidden heuristics, no learned weights, no stochastic reasoning that mysteriously produces outputs. When high-stakes actions fail, you can walk the code and pinpoint exactly why. This is essential for safety: regulators, courts, and oversight boards need to understand how an agent made a decision.

### 2. **Composability**

By separating cognition (kernel) from capability (modules), we achieve plug-and-play architecture. A new capability is simply a new file with `meta()` and `execute()`. The kernel never needs to know its internals; it only reasons about metadata (cost, risk, reversibility). This means you can add, remove, or swap capabilities without touching the kernel. You can even have multiple kernel instances reasoning about different capability sets.

### 3. **Determinism & Reproducibility**

The kernel's decision logic uses no randomness—all choices flow from weights and priorities. Given identical observations and goals, it will always select the same action. This is crucial for testing, debugging, and regulatory compliance. By contrast, RL agents or neural networks produce non-deterministic, non-transparent outputs unsuitable for safety-critical domains.

### 4. **Performance & Scaling**

No ML inference, no searching vast action spaces. Kernel cycle performance varies by hardware; see benchmark results for latency data. You can run 1000s of independent kernel instances in parallel, each with its own world state and episodic memory. This scales to managing large fleets of heterogeneous robots or services.

### 5. **Domain-Agnostic Core**

The kernel itself makes no assumptions about the domain: no AI/ML terms, no specific OS concepts, no task-specific logic. It is pure goal-oriented reasoning: given priorities, evaluate state, select the best action within constraints. You can drop the same kernel into autonomous vehicles, data center management, or spacecraft control systems.

## How the Capability Registry Enables "Anything Adaptive"

The registry is the gateway to extensibility. Each capability is a metadata shard declaring:
- **What it needs** (inputs): e.g., "file_path"
- **What it produces** (outputs): e.g., "summary"
- **What it costs** (compute/energy): 0.0–1.0 scale
- **What risk it carries**: low, medium, high
- **Whether it's reversible**: true => can be undone, false => persistent change

The kernel never executes capability code; it only reasons about these shards. This creates a clean interface layer:
- Capabilities remain fully isolated; a crashy capability cannot corrupt the kernel.
- You can replace a capability implementation without rebuilding anything else.
- You can add runtime safeguards per-capability (e.g., resource limits, sandboxing).
- You can reason about global risk/reward trade-offs across diverse actions.

Example: A Jarvis system managing a data center might have 50+ capabilities (rebalance_services, scale_cluster, patch_nodes, invoke_human, etc.). The kernel weights them all using the same deterministic heuristic. If a service fails, you can swap in a new patch capability with different cost/risk, and the kernel automatically adapts its decision-making.

## Safety-by-Default Architecture

1. **Permission Checks**: High-risk actions require explicit approval. Default handler denies anything with risk > "low".
2. **Append-Only Audit Trail**: Every action, result, and state change is logged immutably. You can replay the entire history.
3. **Sandboxing**: Capabilities write to `sandbox/`; OS integration is restricted to whitelisted commands.
4. **Energy Accounting**: Self-metrics track confidence and energy; if energy depletes, the kernel can self-restrict.
5. **Reflection**: After every action, the kernel updates its model of itself (confidence ↑ on success, ↓ on failure). This enables graceful degradation.

## Integration with Real Perceptions

Future versions will ingest real OS metrics (process trees, network sockets, file integrity) via a perception capability. The kernel's reasoning remains unchanged; only the observations feed different data into the same heuristic.

## Path to Production

See MILESTONES.md for an 8-week roadmap: from simulation → safe operator → productizable agent. Each milestone adds real telemetry, threat modeling, or scalability while preserving the kernel's core interface and safety constraints.

---

**Core insight**: A 400-line kernel is not a limitation; it is a guarantee of intelligibility, safety, and adaptability.
