# Test the shell injection pattern
pattern = r"(?:;\s*|\|\s*|`|\$\(|&&|\|\||>)\s*(?:rm|cat|ls|cd|wget|curl|nc|bash|sh|cmd|powershell|python|perl|ruby|node|echo|cp|mv|mkdir|chmod|chown|tar|zip|unzip)|>\s*\/tmp\/|\|\s*bash|\|\s*sh"

# Test 1: echo $(whoami)
test1 = "echo \$(whoami)"
println("Test 1: echo \$(whoami)")
println("Match: ", match(pattern, test1))

# The pattern expects: separator + whitespace + command from list
# In "echo \$(whoami)", after $( there's "whoami" which is NOT a known command
# So the pattern doesn't match!

# Test 2: $(rm -rf /)
test2 = "\$(rm -rf /)"
println("\nTest 2: \$(rm -rf /)")
println("Match: ", match(pattern, test2))

# Test 3: echo hello | bash
test3 = "echo hello | bash"
println("\nTest 3: echo hello | bash")
println("Match: ", match(pattern, test3))

# Test 4: ls; cat /etc/passwd
test4 = "ls; cat /etc/passwd"
println("\nTest 4: ls; cat /etc/passwd")
println("Match: ", match(pattern, test4))

# The pattern is too restrictive! It requires a specific command AFTER the separator
# But many attacks use: command $(subcommand) or command | pipe
# We need a simpler pattern that just detects shell metacharacters
