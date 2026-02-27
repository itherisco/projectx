# Phase 1: Integration Glue Implementation Plan

## Overview

This plan addresses the critical type mismatches preventing the three brains (ITHERIS Brain, Adaptive Kernel, and Jarvis System) from communicating. The solution uses an **Integration module** with unified types and backward-compatible conversion functions.

## Confirmed Gaps

### 1. ActionProposal Type Mismatch

| Source | Fields |
|--------|--------|
| [`JarvisTypes.ActionProposal`](jarvis/src/types.jl:165) | `id::UUID`, `capability_id`, `confidence`, `predicted_cost`, `predicted_reward`, `risk::Float32`, `reasoning`, `impact_estimate`, `timestamp` |
| [`SharedTypes.ActionProposal`](adaptive-kernel/types.jl:19) | `capability_id`, `confidence`, `predicted_cost`, `predicted_reward`, `risk::String`, `reasoning` |

### 2. WorldState Type Mismatch

| Source | Fields |
|--------|--------|
| [`JarvisTypes.WorldState`](jarvis/src/types.jl:267) | `cpu_load`, `memory_usage`, `disk_usage`, `network_latency`, `overall_severity`, `threat_count`, `trust_level`, `kernel_approvals`, `kernel_denials`, `available_capabilities`, `last_decision`, `last_action_id`, `status` |
| [`Kernel.WorldState`](adaptive-kernel/kernel/Kernel.jl:25) | `timestamp`, `observations::Dict{String, Any}`, `facts::Dict{String, String}` |

### 3. Kernel State Never Initialized

In [`SystemIntegrator.jl:32-34`](jarvis/src/SystemIntegrator.jl:32):
```julia
struct KernelWrapper
    state::Union{Kernel.KernelState, Nothing}
    function KernelWrapper()
        new(nothing, Dict(), false)  # ← state is literally `nothing`
    end
end
```

---

## Implementation Tasks

### Task 1: Add Integration Unified Types to adaptive-kernel/types.jl

**Location:** `adaptive-kernel/types.jl`

Add new unified type definitions with `Integration` prefix:

```julia
# ============================================================================
# INTEGRATION TYPES - Unified types for brain-kernel-jarvis communication
# ============================================================================

"""
    Integration.ActionProposal - Universal action proposal format
    Used as the canonical format for all three brains to communicate
"""
struct IntegrationActionProposal
    id::UUID
    capability_id::String
    confidence::Float32
    predicted_cost::Float32
    predicted_reward::Float32
    risk::Float32           # Unified as Float32 (not String like SharedTypes)
    reasoning::String
    impact_estimate::Float32
    timestamp::DateTime
    
    # Constructor with auto-generated UUID
    function IntegrationActionProposal(
        capability_id::String,
        confidence::Float32,
        cost::Float32,
        reward::Float32,
        risk::Float32;
        reasoning::String = "",
        impact::Float32 = 0.5f0
    )
        new(uuid4(), capability_id, confidence, cost, reward, risk, reasoning, impact, now())
    end
end

"""
    Integration.WorldState - Unified world state format
    Combines Jarvis system metrics with Kernel semantic facts
"""
struct IntegrationWorldState
    timestamp::DateTime
    
    # System metrics (from Jarvis)
    system_metrics::Dict{String, Float32}  # cpu, memory, disk, network
    
    # Security state (from Jarvis)
    severity::Float32
    threat_count::Int
    trust_level::Int  # 0-100 scale
    
    # Kernel observations
    observations::Dict{String, Any}
    
    # Semantic facts (from Kernel)
    facts::Dict{String, String}
    
    # Metadata
    cycle::Int
    last_action_id::Union{String, Nothing}
    
    function IntegrationWorldState(;
        system_metrics::Dict{String, Float32} = Dict{String, Float32}(),
        severity::Float32 = 0.0f0,
        threat_count::Int = 0,
        trust_level::Int = 100,
        observations::Dict{String, Any} = Dict{String, Any}(),
        facts::Dict{String, String} = Dict{String, String}(),
        cycle::Int = 0,
        last_action_id::Union{String, Nothing} = nothing
    )
        new(now(), system_metrics, severity, threat_level, trust_level, 
            observations, facts, cycle, last_action_id)
    end
end

export IntegrationActionProposal, IntegrationWorldState
```

