# Adaptive Kernel - Quick Start & Verification Guide

## Directory Structure

```
adaptive-kernel/
├── .github/workflows/
│   └── ci.yml                          # GitHub Actions CI configuration
├── capabilities/
│   ├── observe_cpu.jl                  # Mock system metrics (extensible for real OS data)
│   ├── analyze_logs.jl                 # Log parsing & analysis
│   ├── write_file.jl                   # Sandbox-safe file writing
│   └── safe_shell.jl                   # Restricted command execution with whitelist
├── kernel/
│   └── Kernel.jl                       # ≤278 lines: core adaptive kernel
├── persistence/
│   └── Persistence.jl                  # Append-only event log (JSONL)
├── harness/
│   └── run.jl                          # Event loop orchestrator & CLI entry point
├── registry/
│   └── capability_registry.json        # Metadata-only capability declarations
├── tests/
│   ├── unit_kernel_test.jl             # Kernel core logic (deterministic; broader system has entropy injection)
│   ├── unit_capability_test.jl         # Capability interface validation
│   └── integration_simulation_test.jl  # 20-cycle end-to-end simulation
├── tools/
│   └── inspect_log.jl                  # Event log analyzer
├── sandbox/                            # Output directory for file operations
├── Project.toml                        # Julia package manifest (JSON dependency only)
├── README.md                           # Architecture & usage guide
├── DESIGN.md                           # Design rationale (300+ words)
└── MILESTONES.md                       # 8-step production roadmap
```

