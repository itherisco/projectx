# Consciousness Metrics Implementation Plan
## 7-Phase 8-Week Roadmap

**Created:** 2026-03-14  
**Based on:** `plans/CONSCIOUSNESS_METRICS_DESIGN.md`

---

## Phase 1: Core Infrastructure (Week 1-2)

### Goals
- Create the consciousness module directory structure
- Implement core data structures
- Set up integration hooks to existing cognitive components
- Basic unit tests

### Tasks
| # | Task | Status | Dependencies |
|---|------|--------|-------------|
| 1.1 | Create `adaptive-kernel/cognition/consciousness/` directory | ✅ Complete | None |
| 1.2 | Implement `ConsciousnessSnapshot` struct | ✅ Complete | None |
| 1.3 | Implement `ConsciousnessMetrics` mutable struct | ✅ Complete | 1.2 |
| 1.4 | Implement `ContextTracker` type | ✅ Complete | None |
| 1.5 | Add integration hooks to DecisionSpine | ✅ Complete | None |
| 1.6 | Add integration hooks to SelfModel | ✅ Complete | None |
| 1.7 | Add integration hooks to WorldModel | ✅ Complete | None |
| 1.8 | Add integration hooks to WorkingMemory | ✅ Complete | None |
| 1.9 | Create integration module | ✅ Complete | 1.3-1.8 |
| 1.10 | Write unit tests for data structures | Pending | 1.9 |

### Deliverables
- `ConsciousnessMetrics.jl` - Core module with data structures
- `ConsciousnessMetricsIntegration.jl` - Integration layer
- `Consciousness.jl` - Main module entry point

---

## Phase 2: Phi Calculations (Week 2-3)

### Goals
- Implement full Phi (Φ) calculation algorithm
- Implement Global Workspace Score (GWS)
- Implement Information Flow Entropy (IFE)
- Connect to DecisionSpine for real-time data

### Tasks
| # | Task | Status | Dependencies |
|---|------|--------|-------------|
| 2.1 | Implement `calculate_phi()` function | ✅ Complete | Phase 1 |
| 2.2 | Implement `calculate_gws()` function | ✅ Complete | Phase 1 |
| 2.3 | Implement `calculate_ife()` function | ✅ Complete | Phase 1 |
| 2.4 | Connect DecisionSpine proposal data | Pending | 2.1-2.3 |
| 2.5 | Connect conflict resolution data | Pending | 2.4 |
| 2.6 | Performance optimization for 136.1 Hz | Pending | 2.5 |
| 2.7 | Unit tests for Phi calculations | Pending | 2.6 |

### Technical Details
- **Phi Formula:** `Φ = √(I × C × S)`
  - I (information): weighted mutual information between modules
  - C (coherence): coherence of agent proposals
  - S (synergy): information gained from integration
- **Target Performance:** Calculate within 7.3ms (1/136.1 Hz)

---

## Phase 3: Context Tracking (Week 3-4)

### Goals
- Track consciousness metrics across conversation turns
- Implement Contextual Depth Index (CDI)
- Implement Temporal Consistency Score (TCS)
- Add belief history tracking with temporal decay

### Tasks
| # | Task | Status | Dependencies |
|---|------|--------|-------------|
| 3.1 | Implement `calculate_cdi()` function | ✅ Complete | Phase 1 |
| 3.2 | Implement `calculate_tcs()` function | ✅ Complete | Phase 1 |
| 3.3 | Implement temporal decay model | ✅ Complete | Phase 1 |
| 3.4 | Add belief history to ContextTracker | ✅ Complete | Phase 1 |
| 3.5 | Implement decision embedding tracking | Pending | 3.1-3.4 |
| 3.6 | Add working memory reuse tracking | Pending | 3.5 |
| 3.7 | Multi-turn integration tests | Pending | 3.6 |

---

## Phase 4: Telemetry Integration (Week 4-5)

### Goals
- JSON export for persistence
- WebSocket real-time updates
- Integration with SystemObserver
- Metrics persistence for historical analysis

### Tasks
| # | Task | Status | Dependencies |
|---|------|--------|-------------|
| 4.1 | Implement JSON export (`to_json`) | ✅ Complete | Phase 1 |
| 4.2 | Implement JSON file export | ✅ Complete | 4.1 |
| 4.3 | Create WebSocket server | ✅ Complete | None |
| 4.4 | Create WebSocket client | ✅ Complete | 4.3 |
| 4.5 | Dashboard data structures | ✅ Complete | 4.2, 4.4 |
| 4.6 | Integration with SystemObserver | Pending | 4.5 |
| 4.7 | Historical data storage | Pending | 4.6 |

### Telemetry Format
```json
{
  "timestamp": "2026-03-14T18:21:00Z",
  "consciousness": {
    "phi": 0.72,
    "global_workspace_score": 0.85,
    "information_flow_entropy": 1.34,
    "world_model_coherence": 0.78,
    "belief_consistency": 0.91,
    "self_model_accuracy": 0.83,
    "confidence_calibration": 0.76,
    "knowledge_boundary_accuracy": 0.88,
    "metacognitive_awareness": 0.81,
    "contextual_depth": 0.69,
    "temporal_consistency": 0.94
  },
  "context": {
    "cycle_number": 12345,
    "turn_count": 47,
    "working_memory_entries": 23,
    "active_modules": 9
  }
}
```

---

## Phase 5: Dashboard & Visualization (Week 5-6)

### Goals
- HTML/JS dashboard frontend
- Phi gauge widget
- Consciousness radar chart
- Timeline visualization

