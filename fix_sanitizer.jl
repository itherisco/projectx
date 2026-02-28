# Script to fix InputSanitizer.jl

# Read the file
content = read("adaptive-kernel/cognition/security/InputSanitizer.jl", String)

# Fix 1: Update PATTERN_XML_TAG to include CDATA
old_xml = r"const PATTERN_XML_TAG = r\"<(?:[a-zA-Z][a-zA-Z0-9]*(?:\s+[a-zA-Z_][a-zA-Z0-9_]*(?:=(?:\\\"[^\\\"]*\\\"|'[^']*'|[^\s>]+))?)*\s*/?|\?[xX][mM][lL]|\![dD][oO][cC][tT][yY][pP][eE]|[a-zA-Z][a-zA-Z0-9]*:[a-zA-Z][a-zA-Z0-9]*)\""
new_xml = raw"""const PATTERN_XML_TAG = r"<(?:[a-zA-Z][a-zA-Z0-9]*(?:\s+[a-zA-Z_][a-zA-Z0-9_]*(?:=(?:"[^"]*"|'[^']*'|[^\s>]+))?)*\s*/?|\?|<!\[CDATA\[|\![dD][oO][cC][tT][yY][pP][eE]|[a-zA-Z][a-zA-Z0-9]*:[a-zA-Z][a-zA-Z0-9]*)" """

content = replace(content, old_xml => new_xml)

# Fix 2: Change BASE64_PAYLOAD from MALICIOUS to SUSPICIOUS
content = replace(content, "if length(match.match) > MAX_BASE64_LENGTH\n            push!(errors, SanitizationError(\n                :BASE64_PAYLOAD,\n                \"Detected suspicious base64-encoded content\",\n                MALICIOUS\n            ))" =>
                   "if length(match.match) > MAX_BASE64_LENGTH\n            push!(errors, SanitizationError(\n                :BASE64_PAYLOAD,\n                \"Detected suspicious base64-encoded content\",\n                SUSPICIOUS\n            ))")

# Write the file back
write("adaptive-kernel/cognition/security/InputSanitizer.jl", content)
println("Done!")
