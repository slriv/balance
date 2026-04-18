#!/usr/bin/env bash
set -euo pipefail

# Configure repository merge settings and main branch protection using GitHub REST API.
#
# Required (one of):
#   GITHUB_TOKEN  - token with admin rights on the repo
#   gh auth login - authenticated GitHub CLI session
#
# Optional:
#   OWNER         - default: slriv
#   REPO          - default: balance
#   APPROVALS     - default: 1
#   ENFORCE_ADMINS- default: true
#
# Example:
#   GITHUB_TOKEN=ghp_xxx ./scripts/configure-github-protection.sh
#   ./scripts/configure-github-protection.sh   # uses `gh auth token` if available
#
# Override target:
#   GITHUB_TOKEN=ghp_xxx OWNER=my-org REPO=my-repo ./scripts/configure-github-protection.sh

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  if command -v gh >/dev/null 2>&1; then
    GITHUB_TOKEN="$(gh auth token)"
  fi
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required (or authenticate gh CLI)}"

OWNER="${OWNER:-slriv}"
REPO="${REPO:-balance}"
APPROVALS="${APPROVALS:-1}"
ENFORCE_ADMINS="${ENFORCE_ADMINS:-true}"

API="https://api.github.com/repos/${OWNER}/${REPO}"
AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.github+json"

echo "==> Updating merge method settings for ${OWNER}/${REPO}"
if command -v gh >/dev/null 2>&1; then
  gh repo edit "${OWNER}/${REPO}" \
    --enable-merge-commit=false \
    --enable-squash-merge=true \
    --enable-rebase-merge=true \
    --delete-branch-on-merge=true >/dev/null
else
  curl -sSf -X PATCH \
    -H "${ACCEPT_HEADER}" \
    -H "${AUTH_HEADER}" \
    "${API}" \
    -d "$(cat <<JSON
{
  \"allow_merge_commit\": false,
  \"allow_squash_merge\": true,
  \"allow_rebase_merge\": true,
  \"delete_branch_on_merge\": true
}
JSON
)" >/dev/null
fi

if command -v gh >/dev/null 2>&1; then
  merge_enabled="$(gh api "repos/${OWNER}/${REPO}" --jq '.allow_merge_commit')"
else
  merge_enabled="$(curl -sSf -H "${ACCEPT_HEADER}" -H "${AUTH_HEADER}" "${API}" | sed -n 's/.*"allow_merge_commit"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' | head -n 1)"
fi
if [[ "${merge_enabled}" != "false" ]]; then
  echo "ERROR: merge commit setting did not apply (allow_merge_commit=${merge_enabled})." >&2
  exit 1
fi

echo "==> Merge commit policy updated (allow_merge_commit=false)"

echo "==> Updating branch protection for ${OWNER}/${REPO}:main"
http_code="$(curl -sS -o /tmp/gh-branch-protection.json -w '%{http_code}' -X PUT \
  -H "${ACCEPT_HEADER}" \
  -H "${AUTH_HEADER}" \
  "${API}/branches/main/protection" \
  -d "$(cat <<JSON
{
  \"required_status_checks\": null,
  \"enforce_admins\": ${ENFORCE_ADMINS},
  \"required_pull_request_reviews\": {
    \"required_approving_review_count\": ${APPROVALS},
    \"dismiss_stale_reviews\": true,
    \"require_code_owner_reviews\": false
  },
  \"restrictions\": null,
  \"required_linear_history\": true,
  \"allow_force_pushes\": false,
  \"allow_deletions\": false,
  \"block_creations\": false,
  \"required_conversation_resolution\": true,
  \"lock_branch\": false,
  \"allow_fork_syncing\": false
}
JSON
)" )"

case "${http_code}" in
  200|201)
    echo "==> Branch protection updated for main"
    ;;
  403)
    message="$(sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/gh-branch-protection.json | head -n 1)"
    echo "WARNING: Could not set branch protection (HTTP 403). ${message}" >&2
    echo "         Merge commits are still disabled at repo level." >&2
    ;;
  *)
    echo "ERROR: Failed to set branch protection (HTTP ${http_code})." >&2
    cat /tmp/gh-branch-protection.json >&2
    exit 1
    ;;
esac

echo "Done. ${OWNER}/${REPO} has merge commits disabled and squash/rebase enabled."
