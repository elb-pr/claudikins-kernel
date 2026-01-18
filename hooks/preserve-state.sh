#!/bin/bash
# preserve-state.sh - PreCompact hook for claudikins-kernel
# Saves critical state before context compaction for recovery
#
# PreCompact fires when context window is about to be compacted.
# This is our last chance to preserve state before potential context loss.

set -euo pipefail

trap 'echo "preserve-state.sh failed at line $LINENO" >&2; exit 1' ERR

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
PLAN_STATE="$CLAUDE_DIR/plan-state.json"

# Read input from stdin
INPUT=$(cat)

# Check if this is an auto compact (context pressure) vs manual (/compact)
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")

# If no plan state exists, nothing to preserve
if [ ! -f "$PLAN_STATE" ]; then
    exit 0
fi

# Read current state
CURRENT_STATUS=$(jq -r '.status // "unknown"' "$PLAN_STATE" 2>/dev/null || echo "unknown")

# Only preserve if session is active (not already completed/abandoned)
if [ "$CURRENT_STATUS" = "completed" ] || [ "$CURRENT_STATUS" = "abandoned" ]; then
    exit 0
fi

# Mark session as interrupted (recoverable)
TIMESTAMP=$(date -Iseconds)

jq --arg ts "$TIMESTAMP" --arg trigger "$TRIGGER" '
  .status = "interrupted" |
  .interrupted_at = $ts |
  .interrupted_by = $trigger |
  .resume_instructions = "Session interrupted during \(.phase // "unknown") phase. Use claudikins-kernel:plans --session-id \(.session_id) to resume."
' "$PLAN_STATE" > "${PLAN_STATE}.tmp" && mv "${PLAN_STATE}.tmp" "$PLAN_STATE"

# Create a backup in archive
ARCHIVE_DIR="$CLAUDE_DIR/archive"
mkdir -p "$ARCHIVE_DIR"

SESSION_ID=$(jq -r '.session_id // "unknown"' "$PLAN_STATE" 2>/dev/null || echo "unknown")
BACKUP_FILE="$ARCHIVE_DIR/plan-state-${SESSION_ID}-${TIMESTAMP//[:]/-}.json"
cp "$PLAN_STATE" "$BACKUP_FILE"

# Output context for Claude (PreCompact stdout can add context)
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": "Plan session interrupted and state preserved. Session: ${SESSION_ID}. To resume after context compaction: claudikins-kernel:plans --session-id ${SESSION_ID}"
  }
}
EOF

exit 0
