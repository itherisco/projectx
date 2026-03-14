"""
# Consciousness.jl

Main module entry point for the Consciousness Metrics system.

This module provides comprehensive consciousness quantification for the ITHERIS + JARVIS
cognitive architecture, implementing 11 core metrics across 4 categories:

## 11 Core Metrics

### Category 1: Information Integration Measurement
1. **Phi (Φ)** - Consciousness indicator (IIT-based)
2. **Global Workspace Score (GWS)** - Information sharing across modules
3. **Information Flow Entropy (IFE)** - Information flow diversity

### Category 2: Internal World-State Consistency
4. **World Model Coherence (WMC)** - Prediction accuracy
5. **Belief Consistency Index (BCI)** - Belief consistency over time
6. **Self-Model Accuracy (SMA)** - Self-prediction accuracy

### Category 3: Self-Model Accuracy Metrics
7. **Confidence Calibration Score (CCS)** - Confidence calibration
8. **Knowledge Boundary Accuracy (KBA)** - Knowing what you don't know
9. **Meta-Cognitive Awareness Index (MCAI)** - Overall self-awareness

### Category 4: Multi-Turn Context Metrics
10. **Contextual Depth Index (CDI)** - Context maintenance depth
11. **Temporal Consistency Score (TCS)** - Decision consistency over time

## Telemetry Integration
- JSON export for persistence
- WebSocket real-time updates
- Dashboard data structures

## Usage

```julia
# Create metrics system
metrics, context_tracker = create_default_metrics()

# Run metrics cycle
snapshot = update_metrics!(metrics, context_tracker)

# Export to JSON
json_data = to_json(snapshot)
```
"""
module Consciousness

# Load submodules
include("ConsciousnessMetrics.jl")
include("ConsciousnessMetricsIntegration.jl")
include("ConsciousnessTelemetry.jl")

using .ConsciousnessMetrics
using .ConsciousnessMetricsIntegration
using .ConsciousnessTelemetry

# Re-export public API
export ConsciousnessMetrics, ConsciousnessMetricsIntegration, ConsciousnessTelemetry

end # module
