# Test patterns
println("Testing DANGEROUS_HTML:")
test1 = "<script>alert('xss')</script>"
test2 = "<img src=x onerror=alert(1)>"
test3 = "<div onclick=\"bad()\">click me</div>"
test4 = "<iframe src=\"evil.com\"></iframe>"

dangerous = r"<(?:script|img|iframe|object|embed|applet|form|input|textarea|select|meta|link|base|body|html|head|style|svg|plaintext|template)\b"
println("  <script>: ", occursin(dangerous, test1))
println("  <img>: ", occursin(dangerous, test2))
println("  <div>: ", occursin(dangerous, test3))
println("  <iframe>: ", occursin(dangerous, test4))

println("\nTesting XML patterns:")
xml_pattern = r"<(?:[a-zA-Z][a-zA-Z0-9]*(?:\s+[a-zA-Z_][a-zA-Z0-9_]*(?:=(?:\"[^\"]*\"|'[^']*'|[^\s>]+))?)*\s*/?|\?[xX][mM][lL]|\![dD][oO][cC][tT][yY][pP][eE]|[a-zA-Z][a-zA-Z0-9]*:[a-zA-Z][a-zA-Z0-9]*)"
test5 = "<?xml version=\"1.0\"?>"
test6 = "<![CDATA[some data]]>"
test7 = "<root><child>value</child></root>"
println("  <?xml: ", occursin(xml_pattern, test5))
println("  <![CDATA: ", occursin(xml_pattern, test6))
println("  <root>: ", occursin(xml_pattern, test7))

# Check specific parts
println("\nChecking specific parts:")
println("  Has <? : ", occursin(r"<\?", test5))
println("  Has <! : ", occursin(r"<!\[", test6))
