#!/bin/bash
# execute-tracker.sh - PostToolUse hook for /execute
# Tracks tool usage during task execution for stuck detection and tracing.
#
# Exit codes:
#   0 - Always (tracking only, never blocks)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_DIR/execute-state.json"
TRACE_FILE="$CLAUDE_DIR/execute-trace.json"

# === File Locking (C-8) — portable (works on macOS + Linux) ===
LOCK_DIR="${STATE_FILE}.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "execute-tracker: Another process is modifying state, skipping" >&2
    exit 0  # Don't block, just skip this update
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# Read input JSON from stdin
INPUT=$(cat)

# Check if we're in an active execution session
if [ ! -f "$STATE_FILE" ]; then
    exit 0  # No active session
fi

STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null || echo "")
if [ "$STATUS" != "executing" ]; then
    exit 0  # Not actively executing
fi

# Extract tool info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
TOOL_RESULT=$(echo "$INPUT" | jq -r '.tool_result // ""' | head -c 500)  # Truncate for storage
TIMESTAMP=$(date -Iseconds)

# Get current task from state
CURRENT_TASK=$(jq -r '.current_task // ""' "$STATE_FILE" 2>/dev/null || echo "")

if [ -z "$CURRENT_TASK" ]; then
    exit 0  # No current task being tracked
fi

# Initialize trace file if it doesn't exist
if [ ! -f "$TRACE_FILE" ]; then
    echo '{"spans": [], "tool_calls": []}' > "$TRACE_FILE"
fi

# Record tool call for tracing
if ! jq --arg task "$CURRENT_TASK" \
   --arg tool "$TOOL_NAME" \
   --arg time "$TIMESTAMP" \
   --arg result "${TOOL_RESULT:0:200}" \
   '.tool_calls += [{"task_id": $task, "tool": $tool, "timestamp": $time, "result_preview": $result}]' \
   "$TRACE_FILE" > "${TRACE_FILE}.tmp" 2>&1; then
    echo "execute-tracker: WARNING - trace file update failed" >&2
fi
mv "${TRACE_FILE}.tmp" "$TRACE_FILE" 2>/dev/null || true

# Update task stats in state file
# Increment tool call count
if ! jq --arg taskId "$CURRENT_TASK" \
   --arg tool "$TOOL_NAME" \
   '(.tasks[] | select(.id == $taskId)).tool_calls += 1 |
    (.tasks[] | select(.id == $taskId)).last_tool = $tool |
    (.tasks[] | select(.id == $taskId)).last_activity = now' \
   "$STATE_FILE" > "${STATE_FILE}.tmp" 2>&1; then
    echo "execute-tracker: WARNING - state file update failed" >&2
fi
mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true

# --- Stuck Detection ---

# Get recent tool calls for this task
RECENT_CALLS=$(jq --arg task "$CURRENT_TASK" \
    '[.tool_calls[] | select(.task_id == $task)] | .[-20:]' \
    "$TRACE_FILE" 2>/dev/null || echo "[]")

# Check for repeated same tool (potential stuck indicator)
REPEATED_COUNT=$(echo "$RECENT_CALLS" | jq --arg tool "$TOOL_NAME" \
    '[.[] | select(.tool == $tool)] | length' 2>/dev/null || echo "0")

# Check for tool flood (many calls without file changes)
TOTAL_RECENT=$(echo "$RECENT_CALLS" | jq 'length' 2>/dev/null || echo "0")
FILE_CHANGING_TOOLS=$(echo "$RECENT_CALLS" | jq \
    '[.[] | select(.tool == "Edit" or .tool == "Write")] | length' 2>/dev/null || echo "0")

# Calculate stuck score
STUCK_SCORE=0

# Same tool repeated 5+ times in last 20 calls
if [ "$REPEATED_COUNT" -ge 5 ]; then
    STUCK_SCORE=$((STUCK_SCORE + 40))
fi

# 15+ tool calls without file changes
if [ "$TOTAL_RECENT" -ge 15 ] && [ "$FILE_CHANGING_TOOLS" -eq 0 ]; then
    STUCK_SCORE=$((STUCK_SCORE + 50))
fi

# Update stuck score in state
if ! jq --arg taskId "$CURRENT_TASK" \
   --argjson score "$STUCK_SCORE" \
   '(.tasks[] | select(.id == $taskId)).stuck_score = $score' \
   "$STATE_FILE" > "${STATE_FILE}.tmp" 2>&1; then
    echo "execute-tracker: WARNING - stuck score update failed" >&2
fi
mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true

# Output warning if stuck score is high (but don't block)
if [ "$STUCK_SCORE" -ge 60 ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "WARNING: Task may be stuck (score: ${STUCK_SCORE}/100). ${REPEATED_COUNT} repeated ${TOOL_NAME} calls. Consider trying a different approach or asking for help."
  }
}
EOF
fi

exit 0
