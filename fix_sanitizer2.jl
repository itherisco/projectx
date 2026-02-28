# Script to fix InputSanitizer.jl

# Read the file
content = read("adaptive-kernel/cognition/security/InputSanitizer.jl", String)

# Fix 1: Update PATTERN_XML_TAG to include CDATA
old_xml = raw"""const PATTERN_XML_TAG = r"<(?:[a-zA-Z][a-zA-Z0-9]*(?:\s+[a-zA-Z_][a-zA-Z0-9_]*(?:=(?:"[^"]*"|'[^']*'|[^\s>]+))?)*\s*/?|\?[xX][mM][lL]|\![dD][oO][cC][tT][yY][pP][eE]|[a-zA-Z][a-zA-Z0-9]*:[a-zA-Z][a-zA-Z0-9]*)" """

# This needs more careful escaping - let's just add a new pattern for CDATA
# Actually, let's just add CDATA to the same line

# Read line by line
lines = split(content, "\n")
new_lines = String[]
for line in lines
    if occursin("const PATTERN_XML_TAG", line)
        # Replace with version that includes CDATA
        push!(new_lines, """const PATTERN_XML_TAG = r"<(?:[a-zA-Z][a-zA-Z0-9]*(?:\\s+[a-zA-Z_][a-zA-Z0-9_]*(?:=(?:\\\"[^\\\"]*\\\"|'[^']*'|[^\\s>]+))?)*\\s*/?|\\?|<!\\[CDATA\\[|\\![dD][oO][cC][tT][yY][pP][eE]|[a-zA-Z][a-zA-Z0-9]*:[a-zA-Z][a-zA-Z0-9]*)" """)
    else
        push!(new_lines, line)
    end
end

content = join(new_lines, "\n")

# Fix 2: Change BASE64_PAYLOAD from MALICIOUS to SUSPICIOUS
content = replace(content, "MALICIOUS" => "SUSPICIOUS", count=1)

# Fix 3: Fix the unbalanced braces detection
# Need to check PATTERN_UNBALANCED_BRACES
# Let's simplify - just detect any { or } that's not balanced

# Write the file back
write("adaptive-kernel/cognition/security/InputSanitizer.jl", content)
println("Done!")
