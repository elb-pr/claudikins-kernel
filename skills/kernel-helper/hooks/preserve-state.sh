#!/bin/bash
# preserve-state.sh - PreCompact hook for claudikins-kernel
# Saves critical state before context compaction for recovery
#
# PreCompact fires when context window is about to be compacted.
# This is our last chance to preserve state before potential context loss.
#
# Exit codes:
#   0 - Success (always output valid JSON to stdout)
#   1 - Non-blocking error (logged, execution continues)

set -uo pipefail
# Note: removed -e to handle errors manually and always produce valid JSON

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
PLAN_STATE="$CLAUDE_DIR/plan-state.json"

# Helper: output noop JSON and exit (for early-exit paths)
output_noop() {
    cat <<'NOOP_EOF'
{}
NOOP_EOF
    exit 0
}

# Helper: output success JSON
output_success() {
    local session_id="$1"
    local phase="$2"
    local resume_cmd

    # Generate phase-appropriate resume command
    case "$phase" in
        outline)
            resume_cmd="claudikins-kernel:outline --session-id ${session_id}"
            ;;
        execute|verify|ship)
            resume_cmd="claudikins-kernel:${phase} --resume ${session_id}"
            ;;
        *)
            resume_cmd="claudikins-kernel:outline --session-id ${session_id}"
            ;;
    esac

    # PreCompact events don't support hookSpecificOutput — use systemMessage instead
    cat <<EOF
{
  "systemMessage": "Plan session interrupted and state preserved. Session: ${session_id}. To resume after context compaction: ${resume_cmd}"
}
EOF
    exit 0
}

# Cleanup .tmp file on any exit
cleanup() {
    rm -f "${PLAN_STATE}.tmp" 2>/dev/null || true
}
trap cleanup EXIT

# Read input from stdin
INPUT=$(cat)

# Check if this is an auto compact (context pressure) vs manual (/compact)
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")

# If no plan state exists, nothing to preserve
if [ ! -f "$PLAN_STATE" ]; then
    output_noop
fi

# Validate plan-state.json is valid JSON before processing
if ! jq empty "$PLAN_STATE" 2>/dev/null; then
    # Corrupted JSON - can't preserve, just log and exit cleanly
    echo "Warning: plan-state.json contains invalid JSON, cannot preserve state" >&2
    output_noop
fi

# Read current state (safe - we validated JSON above)
CURRENT_STATUS=$(jq -r '.status // "unknown"' "$PLAN_STATE" 2>/dev/null || echo "unknown")

# Only preserve if session is active (not already completed/abandoned)
if [ "$CURRENT_STATUS" = "completed" ] || [ "$CURRENT_STATUS" = "abandoned" ]; then
    output_noop
fi

# Mark session as interrupted (recoverable)
TIMESTAMP=$(date -Iseconds)

# Read phase for resume command generation
PHASE=$(jq -r '.phase // "unknown"' "$PLAN_STATE" 2>/dev/null || echo "unknown")

# Try to update the state file
if jq --arg ts "$TIMESTAMP" --arg trigger "$TRIGGER" '
  # Generate phase-appropriate resume command
  (.phase // "unknown") as $phase |
  (if $phase == "outline" then "claudikins-kernel:outline --session-id \(.session_id)"
   elif $phase == "execute" or $phase == "verify" or $phase == "ship" then "claudikins-kernel:\($phase) --resume \(.session_id)"
   else "claudikins-kernel:outline --session-id \(.session_id)" end) as $resume_cmd |
  .status = "interrupted" |
  .interrupted_at = $ts |
  .interrupted_by = $trigger |
  .resume_instructions = "Session interrupted during \($phase) phase. To resume: \($resume_cmd)"
' "$PLAN_STATE" > "${PLAN_STATE}.tmp" 2>/dev/null && [ -s "${PLAN_STATE}.tmp" ]; then
    mv "${PLAN_STATE}.tmp" "$PLAN_STATE"
else
    # jq failed or produced empty output - log warning and continue
    echo "Warning: Failed to update plan-state.json during PreCompact" >&2
    rm -f "${PLAN_STATE}.tmp" 2>/dev/null || true
fi

# Create a backup in archive (best effort)
ARCHIVE_DIR="$CLAUDE_DIR/archive"
mkdir -p "$ARCHIVE_DIR" 2>/dev/null || true

SESSION_ID=$(jq -r '.session_id // "unknown"' "$PLAN_STATE" 2>/dev/null || echo "unknown")
BACKUP_FILE="$ARCHIVE_DIR/plan-state-${SESSION_ID}-${TIMESTAMP//[:]/-}.json"
cp "$PLAN_STATE" "$BACKUP_FILE" 2>/dev/null || true

# Output success JSON
output_success "$SESSION_ID" "$PHASE"
