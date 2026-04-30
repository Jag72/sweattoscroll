#!/bin/bash
# build_policy.sh
# Compiles the OPA Rego policy to WebAssembly and generates the integrity manifest.
#
# Prerequisites:
#   brew install opa
#   pip install pyopenssl  (optional, for ECDSA signing)
#
# Usage:
#   ./scripts/build_policy.sh
#
# Output:
#   app/Sweat2Scroll/Resources/contract.wasm
#   app/Sweat2Scroll/Resources/contract_manifest.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
POLICY_DIR="$PROJECT_ROOT/app/Sweat2Scroll/Policy"
RESOURCES_DIR="$PROJECT_ROOT/app/Sweat2Scroll/Resources"
BUILD_DIR="$PROJECT_ROOT/.build/opa"

echo "═══════════════════════════════════════════════════════════════"
echo "  Sweat2Scroll — OPA Policy Build"
echo "═══════════════════════════════════════════════════════════════"

# Check prerequisites
if ! command -v opa &> /dev/null; then
    echo "❌ OPA CLI not found. Install with: brew install opa"
    exit 1
fi

echo "📋 OPA version: $(opa version | head -1)"

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Compile Rego to Wasm bundle
echo ""
echo "🔨 Compiling Rego policy to WebAssembly..."
opa build \
    -t wasm \
    -e "sweat2scroll/contract/allow" \
    -e "sweat2scroll/contract/requires_grace" \
    -o "$BUILD_DIR/bundle.tar.gz" \
    "$POLICY_DIR/fitness_policy.rego"

echo "   Bundle size: $(du -h "$BUILD_DIR/bundle.tar.gz" | cut -f1)"

# Step 2: Extract contract.wasm from the bundle
echo "📦 Extracting contract.wasm from bundle..."
cd "$BUILD_DIR"
tar xzf bundle.tar.gz

if [ ! -f "$BUILD_DIR/policy.wasm" ]; then
    echo "❌ policy.wasm not found in bundle. Check entrypoint paths."
    echo "   Bundle contents:"
    tar tzf bundle.tar.gz
    exit 1
fi

# Copy to Resources
cp "$BUILD_DIR/policy.wasm" "$RESOURCES_DIR/contract.wasm"
echo "   Wasm size: $(du -h "$RESOURCES_DIR/contract.wasm" | cut -f1)"

# Step 3: Compute SHA-256 hash
echo ""
echo "🔐 Computing SHA-256 integrity hash..."
HASH=$(shasum -a 256 "$RESOURCES_DIR/contract.wasm" | awk '{print $1}')
echo "   Hash: $HASH"

# Step 4: Generate manifest
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OPA_VERSION=$(opa version | head -1 | sed 's/[^0-9.]//g')

cat > "$RESOURCES_DIR/contract_manifest.json" << MANIFEST_EOF
{
  "sha256": "$HASH",
  "signature": null,
  "public_key": null,
  "build_date": "$BUILD_DATE",
  "opa_version": "$OPA_VERSION"
}
MANIFEST_EOF

echo "   Manifest written to contract_manifest.json"

# Step 5: Validate the compiled policy
echo ""
echo "🧪 Validating compiled policy..."
opa eval \
    -d "$POLICY_DIR/fitness_policy.rego" \
    -i /dev/stdin \
    "data.sweat2scroll.contract" << INPUT_EOF
{
  "current_active_calories": 500,
  "current_steps": 10000,
  "daily_calorie_goal": 400,
  "daily_steps_goal": 8000,
  "goal_currency": "activeCalories",
  "override_active": false,
  "override_expiration": 0,
  "current_time": $(date +%s),
  "data_staleness_seconds": 0,
  "ui_timer_expired": false,
  "time_drift_detected": false,
  "hard_cap": 1000
}
INPUT_EOF

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Policy build complete!"
echo "  📄 contract.wasm  → $RESOURCES_DIR/contract.wasm"
echo "  📋 manifest       → $RESOURCES_DIR/contract_manifest.json"
echo "  🔐 SHA-256        → ${HASH:0:16}..."
echo "═══════════════════════════════════════════════════════════════"
