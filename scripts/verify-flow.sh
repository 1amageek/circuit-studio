#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LSI_DIR="$(cd "${REPO_DIR}/.." && pwd)"

run_with_timeout() {
  local seconds="$1"
  shift
  perl -e "alarm ${seconds}; exec @ARGV" "$@"
}

run_step() {
  local name="$1"
  local directory="$2"
  local seconds="$3"
  shift 3

  printf '\n==> %s\n' "${name}"
  (
    cd "${directory}"
    run_with_timeout "${seconds}" "$@"
  )
}

run_step "CircuitStudio build" "${REPO_DIR}" 120 swift build
run_step "CircuitStudio tests" "${REPO_DIR}" 180 swift test
run_step "CoreSpice tests" "${LSI_DIR}/CoreSpice" 180 swift test
run_step "semiconductor-layout tests" "${LSI_DIR}/semiconductor-layout" 180 swift test
run_step "swift-mask-data tests" "${LSI_DIR}/swift-mask-data" 180 swift test
run_step "PEXEngine tests" "${LSI_DIR}/PEXEngine" 180 swift test

run_step "Xcode schemes" "${REPO_DIR}" 60 xcodebuild -list -workspace Xcircuite.xcworkspace
run_step "Xcode app build" "${REPO_DIR}" 180 xcodebuild -workspace Xcircuite.xcworkspace -scheme Xcircuite -destination "platform=macOS" build
run_step "Xcode app tests" "${REPO_DIR}" 240 xcodebuild test -workspace Xcircuite.xcworkspace -scheme Xcircuite -destination "platform=macOS"

printf '\nFlow verification completed.\n'
