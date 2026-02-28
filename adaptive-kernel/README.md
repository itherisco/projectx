# Adaptive Cognitive Kernel

A minimal, auditable adaptive operating system kernel for building safe, intelligent agents. The kernel is ~830 lines of readable Julia code that maintains world state, evaluates priorities, selects actions deterministically, and reflects on outcomes—all without embedding task logic, OS capabilities, or personality.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  HARNESS (run.jl)                       │
│  ├─ loads registry & capabilities                       │
│  ├─ orchestrates event loop                             │
│  └─ manages permissions & persistence                   │
└────────────────┬────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────┐
│            KERNEL (Kernel.jl)                           │
│  ├─ world state & observations                          │
│  ├─ self-metrics (confidence, energy, focus)            │
│  ├─ goals & priorities                                  │
│  ├─ deterministic decision logic                        │
│  └─ episodic memory                                     │
└────────────────┬────────────────────────────────────────┘
                 │
    ┌────────────┼────────────┬────────────┐
    │            │            │            │
┌───▼────┐  ┌────▼────┐  ┌───▼────┐  ┌───▼────┐
│observe │  │analyze  │  │write   │  │ safe   │
│ _cpu   │  │ _logs   │  │ _file  │  │_shell  │
└────────┘  └─────────┘  └────────┘  └────────┘
```

**Key design principles:**
1. **Separation of concerns**: Kernel reasons; capabilities execute.
2. **Determinism**: All decisions are traced and reproducible.
3. **Auditability**: Append-only event log for full transparency.
4. **Minimalism**: Kernel ≤400 lines; capabilities are thin wrappers.
5. **Safety by default**: High-risk actions require explicit permission.

## Running the System

### Prerequisites

```bash
julia --version  # must be 1.8+
```

### Quick Start

```bash
cd adaptive-kernel
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. harness/run.jl --cycles 20
```

### With Unsafe Mode (for testing)

```bash
julia --project=. harness/run.jl --cycles 20 --unsafe
```

This allows high-risk actions without permission checks.

### Test Suite

```bash
# Unit tests
julia --project=. -e 'include("tests/unit_kernel_test.jl")'
julia --project=. -e 'include("tests/unit_capability_test.jl")'

# Integration (20-cycle simulation)
julia --project=. -e 'include("tests/integration_simulation_test.jl")'
```

### Inspect Event Log

```bash
julia --project=. tools/inspect_log.jl
# or with custom log file:
julia --project=. tools/inspect_log.jl my_events.log
```

## Core Abstractions

### KernelState

Immutable-by-design kernel state:

```julia
mutable struct KernelState
    cycle::Int
    goals::Vector{Goal}
    world::WorldState
    active_goal_id::String
    episodic_memory::Vector{Dict{String, Any}}
    self_metrics::Dict{String, Float32}  # confidence, energy, focus
    last_action::Union{ActionProposal, Nothing}
    last_reward::Float32
    last_prediction_error::Float32
end
```

### Goal

```julia
struct Goal
    id::String
    description::String
    priority::Float32  # [0, 1]
    created_at::DateTime
end
```

### Event Loop (observe → evaluate → decide → reflect)

1. **Observe**: Update `kernel.world` with latest observations
2. **Evaluate**: Compute priority scores for goals using `evaluate_world()`
3. **Decide**: Select best action via `select_action()` (heuristic: priority - cost * risk_penalty)
4. **Reflect**: Update episodic memory and self-metrics via `reflect!()`

## Capability Registry

The registry (`registry/capability_registry.json`) declares capability metadata:

```json
{
  "id": "example_capability",
  "name": "Example",
  "description": "Does something",
  "inputs": {"param": "type"},
  "outputs": {"result": "type"},
  "cost": 0.05,
  "risk": "low|medium|high",
  "reversible": true/false
}
```

## Adding a New Capability

1. **Create a file** `capabilities/my_capability.jl`:

```julia
module MyCapability

export meta, execute

function meta()::Dict{String, Any}
    return Dict(
        "id" => "my_capability",
        "name" => "My Capability",
        "description" => "Does X",
        "inputs" => Dict("input_param" => "string"),
        "outputs" => Dict("result" => "string"),
        "cost" => 0.1,
        "risk" => "low",
        "reversible" => true
    )
end

function execute(params::Dict{String, Any})::Dict{String, Any}
    # Your logic here
    
    return Dict(
        "success" => true,
        "effect" => "Completed X",
        "actual_confidence" => 0.9f0,
        "energy_cost" => 0.08f0,
        "data" => Dict("result" => "...")
    )
end

end
```

2. **Register it** in `registry/capability_registry.json`:

```json
{
  "id": "my_capability",
  "name": "My Capability",
  ...
}
```

3. **Test it** (from the project root directory):

```julia
include("capabilities/my_capability.jl")
using .MyCapability
result = MyCapability.execute(Dict("input_param" => "value"))
```

## Permission Model

The harness enforces a permission handler:

```julia
function default_permission_handler(risk::String)::Bool
    # Default: only allow low-risk actions
    return risk == "low"
end
```

Override by passing a custom handler to `step_once()` or `run_loop()`.

## Persistence

All events are logged append-only in `events.log` (JSONL format). The kernel can resume from the latest state:

```julia
events = load_events()  # Load all past events
last_state = get_last_state()  # Resume from previous checkpoint
```

## Safety Checklist

- [ ] All capabilities confined to `sandbox/` for file I/O
- [ ] High-risk capabilities whitelisted (e.g., `safe_shell`)
- [ ] Event log persisted and auditable
- [ ] Permission handler enforces least privilege by default
- [ ] No unvalidated shell execution
- [ ] Deterministic decision logic (no randomness in reasoning)
- [ ] Type-stable code (no `Any` in critical paths)

## Performance

- **Kernel**: ~350 lines, runs a cycle in <1ms
- **Event log**: Append-only; linear reads; space-efficient JSONL
- **Memory**: Episodic memory cap at 5000 events (managed per capability)

## Integration Examples

### Continuous Monitoring Loop

```julia
kernel = init_kernel(config)
for epoch in 1:100_000
    kernel, action, result = step_once(
        kernel, candidates, execute_capability, permission_handler
    )
    sleep(0.1)  # 10Hz control loop
end
```

### Manual Approval Loop

```julia
function interactive_permission(risk::String)::Bool
    if risk == "high"
        print("Approve high-risk action? (y/n) ")
        return readline() in ["y", "yes"]
    end
    return true
end

kernel = run_loop(kernel, candidates, execute_capability, interactive_permission, 50)
```

## Next Steps: Roadmap to Production

See `DESIGN.md` and `MILESTONES.md` for:
- Detailed architecture rationale
- 8-step incremental milestones toward field-usable Jarvis
- Integration with real OS perceptions
- Safe remote execution for trusted environments

## Testing & Debugging

Run the full test suite:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Enable debug output:

```bash
JULIA_DEBUG=all julia --project=. harness/run.jl
```

Inspect log:

```bash
julia tools/inspect_log.jl
```

## License

MIT (or your preferred license)

## References

- [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/)
- [Design Patterns for Safe Autonomous Systems](https://arxiv.org/abs/1806.06515)
- [Specification for OS-Level Sandboxing](https://tools.ietf.org/html/draft-ietf-rtcweb-security-arch)

---

**Questions?** Open an issue or contact the maintainers.
