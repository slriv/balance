#!/usr/bin/env bash
set -euo pipefail

# Local-only helper (ignored by git via .git/info/exclude)
# Put your token below if you want it stored locally in this repo clone.
GITHUB_TOKEN="${GITHUB_TOKEN:-PASTE_YOUR_TOKEN_HERE}"

if [[ "$GITHUB_TOKEN" == "PASTE_YOUR_TOKEN_HERE" ]]; then
  echo "Set GITHUB_TOKEN in this file or export it in your shell first." >&2
  exit 1
fi

exec "$(dirname "$0")/configure-github-protection.sh"