### Tasks
| # | Task | Status | Dependencies |
|---|------|--------|-------------|
| 5.1 | Create dashboard HTML structure | Pending | Phase 4 |
| 5.2 | Implement Phi gauge widget | Pending | 5.1 |
| 5.3 | Implement consciousness radar chart | Pending | 5.1 |
| 5.4 | Implement timeline visualization | Pending | 5.2 |
| 5.5 | Implement module activation heatmap | Pending | 5.3 |
| 5.6 | WebSocket client integration | Pending | 5.4 |
| 5.7 | Dashboard usability testing | Pending | 5.6 |

### Dashboard Layout
```
┌─────────────────────────────────────────────────────────────────┐
│                    CONSCIOUSNESS DASHBOARD                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌────────────────────────────────────┐  │
│  │   Φ GAUGE        │  │       CONSCIOUSNESS RADAR          │  │
│  │   [0.72]         │  │        .                           │  │
│  │   ▓▓▓▓▓▓░░░     │  │     .         .                    │  │
│  │   Moderate       │  │   .    ●──────●                    │  │
│  │                  │  │  ●─────────────●                   │  │
│  └──────────────────┘  │    ●          ●                   │  │
│                        │     ●        ●                      │  │
│  ┌──────────────────┐  │      ●────●                        │  │
│  │  QUICK STATS     │  └────────────────────────────────────┘  │
│  │  WMC:  0.78 ██   │                                          │
│  │  SMA:  0.83 ██   │  ┌────────────────────────────────────┐  │
│  │  CCS:  0.76 ██   │  │      Φ TIMELINE (last 60s)         │  │
│  │  KBA:  0.88 ██   │  │  1.0 ┤        ╭──╮                 │  │
│  │  TCS:  0.94 ██   │  │      │    ╭───╯  ╰───╮               │  │
│  └──────────────────┘  │  0.5 ┼───╯              ╰───╮        │  │
│                        │      │                      ╰──      │  │
│  ┌──────────────────┐  │  0.0 ┼────────────────────────     │  │
│  │ CONTEXT STATE    │  └────────────────────────────────────┘  │
│  │ Turn: 47/100    │                                          │
│  │ WM: 23 entries  │  ┌────────────────────────────────────┐   │
│  │ Modules: 9/9     │  │    MODULE ACTIVATION HEATMAP      │   │
│  └──────────────────┘  │  ▓▓▓ ▓▓░ ░░▓ ░░░ ▓▓▓ ▓▓▓ ▓▓░ ░░▓  │   │
│                        │  (Perception → Decision)             │   │
│                        └────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 6: Testing & Optimization (Week 6-7)

### Goals
- Load testing with simulated cognitive cycles
- Memory optimization for metrics storage
- End-to-end integration testing
- Performance benchmarking

### Tasks
| # | Task | Status | Dependencies |
|---|------|--------|-------------|
| 6.1 | Create load test scenarios | Pending | Phase 5 |
| 6.2 | Memory profiling | Pending | 6.1 |
| 6.3 | Performance benchmarking | Pending | 6.2 |
| 6.4 | End-to-end integration tests | Pending | 6.3 |
| 6.5 | Fix identified issues | Pending | 6.4 |
| 6.6 | Regression tests | Pending | 6.5 |

### Performance Targets
- **Cycle time:** < 7.3ms (136.1 Hz)
- **Memory:** < 100MB for 1000 snapshots
- **Latency:** < 100ms for JSON export

---

## Phase 7: Documentation & Deployment (Week 7-8)

### Goals
- Complete API documentation
- Write interpretation guide
- Deploy to staging environment
- Production deployment

### Tasks
| # | Task | Status | Dependencies |
|---|------|--------|-------------|
| 7.1 | Complete API documentation | Pending | Phase 6 |
| 7.2 | Write interpretation guide | Pending | 7.1 |
| 7.3 | Create example notebooks | Pending | 7.2 |
| 7.4 | Deploy to staging | Pending | 7.3 |
| 7.5 | Staging validation | Pending | 7.4 |
| 7.6 | Production deployment | Pending | 7.5 |

---

## Metric Thresholds Reference

| Metric | Critical | Warning | Normal | Good | Excellent |
|--------|----------|---------|--------|------|-----------|
| Φ (Phi) | < 0.2 | 0.2-0.4 | 0.4-0.6 | 0.6-0.8 | > 0.8 |
| GWS | < 0.3 | 0.3-0.5 | 0.5-0.7 | 0.7-0.85 | > 0.85 |
| WMC | < 0.3 | 0.3-0.5 | 0.5-0.7 | 0.7-0.85 | > 0.85 |
| SMA | < 0.3 | 0.3-0.5 | 0.5-0.7 | 0.7-0.85 | > 0.85 |
| CCS | < 0.3 | 0.3-0.5 | 0.5-0.7 | 0.7-0.85 | > 0.85 |
| CDI | < 0.2 | 0.2-0.4 | 0.4-0.6 | 0.6-0.8 | > 0.8 |
| TCS | < 0.4 | 0.4-0.6 | 0.6-0.8 | 0.8-0.9 | > 0.9 |

---

## Files Implemented

| File | Status | Description |
|------|--------|-------------|
| `consciousness/ConsciousnessMetrics.jl` | ✅ Complete | Core module with all 11 metrics |
| `consciousness/ConsciousnessMetricsIntegration.jl` | ✅ Complete | Integration layer |
| `consciousness/ConsciousnessTelemetry.jl` | ✅ Complete | WebSocket telemetry |
| `consciousness/Consciousness.jl` | ✅ Complete | Main entry point |
| `consciousness/IMPLEMENTATION_PLAN.md` | ✅ Complete | This document |

---

*Plan Version: 1.0*  
*Last Updated: 2026-03-14*
