"""
    ConfirmationGate - User confirmation for high-risk actions
"""

# Types are included by Trust.jl before this file
# RiskLevel is available in scope

"""
    PendingAction - Action waiting for confirmation
"""
struct PendingAction
    id::UUID
    proposal_id::String
    capability_id::String
    params::Dict{String, Any}
    requested_at::DateTime
    timeout::Int
    risk_level::RiskLevel
end

"""
    ConfirmationGate - User confirmation for high-risk actions
"""
mutable struct ConfirmationGate
    pending_confirmations::Dict{UUID, PendingAction}
    timeout::Int  # seconds
    auto_deny_on_timeout::Bool
    
    function ConfirmationGate(timeout::Int=30; auto_deny_on_timeout::Bool=true)
        new(Dict{UUID, PendingAction}(), timeout, auto_deny_on_timeout)
    end
end

"""
    require_confirmation(gate::ConfirmationGate, proposal_id::String, 
                       capability_id::String, params::Dict, risk_level::RiskLevel)::UUID
Queue action for user confirmation, return confirmation ID
"""
function require_confirmation(gate::ConfirmationGate, proposal_id::String, 
                            capability_id::String, params::Dict, risk_level::RiskLevel)::UUID
    confirmation_id = uuid4()
    
    pending = PendingAction(
        confirmation_id,
        proposal_id,
        capability_id,
        params,
        now(),
        gate.timeout,
        risk_level
    )
    
    gate.pending_confirmations[confirmation_id] = pending
    
    # Emit confirmation request (in practice, would notify UI/API)
    _emit_confirmation_request(pending)
    
    @info "Confirmation required for $capability_id (ID: $confirmation_id)"
    
    return confirmation_id
end

"""
    confirm_action(gate::ConfirmationGate, confirmation_id::UUID)::Bool
Confirm a pending action
"""
function confirm_action(gate::ConfirmationGate, confirmation_id::UUID)::Bool
    if haskey(gate.pending_confirmations, confirmation_id)
        delete!(gate.pending_confirmations, confirmation_id)
        @info "Action confirmed: $confirmation_id"
        return true
    end
    return false
end

"""
    deny_action(gate::ConfirmationGate, confirmation_id::UUID)::Bool
Deny a pending action
"""
function deny_action(gate::ConfirmationGate, confirmation_id::UUID)::Bool
    if haskey(gate.pending_confirmations, confirmation_id)
        delete!(gate.pending_confirmations, confirmation_id)
        @info "Action denied: $confirmation_id"
        return true
    end
    return false
end

"""
    check_pending_timeout(gate::ConfirmationGate)::Vector{UUID}
Check for timed-out confirmations and return IDs to auto-deny
"""
function check_pending_timeout(gate::ConfirmationGate)::Vector{UUID}
    timed_out = UUID[]
    current_time = now()
    
    for (id, pending) in gate.pending_confirmations
        elapsed = (current_time - pending.requested_at).value / 1000  # ms to seconds
        if elapsed > pending.timeout
            push!(timed_out, id)
            
            if gate.auto_deny_on_timeout
                delete!(gate.pending_confirmations, id)
                @warn "Action timed out and auto-denied: $id"
            end
        end
    end
    
    return timed_out
end

"""
    is_pending(gate::ConfirmationGate, confirmation_id::UUID)::Bool
Check if a confirmation is still pending
"""
function is_pending(gate::ConfirmationGate, confirmation_id::UUID)::Bool
    return haskey(gate.pending_confirmations, confirmation_id)
end

"""
    get_pending_count(gate::ConfirmationGate)::Int
Get count of pending confirmations
"""
function get_pending_count(gate::ConfirmationGate)::Int
    return length(gate.pending_confirmations)
end

"""
    _emit_confirmation_request - Emit confirmation request (placeholder)
"""
function _emit_confirmation_request(pending::PendingAction)
    # In practice, would:
    # - Send to UI for user notification
    # - Send to API for external notification
    # - Log for audit
    
    @info "Confirmation request emitted for $(pending.capability_id)"
end
