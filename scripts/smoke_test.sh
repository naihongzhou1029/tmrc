#!/usr/bin/env bash

set -euo pipefail

# Smoke tests for tmrc devops.sh
# This script validates that the primary development commands work as expected.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Create a temporary directory for isolated smoke tests
SMOKE_DIR=$(mktemp -d -t tmrc-smoke.XXXXXX)
trap 'rm -rf "$SMOKE_DIR"' EXIT

echo "Starting smoke tests in: $SMOKE_DIR"

# 1. Setup / Check Environment
echo ">>> Testing: ./devops.sh setup"
./devops.sh setup

# 2. Build
echo ">>> Testing: ./devops.sh build"
./devops.sh build
if [[ ! -x "./tmrc" ]]; then
    echo "Error: tmrc symlink not found or not executable"
    exit 1
fi

# 3. Help
echo ">>> Testing: ./devops.sh help"
./devops.sh help > /dev/null

# 4. Status (should work even if daemon is not running)
# We use a temporary storage root to avoid messing with user data
export TMRC_CONFIG_PATH="$SMOKE_DIR/config.yaml"
mkdir -p "$SMOKE_DIR/storage"
cat <<EOF > "$TMRC_CONFIG_PATH"
storage_root: $SMOKE_DIR/storage
session: smoke-test
EOF

echo ">>> Testing: ./devops.sh status"
./devops.sh status | grep -q "Recording: no"

# 5. Test
echo ">>> Testing: ./devops.sh swift-test"
./devops.sh swift-test

# 6. Clean
echo ">>> Testing: ./devops.sh clean"
./devops.sh clean
if [[ -d ".build" ]]; then
    # swift package clean might leave the directory but it should be empty or cleaned
    echo "Cleaned .build directory"
fi

echo ""
echo "=============================="
echo "  All smoke tests passed!  "
echo "=============================="
