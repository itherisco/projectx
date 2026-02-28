# Fix the unbalanced quotes detection

content = read("adaptive-kernel/cognition/security/InputSanitizer.jl", String)

# Find and replace the section
old = """
    if braces_open != braces_close || brackets_open != brackets_close
        push!(errors, SanitizationError(
            :UNBALANCED_BRACES,
            "Input contains unbalanced braces or brackets",
            MALICIOUS  # Changed from SUSPICIOUS to MALICIOUS
        ))
    end
    
    return errors
end"""

new = """
    if braces_open != braces_close || brackets_open != brackets_close
        push!(errors, SanitizationError(
            :UNBALANCED_BRACES,
            "Input contains unbalanced braces or brackets",
            MALICIOUS  # Changed from SUSPICIOUS to MALICIOUS
        ))
    end
    
    # Check for unbalanced quotes
    double_quotes = count(c -> c == '"', input)
    single_quotes = count(c -> c == '\'', input)
    
    if double_quotes % 2 != 0 || single_quotes % 2 != 0
        push!(errors, SanitizationError(
            :UNBALANCED_QUOTES,
            "Input contains unbalanced quotes",
            MALICIOUS
        ))
    end
    
    return errors
end"""

content = replace(content, old => new)

write("adaptive-kernel/cognition/security/InputSanitizer.jl", content)
println("Fixed unbalanced quotes detection")
