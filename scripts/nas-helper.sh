#!/usr/bin/env bash
set -euo pipefail

# Helper for syncing/building/testing this project on Synology NAS.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Defaults are set for your current setup but can be overridden via env vars.
NAS_HOST="${NAS_HOST:-samr@nas.home}"
REMOTE_DIR="${REMOTE_DIR:-/volume1/docker/balance}"
ARTIFACTS_HOST_DIR="${ARTIFACTS_HOST_DIR:-${REMOTE_DIR}/artifacts}"
DOCKER_BIN="${DOCKER_BIN:-/usr/local/bin/docker}"
SERVICE="${SERVICE:-balance}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  sync        Copy project files to NAS (${NAS_HOST}:${REMOTE_DIR})
  build       Build the container image on NAS
  rebuild     Build the container image on NAS (--no-cache)
  config      Validate docker compose config on NAS
  help-test   Run container with --help and show first lines
  smoke       Run container and show first 40 lines of output
  run         Run full container output (generates /artifacts/balance-plan.sh)
  apply         Run planner + apply moves in foreground (long-running)
  apply-bg      Start apply service detached
  apply-logs    Follow apply service logs
  apply-status  Show apply service container state and exit code
  apply-stop    Stop apply service
  apply-restart Restart apply service container
  dry-run       Run planner + rsync dry run (no files moved)
  test-apply    Apply at most MAX_MOVES moves (default 10; override with MAX_MOVES=N)
  tail-log      Tail the live apply log on NAS
  sonarr-config Show resolved Sonarr config (redacted; no API calls)
  sonarr-plan   Build Sonarr reconcile plan from latest manifest
  sonarr-dry-run Preview Sonarr reconcile operations without making API calls
  sonarr-apply  Apply Sonarr reconcile plan (update paths + trigger rescans)
  plex-config   Show resolved Plex config (redacted; no API calls)
  plex-plan     Build Plex reconcile plan from latest manifest
  plex-dry-run  Preview Plex reconcile operations without making API calls
  plex-apply    Apply Plex reconcile plan (scan paths + empty trash)
  all           sync + config + build + help-test + smoke

Environment overrides:
  NAS_HOST    Default: ${NAS_HOST}
  REMOTE_DIR  Default: ${REMOTE_DIR}
  ARTIFACTS_HOST_DIR Default: ${ARTIFACTS_HOST_DIR}
  DOCKER_BIN  Default: ${DOCKER_BIN}
  SERVICE     Default: ${SERVICE}

Examples:
  $(basename "$0") all
  NAS_HOST=samr@192.168.1.5 $(basename "$0") build
  REMOTE_DIR=/volume1/docker/balance $(basename "$0") run
  ARTIFACTS_HOST_DIR=/volume1/docker/shared/balance-artifacts $(basename "$0") run
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

remote() {
  ssh "$NAS_HOST" "$*"
}

remote_env_prefix() {
  local result=()
  local name value
  for name in "$@"; do
    value="${!name-}"
    [[ -n "$value" ]] || continue
    result+=("$(printf '%s=%q' "$name" "$value")")
  done
  printf '%s ' "${result[@]}"
}

load_local_env() {
  if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
  fi
}

sync_files() {
  echo "==> Syncing files to ${NAS_HOST}:${REMOTE_DIR}"
  remote "mkdir -p '$REMOTE_DIR' '$ARTIFACTS_HOST_DIR' '$REMOTE_DIR/config' '$REMOTE_DIR/lib'"
  (
    cd "$ROOT_DIR"
    scp -O Dockerfile docker-compose.yml "$NAS_HOST:$REMOTE_DIR/"
    scp -O -r bin "$NAS_HOST:$REMOTE_DIR/"
    if [[ -d lib ]]; then
      scp -O -r lib "$NAS_HOST:$REMOTE_DIR/"
    fi
    if [[ -d config ]]; then
      scp -O -r config "$NAS_HOST:$REMOTE_DIR/"
    fi
  )
  echo "==> Sync complete"
}

compose_config() {
  echo "==> Validating compose config on NAS"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose config | head -n 80"
}

compose_build() {
  echo "==> Building image on NAS"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose build '$SERVICE'"
}

compose_rebuild() {
  echo "==> Rebuilding image on NAS (--no-cache)"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose build --no-cache '$SERVICE'"
}

help_test() {
  echo "==> Running help test"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose run --rm '$SERVICE' --help | head -n 40"
}

smoke_test() {
  echo "==> Running smoke test (first 40 lines)"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose run --rm '$SERVICE' | head -n 40"
}

full_run() {
  echo "==> Running full planner output"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose run --rm '$SERVICE'"
  echo "==> Plan file should be at ${ARTIFACTS_HOST_DIR}/balance-plan.sh"
}

apply_run() {
  echo "==> Running planner + apply in foreground (this can take a long time)"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose run --rm balance_apply"
}

apply_test() {
  local max_moves="${MAX_MOVES:-10}"
  echo "==> Running test apply (at most ${max_moves} moves)"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose run --rm balance_apply --max-moves='${max_moves}'"
}

apply_status() {
  echo "==> Apply service status"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose ps --all balance_apply"
}

apply_bg() {
  echo "==> Starting apply service in background"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose up -d balance_apply"
  echo "==> Use '$(basename "$0") apply-logs' to follow progress"
}

apply_logs() {
  echo "==> Following apply service logs"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose logs -f --tail=200 balance_apply"
}

