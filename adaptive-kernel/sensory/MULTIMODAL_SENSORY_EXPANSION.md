# Multimodal Sensory Expansion Documentation

## Overview

The Multimodal Sensory Expansion enables the ITHERIS + JARVIS system to transition from processing "telemetry streams" to "perceiving physical spaces" through deep environmental awareness. This expansion integrates computer vision, multi-modal sensor fusion, and workflow management capabilities.

## Stage 4 Autonomous Operation

This expansion represents **Stage 4: Environmental Awareness** in the ITHERIS autonomous development framework. The system now possesses:

1. **Vision Integration** - Camera sources (webcam, IP, file) mapped to 12D perception format
2. **Multi-modal Fusion** - Vision + Audio + Telemetry unified through attention-based weighting
3. **Digital Actuation** - OpenClaw framework for autonomous engineering workflows
4. **Security Hardening** - Warden oversight with LEP veto equation for all actions

### 12D Unified Perception Format

All sensory inputs are mapped to a 12D feature vector for sub-microsecond processing:
```
[1-4]  Spatial features    - Physical space perception
[5-8]  Composite features - Histogram + Edge weighted
[9-12] Temporal features  - Texture + Motion weighted
```

This ensures vision inputs are processed with the same latency as auditory and telemetry data during the **136.1 Hz metabolic tick**.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Multimodal Sensory Expansion                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐   ┌──────────────────────────────────┐  │
│  │   Vision Input   │   │     Sensory Processing Pipeline   │  │
│  │   (Cameras)     │   │                                      │  │
│  └────────┬─────────┘   │  ┌─────────────┐ ┌──────────────┐  │  │
│           │             │  │   Vision    │ │   Legacy      │  │  │
│           ▼             │  │ Perception  │ │  (Audio,      │  │  │
│  ┌──────────────────┐   │  │  Module     │ │   Telemetry)  │  │  │
│  │ VisionPerception │   │  └──────┬──────┘ └──────┬───────┘  │  │
│  │      .jl        │   │         │               │          │  │
│  └────────┬─────────┘   │         ▼               ▼          │  │
│           │             │  ┌─────────────────────────────┐  │  │
│           │             │  │   MultimodalIntegration     │  │  │
│           ▼             │  │           .jl                │  │  │
│  ┌──────────────────┐   │  └──────────────┬──────────────┘  │  │
│  │  Feature Extract │   │                   │                  │  │
│  │  - Spatial       │   │                   ▼                  │  │
│  │  - Histogram     │   │  ┌─────────────────────────────┐   │  │
│  │  - Edge          │   │  │   12D Unified Perception    │   │  │
│  │  - Texture       │   │  │   (Brain Input Format)      │   │  │
│  │  - Motion        │   │  └─────────────────────────────┘   │  │
│  └────────┬─────────┘   │                                    │  │
│           │             └────────────────────────────────────┘  │
│           ▼                                                  │
│  ┌──────────────────┐                                       │
│  │  12D Perception  │───────────────► Brain.jl              │
│  └──────────────────┘                                       │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │              OpenClaw Workflow Management                  │  │
│  │  ┌──────────┐ ┌────────────┐ ┌──────────────┐           │  │
│  │  │Development│ │Data Science│ │ Deployment   │           │  │
│  │  │ Workflows │ │ Workflows  │ │  Pipelines   │           │  │
│  │  └──────────┘ └────────────┘ └──────────────┘           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Modules

### 1. VisionPerception.jl

Camera integration and image processing module.

**Features:**
- Multi-source camera support (webcam, IP camera, file, virtual)
- Real-time frame capture with configurable resolution and FPS
- Feature extraction pipelines:
  - **Spatial Features (4D):** Quadrant-based statistics
  - **Histogram Features (4D):** 16-bin intensity histograms
  - **Edge Features (4D):** Gradient-based edge detection
  - **Texture Features (4D):** Local variance analysis
  - **Motion Features (4D):** Frame-difference motion detection
- Object detection placeholder (for YOLO/detron integration)
- **Centralized Attention.jl Integration** - Salience computed via ITHERIS Brain's attention system
- Novelty detection against history

**Attention Integration:**
Vision salience is computed using the central `Attention.jl` module to ensure consistent salience scoring across all modalities. The `central_attention_salience()` function creates a `Stimulus` and routes it through the ITHERIS Brain's unified attention mechanism.

**12D Perception Format:**
```
[1-4]  Spatial features (quadrant means + contrast)
[5-8]  Composite (histogram + edges weighted)
[9-12] Temporal (texture + motion weighted)
```

**Usage:**
```julia
using VisionPerception

# Create vision processor
config = VisionConfig(
    resolution=(640, 480),
    fps=30.0,
    enable_object_detection=false
)
processor = create_vision_processor(config)

# Process frame
result = process_vision_input(processor, :camera)

# Access 12D perception
perception_12d = result.perception_12d
```

### 2. MultimodalIntegration.jl

Unified multi-modal sensory fusion module.

**Features:**
- Vision + Audio + Telemetry fusion
- Multiple fusion strategies:
  - `:weighted` - Fixed weight fusion
  - `:attention` - Softmax-weighted attention fusion
  - `:concatenate` - Feature concatenation
