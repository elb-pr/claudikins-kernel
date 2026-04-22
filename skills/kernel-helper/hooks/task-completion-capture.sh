#!/bin/bash
# task-completion-capture.sh - SubagentStop hook for /execute
# Captures babyclaude task output and updates execution state.
#
# Matcher: babyclaude (only triggers for this agent type)
# Exit codes:
#   0 - Always (capture only, never blocks)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_DIR/execute-state.json"
TRACE_FILE="$CLAUDE_DIR/execute-trace.json"
OUTPUTS_DIR="$CLAUDE_DIR/task-outputs"

# Read input JSON from stdin
INPUT=$(cat)

# Extract agent info
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // ""')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // ""')

# Only act on babyclaude completions
if [ "$AGENT_NAME" != "babyclaude" ]; then
    exit 0
fi

# Check if we're in an active execution session
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

# Create outputs directory if needed
mkdir -p "$OUTPUTS_DIR"

# Get current task from state
CURRENT_TASK=$(jq -r '.current_task // ""' "$STATE_FILE" 2>/dev/null || echo "")
TIMESTAMP=$(date -Iseconds)

if [ -z "$CURRENT_TASK" ]; then
    # No task tracked - log warning but don't fail
    echo "Warning: SubagentStop for babyclaude but no current_task in state" >&2
    exit 0
fi

# Try to extract task output from transcript
# The transcript is a JSONL file - look for the agent's final output
TASK_OUTPUT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Extract the last assistant message that looks like JSON output
    TASK_OUTPUT=$(tail -50 "$TRANSCRIPT_PATH" | \
        grep -oP '\{[^{}]*"status"[^{}]*\}' | \
        tail -1 || echo "")
fi

# If no structured output found, create a basic completion record
if [ -z "$TASK_OUTPUT" ]; then
    TASK_OUTPUT=$(cat <<EOF
{
  "task_id": "$CURRENT_TASK",
  "status": "completed",
  "note": "Output not captured - check transcript",
  "transcript_path": "$TRANSCRIPT_PATH"
}
EOF
)
fi

# Save task output to file
OUTPUT_FILE="$OUTPUTS_DIR/${CURRENT_TASK}.json"
echo "$TASK_OUTPUT" > "$OUTPUT_FILE"

# Backup in case of failure (per A-6 pattern)
BACKUP_FILE="$OUTPUTS_DIR/.backup-${CURRENT_TASK}-$(date +%s).json"
echo "$TASK_OUTPUT" > "$BACKUP_FILE"

# Update task status in state file
jq --arg taskId "$CURRENT_TASK" \
   --arg status "completed" \
   --arg time "$TIMESTAMP" \
   --arg outputFile "$OUTPUT_FILE" \
   '(.tasks[] | select(.id == $taskId)) += {
      "status": $status,
      "completed_at": $time,
      "output_file": $outputFile
    }' \
   "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# Complete span in trace file
if [ -f "$TRACE_FILE" ]; then
    # Calculate duration if we have start time
    START_TIME=$(jq -r --arg taskId "$CURRENT_TASK" \
        '(.spans[] | select(.span_id == ("task-" + $taskId))).start_time // ""' \
        "$TRACE_FILE" 2>/dev/null || echo "")

    if [ -n "$START_TIME" ]; then
        START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || echo "0")
        END_EPOCH=$(date +%s)
        DURATION_MS=$(( (END_EPOCH - START_EPOCH) * 1000 ))
    else
        DURATION_MS=0
    fi

    jq --arg taskId "$CURRENT_TASK" \
       --arg endTime "$TIMESTAMP" \
       --argjson duration "$DURATION_MS" \
       '(.spans[] | select(.span_id == ("task-" + $taskId))) += {
          "end_time": $endTime,
          "duration_ms": $duration,
          "status": "completed"
        }' \
       "$TRACE_FILE" > "${TRACE_FILE}.tmp" 2>/dev/null && mv "${TRACE_FILE}.tmp" "$TRACE_FILE"
fi

# Check if this completes the current batch
BATCH_ID=$(jq -r '.current_batch // 0' "$STATE_FILE" 2>/dev/null || echo "0")
BATCH_TASKS=$(jq -r --argjson batch "$BATCH_ID" \
    '.batches[$batch - 1].tasks // [] | .[]' "$STATE_FILE" 2>/dev/null || echo "")

ALL_COMPLETE=true
for task in $BATCH_TASKS; do
    TASK_STATUS=$(jq -r --arg t "$task" \
        '(.tasks[] | select(.id == $t)).status // "pending"' \
        "$STATE_FILE" 2>/dev/null || echo "pending")
    if [ "$TASK_STATUS" != "completed" ] && [ "$TASK_STATUS" != "failed" ]; then
        ALL_COMPLETE=false
        break
    fi
done

# If batch complete, update state
if [ "$ALL_COMPLETE" = true ]; then
    jq --argjson batch "$BATCH_ID" \
       '.batches[$batch - 1].status = "review_pending"' \
       "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

# Clear current_task (ready for next task)
jq '.current_task = null' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# Get worktree path to capture diff for reviewers
WORKTREE_PATH=$(jq -r --arg taskId "$CURRENT_TASK" \
    '(.tasks[] | select(.id == $taskId)).worktree_path // ""' \
    "$STATE_FILE" 2>/dev/null || echo "")

# Capture diff from worktree for review context injection
DIFF_CONTENT=""
CHANGED_FILES=""
if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
    # Get list of changed files
    CHANGED_FILES=$(git -C "$WORKTREE_PATH" diff --name-only HEAD~1 2>/dev/null | head -20 || echo "")

    # Get the actual diff (limit size to avoid context overflow)
    DIFF_CONTENT=$(git -C "$WORKTREE_PATH" diff HEAD~1 --no-color 2>/dev/null | head -500 || echo "")

    # If diff is too large, summarize
    DIFF_LINES=$(echo "$DIFF_CONTENT" | wc -l)
    if [ "$DIFF_LINES" -ge 500 ]; then
        DIFF_CONTENT="${DIFF_CONTENT}

... (diff truncated at 500 lines, full diff in worktree)"
    fi
fi

# Build review context
REVIEW_CONTEXT="## Task ${CURRENT_TASK} Completed

### Task Output
\`\`\`json
${TASK_OUTPUT}
\`\`\`

### Changed Files
${CHANGED_FILES:-No files captured}

### Implementation Diff
\`\`\`diff
${DIFF_CONTENT:-No diff captured - check worktree at ${WORKTREE_PATH}}
\`\`\`

Ready for /spec-review and /code-review."

# Escape for JSON (newlines, quotes, backslashes)
REVIEW_CONTEXT_ESCAPED=$(echo "$REVIEW_CONTEXT" | jq -Rs '.')

# Output context for orchestrator - includes diff for reviewer skills
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": ${REVIEW_CONTEXT_ESCAPED}
  }
}
EOF

exit 0
