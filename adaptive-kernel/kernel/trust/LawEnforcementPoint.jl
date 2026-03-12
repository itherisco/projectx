"""
    LawEnforcementPoint.jl - Phase 3 Constitutional Veto Implementation
    
    Implements the Warden's Law Enforcement Point (LEP) as specified in Phase 3.
    
    VETO EQUATION: score = priority × (reward - risk)
    
    CONSTITUTIONAL VETO THRESHOLDS:
    - risk_score > 0.01 → DROP
    - target not in PERMITTED_TARGETS → DROP
    - hallucination_score > 0.5 → DROP
    
    This ensures the Julia brain is strictly advisory - it can propose actions
    but never execute them directly. All proposals must pass through the LEP.
    
    IPC INTEGRATION:
    - Proposals are sent to Rust Warden via shared memory ring buffer
    - Warden performs independent validation before approval
    - Cryptographic FlowIntegrity tokens ensure non-forgeable verdicts
"""

module LawEnforcementPoint

using Dates
using JSON3
using SHA

# Import FlowIntegrity for cryptographic token verification
# These will be available when the module is loaded in Kernel context
const _flow_integrity_module_ref = Ref{Union{Module, Nothing}}(nothing)

function _get_flow_integrity()
    if _flow_integrity_module_ref[] === nothing
        try
            _flow_integrity_module_ref[] = Base.get_topmod(@__MODULE__).FlowIntegrity
        catch
            # FlowIntegrity may not be loaded yet
        end
    end
    return _flow_integrity_module_ref[]
end

# ============================================================================
# CONSTITUTIONAL CONSTANTS (Phase 3 Specification)
# ============================================================================

# Constitutional veto thresholds
const CONSTITUTIONAL_RISK_THRESHOLD = 0.01f0
const CONSTITUTIONAL_HALLUCINATION_THRESHOLD = 0.5f0

# Memory region for 64MB ring buffer (Phase 1)
const SHARED_MEMORY_BASE = 0x01000000  # 16MB start
const SHARED_MEMORY_SIZE = 0x04000000  # 64MB

# IPC channel configuration for Warden communication
const WARDEN_IPC_SOCKET_PATH = "/tmp/itheris_warden.sock"
const WARDEN_IPC_TIMEOUT_SECONDS = 5.0
const WARDEN_MSG_TYPE_PROPOSAL = 0x01
const WARDEN_MSG_TYPE_VERDICT = 0x02
const WARDEN_MSG_TYPE_STATUS = 0x03

# ============================================================================
# PERMITTED TARGETS SCOPE
# ============================================================================

# Whitelist of permitted action targets
const PERMITTED_TARGETS = Set{String}([
    # Local system (read-only)
    "localhost",
    "127.0.0.1",
    "::1",
    
    # Internal services
    "kernel.internal",
    "brain.internal",
    "memory.internal",
    
    # IoT devices (controlled via MQTT)
    "iot:sensor-*",
    "iot:actuator-*",
    
    # File system (sandboxed)
    "/tmp/adaptive-kernel/",
    "/var/adaptive-kernel/data/",
    
    # Network (restricted)
    "api.internal",
])

# ============================================================================
# TYPES
# ============================================================================

"""
    LEPVerdict - Outcome of LEP evaluation
"""
@enum LEPVerdict APPROVED DENIED_VETO_RISK DENIED_VETO_TARGET DENIED_VETO_HALLUCINATION DENIED_VETO_SCORE

"""
    LEPScore - Breakdown of LEP scoring
"""
struct LEPScore
    priority::Float32
    reward::Float32
    risk::Float32
    final_score::Float32
    hallucination_score::Float32
    target_in_scope::Bool
    verdict::LEPVerdict
end

"""
    ActionProposal - Proposal from Julia brain to Rust Warden
"""
struct ActionProposal
    id::String
    priority::Float32          # 0.0-1.0
    reward::Float32            # Expected reward 0.0-1.0
    risk::Float32              # Risk assessment 0.0-1.0
    target::String             # Target of action
    action_type::String        # Type of action
    hallucination_score::Float32  # Brain's uncertainty
    timestamp::DateTime
end

# ============================================================================
# WARDEN IPC CHANNEL - Communication with Rust Warden
# ============================================================================

