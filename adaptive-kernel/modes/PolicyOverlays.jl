module PolicyOverlays

export permission_for_mode, Mode

abstract type Mode end
struct ObserverMode <: Mode end
struct AdvisorMode <: Mode end
struct OperatorMode <: Mode end
struct AutonomousSandboxMode <: Mode end

"""
permission_for_mode(mode::Mode, risk::String)::Bool
Policy overlay that enforces execution policies by mode.
"""
function permission_for_mode(::ObserverMode, risk::String)::Bool
    return false
end
function permission_for_mode(::AdvisorMode, risk::String)::Bool
    return false
end
function permission_for_mode(::OperatorMode, risk::String)::Bool
    # Operator: allow low and medium risk
    return risk == "low" || risk == "medium"
end
function permission_for_mode(::AutonomousSandboxMode, risk::String)::Bool
    # Sandbox can allow medium but not high by default
    return risk == "low" || risk == "medium"
end

end # module
