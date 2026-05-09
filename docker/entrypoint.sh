#!/bin/sh
set -e

ARTIFACT_ROOT="${BALANCE_ARTIFACT_ROOT:-/artifacts}"

# Ensure artifact directory exists
mkdir -p "$ARTIFACT_ROOT"

# Validate it is writable
if ! touch "$ARTIFACT_ROOT/.write_test" 2>/dev/null; then
    echo "ERROR: $ARTIFACT_ROOT is not writable. Mount it with the correct permissions." >&2
    exit 1
fi
rm -f "$ARTIFACT_ROOT/.write_test"

exec "$@"