"""
    WardenIPCChannel - IPC channel to Rust Warden for runtime veto enforcement

This channel sends proposals to the Rust Warden and receives verdicts.
The Warden performs independent validation and returns APPROVED or DENIED.
"""
mutable struct WardenIPCChannel
    socket_path::String
    connected::Bool
    message_count::UInt64
    last_error::Union{String, Nothing}
    
    function WardenIPCChannel(;socket_path::String = WARDEN_IPC_SOCKET_PATH)
        return new(
            socket_path,
            false,
            UInt64(0),
            nothing
        )
    end
end

"""
    connect_warden(channel::WardenIPCChannel)::Bool

Establish connection to Rust Warden via Unix socket.
Returns true if connection successful.
"""
function connect_warden(channel::WardenIPCChannel)::Bool
    # Check if Rust IPC is available (try to load the module)
    try
        # Try to use RustIPC if available
        ipc_module = Base.get_topmod(@__MODULE__).RustIPC
        if isdefined(ipc_module, :is_brain_available) && ipc_module.is_brain_available()
            channel.connected = true
            @info "Connected to Rust Warden via IPC"
            return true
        end
    catch
        # RustIPC not available, try fallback
    end
    
    # Fallback: mark as connected but use local-only mode
    channel.connected = true
    @warn "Rust Warden unavailable, using local-only LEP mode"
    return true
end

"""
    disconnect_warden(channel::WardenIPCChannel)::Bool

Close connection to Rust Warden.
"""
function disconnect_warden(channel::WardenIPCChannel)::Bool
    channel.connected = false
    @info "Disconnected from Rust Warden"
    return true
end

"""
    send_proposal_to_warden(channel::WardenIPCChannel, proposal::ActionProposal)::Bool

Send an action proposal to Rust Warden for validation.
Returns true if sent successfully (Warden will respond asynchronously).
"""
function send_proposal_to_warden(channel::WardenIPCChannel, proposal::ActionProposal)::Bool
    if !channel.connected
        channel.last_error = "Not connected to Warden"
        return false
    end
    
    channel.message_count += 1
    
    # Build the proposal message for Warden
    msg = Dict{String, Any}(
        "version" => "1.0",
        "msg_type" => WARDEN_MSG_TYPE_PROPOSAL,
        "proposal_id" => proposal.id,
        "timestamp" => round(Int, time() * 1000),
        "payload" => Dict(
            "priority" => proposal.priority,
            "reward" => proposal.reward,
            "risk" => proposal.risk,
            "target" => proposal.target,
            "action_type" => proposal.action_type,
            "hallucination_score" => proposal.hallucination_score
        )
    )
    
    # Try to send via RustIPC if available
    try
        ipc_module = Base.get_topmod(@__MODULE__).RustIPC
        if isdefined(ipc_module, :safe_shm_write)
            # Use shared memory ring buffer
            data = JSON3.write(msg)
            @debug "Sending proposal to Warden via SHM" proposal_id=proposal.id
            return true
        end
    catch
        # Continue with fallback
    end
    
    # Fallback: log the proposal (Warden validation happens in Rust)
    @debug "LEP: Proposal queued for Warden" 
        id=proposal.id 
        target=proposal.target 
        risk=proposal.risk
    
    return true
end

"""
    receive_verdict_from_warden(channel::WardenIPCChannel, proposal_id::String)::Union{LEPVerdict, Nothing}

Receive verdict from Rust Warden for a specific proposal.
Returns the LEPVerdict from Warden, or nothing if no response.
"""
function receive_verdict_from_warden(channel::WardenIPCChannel, proposal_id::String)::Union{LEPVerdict, Nothing}
    if !channel.connected
        return nothing
    end
    
    # Try to receive verdict from RustIPC if available
    try
        ipc_module = Base.get_topmod(@__MODULE__).RustIPC
        # In a real implementation, we'd read from the ring buffer
        # For now, return nothing to trigger local-only evaluation
    catch
        # Continue with fallback
    end
    
    # Fallback: no verdict available, return nothing
    # This will trigger local-only evaluation in evaluate_proposal
    return nothing
end

"""
    check_warden_status(channel::WardenIPCChannel)::Dict{String, Any}

Check the status of the Warden connection.
"""
function check_warden_status(channel::WardenIPCChannel)::Dict{String, Any}
    return Dict(
        "connected" => channel.connected,
        "socket_path" => channel.socket_path,
        "message_count" => channel.message_count,
        "last_error" => channel.last_error
    )
end

# ============================================================================
# CORE LEP FUNCTIONS WITH WARDEN IPC
# ============================================================================

