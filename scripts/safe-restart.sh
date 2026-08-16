#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OC="${OPENCLAW_CLI:-$(command -v openclaw || true)}"
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
WAIT_SECONDS="${OPENCLAW_RESTART_WAIT_SECONDS:-600}"
POLL_SECONDS="${OPENCLAW_RESTART_POLL_SECONDS:-1}"
LOG_FILE="${OPENCLAW_RESTART_LOG_FILE:-/tmp/openclaw-safe-restart.log}"
FORCE=0

usage() {
  cat <<'EOF'
Usage: openclaw-safe-restart [--force]

Requests an OpenClaw safe restart and waits for fresh healthy runtime proof.
--force adds --skip-deferral and should be used only for an explicit emergency.
EOF
}

for argument in "$@"; do
  case "$argument" in
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unsupported argument: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$OC" || ! -x "$OC" ]]; then
  printf 'OpenClaw CLI not found. Set OPENCLAW_CLI.\n' >&2
  exit 1
fi
if ! [[ "$WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'OPENCLAW_RESTART_WAIT_SECONDS must be a positive integer.\n' >&2
  exit 2
fi

mkdir -p "$(dirname "$LOG_FILE")"
log() {
  printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "$LOG_FILE"
}

gateway_pids() {
  if command -v fuser >/dev/null 2>&1; then
    fuser -n tcp "$PORT" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -u
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sort -u
  fi
}

health_snapshot() {
  "$OC" health --json 2>/dev/null
}

health_fields() {
  node "$SCRIPT_DIR/lib/reload-marker.mjs"
}

mapfile -t BEFORE_PIDS < <(gateway_pids)
if ((${#BEFORE_PIDS[@]} == 0)); then
  log "ERROR: no gateway listener found on port $PORT"
  exit 1
fi

BEFORE_HEALTH="$(health_snapshot || true)"
BEFORE_FIELDS="$(printf '%s' "$BEFORE_HEALTH" | health_fields 2>/dev/null || true)"
BEFORE_MARKER="$(node -e 'const x=JSON.parse(process.argv[1]||"{}"); console.log(x.marker??"")' "$BEFORE_FIELDS" 2>/dev/null || true)"

restart_args=(gateway restart --safe --json)
if ((FORCE == 1)); then
  restart_args+=(--skip-deferral)
  log "Requesting explicit forced safe restart for pid(s): ${BEFORE_PIDS[*]}"
else
  log "Requesting deferred safe restart for pid(s): ${BEFORE_PIDS[*]}"
fi
"$OC" "${restart_args[@]}" >>"$LOG_FILE" 2>&1

deadline=$((SECONDS + WAIT_SECONDS))
while ((SECONDS < deadline)); do
  CURRENT_HEALTH="$(health_snapshot || true)"
  CURRENT_FIELDS="$(printf '%s' "$CURRENT_HEALTH" | health_fields 2>/dev/null || true)"
  CURRENT_OK="$(node -e 'const x=JSON.parse(process.argv[1]||"{}"); console.log(x.ok===true?"yes":"no")' "$CURRENT_FIELDS" 2>/dev/null || true)"
  CURRENT_MARKER="$(node -e 'const x=JSON.parse(process.argv[1]||"{}"); console.log(x.marker??"")' "$CURRENT_FIELDS" 2>/dev/null || true)"
  mapfile -t CURRENT_PIDS < <(gateway_pids)

  fresh_pid=0
  for current in "${CURRENT_PIDS[@]}"; do
    seen=0
    for old in "${BEFORE_PIDS[@]}"; do
      [[ "$current" == "$old" ]] && seen=1
    done
    ((seen == 0)) && fresh_pid=1
  done

  fresh_marker=0
  if [[ "$BEFORE_MARKER" =~ ^[0-9]+$ && "$CURRENT_MARKER" =~ ^[0-9]+$ ]] &&
     ((CURRENT_MARKER > BEFORE_MARKER)); then
    fresh_marker=1
  fi

  if [[ "$CURRENT_OK" == "yes" ]] && ((fresh_pid == 1 || fresh_marker == 1)); then
    if ((fresh_pid == 1)); then
      log "SUCCESS: healthy gateway confirmed with a new listener pid"
    else
      log "SUCCESS: healthy in-process reload confirmed by runtime generation ($BEFORE_MARKER -> $CURRENT_MARKER)"
    fi
    exit 0
  fi
  sleep "$POLL_SECONDS"
done

log "ERROR: restart request did not produce fresh healthy runtime proof within ${WAIT_SECONDS}s"
exit 1
