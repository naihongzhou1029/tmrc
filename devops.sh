#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

readonly GREEN="\033[0;32m"
readonly YELLOW="\033[1;33m"
readonly RED="\033[0;31m"
readonly NC="\033[0m"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ok() {
  echo -e "${GREEN}[ok]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[warn]${NC} $1"
}

err() {
  echo -e "${RED}[error]${NC} $1" >&2
}

usage() {
  cat <<'EOF'
tmrc development command center

Usage:
  ./devops.sh <command>

Commands:
  setup       Validate local development prerequisites
  check-env   Alias of setup
  build       Run swift build
  test        Run swift test
  lint        Run SwiftLint (if installed)
  run         Run tmrc via swift run
  clean       Clean Swift package artifacts
  help        Show this help message

Examples:
  ./devops.sh setup
  ./devops.sh build
  ./devops.sh test
EOF
}

assert_swift_package() {
  if [[ ! -f "$PROJECT_ROOT/Package.swift" ]]; then
    err "Package.swift not found in project root: $PROJECT_ROOT"
    err "This repository is likely still in planning mode."
    exit 1
  fi
}

run_setup() {
  local failures=0

  if [[ "$(uname -s)" != "Darwin" ]]; then
    err "tmrc targets macOS. Current OS is not Darwin."
    ((failures++))
  else
    ok "Operating system: macOS"
  fi

  if [[ "$(uname -m)" != "arm64" ]]; then
    warn "Apple Silicon (arm64) is recommended for first target."
  else
    ok "CPU architecture: arm64"
  fi

  if ! xcode-select -p >/dev/null 2>&1; then
    err "Xcode Command Line Tools are not configured."
    err "Run: xcode-select --install"
    ((failures++))
  else
    ok "Xcode Command Line Tools are configured"
  fi

  if ! has_cmd swift; then
    err "Swift toolchain not found in PATH."
    ((failures++))
  else
    ok "Swift: $(swift --version | head -n 1)"
  fi

  if [[ -f "$PROJECT_ROOT/config.yaml" ]]; then
    ok "config.yaml found at project root"
  else
    warn "config.yaml not found at project root"
  fi

  if has_cmd ffprobe; then
    ok "ffprobe found (useful for export media tests)"
  else
    warn "ffprobe not found (optional, recommended for export test validation)"
    warn "Install with Homebrew: brew install ffmpeg"
  fi

  if has_cmd swiftlint; then
    ok "SwiftLint found"
  else
    if has_cmd brew; then
      ok "Installing SwiftLint via Homebrew..."
      brew install swiftlint || true
      if has_cmd swiftlint; then
        ok "SwiftLint installed"
      else
        warn "SwiftLint install failed or not in PATH (full Xcode may be required)"
        warn "Run manually: brew install swiftlint"
      fi
    else
      warn "SwiftLint not found and Homebrew not available"
      warn "Install Homebrew from https://brew.sh or run: brew install swiftlint"
    fi
  fi

  if [[ "$failures" -gt 0 ]]; then
    err "Environment check failed with $failures blocking issue(s)."
    exit 1
  fi

  ok "Environment check passed."
}

cmd_build() {
  run_setup
  assert_swift_package
  swift build
}

cmd_test() {
  run_setup
  assert_swift_package
  swift test
}

cmd_lint() {
  run_setup
  if ! has_cmd swiftlint; then
    err "SwiftLint is required for lint command."
    err "Install with Homebrew: brew install swiftlint"
    exit 1
  fi
  swiftlint
}

cmd_run() {
  run_setup
  assert_swift_package
  swift run tmrc
}

cmd_clean() {
  assert_swift_package
  swift package clean
  ok "Swift package artifacts cleaned."
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  local command="$1"
  shift

  case "$command" in
    setup|check-env)
      run_setup
      ;;
    build)
      cmd_build "$@"
      ;;
    test)
      cmd_test "$@"
      ;;
    lint)
      cmd_lint "$@"
      ;;
    run)
      cmd_run "$@"
      ;;
    clean)
      cmd_clean "$@"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      err "Unknown command: $command"
      usage
      exit 1
      ;;
  esac
}

main "$@"
