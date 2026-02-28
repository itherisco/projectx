# Fix CDATA detection

content = read("adaptive-kernel/cognition/security/InputSanitizer.jl", String)

# The XML_TAG pattern needs to also match CDATA
# Let's add a separate check for CDATA in detect_xml_tags

old = """
    # Check for any XML/HTML tags (only if not already caught by role tags)
    # These are SUSPICIOUS per test requirements
    if occursin(PATTERN_XML_TAG, input)
        push!(errors, SanitizationError(
            :XML_TAG_DETECTED,
            "Detected XML/HTML tags in input",
            SUSPICIOUS
        ))
    end"""

new = """
    # Check for any XML/HTML tags (only if not already caught by role tags)
    # These are SUSPICIOUS per test requirements
    if occursin(PATTERN_XML_TAG, input) || occursin(r\"<!\", input)
        push!(errors, SanitizationError(
            :XML_TAG_DETECTED,
            "Detected XML/HTML tags in input",
            SUSPICIOUS
        ))
    end"""

content = replace(content, old => new)

write("adaptive-kernel/cognition/security/InputSanitizer.jl", content)
println("Fixed CDATA detection")
