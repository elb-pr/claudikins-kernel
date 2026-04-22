#!/bin/bash
# setup.sh - claudikins-kernel mobile bootstrap
# Idempotent. Safe to run multiple times per session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$PLUGIN_ROOT/../../../.." && pwd)}"

export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
export CLAUDE_PROJECT_DIR="$PROJECT_DIR"

echo "claudikins-kernel mobile setup"
echo "  CLAUDE_PROJECT_DIR=$CLAUDE_PROJECT_DIR"
echo "  CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT"
echo ""

# ============================================================
# Step 1 — Dependencies
# ============================================================

echo "▶ Checking dependencies..."

if ! command -v jq &>/dev/null; then
  echo "  Installing jq..."
  apt-get install -y jq 2>/dev/null
else
  echo "  jq: ok"
fi

if ! command -v inotifywait &>/dev/null; then
  echo "  Installing inotify-tools..."
  apt-get install -y inotify-tools 2>/dev/null
else
  echo "  inotify-tools: ok"
fi

# ============================================================
# Step 2 — Directory structure
# ============================================================

echo ""
echo "▶ Initialising .claude/ structure..."
bash "$CLAUDE_PLUGIN_ROOT/hooks/session-startup.sh"

# ============================================================
# Step 3 — Restore uploaded state files if present
# ============================================================

UPLOADS_DIR="/mnt/user-data/uploads"
STATE_FILES="execute-state.json ship-state.json verify-state.json plan-state.json"
RESTORED=0

if [ -d "$UPLOADS_DIR" ]; then
  for f in $STATE_FILES; do
    if [ -f "$UPLOADS_DIR/$f" ]; then
      cp "$UPLOADS_DIR/$f" "$PROJECT_DIR/.claude/$f"
      echo "  Restored: $f"
      RESTORED=$((RESTORED + 1))
    fi
  done
fi

if [ "$RESTORED" -gt 0 ]; then
  echo ""
  echo "  Restored $RESTORED state file(s) from previous session."
fi

# ============================================================
# Step 4 — inotifywait daemon
# ============================================================

echo ""
echo "▶ Starting inotifywait daemon..."

DAEMON_PID_FILE="/home/claude/daemon.pid"
HOOK_LOG="/home/claude/hook-log.txt"
DISPATCH="$CLAUDE_PLUGIN_ROOT/hooks/dispatch.sh"

# Kill any existing daemon
if [ -f "$DAEMON_PID_FILE" ]; then
  OLD_PID=$(cat "$DAEMON_PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID"
    echo "  Stopped previous daemon (pid $OLD_PID)"
  fi
fi

# Start fresh daemon
inotifywait -m -r -e close_write \
  "$PROJECT_DIR" \
  --format '%w%f' 2>/dev/null | while read -r FILE; do
  bash "$DISPATCH" "$FILE" >> "$HOOK_LOG" 2>&1
done &

DAEMON_PID=$!
echo "$DAEMON_PID" > "$DAEMON_PID_FILE"
echo "  Daemon started (pid $DAEMON_PID)"

# ============================================================
# Step 5 — Status summary
# ============================================================

echo ""
echo "▶ Status"
echo "  Daemon:  running (pid $DAEMON_PID)"
echo "  Watching: $PROJECT_DIR"
echo "  Hook log: $HOOK_LOG"
echo ""

# Report existing session state
for f in $STATE_FILES; do
  STATE_PATH="$PROJECT_DIR/.claude/$f"
  if [ -f "$STATE_PATH" ]; then
    STATUS=$(jq -r '.status // "unknown"' "$STATE_PATH" 2>/dev/null || echo "unreadable")
    SESSION=$(jq -r '.session_id // "unknown"' "$STATE_PATH" 2>/dev/null || echo "unknown")
    echo "  $f: session=$SESSION status=$STATUS"
  fi
done

echo ""
echo "claudikins-kernel mobile runtime is live."
echo "Run /kernel-outline, /kernel-execute, /kernel-verify, or /kernel-ship to begin."
