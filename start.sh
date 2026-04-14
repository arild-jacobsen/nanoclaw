#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONECLI_COMPOSE_FILE="$HOME/.onecli/docker-compose.yml"
ONECLI_PROJECT="onecli"
LOG_FILE="$PROJECT_ROOT/logs/nanoclaw.log"

mkdir -p "$PROJECT_ROOT/logs"

# --- Mode selection ---

MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "Start NanoClaw in which mode?"
  echo "  1) dev  — hot reload (npm run dev)"
  echo "  2) prod — compiled   (node dist/index.js)"
  read -rp "Choice [1/2]: " choice
  case "$choice" in
    1|dev)  MODE="dev" ;;
    2|prod) MODE="prod" ;;
    *) echo "Invalid choice. Use 'dev' or 'prod'."; exit 1 ;;
  esac
fi

case "$MODE" in
  dev|prod) ;;
  *) echo "Usage: $0 [dev|prod]"; exit 1 ;;
esac

# --- OneCLI ---

start_onecli() {
  if [ ! -f "$ONECLI_COMPOSE_FILE" ]; then
    echo "OneCLI compose file not found at $ONECLI_COMPOSE_FILE — skipping."
    return
  fi

  local running
  running=$(docker compose -p "$ONECLI_PROJECT" -f "$ONECLI_COMPOSE_FILE" ps --status running --quiet 2>/dev/null | wc -l)

  if [ "$running" -gt 0 ]; then
    echo "OneCLI already running."
    return
  fi

  echo "Starting OneCLI..."
  docker compose -p "$ONECLI_PROJECT" -f "$ONECLI_COMPOSE_FILE" up -d

  echo -n "Waiting for OneCLI health check"
  local attempts=0
  until curl -sf http://127.0.0.1:10254/health >/dev/null 2>&1; do
    sleep 1
    attempts=$((attempts + 1))
    echo -n "."
    if [ "$attempts" -ge 30 ]; then
      echo " timed out after 30s."
      return 1
    fi
  done
  echo " healthy."
}

start_onecli

# --- NanoClaw ---

cd "$PROJECT_ROOT"

if [ "$MODE" = "dev" ]; then
  echo "Starting NanoClaw (dev)..."
  exec npm run dev
else
  echo "Starting NanoClaw (prod)..."
  exec node dist/index.js
fi