---

### Task 2: Create Forward Conversion Functions

**Location:** `adaptive-kernel/types.jl` (or new file `adaptive-kernel/integration/Conversions.jl`)

Convert from existing types to Integration types:

```julia
# ============================================================================
# CONVERSION FUNCTIONS - Existing → Integration
# ============================================================================

"""
    convert_to_integration(proposal::JarvisTypes.ActionProposal)::IntegrationActionProposal
Convert JarvisTypes.ActionProposal to IntegrationActionProposal
"""
function convert_to_integration(proposal::JarvisTypes.ActionProposal)::IntegrationActionProposal
    return IntegrationActionProposal(
        proposal.capability_id,
        proposal.confidence,
        proposal.predicted_cost,
        proposal.predicted_reward,
        proposal.risk,
        reasoning=proposal.reasoning,
        impact=proposal.impact_estimate
    )
end

"""
    convert_to_integration(proposal::SharedTypes.ActionProposal)::IntegrationActionProposal
Convert SharedTypes.ActionProposal to IntegrationActionProposal
"""
function convert_to_integration(proposal::SharedTypes.ActionProposal)::IntegrationActionProposal
    # Parse risk string to Float32
    risk_float = parse_risk_string(proposal.risk)
    
    return IntegrationActionProposal(
        proposal.capability_id,
        proposal.confidence,
        proposal.predicted_cost,
        proposal.predicted_reward,
        risk_float,
        reasoning=proposal.reasoning
    )
end

"""
    convert_to_integration(world::JarvisTypes.WorldState, kernel_world::Kernel.WorldState)::IntegrationWorldState
Convert both Jarvis and Kernel WorldStates to unified IntegrationWorldState
"""
function convert_to_integration(
    jarvis_world::JarvisTypes.WorldState, 
    kernel_world::Kernel.WorldState
)::IntegrationWorldState
    system_metrics = Dict{String, Float32}(
        "cpu_load" => jarvis_world.cpu_load,
        "memory_usage" => jarvis_world.memory_usage,
        "disk_usage" => jarvis_world.disk_usage,
        "network_latency" => jarvis_world.network_latency
    )
    
    trust_level_int = _trust_level_to_int(jarvis_world.trust_level)
    
    return IntegrationWorldState(
        system_metrics=system_metrics,
        severity=jarvis_world.overall_severity,
        threat_count=jarvis_world.threat_count,
        trust_level=trust_level_int,
        observations=kernel_world.observations,
        facts=kernel_world.facts,
        cycle=0,  # Would need to track this separately
        last_action_id=jarvis_world.last_action_id
    )
end

# Helper functions
function parse_risk_string(risk::String)::Float32
    risk_lowercase = lowercase(risk)
    if risk_lowercase == "high" || risk_lowercase == "h"
        return 0.8f0
    elseif risk_lowercase == "medium" || risk_lowercase == "m"
        return 0.5f0
    elseif risk_lowercase == "low" || risk_lowercase == "l"
        return 0.2f0
    else
        return 0.3f0  # Default
    end
end

function _trust_level_to_int(level::JarvisTypes.TrustLevel)::Int
    return Int(JarvisTypes.trust_level)
end
```

---

### Task 3: Create Reverse Conversion Functions

Convert from Integration types back to existing types:

