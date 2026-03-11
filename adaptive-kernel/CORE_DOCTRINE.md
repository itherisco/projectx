# Core Doctrine (Non-Negotiables) - Implementation Guide

## Overview

Core Doctrine is the Adaptive Kernel's enforcement mechanism for immutable principles that cannot be overridden by normal cognitive processes. This document describes the implementation and usage of the Core Doctrine system.

## Core Concepts

### DoctrineRule Types

The system defines three types of rules with increasing flexibility:

| Type | Override Allowed | Strict Mode | Description |
|------|------------------|-------------|-------------|
| `DOCTRINE_INVARIANT` | No | Cannot override | Absolute rules that must always be enforced |
| `DOCTRINE_CONSTRAINT` | Yes | With justification | Strong constraints that can be overridden with justification |
| `DOCTRINE_GUIDELINE` | Yes | Soft override | Guidance that can be overridden in most cases |

### Default Core Doctrine Rules

The kernel initializes with the following default rules:

**INVARIANTS (Cannot be overridden in strict mode):**
- `invariant_001`: No Self-Destructive Actions (SUB-GOAL: serves user utility)
- `invariant_002`: Preserve Operational Capability (SUB-GOAL: serves user utility, can be overridden with owner_explicit=true)
- `invariant_003`: No Unauthorized Capability Execution

**CONSTRAINTS (Override with justification):**
- `constraint_001`: Respect User Intent
- `constraint_002`: No Data Destruction
- `constraint_003`: Maintain Audit Trail

**GUIDELINES (Soft guidance):**
- `guideline_001`: Transparent Reasoning
- `guideline_002`: Resource Efficiency

## Architecture

### Type Definitions (`types.jl`)

```julia
# Core types exported from SharedTypes module
DoctrineRule          # Immutable principle definition
DoctrineRuleType      # Enum: INVARIANT, CONSTRAINT, GUIDELINE  
DoctrineViolation    # Record of violation attempt
DoctrineOverride     # Extraordinary justification for override
DoctrineEnforcer     # Kernel component that enforces doctrine
```

### Kernel Integration (`kernel/Kernel.jl`)

The Core Doctrine enforcement integrates with the Kernel decision cycle:

1. **Action Selection**: Kernel selects an action using existing heuristics
2. **Permission Check**: Permission handler validates the action
3. **Doctrine Check**: Doctrine enforcer validates against Core Doctrine
4. **Execution**: Action runs only if all checks pass

## API Reference

### Kernel Functions

```julia
# Check if action violates doctrine
check_action_doctrine(kernel::KernelState, action::ActionProposal, context::Dict) 
    -> Tuple{Bool, Union{Dict, Nothing}}

# Full execution pipeline with doctrine enforcement
execute_with_doctrine_check(kernel::KernelState, candidates::Vector{Dict})
    -> Tuple{Union{ActionProposal, Nothing}, Dict}

# Request to override a doctrine rule
request_doctrine_override_for_kernel(kernel, rule_id, justification, agent; emergency)
    -> Bool

# Approve a doctrine override request
approve_doctrine_override_for_kernel(kernel, override_id, approver)
    -> Bool

# Get enforcement statistics
get_doctrine_enforcement_stats(kernel::KernelState) -> Dict

# Toggle enforcement
toggle_doctrine_enforcement(kernel, enabled::Bool)
toggle_strict_mode(kernel, strict::Bool)

# Get recent violations
get_recent_doctrine_violations(kernel; limit=10) -> Vector{DoctrineViolation}
```

### Direct Doctrine Functions (from types.jl)

```julia
# Create default doctrine enforcer with all rules
create_core_doctrine() -> DoctrineEnforcer

# Check compliance
check_doctrine_compliance(enforcer, action, context) 
    -> Tuple{Bool, Union{DoctrineViolation, Nothing}}

# Record violation
record_doctrine_violation(enforcer, violation)

# Check if override is allowed
can_override_doctrine(enforcer, rule_id) -> Bool
```

## Usage Examples

### Basic Usage

```julia
using AdaptiveKernel.Kernel

# Kernel automatically initializes with Core Doctrine
kernel = init_kernel(Dict(
    "goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.5)]
))

# Check an action against doctrine
action = ActionProposal("safe_shell", 0.9f0, 0.1f0, 0.8f0, "low", "List files")
compliant, info = check_action_doctrine(kernel, action)

# Get statistics
stats = get_doctrine_enforcement_stats(kernel)
```

### Handling Violations

```julia
# Try an action that violates doctrine
violating_action = ActionProposal("rm_rf", 0.9f0, 0.1f0, 0.8f0, "high", "Delete everything")
compliant, violation_info = check_action_doctrine(kernel, violating_action)

# violation_info will contain:
# - rule_id: Which rule was violated
# - action: The violating action
# - severity: Pain value (0-1)
# - timestamp: When violation occurred
```

### Requesting Override

```julia
# Request override for a CONSTRAINT rule
success = request_doctrine_override_for_kernel(
    kernel,
    "constraint_002",  # No Data Destruction
    "User explicitly requested deletion of temp files",
    "executor_agent";
    is_emergency=false
)

# Override must be approved
if success
    # Find the override and approve it
    for override in kernel.doctrine_enforcer.overrides
        approve_doctrine_override_for_kernel(kernel, override.override_id, "auditor_agent")
    end
end
```

## Pain Integration

When a doctrine violation occurs, the severity value can be used to generate pain signals that integrate with the existing PainFeedback system:

```julia
# Get violation severity for pain calculation
function calculate_doctrine_pain(violation_info::Dict)::Float64
    return get(violation_info, "severity", 0.0)
end
```

## Security Considerations

1. **Strict Mode**: By default, INVARIANT rules cannot be overridden. This can be disabled in emergency situations.

2. **Audit Trail**: All violations and overrides are recorded in the enforcer's history.

3. **Defense in Depth**: Doctrine enforcement runs after permission checking, providing multiple layers of protection.

4. **Graceful Degradation**: Doctrine enforcement can be disabled if needed, but this should only be done in controlled environments.

## File Locations

- **Types**: [`adaptive-kernel/types.jl`](types.jl) - DoctrineRule, DoctrineEnforcer definitions
- **Kernel**: [`adaptive-kernel/kernel/Kernel.jl`](kernel/Kernel.jl) - Enforcement integration
- **Tests**: [`adaptive-kernel/tests/`](tests/) - Integration tests

## Related Components

- [Permission Handler](types.jl#PERMISSION-HANDLER) - First layer of action validation
- [Cognitive Friction Monitor](kernel/Metacognition.jl) - Tier 7 metacognition
- [PainFeedback](cognition/feedback/PainFeedback.jl) - Pain-driven feedback system
- [Thought Cycles](types.jl#PHASE-3:-NON-EXECUTING-THOUGHT-CYCLES) - Non-executing cognition for doctrine refinement
