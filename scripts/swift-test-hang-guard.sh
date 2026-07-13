#!/usr/bin/env bash
set -euo pipefail

repeats=3
timeout_seconds=30
build_timeout_seconds=120
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --repeats)
            repeats="$2"
            shift 2
            ;;
        --timeout)
            timeout_seconds="$2"
            shift 2
            ;;
        --build-timeout)
            build_timeout_seconds="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            printf 'unknown option: %s\n' "$1" >&2
            exit 64
            ;;
    esac
done

if [[ "$timeout_seconds" -gt 120 || "$build_timeout_seconds" -gt 120 ]]; then
    printf 'timeouts must not exceed 120 seconds\n' >&2
    exit 64
fi

if [[ "$repeats" -lt 1 ]]; then
    printf 'repeats must be positive\n' >&2
    exit 64
fi

script_directory="$(cd "$(dirname "$0")" && pwd)"
artifact_directory="${HANG_GUARD_ARTIFACT_DIRECTORY:-.test-artifacts/hang-guard/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$artifact_directory"

for run in $(seq 1 "$repeats"); do
    log_path="$artifact_directory/run-$run.log"
    command_timeout="$timeout_seconds"
    if [[ "$run" -eq 1 ]]; then
        command_timeout="$build_timeout_seconds"
    fi
    set +e
    "$script_directory/swift-test-timeout.sh" "$command_timeout" swift test "$@" >"$log_path" 2>&1
    status=$?
    set -e
    if [[ "$status" -ne 0 ]]; then
        printf 'test run %s failed with status %s\n' "$run" "$status" >&2
        exit "$status"
    fi
    if pgrep -f 'swiftpm-testing-helper|textstory-manifest' >/dev/null 2>&1; then
        printf 'stale SwiftPM test helper detected after run %s\n' "$run" >&2
        pgrep -af 'swiftpm-testing-helper|textstory-manifest' >"$artifact_directory/run-$run.diag.txt" || true
        exit 1
    fi
done

printf 'OK: %s runs completed without timeout or stale helper\n' "$repeats"