apply_stop() {
  echo "==> Stopping apply service"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose stop balance_apply"
}

apply_restart() {
  echo "==> Restarting apply service"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose restart balance_apply"
}

dry_run() {
  echo "==> Running planner + rsync dry-run (no files will be moved)"
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix ARTIFACTS_HOST_DIR)sudo -n '$DOCKER_BIN' compose run --rm balance --dry-run"
}

tail_log() {
  echo "==> Tailing apply log on NAS (Ctrl+C to stop)"
  ssh "$NAS_HOST" "tail -f '${ARTIFACTS_HOST_DIR}/balance-apply.log'"
}

sonarr_plan() {
  echo "==> Building Sonarr reconcile plan from latest manifest"
  load_local_env
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix BALANCE_MANIFEST_FILE SONARR_BASE_URL SONARR_API_KEY SONARR_PATH_MAP_FILE SONARR_REPORT_FILE SONARR_RETRY_QUEUE_FILE) perl -Ilib bin/sonarr_reconcile.pl"
}

sonarr_dry_run() {
  echo "==> Previewing Sonarr reconcile (dry-run; no API writes)"
  load_local_env
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix BALANCE_MANIFEST_FILE SONARR_BASE_URL SONARR_API_KEY SONARR_PATH_MAP_FILE SONARR_REPORT_FILE SONARR_RETRY_QUEUE_FILE) perl -Ilib lib/Balance/Sonarr.pm dry-run"
}

sonarr_apply() {
  echo "==> Applying Sonarr reconcile plan (update paths + trigger rescans)"
  load_local_env
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix BALANCE_MANIFEST_FILE SONARR_BASE_URL SONARR_API_KEY SONARR_PATH_MAP_FILE SONARR_REPORT_FILE SONARR_RETRY_QUEUE_FILE) perl -Ilib lib/Balance/Sonarr.pm apply"
}

sonarr_config() {
  echo "==> Showing Sonarr config (credentials redacted; no API calls)"
  load_local_env
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix BALANCE_MANIFEST_FILE SONARR_BASE_URL SONARR_API_KEY SONARR_PATH_MAP_FILE SONARR_REPORT_FILE SONARR_RETRY_QUEUE_FILE) perl -Ilib bin/sonarr_reconcile.pl --show-config"
}

plex_plan() {
  echo "==> Building Plex reconcile plan from latest manifest"
  load_local_env
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix BALANCE_MANIFEST_FILE PLEX_BASE_URL PLEX_TOKEN PLEX_LIBRARY_IDS PLEX_PATH_MAP_FILE PLEX_REPORT_FILE PLEX_RETRY_QUEUE_FILE) perl -Ilib bin/plex_reconcile.pl"
}

plex_dry_run() {
  echo "==> Previewing Plex reconcile (dry-run; no API writes)"
  load_local_env
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix BALANCE_MANIFEST_FILE PLEX_BASE_URL PLEX_TOKEN PLEX_LIBRARY_IDS PLEX_PATH_MAP_FILE PLEX_REPORT_FILE PLEX_RETRY_QUEUE_FILE) perl -Ilib lib/Balance/Plex.pm dry-run"
}

plex_apply() {
  echo "==> Applying Plex reconcile plan (scan paths + empty trash)"
  load_local_env
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix BALANCE_MANIFEST_FILE PLEX_BASE_URL PLEX_TOKEN PLEX_LIBRARY_IDS PLEX_PATH_MAP_FILE PLEX_REPORT_FILE PLEX_RETRY_QUEUE_FILE) perl -Ilib lib/Balance/Plex.pm apply"
}

plex_config() {
  echo "==> Showing Plex config (credentials redacted; no API calls)"
  load_local_env
  remote "cd '$REMOTE_DIR' && $(remote_env_prefix BALANCE_MANIFEST_FILE PLEX_BASE_URL PLEX_TOKEN PLEX_LIBRARY_IDS PLEX_PATH_MAP_FILE PLEX_REPORT_FILE PLEX_RETRY_QUEUE_FILE) perl -Ilib bin/plex_reconcile.pl --show-config"
}

main() {
  need_cmd ssh
  need_cmd scp

  local cmd="${1:-}"
  case "$cmd" in
    sync)
      sync_files
      ;;
    build)
      compose_build
      ;;
    rebuild)
      compose_rebuild
      ;;
    config)
      compose_config
      ;;
    help-test)
      help_test
      ;;
    smoke)
      smoke_test
      ;;
    run)
      full_run
      ;;
    apply)
      apply_run
      ;;
    test-apply)
      apply_test
      ;;
    apply-bg)
      apply_bg
      ;;
    apply-logs)
      apply_logs
      ;;
    apply-status)
      apply_status
      ;;
    apply-stop)
      apply_stop
      ;;
    apply-restart)
      apply_restart
      ;;
    dry-run)
      dry_run
      ;;
    tail-log)
      tail_log
      ;;
    sonarr-config)
      sonarr_config
      ;;
    sonarr-plan)
      sonarr_plan
      ;;
    sonarr-dry-run)
      sonarr_dry_run
      ;;
    sonarr-apply)
      sonarr_apply
      ;;
    plex-config)
      plex_config
      ;;
    plex-plan)
      plex_plan
      ;;
    plex-dry-run)
      plex_dry_run
      ;;
    plex-apply)
      plex_apply
      ;;
    all)
      sync_files
      compose_config
      compose_build
      help_test
      smoke_test
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      echo "ERROR: unknown command '$cmd'" >&2
      echo >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