- **Attention-Based Gating** - Uses `Attention.jl` for unified salience computation
- Cross-modal attention with modality-specific salience
- Real-time fusion with history tracking

**Attention Gating:**
The `apply_attention_gating()` function uses the central Attention system to compute salience for each modality. Low-salience modalities are gated out (features zeroed) to prevent "sensory bypass" - ensuring every perceived event is evaluated by the sovereign kernel before influencing the system's affective state or action proposals.

**LEP Integration:**
In high-risk scenarios, telemetry anomalies may be weighted more heavily than visual background noise to ensure the **Law Enforcement Point (LEP)** has the most accurate data for its veto decision.

**Usage:**
```julia
using MultimodalIntegration

# Create multimodal pipeline
config = MultimodalConfig(
    enable_vision=true,
    enable_audio=true,
    enable_telemetry=true,
    fusion_strategy=:attention
)
state = create_multimodal_pipeline(config)

# Add inputs
process_audio_input(state, config, audio_features)
process_telemetry_input(state, config, telemetry_features)

# Get unified perception
result = get_unified_perception(state, config)

# Brain-ready 12D vector
brain_input = result.perception_12d
```

### 3. OpenClawWorkflow.jl

Workflow management framework for autonomous operations.

**Features:**
- Pre-defined workflow templates:
  - Development Pipeline (lint → test → docs)
  - Data Science Pipeline (load → preprocess → train → evaluate)
  - Deployment Pipeline (build → scan → staging → test → prod)
- Custom workflow creation
- Step dependencies and execution ordering
- Circular dependency detection
- Execution status tracking
- Workflow history

**Warden Oversight:**
Every action taken within OpenClaw pipelines (e.g., `git commit`, `curl`, `shell exec`) is strictly monitored by the Rust Warden through the LEP veto system.

**LEP Veto Equation:**
```
score = priority × (reward - risk)
```

| Score Range | Decision |
|-------------|----------|
| score < 0 | VETO (negative expected value) |
| risk > 0.8 | VETO (too risky) |
| high-risk action && score < 0.3 | VETO |
| otherwise | APPROVE with conditions if risk > 0.5 |

**Usage:**
```julia
using OpenClawWorkflow

# Create workflow from template
config = OpenClawConfig(endpoint="http://localhost:3000")
template = get_deployment_template(config)

workflow = create_workflow(
    "My Deployment",
    WORKFLOW_DEPLOYMENT,
    "Deploy my application",
    config
)

# Add steps
add_step!(workflow, "Build", "shell", Dict("command" => "make build"))
add_step!(workflow, "Test", "shell", Dict("command" => "make test"); 
          depends_on=["Build"])

# Execute
execution = execute_workflow(workflow)

# Check status
status = get_workflow_status(execution)
```

## Integration Points

### Brain.jl Integration

The 12D unified perception format directly maps to BrainInput:

```julia
# From VisionPerception or MultimodalIntegration
perception_12d = result.perception_12d

# Directly compatible with Brain.jl
brain_input = BrainInput(perception_12d)
```

### IoTBridge Integration

Vision can be combined with IoT sensor data:

```julia
# Get vision perception
vision_result = process_vision_input(processor, :camera)

# Get IoT telemetry via IoTBridge
iot_data = read_sensor(bridge, "temperature sensor")

# Fuse in multimodal pipeline
config = MultimodalConfig(enable_vision=true, enable_telemetry=true)
```

### RealityIngestion Integration

Environmental reality signals enhance vision:

```julia
# Ingest reality signals
signal = ingest_signal(SOURCE_SENSORS, reality_data, assumptions)

# Use with vision for grounded perception
fused = fuse_perceptions(vision_result, reality_signal)
```

## Security

### Vision Processing
- Frame validation (bounds checking, NaN/Inf detection)
- Timestamp validation
- Rate limiting for frame processing
- Sandboxed object detection

### Workflow Execution
- All tools validated against whitelist
- Dependency graph validation
- Approval gates for critical operations
- Audit logging for all executions

## Performance

Typical performance metrics:
- Vision processing: 50-100 FPS (640x480)
- Feature extraction: <10ms per frame
- Multi-modal fusion: <1ms
- Workflow step execution: Tool-dependent

## Testing

Run tests with:
```bash
julia --project=. test_multimodal_sensory.jl
```

Test coverage:
- VisionPerception: Config, frame capture, feature extraction, 12D conversion
- MultimodalIntegration: Fusion strategies, cross-modal attention
- Integration: Brain.jl format compatibility

## Applications

### Physical Security
- Real-time camera monitoring
- Motion detection alerts
- Perimeter surveillance integration

### Autonomous Robotics
- Spatial environment mapping
- Obstacle detection
- Navigation assistance

### Environmental Monitoring
- Multi-sensor fusion
- Anomaly detection
- Predictive maintenance

## Future Enhancements

- Deep learning-based feature extraction
- Real object detection (YOLO, detectron)
- 3D vision (stereo, depth cameras)
- Multi-camera fusion
- Edge deployment optimization
