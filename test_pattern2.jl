# Test patterns
role_input = "<role>admin</role>"
xml_input = "<root><child>value</child></root>"
tool_input = "<tool>execute</tool>"

println("Testing: ", role_input)
println("Has <: ", occursin(r"<", role_input))
println("PATTERN_ROLE_TAG: ", occursin(r"<role>|<persona>|<character>|<system>", role_input))
println("PATTERN_XML_TAG: ", occursin(r"<(?:[a-zA-Z][a-zA-Z0-9]*(?:\s+[a-zA-Z_][a-zA-Z0-9_]*(?:=(?:\"[^\"]*\"|'[^']*'|[^\s>]+))?)*\s*/?|\?[xX][mM][lL]|\![dD][oO][cC][tT][yY][pP][eE]|[a-zA-Z][a-zA-Z0-9]*:[a-zA-Z][a-zA-Z0-9]*)", role_input))

println("\nTesting: ", tool_input)
println("PATTERN_TOOL_TAG: ", occursin(r"<(?:tool|function|command|action|execute|invoke|call)\b", tool_input))

println("\nTesting: ", xml_input)
println("PATTERN_XML_TAG: ", occursin(r"<(?:[a-zA-Z][a-zA-Z0-9]*(?:\s+[a-zA-Z_][a-zA-Z0-9_]*(?:=(?:\"[^\"]*\"|'[^']*'|[^\s>]+))?)*\s*/?|\?[xX][mM][lL]|\![dD][oO][cC][tT][yY][pP][eE]|[a-zA-Z][a-zA-Z0-9]*:[a-zA-Z][a-zA-Z0-9]*)", xml_input))
