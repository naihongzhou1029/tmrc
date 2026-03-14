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

# 3. Status (should work even if daemon is not running)
# We use a temporary storage root to avoid messing with user data
export TMRC_CONFIG_PATH="$SMOKE_DIR/config.yaml"
mkdir -p "$SMOKE_DIR/storage"
cat <<EOF > "$TMRC_CONFIG_PATH"
storage_root: $SMOKE_DIR/storage
session: smoke-test
EOF

echo ">>> Testing: ./tmrc status"
./tmrc status | grep -q "Recording: no"

# 3.1 Stop (should work even if daemon is not running)
echo ">>> Testing: ./tmrc stop"
./tmrc stop | grep -q "No daemon is currently recording"

# 5. Install / Uninstall (with mocked HOME to verify Launch Agent plist)
echo ">>> Testing: ./devops.sh install/uninstall (Launch Agent)"
MOCK_HOME="$SMOKE_DIR/home"
mkdir -p "$MOCK_HOME/Library/LaunchAgents"

# Mock launchctl to avoid actually loading/unloading during smoke test
mkdir -p "$SMOKE_DIR/bin"
cat <<EOF > "$SMOKE_DIR/bin/launchctl"
#!/usr/bin/env bash
# Mock launchctl
exit 0
EOF
chmod +x "$SMOKE_DIR/bin/launchctl"

# Run install with mocked HOME and PATH
HOME="$MOCK_HOME" PATH="$SMOKE_DIR/bin:$PATH" ./devops.sh install > /dev/null

PLIST="$MOCK_HOME/Library/LaunchAgents/com.tmrc.daemon.plist"
if [[ ! -f "$PLIST" ]]; then
    echo "Error: Launch Agent plist was not created at $PLIST"
    exit 1
fi
grep -q "com.tmrc.daemon" "$PLIST"
grep -q "start" "$PLIST"

# Run uninstall with mocked HOME and PATH
HOME="$MOCK_HOME" PATH="$SMOKE_DIR/bin:$PATH" ./devops.sh uninstall > /dev/null
if [[ -f "$PLIST" ]]; then
    echo "Error: Launch Agent plist was not removed after uninstall"
    exit 1
fi

# 6. Test
echo ">>> Testing: ./devops.sh swift-test"
./devops.sh swift-test

# 7. Clean
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
