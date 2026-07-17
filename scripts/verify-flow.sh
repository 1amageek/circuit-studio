#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LSI_DIR="$(cd "${REPO_DIR}/.." && pwd)"

run_step() {
  local name="$1"
  local directory="$2"
  local seconds="$3"
  shift 3

  printf '\n==> %s\n' "${name}"
  (
    cd "${directory}"
    "${REPO_DIR}/scripts/swift-test-timeout.sh" "${seconds}" "$@"
  )
}

run_package_baseline() {
  local name="$1"
  local directory="$2"
  local scheme="$3"

  run_step "${name} build" "${directory}" 300 \
    xcodebuild -workspace .swiftpm/xcode/package.xcworkspace \
      -scheme "${scheme}" -destination "platform=macOS" build
  run_step "${name} tests" "${directory}" 1800 \
    xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace \
      -scheme "${scheme}" -destination "platform=macOS" \
      -parallel-testing-enabled NO -test-timeouts-enabled YES \
      -maximum-test-execution-time-allowance 30
}

run_package_baseline "CircuitStudio" "${REPO_DIR}" "CircuitStudio-Package"
run_package_baseline "CoreSpice" "${LSI_DIR}/CoreSpice" "CoreSpice"
run_package_baseline "semiconductor-layout" "${LSI_DIR}/semiconductor-layout" "SemiconductorLayout"
run_package_baseline "swift-mask-data" "${LSI_DIR}/swift-mask-data" "swift-mask-data"
run_package_baseline "PEXEngine" "${LSI_DIR}/PEXEngine" "PEXEngine"

run_step "Xcode schemes" "${REPO_DIR}" 60 xcodebuild -list -workspace Xcircuite.xcworkspace
run_step "Xcode app build" "${REPO_DIR}" 180 xcodebuild -workspace Xcircuite.xcworkspace -scheme Xcircuite -destination "platform=macOS" build
run_step "Xcode app tests" "${REPO_DIR}" 240 xcodebuild test -workspace Xcircuite.xcworkspace -scheme Xcircuite -destination "platform=macOS"

printf '\nFlow verification completed.\n'
