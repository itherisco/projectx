# AI Coding Agent Prompt: ITHERIS Full OS Interface Implementation

*This prompt is designed for an AI coding agent (like Cursor, GitHub Copilot, or a specialized agentic LLM) to build the portable "Management Console" OS layer.*

---

## Context

Act as a Senior Systems Architect specializing in **Rust, WebAssembly (WASM), and Neuro-Symbolic AI**. You are building the "Full OS Interface" for **ProjectX Jarvis (ITHERIS)**, a system that runs on a bare-metal Type-1 hypervisor (the Warden). The interface is a management console that must work across Terminal (TUI), Laptop (Tauri), and VM (Browser).

## Core Philosophy

- **"Brain is advisory, Kernel is sovereign."** The UI must visualize the **Decision Spine** where the Julia Brain proposes "Thoughts" and the Rust Warden approves or vetoes them.
- **Metabolic Grounding:** The system has a **136.1 Hz metabolic tick loop** and a finite **Viability Budget**. The UI must reflect this "Artificial Hunger".

## Technical Requirements

### 1. Framework

Use **Leptos (Rust/WASM)** for the frontend. Implement **fine-grained reactivity using Signals** to avoid Virtual DOM overhead, ensuring real-time telemetry from the metabolic tick.

### 2. Communication

Implement a **gRPC-Web bridge** using `prost` and `tonic`. Data structures must use **Protobuf** for sub-millisecond serialization efficiency.

### 3. UI Design System

- **Bento Grid Layout:** Organize cognitive modules (Executor, Strategist, Auditor) into modular tiles.
- **Glassmorphism 2.0:** Use depth and vibrant gradients to distinguish between advisory and sovereign notifications.
- **Circadian OS Skin:** Dynamically shift the UI color temperature (RGBTW 1500K–6500K) based on the **Metabolic Clock**.

## Specific Feature Tasks

### The Decision Spine Tile

Create a feed of autonomous proposals. Use **"Rationale Chips"** that, when clicked, reveal the **LEP Veto Equation** ($score = priority \times (reward - risk)$) and explain why a thought was dropped (e.g., hallucination score > 0.058).

### Metabolic Energy Bar

Implement a reactive progress bar for the **Viability Budget**. If energy hits the `DEATH_ENERGY` threshold, transition the entire UI to **Containment Mode**.

### Oneiric State Indicator

Add a status icon for **"Consolidating" (Dreaming)** vs. **"Awake"**. When dreaming, show that Extended Page Tables (EPT) are set to `RO_NOEXEC`, locking physical hardware.

### Manual Unsealing Ceremony UI

Design a high-security recovery interface for **TPM 2.0 PCR register resets** if the Warden triggers a hardware lockdown.

## Project Structure

Follow the `console/` structure: `src/components/bento_grid`, `src/services/grpc.rs`, and `src/state/signals.rs`. Ensure all telemetry signals update directly without re-rendering the entire page.

## Output Requirements

Generate:

1. The foundational `Cargo.toml`
2. The gRPC service contracts in `warden.proto`
3. The reactive `MetabolicTile` component in Rust

---

## Strategic Rationale

### Performance

By specifying **Leptos Signals** and **Protobuf**, you ensure the coding agent doesn't default to slow JSON/VDOM patterns that would choke on the 136.1 Hz metabolic loop.

### Transparency

Including **Rationale Chips** and the **Veto Equation** forces the agent to implement the "explainability" layer required for user trust in autonomous systems.

### Safety

The **Containment Mode** and **TPM Unsealing** requirements ensure the UI supports the system's "Fail-Closed" security architecture.

---

## Veto Equation Reference

The LEP (Law Enforcement Point) Veto Equation:

```
score = priority × (reward - risk)
```

- If `score < threshold`, the proposal is dropped
- Hallucination score > 0.058 triggers automatic veto
- Risk assessment uses the formula from `adaptive-kernel/cognition/security/InputSanitizer.jl`

## Metabolic Thresholds

| Threshold | Value | Action |
|-----------|-------|--------|
| `ENERGY_MAX` | 1.0 | Full capacity |
| `ENERGY_FULL` | 0.90 | Full capacity |
| `ENERGY_RECOVERY` | 0.70 | Can do heavy processing |
| `ENERGY_SUSTAINED` | 0.50 | Normal operation |
| `ENERGY_LOW` | 0.30 | Recovery mode |
| `DREAMING_THRESHOLD` | 0.20 | Dreaming mode triggered |
| `ENERGY_CRITICAL` | 0.15 | Emergency mode |
| `ENERGY_DEATH` | 0.05 | System shutdown / Containment |

## Cognitive Modes

| Mode | Energy Range | UI Indicator |
|------|--------------|--------------|
| `MODE_ACTIVE` | 0.50 - 1.0 | Green - Full function |
| `MODE_IDLE` | 0.30 - 0.50 | Blue - Baseline function |
| `MODE_RECOVERY` | 0.15 - 0.30 | Yellow - Limited function |
| `MODE_CRITICAL` | 0.05 - 0.15 | Amber - Emergency mode |
| `MODE_DREAMING` | 0.20 - 0.40 | Purple - Offline consolidation |
| `MODE_DEATH` | < 0.05 | Red - System dead |