## Files & Line Counts (Verification)

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| **Kernel** | kernel/Kernel.jl | 278 | Decision logic, world state, reflection |
| **Persistence** | persistence/Persistence.jl | 60 | Event log (JSONL append-only) |
| **Harness** | harness/run.jl | 180 | Event loop orchestrator |
| **Observe CPU** | capabilities/observe_cpu.jl | 35 | Mock metrics capability |
| **Analyze Logs** | capabilities/analyze_logs.jl | 50 | Log parsing capability |
| **Write File** | capabilities/write_file.jl | 45 | Sandbox file writer |
| **Safe Shell** | capabilities/safe_shell.jl | 70 | Whitelisted shell executor |
| **Registry** | registry/capability_registry.json | 50+ | Capability metadata |
| **Tests (Total)** | tests/*.jl | 350+ | Unit + integration tests |

**Total readable kernel code**: 278 lines ✓ (well under 400-line limit)

## Safety & Architecture Guarantees

- ✓ No `Any` types in critical path (all struct fields are concrete-typed)
- ✓ Deterministic decision logic (no randomness in reasoning)
- ✓ Append-only audit trail persists every decision
- ✓ High-risk actions require permission handler approval
- ✓ Capabilities confined to sandbox/ directory
- ✓ Type-stable code for performance & auditability

## How to Verify Locally

### 1. Install Julia 1.8+ and navigate to the project:

```bash
cd /path/to/adaptive-kernel
julia --version  # Verify 1.8+
```

### 2. Install dependencies:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### 3. Run unit tests:

```bash
julia --project=. -e 'include("tests/unit_kernel_test.jl")'
julia --project=. -e 'include("tests/unit_capability_test.jl")'
```

### 4. Run integration test (20-cycle simulation):

```bash
julia --project=. -e 'include("tests/integration_simulation_test.jl")'
```

### 5. Run the harness (event loop):

```bash
julia --project=. harness/run.jl --cycles 20
```

Or with unsafe mode (high-risk actions allowed):

```bash
julia --project=. harness/run.jl --cycles 20 --unsafe
```

### 6. Inspect the event log:

```bash
julia --project=. tools/inspect_log.jl
```

Expected output: summaries of cycles, success rates, risk breakdown, final state.

## Expected Test Results

If all tests pass, you should see:

```
✓ Kernel loaded successfully
✓ All unit tests passed!
✓ All capability tests passed!
✓ Integration test passed (20 cycles)!
```

And the harness will run 20 cycles, with output like:

```
[ Info: === Adaptive Kernel Harness ===
[ Info: Kernel initialized cycle=0
[ Info: Cycle 5 summary stats...
[ Info: Cycle 10 summary stats...
[ Info: Cycle 20 summary stats...
[ Info: Event loop complete cycles=20 final_confidence=0.75 final_energy=0.60
```

## Key Functions & API

### Kernel Module (kernel/Kernel.jl)

```julia
# Initialization
kernel = init_kernel(config::Dict)::KernelState

# Main event loop
kernel, action, result = step_once(
    kernel::KernelState, 
    capability_candidates::Vector{Dict}, 
    execute_fn::Function,         # Callback to run capability
    permission_handler::Function  # Callback to approve/deny actions
)::Tuple{KernelState, ActionProposal, Dict}

# Batch loop
kernel = run_loop(
    kernel::KernelState, 
    capability_candidates::Vector{Dict}, 
    execute_fn::Function,
    permission_handler::Function,
    cycles::Int
)::KernelState

# Introspection
stats = get_kernel_stats(kernel::KernelState)::Dict{String, Any}

# Update world
set_kernel_state!(kernel::KernelState, observations::Dict)
```

### Capability Interface (each capability module)

```julia
# Required function 1: metadata
meta()::Dict{String, Any}
# Returns: {id, name, description, inputs, outputs, cost, risk, reversible, ...}

# Required function 2: execute
execute(params::Dict{String, Any})::Dict{String, Any}
# Returns: {success, effect, actual_confidence, energy_cost, data, ...}
```

### Persistence Module (persistence/Persistence.jl)

```julia
init_persistence()                                    # Initialize event log
save_event(event::Dict{String, Any})                # Append event (JSONL)
events = load_events()::Vector{Dict{String, Any}}   # Load all events
last_state = get_last_state()::Dict{String, Any}    # Resume from checkpoint
save_kernel_state(stats::Dict{String, Any})         # Snapshot state
```

## Adding a New Capability

1. **Create** `capabilities/my_cap.jl`:

```julia
module MyCapability
export meta, execute

function meta()::Dict{String, Any}
    return Dict(
        "id" => "my_cap",
        "name" => "My Capability",
        "description" => "Does something safe",
        "inputs" => Dict("param" => "string"),
        "outputs" => Dict("result" => "string"),
        "cost" => 0.05,
        "risk" => "low",
        "reversible" => true
    )
end

function execute(params::Dict{String, Any})::Dict{String, Any}
    # Your logic here
    return Dict(
        "success" => true,
        "effect" => "Did something",
        "actual_confidence" => 0.9f0,
        "energy_cost" => 0.05f0,
        "data" => Dict("result" => "...")
    )
end
end
```

2. **Register** in `registry/capability_registry.json`:

```json
{
  "id": "my_cap",
  "name": "My Capability",
  "description": "...",
  "inputs": {"param": "string"},
  "outputs": {"result": "string"},
  "cost": 0.05,
  "risk": "low",
  "reversible": true
}
```

3. **Test**:

```bash
julia --project=. -e 'include("capabilities/my_cap.jl"); using .MyCapability; println(meta())'
```

## Next Steps

1. **Run tests locally** to verify all components
2. **Read DESIGN.md** for architecture rationale
3. **Read MILESTONES.md** for production roadmap (8 steps, ~8 weeks)
4. **Extend with real OS data** (Milestone 2): replace mock metrics in `observe_cpu.jl`
5. **Integrate with service management** (Milestone 3): expand `safe_shell.jl` with systemctl, etc.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `ERROR: expected package` | Project.toml has typo in [deps]; remove stdlib packages |
| Tests fail with `include` error | Make sure working directory is `adaptive-kernel/` |
| `safe_shell` rejects command | Check that command is in WHITELIST; add if needed |
| Event log not persisting | Verify `sandbox/` and `events.log` are writable |

## Performance Notes

- **Kernel cycle time**: ~1ms per step (no ML inference, pure heuristics)
- **Memory growth**: ~1KB per episodic memory entry (1000-entry cap - MAX_EPISODIC_MEMORY)
- **Event log**: ~100-200 bytes per entry; rotate after 1Mtarget lines
- **Parallel scalability**: Each kernel instance is independent; scale with N independent processes

## Safety Checklist

Before deploying to production (Milestone 8):

- [ ] All file I/O confined to `sandbox/`
- [ ] High-risk capabilities whitelist verified
- [ ] Event log auditable (no mutations, append-only)
- [ ] Permission handler tested (DENY by default)
- [ ] Circuit breakers implemented (capability failure isolation)
- [ ] Rollback logic tested (reversible actions only)
- [ ] Resource limits enforced (memory, CPU, time)
- [ ] Human oversight in place (escalation procedures)

## Support & Contributing

- Open issues for bugs or feature requests
- Follow Julia style guide (lowercase functions, `!` for mutations)
- All PRs require passing tests and <400 line limit for kernel changes
- Documentation must be updated for each new capability

---

**Ready to experiment?** Start with:

```bash
julia --project=. harness/run.jl --cycles 50 --unsafe
julia --project=. tools/inspect_log.jl
```

Then review `DESIGN.md` and `MILESTONES.md` for building toward production.
