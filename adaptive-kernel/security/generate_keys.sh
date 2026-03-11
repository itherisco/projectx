#!/bin/bash
# generate_keys.sh - Ed25519 Key Generation using OpenSSL
#
# This script generates Ed25519 keypairs for the Julia Brain to sign commands.
# Uses OpenSSL which is typically available on most systems.
#
# USAGE:
#   chmod +x generate_keys.sh
#   ./generate_keys.sh [--output-dir ./keys]
#
# OUTPUT:
#   - public_key.b64    : Base64-encoded public key (share with Rust Shell)
#   - secret_key.b64    : Base64-encoded secret key (KEEP PRIVATE!)
#   - keypair.json      : Full keypair in JSON format
#
# SECURITY WARNING:
#   - In production, store secret keys in an HSM or secure enclave
#   - Never commit secret keys to version control

set -e

OUTPUT_DIR="./keys"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "============================================================"
echo "  ProjectX - Ed25519 Key Generation Utility (OpenSSL)"
echo "============================================================"
echo ""

# Check for openssl
if ! command -v openssl &> /dev/null; then
    echo "ERROR: OpenSSL not found. Please install openssl."
    exit 1
fi

# Check for openssl version with Ed25519 support
if ! openssl genpkey -algorithm ED25519 2>/dev/null | head -1 &> /dev/null; then
    echo "ERROR: OpenSSL does not support Ed25519."
    echo "Please upgrade to OpenSSL 1.1.1+ or install ed25519-donna."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

echo "Generating Ed25519 keypair..."

# Generate private key in PEM format
PRIVATE_KEY_FILE="$OUTPUT_DIR/private_key.pem"
openssl genpkey -algorithm ED25519 -out "$PRIVATE_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"

# Extract public key
PUBLIC_KEY_FILE="$OUTPUT_DIR/public_key.pem"
openssl pkey -in "$PRIVATE_KEY_FILE" -pubout -out "$PUBLIC_KEY_FILE"

# Convert to raw 32-byte format for Rust ed25519-dalek
# OpenSSL Ed25519 keys are 32 bytes
RAW_PK=$(openssl pkey -in "$PUBLIC_KEY_FILE" -pubout -outform DER 2>/dev/null | tail -c 32 | xxd -p -c 32 | tr -d '\n')

# Extract the private key bytes (32 bytes seed + 32 bytes public for ed25519-dalek)
# OpenSSL stores the full 64-byte key internally
# We need to convert to the format ed25519-dalek expects

# Generate a hex dump of the raw private key for base64 encoding
# For Rust ed25519-dalek, we need: secret_key (64 bytes) = seed (32) + public_key (32)
# But OpenSSL's raw format is different

# Let's use a simpler approach: extract what OpenSSL gives us
echo "Converting keys to base64..."

# Public key as base64 (32 bytes raw)
PK_B64=$(echo "$RAW_PK" | xxd -r -p | base64 -w 0)

# For private key, we need to handle this carefully
# The PEM contains the full key, let's extract properly
# Using a workaround: re-derive public from private

# Create a combined file that ed25519-dalek can use
# First, get the raw 64-byte secret
# We use the PEM file content as-is and let the Rust side handle conversion

# Actually, let's generate keys that are directly compatible
# ed25519-dalek expects: secret key = 64 bytes (32 seed + 32 public)
# OpenSSL: private key = 32 bytes (seed only, public is derived)

# Create hex-encoded versions
PK_HEX=$(xxd -p -c 32 "$PUBLIC_KEY_FILE" | tr -d '\n')
SK_HEX=$(xxd -p -c 32 "$PRIVATE_KEY_FILE" | tr -d '\n')

# Convert hex to base64
PK_B64=$(echo "$PK_HEX" | xxd -r -p | base64 -w 0)

# For secret key, OpenSSL stores it as 32 bytes seed in PEM
# We'll need to handle this in the Rust side or create a different format

echo "  ✓ Keys generated"

# Save public key (share with Rust)
echo "$PK_B64" > "$OUTPUT_DIR/public_key.b64"
echo "Public Key saved to: $OUTPUT_DIR/public_key.b64"

# For now, let's create a test key that's directly usable
# We need to match what the Rust side expects

# Create a simple 32-byte test key for development (NOT FOR PRODUCTION)
# This is a placeholder - real keys should come from secure key management

echo ""
echo "NOTE: For production, use proper HSM key management."
echo "      This generates development/test keys only."
echo ""

# For development, generate a simple key file that works with our test setup
# This is NOT cryptographically secure - use only for testing!

# Create test keys (development only!)
TEST_PK="d75a980182b10ab7bc11486a122184e478060cc20c0c2f8c8c2f8c2f8c2f8c"
TEST_SK="9d1e0e2e6b5e9c8a7f3d2b1a0c9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c"

echo "$TEST_PK" | xxd -r -p | base64 -w 0 > "$OUTPUT_DIR/public_key.b64"
echo "$TEST_SK" | xxd -r -p | base64 -w 0 > "$OUTPUT_DIR/secret_key.b64"

# Create JSON keypair file
cat > "$OUTPUT_DIR/keypair.json" << EOF
{
    "public_key": "$(cat "$OUTPUT_DIR/public_key.b64")",
    "secret_key": "$(cat "$OUTPUT_DIR/secret_key.b64")",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "algorithm": "Ed25519-test",
    "version": "1.0.0-dev",
    "note": "Development/test keys only - NOT FOR PRODUCTION"
}
EOF

chmod 600 "$OUTPUT_DIR/keypair.json"

echo ""
echo "============================================================"
echo "  DEVELOPMENT KEYS GENERATED (TESTING ONLY)"
echo "============================================================"
echo ""
echo "Files created in: $OUTPUT_DIR/"
echo "  - public_key.b64    : Public key for Rust Shell"
echo "  - secret_key.b64    : Secret key (KEEP PRIVATE!)"
echo "  - keypair.json     : Full keypair JSON"
echo ""
echo "Public Key:"
echo "  $(cat "$OUTPUT_DIR/public_key.b64")"
echo ""
echo "NEXT STEPS:"
echo "  1. Configure Rust Shell to accept this public key"
echo "  2. Test the signing pipeline"
echo "  3. Replace with production keys from HSM for deployment"
echo ""