```julia
# ============================================================================
# CONVERSION FUNCTIONS - Integration → Existing
# ============================================================================

"""
    convert_from_integration(proposal::IntegrationActionProposal)::JarvisTypes.ActionProposal
Convert IntegrationActionProposal to JarvisTypes.ActionProposal
"""
function convert_from_integration(proposal::IntegrationActionProposal)::JarvisTypes.ActionProposal
    return JarvisTypes.ActionProposal(
        proposal.capability_id,
        proposal.confidence,
        proposal.predicted_cost,
        proposal.predicted_reward,
        proposal.risk,
        reasoning=proposal.reasoning,
        impact=proposal.impact_estimate
    )
end

"""
    convert_from_integration(proposal::IntegrationActionProposal)::SharedTypes.ActionProposal
Convert IntegrationActionProposal to SharedTypes.ActionProposal
"""
function convert_from_integration(proposal::IntegrationActionProposal)::SharedTypes.ActionProposal
    return SharedTypes.ActionProposal(
        proposal.capability_id,
        proposal.confidence,
        proposal.predicted_cost,
        proposal.predicted_reward,
        _float_to_risk_string(proposal.risk),  # Convert Float32 to String
        proposal.reasoning
    )
end

function _float_to_risk_string(risk::Float32)::String
    if risk >= 0.7f0
        return "high"
    elseif risk >= 0.4f0
        return "medium"
    else
        return "low"
    end
end
```

---

### Task 4: Fix KernelWrapper State Initialization

**Location:** `jarvis/src/SystemIntegrator.jl`

Fix the `KernelWrapper` to actually initialize the kernel state:

```julia
# Current (broken):
struct KernelWrapper
    state::Union{Kernel.KernelState, Nothing}
    config::Dict
    initialized::Bool
    
    function KernelWrapper()
        new(nothing, Dict(), false)  # ← state is literally `nothing`
    end
end

# Fixed:
function initialize_kernel!(wrapper::KernelWrapper, config::Dict)
    wrapper.config = config
    try
        wrapper.state = Kernel.init_kernel(config)
        wrapper.initialized = true
        @info "Kernel initialized successfully"
    catch e
        @error "Failed to initialize kernel" error=e
        wrapper.initialized = false
    end
end
```

Also update `initialize_jarvis` to call `initialize_kernel!`:

```julia
function initialize_jarvis(config::JarvisConfig)::JarvisSystem
    # ... existing code ...
    
    # Initialize kernel
    kernel_config = Dict(
        "goals" => [
            Dict("id" => "system_nominal", "description" => "Keep system running smoothly", "priority" => 0.8)
        ],
        "observations" => Dict{String, Any}()
    )
    initialize_kernel!(system.kernel, kernel_config)
    
    return system
end
```

---

### Task 5: Update run_cycle with Type Conversions

**Location:** `jarvis/src/SystemIntegrator.jl`

Update the execution cycle to properly convert types at boundaries:

```julia
function run_cycle(system::JarvisSystem)::CycleResult
    start_time = time()
    system.state.current_cycle += 1
    cycle_num = system.state.current_cycle
    
    # 1. Observe world state (Jarvis format)
    observation = _observe_world(system)
    
    # 2. Build perception vector
    perception = _build_perception(observation)
    
    # 3. Get brain inference → returns JarvisTypes.ActionProposal
    jarvis_proposal = _brain_infer(system, perception)
    
    # 4. CONVERT: JarvisTypes → Integration format for kernel
    integration_proposal = convert_to_integration(jarvis_proposal)
    
    # 5. KERNEL APPROVAL (now uses Integration format internally)
    executable_action = _kernel_approval(system, integration_proposal, perception)
    
    # 6. If kernel approved, convert back to Jarvis format for execution
    if executable_action !== nothing
        execution_result = _execute_action(system, executable_action)
    else
        execution_result = nothing
    end
    
    # 7. Learn from outcome
    reward = _compute_reward(execution_result)
    _learn!(system, perception, jarvis_proposal, reward)
    
    # ... rest unchanged ...
end
```

---

### Task 6: Add Error Handling

Add comprehensive error handling for type conversion failures:

