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
  [[ -n "${DEVOPS_QUIET:-}" ]] && return
  echo -e "${GREEN}[ok]${NC} $1"
}

warn() {
  [[ -n "${DEVOPS_QUIET:-}" ]] && return
  echo -e "${YELLOW}[warn]${NC} $1"
}

err() {
  echo -e "${RED}[error]${NC} $1" >&2
}

# Print the actual command line so users can see/copy what is run. Use stderr so
# command substitution (e.g. swift build --show-bin-path) only captures real output.
show_cmd() {
  [[ -n "${DEVOPS_QUIET:-}" ]] && return
  echo -ne "${YELLOW}\$ ${NC}" >&2
  printf '%q ' "$@" >&2
  echo >&2
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
  record      Toggle recording (start if stopped, stop if running)
  status      Get recording status (tmrc status)
  dump        Export all recordings to current folder (one MP4)
  wipe        Remove all recordings and index; daemon keeps running
  clean       Clean Swift package artifacts
  help        Show this help message

Examples:
  ./devops.sh setup
  ./devops.sh build
  ./devops.sh record
  ./devops.sh dump
  ./devops.sh wipe
EOF
}

assert_swift_package() {
  if [[ ! -f "$PROJECT_ROOT/Package.swift" ]]; then
    err "Package.swift not found in project root: $PROJECT_ROOT"
    err "This repository is likely still in planning mode."
    exit 1
  fi
}

# Run a command and filter stderr to drop swift-driver version line
run_swift() {
  show_cmd "$@"
  local stderr_file
  stderr_file=$(mktemp)
  "$@" 2>"$stderr_file"
  local ret=$?
  grep -v 'swift-driver version' "$stderr_file" >&2
  rm -f "$stderr_file"
  return $ret
}

# Build quietly and run the tmrc binary (no "Building for debugging..." from swift run).
run_tmrc() {
  show_cmd bash -c "cd $(printf '%q' "$PROJECT_ROOT") && swift build -q"
  (cd "$PROJECT_ROOT" && swift build -q 2> >(grep -v --line-buffered 'swift-driver version' >&2)) || true
  local bin
  bin="$(cd "$PROJECT_ROOT" && run_swift swift build --show-bin-path)/tmrc"
  show_cmd "$bin" "$@"
  (cd "$PROJECT_ROOT" && "$bin" "$@")
}

# Install SwiftLint from GitHub portable binary when Homebrew is unavailable or fails
install_swiftlint_portable() {
  [[ "$(uname -s)" != "Darwin" ]] && return 1
  if ! has_cmd curl; then
    warn "curl not found; cannot download SwiftLint portable binary"
    return 1
  fi
  local tag
  tag=$(curl -sL https://api.github.com/repos/realm/SwiftLint/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
  [[ -z "$tag" ]] && warn "Could not resolve SwiftLint latest release tag" && return 1
  ok "Downloading SwiftLint $tag (portable macOS binary)..."
  mkdir -p "$PROJECT_ROOT/.bin"
  local zip_path
  zip_path=$(mktemp -t swiftlint.XXXXXX.zip)
  if ! curl -sL "https://github.com/realm/SwiftLint/releases/download/${tag}/portable_swiftlint.zip" -o "$zip_path"; then
    rm -f "$zip_path"
    warn "SwiftLint download failed"
    return 1
  fi
  if ! unzip -o -q -j "$zip_path" -d "$PROJECT_ROOT/.bin" 2>/dev/null; then
    rm -f "$zip_path"
    warn "SwiftLint unzip failed"
    return 1
  fi
  rm -f "$zip_path"
  chmod +x "$PROJECT_ROOT/.bin/swiftlint"
  export PATH="$PROJECT_ROOT/.bin:$PATH"
  return 0
}

run_setup() {
  local failures=0
  if [[ "${1:-}" == "quiet" ]]; then
    DEVOPS_QUIET=1
    shift
  fi

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

  # Prefer project-local portable install so it's found without relying on PATH
  if [[ -d "$PROJECT_ROOT/.bin" ]]; then
    export PATH="$PROJECT_ROOT/.bin:$PATH"
  fi

  if has_cmd swiftlint; then
    ok "SwiftLint found"
  else
    if has_cmd brew; then
      ok "Installing SwiftLint via Homebrew..."
      if brew install swiftlint 2>/dev/null; then
        ok "SwiftLint installed via Homebrew"
      else
        install_swiftlint_portable
      fi
    else
      install_swiftlint_portable
    fi
    if has_cmd swiftlint; then
      ok "SwiftLint installed"
    else
      warn "SwiftLint install failed. Install manually: brew install swiftlint"
    fi
  fi

  if [[ "$failures" -gt 0 ]]; then
    err "Environment check failed with $failures blocking issue(s)."
    exit 1
  fi

  ok "Environment check passed."
  unset -v DEVOPS_QUIET 2>/dev/null || true
}

cmd_build() {
  run_setup quiet
  assert_swift_package
  run_swift swift build
}

cmd_test() {
  run_setup quiet
  assert_swift_package
  run_swift swift test
}

cmd_lint() {
  run_setup quiet
  if ! has_cmd swiftlint; then
    err "SwiftLint is required for lint command."
    err "Install with Homebrew: brew install swiftlint"
    exit 1
  fi
  swiftlint
}

cmd_record() {
  run_setup quiet
  assert_swift_package
  local status_out
  status_out=$(run_tmrc status 2>/dev/null) || true
  if echo "$status_out" | grep -q "Recording: yes"; then
    run_tmrc record --stop
  else
    run_tmrc record --start
  fi
}

cmd_status() {
  run_setup quiet
  assert_swift_package
  run_tmrc status
}

cmd_dump() {
  run_setup quiet
  assert_swift_package
  local out
  out="${PROJECT_ROOT}/tmrc_dump_$(date +%Y-%m-%d_%H-%M-%S).mp4"
  run_tmrc export --from "1000d ago" --to "now" -o "$out"
}

cmd_wipe() {
  run_setup quiet
  assert_swift_package
  run_tmrc wipe
}

cmd_clean() {
  assert_swift_package
  run_swift swift package clean
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
    record)
      cmd_record "$@"
      ;;
    status)
      cmd_status "$@"
      ;;
    dump)
      cmd_dump "$@"
      ;;
    wipe)
      cmd_wipe "$@"
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

# Filter swift-driver version from stderr (it can appear from subshells where run_swift isn't applied).
main "$@" 2> >(grep -v --line-buffered 'swift-driver version' >&2)