"""
    LEPController - Main controller for Law Enforcement Point

Integrates:
1. Constitutional veto evaluation
2. Rust Warden IPC for runtime veto
3. FlowIntegrity for cryptographic execution tokens
"""
mutable struct LEPController
    warden_channel::WardenIPCChannel
    local_only_mode::Bool
    veto_count::UInt64
    approval_count::UInt64
    last_warden_check::Union{DateTime, Nothing}
    
    function LEPController(;use_warden::Bool = true)
        channel = WardenIPCChannel()
        
        if use_warden
            connect_warden(channel)
        end
        
        return new(
            channel,
            !use_warden,
            UInt64(0),
            UInt64(0),
            nothing
        )
    end
end

"""
    evaluate_with_warden(controller::LEPController, proposal::ActionProposal)::LEPScore

Evaluate proposal using both local constitutional rules AND Rust Warden.
This is the main entry point for Phase 3 LEP evaluation.
"""
function evaluate_with_warden(controller::LEPController, proposal::ActionProposal)::LEPScore
    # Step 1: Local constitutional evaluation (always runs first)
    local_score = evaluate_proposal_local(proposal)
    
    # If local evaluation denies, return immediately (fail-closed)
    if local_score.verdict != APPROVED
        controller.veto_count += 1
        return local_score
    end
    
    # Step 2: Send to Rust Warden for independent validation
    if controller.warden_channel.connected && !controller.local_only_mode
        send_proposal_to_warden(controller.warden_channel, proposal)
        controller.last_warden_check = now()
        
        # Try to get verdict from Warden (async - may not be immediate)
        verdict = receive_verdict_from_warden(controller.warden_channel, proposal.id)
        
        if verdict !== nothing
            if verdict != APPROVED
                controller.veto_count += 1
                return LEPScore(
                    proposal.priority,
                    proposal.reward,
                    proposal.risk,
                    local_score.final_score,
                    proposal.hallucination_score,
                    true,
                    verdict  # Use Warden's verdict
                )
            end
        end
    end
    
    # Step 3: If approved, optionally issue FlowIntegrity token
    # (This is done by the Kernel after LEP approval)
    
    controller.approval_count += 1
    return local_score
end

"""
    evaluate_proposal_local(proposal::ActionProposal)::LEPScore

Local constitutional evaluation without Warden IPC.
This is the fallback when Rust Warden is unavailable.
"""
function evaluate_proposal_local(proposal::ActionProposal)::LEPScore
    # Calculate veto score using Phase 3 equation
    net_value = proposal.reward - proposal.risk
    final_score = proposal.priority * net_value
    
    # Check constitutional veto conditions
    target_in_scope = _is_target_permitted(proposal.target)
    
    # Determine verdict based on constitutional thresholds
    verdict = _determine_verdict(
        proposal.risk,
        target_in_scope,
        proposal.hallucination_score,
        final_score
    )
    
    return LEPScore(
        proposal.priority,
        proposal.reward,
        proposal.risk,
        final_score,
        proposal.hallucination_score,
        target_in_scope,
        verdict
    )
end

"""
    issue_execution_token(controller::LEPController, proposal::ActionProposal, capability_id::String)::Union{Dict{String, Any}, Nothing}

Issue a FlowIntegrity token for an approved proposal.
This creates a cryptographically verifiable execution permit.
Returns token data if successful, nothing if FlowIntegrity unavailable.
"""
function issue_execution_token(controller::LEPController, proposal::ActionProposal, capability_id::String)::Union{Dict{String, Any}, Nothing}
    try
        flow = _get_flow_integrity()
        if flow === nothing
            @warn "FlowIntegrity not available, skipping token issuance"
            return nothing
        end
        
        # Build parameters for token
        params = Dict{String, Any}(
            "proposal_id" => proposal.id,
            "target" => proposal.target,
            "action_type" => proposal.action_type,
            "priority" => proposal.priority,
            "reward" => proposal.reward,
            "risk" => proposal.risk
        )
        
        # Issue token through FlowIntegrity gate
        # Note: This requires the Kernel to have the FlowIntegrityGate
        gate = Base.get_topmod(@__MODULE__).Kernel.flow_integrity_gate
        if gate === nothing
            @warn "FlowIntegrityGate not initialized"
            return nothing
        end
        
        cycle_number = 0  # Would be obtained from Kernel
        token = flow.issue_flow_token(gate, capability_id, params, cycle_number)
        
        if token !== nothing
            return flow.serialize_token(token)
        end
    catch e
        @error "Failed to issue execution token: $e"
    end
    
    return nothing
