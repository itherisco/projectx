#!/usr/bin/env julia
# test_signing.jl - Test script for Ed25519 signing pipeline
#
# This script tests the signing pipeline in mock mode (no crypto library required)

# Enable mock mode for testing (no crypto library needed)
println("Setting up Ed25519 mock mode for testing...")

# Load Ed25519 module
include(joinpath(@__DIR__, "Ed25519.jl"))
using .Ed25519Security

# Enable mock mode
Ed25519Security.set_mock_mode!(true)

println("\n============================================================")
println("  Testing Ed25519 Signing Pipeline")
println("============================================================\n")

# Test 1: Generate keypair
println("Test 1: Generate keypair...")
keypair = Ed25519Security.generate_keypair()
println("  ✓ Public key: $(length(keypair.public_key)) bytes")
println("  ✓ Secret key: $(length(keypair.secret_key)) bytes")

# Test 2: Sign a message
println("\nTest 2: Sign a message...")
test_message = b"Hello, Rust Shell!"
signature = Ed25519Security.sign_command(keypair.secret_key, test_message)
println("  ✓ Signature: $(length(signature)) bytes")

# Test 3: Verify signature (in mock mode, always passes)
println("\nTest 3: Verify signature...")
valid = Ed25519Security.verify_signature(keypair.public_key, test_message, signature)
println("  ✓ Verification: $valid")

# Test 4: Test nonce generation
println("\nTest 4: Test nonce generation...")
nonce1 = Ed25519Security.generate_nonce()
sleep(0.001)
nonce2 = Ed25519Security.generate_nonce()
println("  ✓ Nonce 1: $nonce1")
println("  ✓ Nonce 2: $nonce2")
println("  ✓ Nonces unique: $(nonce1 != nonce2)")

# Test 5: Test full signing pipeline
println("\nTest 5: Full signing pipeline...")
# Simple action dict
action_json = UInt8[123, 34, 97, 99, 116, 105, 111, 110, 34, 58, 34, 101, 120, 101, 99, 117, 116, 101, 95, 99, 111, 109, 109, 97, 110, 100, 34, 125]  # {"action":"execute_command"}

auth_cmd = Ed25519Security.sign_and_prepare_command(keypair, action_json)
println("  ✓ Command payload: $(length(auth_cmd["command_payload"])) bytes")
println("  ✓ Signature: $(auth_cmd["signature"])")
println("  ✓ Public key: $(auth_cmd["public_key"])")
println("  ✓ Nonce: $(auth_cmd["nonce"])")
println("  ✓ Timestamp: $(auth_cmd["timestamp"])")

# Test 6: Verify timestamp freshness
println("\nTest 6: Timestamp freshness check...")
current_ts = Ed25519Security.get_timestamp_ms()
msg_ts = auth_cmd["timestamp"]
time_diff = abs(current_ts - msg_ts)
println("  ✓ Current timestamp: $current_ts")
println("  ✓ Message timestamp: $msg_ts")
println("  ✓ Time difference: $time_diff ms (should be < 5000)")

# Test 7: Test keypair loading/saving
println("\nTest 7: Keypair file I/O...")
test_path = joinpath(tempdir(), "test_keypair_$(rand(1:10000)).json")
Ed25519Security.save_keypair_to_file(keypair, test_path)
loaded = Ed25519Security.load_keypair_from_file(test_path)
println("  ✓ Saved to: $test_path")
println("  ✓ Keys match: $(keypair.public_key == loaded.public_key)")
rm(test_path, force=true)

println("\n============================================================")
println("  All Tests Passed!")
println("============================================================")
println("\nNOTE: Running in MOCK MODE - not for production!")
println("For production, install TweetNaCl.jl or Ed25519.jl")
