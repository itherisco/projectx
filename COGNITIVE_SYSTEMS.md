# Cognitive Systems Documentation

**Version:** 1.0.0  
**Last Updated:** 2026-03-12  

> **⚠️ IMPORTANT:** For the authoritative and current feature maturity status, always refer to [STATUS.md](STATUS.md).

---

## Table of Contents

1. [Cognitive Architecture Overview](#1-cognitive-architecture-overview)
2. [Decision Spine](#2-decision-spine)
3. [Multi-Agent System](#3-multi-agent-system)
4. [Goal System](#4-goal-system)
5. [World Model](#5-world-model)
6. [Memory Systems](#6-memory-systems)
7. [Emotional Architecture](#7-emotional-architecture)
8. [Sleep and Consolidation](#8-sleep-and-consolidation)

---

## 1. Cognitive Architecture Overview

### System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              COGNITIVE ARCHITECTURE                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐   │
│  │   SENSORY    │────▶│   ATTENTION  │────▶│ WORLD MODEL │────▶│ GOAL SYSTEM  │   │
│  │   BUFFER     │     │   & SALIENCE │     │              │     │              │   │
│  └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘   │
│         │                    │                    │                    │            │
│         ▼                    ▼                    ▼                    ▼            │
│  ┌─────────────────────────────────────────────────────────────────────────────┐    │
│  │                          ITHERIS CORE (Neural Brain)                         │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │    │
│  │  │  VALUE_NET  │  │  POLICY_NET │  │ PREDICTOR   │  │   ATTENTION_NET     │ │    │
│  │  │  (Critic)   │  │   (Actor)   │  │  (World)    │  │   (Salience)        │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────┘ │    │
│  │         │                │                │                  │              │    │
│  │         ▼                ▼                ▼                  ▼              │    │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐ │    │
│  │  │                    EXPERIENCE REPLAY BUFFER                              │ │    │
│  │  │            (Sandboxed, Reversible Learning Environment)                 │ │    │
│  │  └──────────────────────────────────────────────────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
│                                      │                                               │
│                                      ▼                                               │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                          │
│  │ EMOTIONAL    │────▶│   ACTION    │────▶│   KERNEL     │                          │
│  │ ARCHITECTURE │     │  PROPOSAL   │     │  APPROVAL    │                          │
│  │              │     │             │     │   (SOVEREIGN)│                          │
│  └──────────────┘     └──────────────┘     └──────────────┘                          │
│         │                                       │                                    │
│         ▼                                       ▼                                    │
│  ┌──────────────┐                      ┌──────────────┐                               │
│  │ METACOGNITION│◀─────────────────────│  EXECUTION   │                               │
│  │ / SELF-MODEL │                      │    & FEEDBACK│                               │
│  └──────────────┘                      └──────────────┘                               │
│         │                                       │                                     │
│         ▼                                       ▼                                     │
│  ┌──────────────┐                      ┌──────────────┐                               │
│  │    SLEEP     │◀─────────────────────│  REFLECTION  │                               │
│  │ CONSOLIDATION│                      │  & LEARNING  │                               │
│  └──────────────┘                      └──────────────┘                               │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### Cognitive Cycle Data Flow

| Stage | Input | Processing | Output |
|-------|-------|------------|--------|
| **Sensory** | Raw streams | Event-based buffering | `SensorySnapshot` |
| **Attention** | `SensorySnapshot` | Salience scoring | `AttendedPercept` |
| **World Model** | `AttendedPercept` | State prediction | `PredictedState` |
| **Goal System** | `PredictedState` | Goal activation | `ActiveGoals` |
| **Brain Inference** | Percepts + Goals + Emotions | Neural forward pass | `BrainOutput` |
| **Kernel Approval** | `BrainOutput` | Sovereignty checks | `Decision` |
| **Execution** | `Decision=APPROVED` | Capability execution | `ExecutionResult` |
| **Reflection** | `ExecutionResult` | Self-model update | `ReflectionEvent` |

---

## 2. Decision Spine

### Overview

The Decision Spine coordinates multi-agent proposals and commits to final decisions.

### Key Types

```julia
"""
    DecisionSpine - Coordinates agent proposals into decisions
"""
mutable struct DecisionSpine
    config::SpineConfig
    proposals::Vector{AgentProposal}
    committed::Union{CommittedDecision, Nothing}
end

"""
    SpineConfig - Configuration for decision spine
"""
struct SpineConfig
    require_unanimity::Bool
    conflict_threshold::Float32
    entropy_injection_enabled::Bool
    entropy_threshold::Float32
end
```

### Conflict Resolution

The spine implements sophisticated conflict resolution:

1. **Unanimous Agreement**: All agents agree → immediate approval
2. **Majority Vote**: Weighted voting based on agent confidence
3. **Conflict Detection**: Flag divergence for deliberation
4. **Entropy Injection**: When agents agree too often, inject diversity

---

## 3. Multi-Agent System

### Agent Types

| Agent | Role | Function |
|-------|------|----------|
| **Executor** | Action execution | Translates decisions into capability calls |
| **Strategist** | Long-horizon planning | Plans multi-step goal achievement |
| **Auditor** | Safety constraint enforcement | Validates safety and policy compliance |
| **Evolution** | Strategy adaptation | Evolves doctrine based on outcomes |

### Agent Proposal Structure

```julia
"""
    AgentProposal - Output from each agent
"""
struct AgentProposal
    agent_id::String
    agent_type::Symbol
    decision::String
    confidence::Float32
    reasoning::String
    weight::Float32
    evidence::Dict{String, Any}
    timestamp::DateTime
end
```

### Agent Performance Tracking

```julia
"""
    AgentPerformance - Tracks agent effectiveness over time
"""
mutable struct AgentPerformance
    agent_id::String
    agent_type::Symbol
    success_count::Int
    failure_count::Int
    current_weight::Float32
    average_confidence::Float32
end
```

---

## 4. Goal System

### Goal Structure

```julia
"""
    Goal - Immutable struct representing an objective
"""
struct Goal
    id::String
    description::String
    priority::Float32      # [0, 1]
    created_at::DateTime
    deadline::DateTime
end

"""
    GoalState - Mutable progress tracking for Goals
"""
mutable struct GoalState
    goal_id::String
    status::Symbol          # :active, :completed, :failed, :paused
    progress::Float32       # [0, 1]
    last_updated::DateTime
    iterations::Int
end
```

### Goal Lifecycle

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   CREATED   │────▶│   ACTIVE    │────▶│ COMPLETED   │     │   FAILED    │
└─────────────┘     └──────┬──────┘     └─────────────┘     └─────────────┘
                          │
                          ▼
                   ┌─────────────┐
                   │   PAUSED    │
                   └─────────────┘
```

### Goal Activation

```julia
const MIN_ACTIVATION_THRESHOLD = 0.3f0
const MAX_GOALS_ACTIVE = 5

function should_activate_goal(
    goal::Goal,
    current_goals::Vector{GoalState}
)::Bool
    # Check priority threshold
    goal.priority >= MIN_ACTIVATION_THRESHOLD || return false
    
    # Check max active goals
    length(current_goals) < MAX_GOALS_ACTIVE || return false
    
    return true
end
```

---

## 5. World Model

### Overview

The World Model provides predictive capabilities for state estimation and counterfactual reasoning.

### Key Functions

```julia
"""
    WorldModel - Predictive model of environment
"""
mutable struct WorldModel
    causal_graph::Dict{String, Vector{String}}
    state_history::Vector{Dict}
    trajectories::Vector{Trajectory}
end

"""
    predict_next_state - Predict next state given action
"""
function predict_next_state(
    model::WorldModel,
    current_state::Dict,
    action::String
)::Dict

"""
    predict_reward - Predict expected reward for action
"""
function predict_reward(
    model::WorldModel,
    state::Dict,
    action::String
)::Float32

"""
    simulate_trajectory - Simulate multi-step trajectory
"""
function simulate_trajectory(
    model::WorldModel,
    start_state::Dict,
    actions::Vector{String}
)::Trajectory
```

### Causal Graph

The world model maintains a causal graph of system relationships:

```
cpu_load ──────▶ memory_pressure ──────▶ response_time
    │                                        │
    ▼                                        ▼
disk_io ──────▶ swap_activity ──────────▶ energy_usage
```

---

## 6. Memory Systems

### Memory Types

| Memory Type | Purpose | Characteristics |
|-------------|---------|-----------------|
| **Episodic** | Event logging | Timestamped, raw |
| **Semantic** | Structured knowledge | Queryable, abstracted |
| **Tactical** | Short-term decisions | Recent, high-velocity |
| **Doctrine** | Long-term principles | Immutable, learned |

### Memory Integration

```julia
"""
    DoctrineMemory - Immutable learned principles
"""
struct DoctrineMemory
    principles::Vector{String}
    policies::Dict{Symbol, Any}
end

"""
    TacticalMemory - Recent decision context
"""
mutable struct TacticalMemory
    capacity::Int
    entries::Vector{Dict}
end
```

---

## 7. Emotional Architecture

### Emotional State Model

```julia
"""
    AffectiveState - Emotional state representation
"""
struct AffectiveState
    valence::Float32        # Positive/Negative [-1, 1]
    arousal::Float32        # Activation level [0, 1]
    fear::Float32          # Fear response [0, 1]
    curiosity::Float32     # Exploration drive [0, 1]
    frustration::Float32   # Frustration level [0, 1]
end
```

### Emotional Modulation

> **Important**: Emotions modulate value signals but do not override safety.

```julia
function compute_emotional_modulation(
    emotion::AffectiveState
)::Vector{Float32}
    return Float32[
        emotion.valence,
        emotion.arousal,
        emotion.fear,
        emotion.curiosity,
        emotion.frustration
    ]
end
```

### Emotional Impact on Decision Making

| Emotion | Effect on Brain | Safety Override |
|---------|-----------------|-----------------|
| High Fear | Risk aversion | None (kernel vetoes) |
| High Curiosity | Exploration drive | None |
| High Frustration | Impulsiveness | Kernel approval required |
| Negative Valence | Negative rewards | Kernel unchanged |

---

## 8. Sleep and Consolidation

### Sleep Cycle Functions

```julia
"""
    sleep_cycle! - Consolidate memories during idle periods
"""
function sleep_cycle!(
    engine::CognitiveEngine
)::Dict
    # Step 1: Consolidate episodic → semantic memory
    consolidate_memory!(engine.tactical, engine.doctrine)
    
    # Step 2: Dream/counterfactual exploration
    insights = dream!(engine.world_model)
    
    # Step 3: Update doctrine based on insights
    update_doctrine!(engine.doctrine, insights)
    
    return Dict("insights" => insights)
end

"""
    consolidate_memory! - Transfer episodic to semantic
"""
function consolidate_memory!(
    tactical::TacticalMemory,
    doctrine::DoctrineMemory
)::Vector{String}
    # Extract patterns from recent decisions
    patterns = extract_patterns(tactical)
    
    # Add to doctrine if significant
    for pattern in patterns
        if pattern.significance > 0.8
            push!(doctrine.principles, pattern.principle)
        end
    end
    
    return patterns
end
```

### Dream/Imagination

The system performs counterfactual exploration during sleep cycles:

```julia
"""
    dream! - Counterfactual exploration
"""
function dream!(
    model::WorldModel
)::Vector{String}
    insights = String[]
    
    # Generate counterfactual scenarios
    for _ in 1:10
        # Randomly perturb initial state
        perturbed = perturb_state(model.state_history[end])
        
        # Simulate alternative trajectory
        trajectory = simulate_trajectory(model, perturbed, ["", "", ""])
        
        # Extract insight if novel
        if is_novel(trajectory, model.trajectories)
            push!(insights, summarize_insight(trajectory))
        end
    end
    
    return insights
end
```

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [`adaptive-kernel/cognition/Cognition.jl`](adaptive-kernel/cognition/Cognition.jl) | Main cognition module |
| [`adaptive-kernel/cognition/goals/GoalSystem.jl`](adaptive-kernel/cognition/goals/GoalSystem.jl) | Goal management |
| [`adaptive-kernel/cognition/worldmodel/WorldModel.jl`](adaptive-kernel/cognition/worldmodel/WorldModel.jl) | World modeling |
| [`adaptive-kernel/cognition/feedback/Emotions.jl`](adaptive-kernel/cognition/feedback/Emotions.jl) | Emotional system |
| [`plans/JARVIS_NEUROSYMBOLIC_ARCHITECTURE.md`](plans/JARVIS_NEUROSYMBOLIC_ARCHITECTURE.md) | Full architecture spec |

---

*Last Updated: 2026-03-12*
