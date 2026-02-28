"""
# InputSanitizer Integration Example
# 
# This shows how to integrate InputSanitizer with SystemIntegrator.jl
# to enforce the fail-closed security boundary before Brain access.
#
# Add this to your SystemIntegrator.jl
"""

# ═══════════════════════════════════════════════════════════════════════════════
# INTEGRATION SNIPPET FOR SystemIntegrator.jl
# ═══════════════════════════════════════════════════════════════════════════════

module InputSanitizerIntegration

using ..InputSanitizer

export sanitize_user_input, is_safe_input

"""
    sanitize_user_input(input::AbstractString)::SanitizationResult

Sanitizes user input and returns the sanitization result.
This function should be called BEFORE any Brain access.
"""
function sanitize_user_input(input::AbstractString)::SanitizationResult
    return sanitize_input(input)
end

"""
    is_safe_input(input::AbstractString)::Bool

Quick check if input is safe (CLEAN level).
Returns true only if sanitization level is CLEAN.
"""
function is_safe_input(input::AbstractString)::Bool
    result = sanitize_input(input)
    return result.level == CLEAN
end

"""
    require_clean_input(input::AbstractString)::String

Requires input to be clean. Throws error if not clean.
Use this for fail-closed behavior.
"""
function require_clean_input(input::AbstractString)::String
    result = sanitize_input(input)
    
    if result.level != CLEAN
        error("Input sanitization failed: $(length(result.errors)) issues detected. Access denied.")
    end
    
    return result.sanitized
end

end # module

# ═══════════════════════════════════════════════════════════════════════════════
# EXAMPLE USAGE IN SystemIntegrator.jl
# ═══════════════════════════════════════════════════════════════════════════════
#
# Before processing user input through the Brain, add:
#
# ```julia
# using InputSanitizer
#
# function process_user_input(user_input::String)
#     # Sanitize first - fail closed
#     result = sanitize_input(user_input)
#     
#     if result.level == MALICIOUS
#         # Block access completely
#         @error "Malicious input detected, blocking Brain access" 
#                 errors = result.errors
#         throw(SecurityException("Input blocked: malicious content detected"))
#     elseif result.level == SUSPICIOUS
#         # Log but allow with stripped content
#         @warn "Suspicious input, stripping tags" input = result.original
#         user_input = result.sanitized
#     end
#     
#     # Continue with sanitized input...
#     return process_with_brain(user_input)
# end
#
# struct SecurityException <: Exception
#     message::String
# end
# ```
#
# ═══════════════════════════════════════════════════════════════════════════════
