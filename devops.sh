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

Development:
  setup       Validate local development prerequisites
  build       Run swift build
  test        Run full self-validating test suite (includes swift tests)
  lint        Run SwiftLint (if installed)
  symlink     Create symlink in project root pointing to debug binary
  release     Build for production, zip, and upload to GitHub (--no-upload to skip)
  clean       Clean Swift package artifacts

User:
  install     Build, install CLI config, and set to start on login
  uninstall   Remove login item and stop recording

Executable (proxied to tmrc binary):
  dump        Export all recordings to current folder (one MP4)
  wipe        Remove all recordings and index; daemon keeps running

Examples:
  ./devops.sh setup
  ./devops.sh build
  ./devops.sh install
  ./devops.sh dump
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
  grep -v 'swift-driver version' "$stderr_file" >&2 || true
  rm -f "$stderr_file"
  return $ret
}

# Build quietly and run the tmrc binary. Uses the symlink if available to avoid redundant builds.
run_tmrc() {
  local bin="$PROJECT_ROOT/tmrc"
  if [[ ! -x "$bin" ]]; then
    show_cmd bash -c "cd $(printf '%q' "$PROJECT_ROOT") && swift build -q"
    (cd "$PROJECT_ROOT" && swift build -q 2> >(grep -v --line-buffered 'swift-driver version' >&2)) || true
    local bin_path
    bin_path="$(cd "$PROJECT_ROOT" && swift build --show-bin-path)"
    bin="$bin_path/tmrc"
  fi
  show_cmd "$bin" "$@"
  "$bin" "$@"
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
  local bin_path
  bin_path="$(cd "$PROJECT_ROOT" && swift build --show-bin-path)"
  ln -sf "$bin_path/tmrc" "$PROJECT_ROOT/tmrc"
  ok "Symlink $PROJECT_ROOT/tmrc -> $bin_path/tmrc"
}

cmd_install() {
  cmd_build
  run_tmrc install

  local plist_path="$HOME/Library/LaunchAgents/com.tmrc.daemon.plist"
  local bin_path="$PROJECT_ROOT/tmrc"
  
  ok "Installing Launch Agent to $plist_path..."
  mkdir -p "$(dirname "$plist_path")"
  
  cat <<EOF > "$plist_path"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tmrc.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$bin_path</string>
        <string>start</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

  launchctl unload "$plist_path" 2>/dev/null || true
  launchctl load "$plist_path"
  ok "tmrc is now set to start on login."
}

cmd_uninstall() {
  local plist_path="$HOME/Library/LaunchAgents/com.tmrc.daemon.plist"
  if [[ -f "$plist_path" ]]; then
    ok "Removing Launch Agent..."
    launchctl unload "$plist_path" 2>/dev/null || true
    rm -f "$plist_path"
  fi
  run_tmrc stop || true
  ok "tmrc has been uninstalled from login items and stopped."
}

cmd_swift_test() {
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

cmd_symlink() {
  assert_swift_package
  local bin_path
  bin_path="$(cd "$PROJECT_ROOT" && swift build --show-bin-path 2>/dev/null)"
  local bin="$bin_path/tmrc"
  if [[ ! -x "$bin" ]]; then
    err "Debug binary not found at $bin. Run './devops.sh build' first."
    exit 1
  fi
  ln -sf "$bin" "$PROJECT_ROOT/tmrc"
  ok "Symlink $PROJECT_ROOT/tmrc -> $bin"
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

cmd_release() {
  local version=""
  local upload=1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-upload)
        upload=0
        shift
        ;;
      v*)
        version="$1"
        shift
        ;;
      *)
        err "Unknown release argument: $1"
        exit 1
        ;;
    esac
  done

  if [[ -z "$version" ]]; then
    err "Usage: ./devops.sh release [--no-upload] <vX.Y.Z>"
    exit 1
  fi

  run_setup quiet
  assert_swift_package

  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  local arch
  arch=$(uname -m)
  local bundle_name="tmrc-${version}-${os}-${arch}"
  local dist_dir="${PROJECT_ROOT}/dist/${bundle_name}"
  local zip_file="${PROJECT_ROOT}/dist/${bundle_name}.zip"

  ok "Building tmrc $version for $os-$arch in release mode..."
  run_swift swift build -c release

  local bin_path
  bin_path="$(cd "$PROJECT_ROOT" && swift build -c release --show-bin-path)"

  ok "Preparing distribution bundle in $dist_dir..."
  rm -rf "$dist_dir" "$zip_file"
  mkdir -p "$dist_dir"

  cp "$bin_path/tmrc" "$dist_dir/"
  [[ -f "$PROJECT_ROOT/config.yaml" ]] && cp "$PROJECT_ROOT/config.yaml" "$dist_dir/"
  [[ -f "$PROJECT_ROOT/README.md" ]] && cp "$PROJECT_ROOT/README.md" "$dist_dir/"
  cp "$PROJECT_ROOT/devops.sh" "$dist_dir/"

  ok "Creating zip archive: $zip_file"
  (cd "${PROJECT_ROOT}/dist" && zip -r "${bundle_name}.zip" "${bundle_name}")

  if [[ "$upload" -eq 0 ]]; then
    ok "Release bundle is ready at: $zip_file (upload skipped)"
  elif ! has_cmd gh; then
    warn "gh (GitHub CLI) not found. Skipping upload."
    ok "Release bundle is ready at: $zip_file"
  else
    ok "Checking if tag $version exists..."
    if ! git rev-parse "$version" >/dev/null 2>&1; then
      ok "Tagging $version..."
      git tag -a "$version" -m "Release $version"
      git push origin "$version"
    fi

    ok "Creating GitHub release and uploading $zip_file..."
    if gh release view "$version" >/dev/null 2>&1; then
      gh release upload "$version" "$zip_file" --clobber
    else
      gh release create "$version" "$zip_file" --title "$version" --notes "Release $version for $os-$arch"
    fi
    ok "Release $version published."
  fi
}

cmd_clean() {
  assert_swift_package
  run_swift swift package clean
  rm -f "$PROJECT_ROOT/tmrc"
  ok "Swift package artifacts and symlink cleaned."
}

cmd_test() {
  ./scripts/smoke_test.sh
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  local command="$1"
  shift

  case "$command" in
    setup)
      run_setup
      ;;
    build)
      cmd_build "$@"
      ;;
    test)
      cmd_test "$@"
      ;;
    swift-test)
      cmd_swift_test "$@"
      ;;
    lint)
      cmd_lint "$@"
      ;;
    install)
      cmd_install "$@"
      ;;
    uninstall)
      cmd_uninstall "$@"
      ;;
    symlink)
      cmd_symlink "$@"
      ;;
    dump)
      cmd_dump "$@"
      ;;
    wipe)
      cmd_wipe "$@"
      ;;
    release)
      cmd_release "$@"
      ;;
    clean)
      cmd_clean "$@"
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
