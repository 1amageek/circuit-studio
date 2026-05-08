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

run_package_baseline() {
  local name="$1"
  local directory="$2"

  run_step "${name} build" "${directory}" 120 swift build
  run_step "${name} tests" "${directory}" 180 swift test
}

run_package_baseline "CircuitStudio" "${REPO_DIR}"
run_package_baseline "CoreSpice" "${LSI_DIR}/CoreSpice"
run_package_baseline "semiconductor-layout" "${LSI_DIR}/semiconductor-layout"
run_package_baseline "swift-mask-data" "${LSI_DIR}/swift-mask-data"
run_package_baseline "PEXEngine" "${LSI_DIR}/PEXEngine"

run_step "Xcode schemes" "${REPO_DIR}" 60 xcodebuild -list -workspace Xcircuite.xcworkspace
run_step "Xcode app build" "${REPO_DIR}" 180 xcodebuild -workspace Xcircuite.xcworkspace -scheme Xcircuite -destination "platform=macOS" build
run_step "Xcode app tests" "${REPO_DIR}" 240 xcodebuild test -workspace Xcircuite.xcworkspace -scheme Xcircuite -destination "platform=macOS"

printf '\nFlow verification completed.\n'
