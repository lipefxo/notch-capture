#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_DIR="$ROOT/.build/Notch Capture.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/NotchCapture"

workspace_pids() {
  ps -axo pid=,command= -ww | awk -v target="$EXECUTABLE" '
    {
      pid = $1
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", $0)
      if ($0 == target) print pid
    }
  '
}

stop_workspace_app() {
  local -a pids
  pids=($(workspace_pids))
  if (( ${#pids} == 0 )); then
    return
  fi

  kill -TERM "${pids[@]}" 2>/dev/null || true
  for _ in {1..20}; do
    pids=($(workspace_pids))
    if (( ${#pids} == 0 )); then
      return
    fi
    sleep 0.1
  done

  kill -KILL "${pids[@]}" 2>/dev/null || true
}

case "${1:-run}" in
  run)
    ;;
  --stop)
    stop_workspace_app
    exit 0
    ;;
  *)
    echo "usage: Scripts/run-app.sh [--stop]" >&2
    exit 64
    ;;
esac

cleanup() {
  trap - EXIT HUP INT TERM
  stop_workspace_app
}

trap cleanup EXIT HUP INT TERM
stop_workspace_app
"$ROOT/Scripts/build-app.sh" debug
open -n -W "$APP_DIR"
