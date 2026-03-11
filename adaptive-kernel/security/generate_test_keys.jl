#!/usr/bin/env julia
# generate_test_keys.jl - Generate test keys without any package dependencies
#
# This generates simple test keys for development/testing only
# Uses only Base64 from stdlib

using Base64
using Random
using Dates

println("============================================================")
println("  ProjectX - Test Key Generation (Development Only)")
println("============================================================")
println()

# Generate random 32-byte keys (NOT CRYPTOGRAPHICALLY SECURE!)
public_key = rand(UInt8, 32)
secret_key = rand(UInt8, 64)

# Encode to base64
pk_b64 = base64encode(public_key)
sk_b64 = base64encode(secret_key)

# Save to files
output_dir = joinpath(@__DIR__, "keys")
mkpath(output_dir)

# Save public key
pk_path = joinpath(output_dir, "public_key.b64")
write(pk_path, pk_b64)
println("Public key saved to: $pk_path")

# Save secret key
sk_path = joinpath(output_dir, "secret_key.b64")
write(sk_path, sk_b64)
println("Secret key saved to: $sk_path")

# Save combined keypair
keypair_path = joinpath(output_dir, "keypair.txt")
open(keypair_path, "w") do io
    write(io, "public: $pk_b64\n")
    write(io, "secret: $sk_b64\n")
    write(io, "created: $(now(UTC))\n")
    write(io, "NOTE: Development/test keys only - NOT FOR PRODUCTION\n")
end
println("Keypair saved to: $keypair_path")
println()

println("============================================================")
println("  DEVELOPMENT KEYS GENERATED")
println("============================================================")
println()
println("Public Key (for Rust Shell):")
println("  $pk_b64")
println()
println("NEXT STEPS:")
println("  1. Copy the public key to Rust Shell's trusted keys")
println("  2. Test the signing pipeline")
println("  3. Replace with production keys for deployment")
println()
println("⚠️  WARNING: These are test keys - NOT for production use!")
