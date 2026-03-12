"""
    Trust - Dynamic risk classification and user confirmation module
"""
module Trust

using Dates
using UUIDs
using Logging
using SHA
using Random
using JSON

# Export enums and types
export RiskLevel, TrustLevel
export RiskClassifier, TrustEvent

# Export secure trust types and functions
export SecureTrustLevel
export verify_trust, get_trust_secret, trust_secret_is_set
export create_secure_trust

# Export verification functions
export verify_and_get_trust, require_verified_trust, check_trust_transition_valid

# Export functions
export classify_action_risk, get_required_trust, record_decision!
export require_confirmation, confirm_action, deny_action
export check_pending_timeout, is_pending, get_pending_count

# Export secure confirmation gate (P0 C4 fix)
export SecureConfirmationGate, SecureToken, PendingSecureAction

# Include types first (enums)
include("Types.jl")

# Then include the implementation files
include("RiskClassifier.jl")

# Include secure confirmation gate (P0 C4 fix)
include("SecureConfirmationGate.jl")

end # module
