#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
    printf 'usage: %s <path>...\n' "$0" >&2
    exit 64
fi

if rg -n -U 'deinit\s*\{[^}]{0,400}syncShutdownGracefully' "$@"; then
    printf 'synchronous shutdown from deinit was found\n' >&2
    exit 1
fi
