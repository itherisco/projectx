# Phase 2 Migration Guide: Sovereign Cognition

## Table of Contents

1. [Overview](#overview)
2. [Architecture Changes](#architecture-changes)
   - [Phase 1 Architecture](#phase-1-architecture)
   - [Phase 2 Architecture](#phase-2-architecture)
3. [Migration Steps](#migration-steps)
   - [Step 1: Dependency Updates](#step-1-dependency-updates)
   - [Step 2: Integrate Decision Spine](#step-2-integrate-decision-spine)
   - [Step 3: Configure Agent Weights](#step-3-configure-agent-weights)
   - [Step 4: Memory System Integration](#step-4-memory-system-integration)
   - [Step 5: Power Metric Setup](#step-5-power-metric-setup)
4. [Configuration Options](#configuration-options)
5. [Testing](#testing)

---

## Overview

This document describes the migration from Phase 1 (reactive assistant) to Phase 2 (self-directing, multi-agent intelligence engine).

## Architecture Changes

### Phase 1 Architecture
```
User Input → ITHERIS Brain → Action Proposal → Kernel → Execution
```

### Phase 2 Architecture
```
Perception → [Executor | Strategist | Auditor | Evolution] 
              → Conflict Resolution → Decision Spine 
              → Kernel Approval → Execution → Feedback → Memory
```

## Migration Steps

### Step 1: Dependency Updates

The new modules require no additional external dependencies beyond the existing Julia environment.

### Step 2: Integrate Decision Spine

Replace direct brain-to-kernel calls with the Decision Spine.

### Step 3: Configure Agent Weights

Initialize agent performance tracking for pain/reward system.

### Step 4: Memory System Integration

Three-tier memory must be initialized: Doctrine, Tactical, Adversary.

### Step 5: Power Metric Setup

Initialize weekly power tracking for optionality measurement.

## Configuration Options

| Parameter | Default | Description |
|-----------|--------|-------------|
| require_unanimity | false | Require all agents to agree |
| conflict_threshold | 0.3 | Threshold for conflict resolution |
| entropy_injection_enabled | true | Inject entropy if agents agree too often |
| kernel_approval_required | true | Always require kernel approval |

## Testing

Run the migration test suite: julia test_sovereign_cognition.jl
