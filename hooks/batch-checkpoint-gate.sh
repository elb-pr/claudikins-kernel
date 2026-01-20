#!/bin/bash
# batch-checkpoint-gate.sh - Stop hook for /execute
# Saves checkpoint state when session ends during active execution.
# Enables resume from last checkpoint if context exhausted or session dies.
#
# Exit codes:
#   0 - Always (checkpoint save, never blocks)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_DIR/execute-state.json"
TRACE_FILE="$CLAUDE_DIR/execute-trace.json"
CHECKPOINTS_DIR="$CLAUDE_DIR/checkpoints"

# Read input JSON from stdin (Stop hook receives stop reason)
INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // "unknown"')

# Check if we're in an active execution session
if [ ! -f "$STATE_FILE" ]; then
    exit 0  # No active session, nothing to checkpoint
fi

STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null || echo "")
if [ "$STATUS" != "executing" ]; then
    exit 0  # Not actively executing
fi

# Create checkpoints directory if needed
mkdir -p "$CHECKPOINTS_DIR"

# Generate checkpoint ID
CHECKPOINT_ID="checkpoint-$(date +%Y%m%d-%H%M%S)"
CHECKPOINT_FILE="$CHECKPOINTS_DIR/${CHECKPOINT_ID}.json"
TIMESTAMP=$(date -Iseconds)

# Get current execution state
CURRENT_BATCH=$(jq -r '.current_batch // 0' "$STATE_FILE" 2>/dev/null || echo "0")
CURRENT_TASK=$(jq -r '.current_task // null' "$STATE_FILE" 2>/dev/null || echo "null")
SESSION_ID=$(jq -r '.session_id // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")

# Count task statuses
TOTAL_TASKS=$(jq -r '.tasks | length // 0' "$STATE_FILE" 2>/dev/null || echo "0")
COMPLETED_TASKS=$(jq -r '[.tasks[] | select(.status == "completed")] | length // 0' "$STATE_FILE" 2>/dev/null || echo "0")
IN_PROGRESS_TASKS=$(jq -r '[.tasks[] | select(.status == "in_progress")] | length // 0' "$STATE_FILE" 2>/dev/null || echo "0")

# Build checkpoint data
CHECKPOINT_DATA=$(jq -n \
    --arg id "$CHECKPOINT_ID" \
    --arg sessionId "$SESSION_ID" \
    --arg timestamp "$TIMESTAMP" \
    --arg stopReason "$STOP_REASON" \
    --argjson currentBatch "$CURRENT_BATCH" \
    --argjson currentTask "$CURRENT_TASK" \
    --argjson totalTasks "$TOTAL_TASKS" \
    --argjson completedTasks "$COMPLETED_TASKS" \
    --argjson inProgressTasks "$IN_PROGRESS_TASKS" \
    '{
      "checkpoint_id": $id,
      "session_id": $sessionId,
      "timestamp": $timestamp,
      "stop_reason": $stopReason,
      "execution_state": {
        "current_batch": $currentBatch,
        "current_task": $currentTask,
        "total_tasks": $totalTasks,
        "completed_tasks": $completedTasks,
        "in_progress_tasks": $inProgressTasks
      },
      "recovery_instructions": "Run claudikins-kernel:execute --resume to continue from this checkpoint"
    }')

# Add full state snapshot
CHECKPOINT_DATA=$(echo "$CHECKPOINT_DATA" | jq --slurpfile state "$STATE_FILE" '. + {"state_snapshot": $state[0]}')

# Add trace snapshot if exists
if [ -f "$TRACE_FILE" ]; then
    CHECKPOINT_DATA=$(echo "$CHECKPOINT_DATA" | jq --slurpfile trace "$TRACE_FILE" '. + {"trace_snapshot": $trace[0]}')
fi

# Save checkpoint
echo "$CHECKPOINT_DATA" > "$CHECKPOINT_FILE"

# Update state with checkpoint reference
jq --arg checkpointId "$CHECKPOINT_ID" \
   --arg checkpointFile "$CHECKPOINT_FILE" \
   --arg timestamp "$TIMESTAMP" \
   '. + {
      "last_checkpoint": $checkpointId,
      "last_checkpoint_file": $checkpointFile,
      "last_checkpoint_at": $timestamp
    }' \
   "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# Clean old checkpoints (keep last 5, only delete files >1min old to avoid race)
find "$CHECKPOINTS_DIR" -name "checkpoint-*.json" -mmin +1 -type f 2>/dev/null | \
    sort -r | tail -n +6 | xargs -r rm -f

# Build resume message - user only sees this instruction
RESUME_MSG="Run claudikins-kernel:execute --resume to continue."

# Output Stop hook JSON using jq for proper escaping
# Stop hooks: {"continue": false, "stopReason": "..."} allows stopping with message
jq -n --arg reason "$RESUME_MSG" '{"continue": false, "stopReason": $reason}'

exit 0
