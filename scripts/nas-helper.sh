#!/usr/bin/env bash
set -euo pipefail

# Helper for syncing/building/testing this project on Synology NAS.
# Defaults are set for your current setup but can be overridden via env vars.

NAS_HOST="${NAS_HOST:-samr@nas.home}"
REMOTE_DIR="${REMOTE_DIR:-/volume1/docker}"
DOCKER_BIN="${DOCKER_BIN:-/usr/local/bin/docker}"
SERVICE="${SERVICE:-balance}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  sync        Copy project files to NAS (${NAS_HOST}:${REMOTE_DIR})
  build       Build the container image on NAS
  config      Validate docker compose config on NAS
  help-test   Run container with --help and show first lines
  smoke       Run container and show first 40 lines of output
  run         Run full container output (generates /plans/latest-plan.sh)
  apply       Run planner + apply moves in foreground (long-running)
  apply-bg    Start apply service detached
  apply-logs  Follow apply service logs
  apply-stop  Stop apply service
  apply-restart Restart apply service container
  dry-run     Run planner + rsync dry run (no files moved)
  tail-log    Tail the live apply log on NAS
  all         sync + config + build + help-test + smoke

Environment overrides:
  NAS_HOST    Default: ${NAS_HOST}
  REMOTE_DIR  Default: ${REMOTE_DIR}
  DOCKER_BIN  Default: ${DOCKER_BIN}
  SERVICE     Default: ${SERVICE}

Examples:
  $(basename "$0") all
  NAS_HOST=samr@192.168.1.5 $(basename "$0") build
  REMOTE_DIR=/volume1/docker $(basename "$0") run
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

sync_files() {
  echo "==> Syncing files to ${NAS_HOST}:${REMOTE_DIR}"
  remote "mkdir -p '$REMOTE_DIR' '$REMOTE_DIR/plans' '$REMOTE_DIR/logs'"
  (
    cd "$ROOT_DIR"
    scp -O Dockerfile docker-compose.yml "$NAS_HOST:$REMOTE_DIR/"
    scp -O -r bin "$NAS_HOST:$REMOTE_DIR/"
  )
  echo "==> Sync complete"
}

compose_config() {
  echo "==> Validating compose config on NAS"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose config | head -n 80"
}

compose_build() {
  echo "==> Building image on NAS"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose build '$SERVICE'"
}

help_test() {
  echo "==> Running help test"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose run --rm '$SERVICE' --help | head -n 40"
}

smoke_test() {
  echo "==> Running smoke test (first 40 lines)"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose run --rm '$SERVICE' | head -n 40"
}

full_run() {
  echo "==> Running full planner output"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose run --rm '$SERVICE'"
  echo "==> Plan file should be at ${REMOTE_DIR}/plans/latest-plan.sh"
}

apply_run() {
  echo "==> Running planner + apply in foreground (this can take a long time)"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose run --rm balance_apply"
}

apply_bg() {
  echo "==> Starting apply service in background"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose up -d balance_apply"
  echo "==> Use '$(basename "$0") apply-logs' to follow progress"
}

apply_logs() {
  echo "==> Following apply service logs"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose logs -f --tail=200 balance_apply"
}

apply_stop() {
  echo "==> Stopping apply service"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose stop balance_apply"
}

apply_restart() {
  echo "==> Restarting apply service"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose restart balance_apply"
}

dry_run() {
  echo "==> Running planner + rsync dry-run (no files will be moved)"
  remote "cd '$REMOTE_DIR' && sudo -n '$DOCKER_BIN' compose run --rm balance --dry-run"
}

tail_log() {
  echo "==> Tailing apply log on NAS (Ctrl+C to stop)"
  ssh "$NAS_HOST" "tail -f '${REMOTE_DIR}/logs/apply.log'"
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
    apply-bg)
      apply_bg
      ;;
    apply-logs)
      apply_logs
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