```julia
"""
    safe_convert_to_integration(proposal)::Union{IntegrationActionProposal, Nothing}
Convert with error handling - returns nothing on failure instead of throwing
"""
function safe_convert_to_integration(proposal)::Union{IntegrationActionProposal, Nothing}
    try
        if proposal === nothing
            return nothing
        elseif isa(proposal, JarvisTypes.ActionProposal)
            return convert_to_integration(proposal)
        elseif isa(proposal, SharedTypes.ActionProposal)
            return convert_to_integration(proposal)
        else
            @warn "Unknown proposal type for conversion" type=typeof(proposal)
            return nothing
        end
    catch e
        @error "Failed to convert proposal to integration format" error=e
        return nothing
    end
end
```

---

### Task 7: Write Integration Test

**Location:** `adaptive-kernel/tests/test_integration.jl` (or `jarvis/tests/`)

```julia
# ============================================================================
# Integration Test - Three Brain Communication
# ============================================================================

using Test
using Dates
using UUIDs

# Import all modules
include("../../jarvis/src/types.jl")
include("../../jarvis/src/SystemIntegrator.jl")
include("../types.jl")
include("../kernel/Kernel.jl")
include("conversion_functions.jl")

@testset "Type Conversion Tests" begin
    # Test Jarvis → Integration conversion
    jarvis_proposal = JarvisTypes.ActionProposal(
        "observe_cpu", 0.9f0, 0.1f0, 0.8f0, 0.05f0;
        reasoning="CPU usage appears high"
    )
    
    integration_proposal = convert_to_integration(jarvis_proposal)
    @test integration_proposal isa IntegrationActionProposal
    @test integration_proposal.capability_id == "observe_cpu"
    @test integration_proposal.confidence == 0.9f0
    
    # Test Integration → Jarvis conversion
    jarvis_back = convert_from_integration(integration_proposal)
    @test jarvis_back.capability_id == jarvis_proposal.capability_id
    
    # Test SharedTypes → Integration conversion
    shared_proposal = SharedTypes.ActionProposal(
        "safe_shell", 0.7f0, 0.2f0, 0.6f0, "low", "Shell command safe"
    )
    
    integration_from_shared = convert_to_integration(shared_proposal)
    @test integration_from_shared.risk ≈ 0.2f0  # "low" → 0.2
end

@testset "Kernel Initialization Test" begin
    kernel_config = Dict(
        "goals" => [Dict("id" => "test", "description" => "Test goal", "priority" => 0.5)],
        "observations" => Dict{String, Any}()
    )
    
    wrapper = KernelWrapper()
    initialize_kernel!(wrapper, kernel_config)
    
    @test wrapper.initialized == true
    @test wrapper.state !== nothing
    @test wrapper.state.cycle == 0
end

@testset "End-to-End Cycle Test" begin
    # This would test the full cycle: brain → kernel → execution
    # Requires full system initialization
    @test_broken "Full integration test not yet implemented"
end
```

---

## File Structure Summary

After implementation, the file structure will be:

```
adaptive-kernel/
├── types.jl                    # Extended with Integration types
├── integration/
│   └── Conversions.jl          # New: Conversion functions
└── tests/
    └── test_integration.jl    # New: Integration tests

jarvis/
└── src/
    └── SystemIntegrator.jl     # Updated: Kernel initialization + type conversions
```

---

## Execution Order

1. **Add Integration types** to `adaptive-kernel/types.jl`
2. **Create conversion functions** in `adaptive-kernel/integration/Conversions.jl`
3. **Fix KernelWrapper** initialization in `jarvis/src/SystemIntegrator.jl`
4. **Update run_cycle** to use type conversions
5. **Add error handling** for conversion failures
6. **Write integration tests** to verify communication

---

## Notes

- All changes maintain **backward compatibility** - existing code continues to work
- The Integration types serve as the **canonical format** for inter-brain communication
- Type conversions happen at **boundary points** (brain→kernel, kernel→execution)
- Error handling ensures **graceful degradation** if conversion fails