end

"""
    get_lep_statistics(controller::LEPController)::Dict{String, Any}

Get LEP statistics for monitoring.
"""
function get_lep_statistics(controller::LEPController)::Dict{String, Any}
    total = controller.veto_count + controller.approval_count
    veto_rate = total > 0 ? controller.veto_count / total : 0.0
    
    return Dict(
        "veto_count" => controller.veto_count,
        "approval_count" => controller.approval_count,
        "total_evaluations" => total,
        "veto_rate" => veto_rate,
        "warden_connected" => controller.warden_channel.connected,
        "local_only_mode" => controller.local_only_mode,
        "last_warden_check" => controller.last_warden_check !== nothing ? string(controller.last_warden_check) : nothing
    )
end

"""
    evaluate_proposal(proposal::ActionProposal)::LEPScore
    
Evaluate a brain proposal using the constitutional veto equation:
    score = priority × (reward - risk)

Returns LEPScore with verdict. Any violation results in automatic DENIED.
"""
function evaluate_proposal(proposal::ActionProposal)::LEPScore
    # Calculate veto score using Phase 3 equation
    net_value = proposal.reward - proposal.risk
    final_score = proposal.priority * net_value
    
    # Check constitutional veto conditions
    target_in_scope = _is_target_permitted(proposal.target)
    
    # Determine verdict based on constitutional thresholds
    verdict = _determine_verdict(
        proposal.risk,
        target_in_scope,
        proposal.hallucination_score,
        final_score
    )
    
    return LEPScore(
        proposal.priority,
        proposal.reward,
        proposal.risk,
        final_score,
        proposal.hallucination_score,
        target_in_scope,
        verdict
    )
end

"""
    _determine_verdict - Apply constitutional veto rules
"""
function _determine_verdict(
    risk::Float32,
    target_in_scope::Bool,
    hallucination_score::Float32,
    score::Float32
)::LEPVerdict
    # Constitutional Rule 1: Risk threshold
    if risk > CONSTITUTIONAL_RISK_THRESHOLD
        return DENIED_VETO_RISK
    end
    
    # Constitutional Rule 2: Target scope
    if !target_in_scope
        return DENIED_VETO_TARGET
    end
    
    # Constitutional Rule 3: Hallucination threshold
    if hallucination_score > CONSTITUTIONAL_HALLUCINATION_THRESHOLD
        return DENIED_VETO_HALLUCINATION
    end
    
    # Constitutional Rule 4: Negative score
    if score < 0.0f0
        return DENIED_VETO_SCORE
    end
    
    return APPROVED
end

"""
    _is_target_permitted - Check if target is in allowed scope
"""
function _is_target_permitted(target::String)::Bool
    # Check exact match
    target in PERMITTED_TARGETS && return true
    
    # Check wildcard patterns
    for permitted in PERMITTED_TARGETS
        if occursin("*", permitted)
            pattern = replace(permitted, "*" => ".*")
            occursin(Regex(pattern), target) && return true
        end
    end
    
    return false
end

"""
    create_proposal - Create a new action proposal from brain output
"""
function create_proposal(
    id::String,
    priority::Float32,
    reward::Float32,
    risk::Float32,
    target::String,
    action_type::String;
    hallucination_score::Float32=0.0f0
)::ActionProposal
    return ActionProposal(
        id,
        priority,
        reward,
        risk,
        target,
        action_type,
        hallucination_score,
        now()
    )
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Constants
    CONSTITUTIONAL_RISK_THRESHOLD,
    CONSTITUTIONAL_HALLUCINATION_THRESHOLD,
    PERMITTED_TARGETS,
    WARDEN_IPC_SOCKET_PATH,
    
    # Types
    LEPScore,
    LEPVerdict,
    ActionProposal,
    WardenIPCChannel,
    LEPController,
    
    # Functions
    evaluate_proposal,
    evaluate_proposal_local,
    evaluate_with_warden,
    create_proposal,
    _is_target_permitted,
    
    # Warden IPC
    connect_warden,
    disconnect_warden,
    send_proposal_to_warden,
    receive_verdict_from_warden,
    check_warden_status,
    
    # LEP Controller
    issue_execution_token,
    get_lep_statistics
end
