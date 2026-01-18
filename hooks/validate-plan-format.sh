#!/bin/bash
# validate-plan-format.sh - UserPromptSubmit hook for /execute command
# Validates that the plan file has EXECUTION_TASKS markers before allowing execution.
#
# Exit codes:
#   0 - Plan valid or not an /execute command (allow)
#   2 - Plan missing markers (block with stderr message)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"

# Read input JSON from stdin
INPUT=$(cat)

# Extract prompt from JSON
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')

# Only validate if this is an /execute command
if ! echo "$PROMPT" | grep -qE '^/execute'; then
    exit 0
fi

# Extract plan path from arguments, or use default
# Patterns: /execute <path>, /execute --flag <path>, etc.
PLAN_PATH=""

# Try to extract path argument (first non-flag argument after /execute)
# Use array to handle paths with spaces correctly
ARGS=$(echo "$PROMPT" | sed 's|^/execute||')
read -ra ARGS_ARRAY <<< "$ARGS"
for arg in "${ARGS_ARRAY[@]}"; do
    # Skip flags
    if [[ "$arg" == --* ]] || [[ "$arg" == -* ]]; then
        continue
    fi
    PLAN_PATH="$arg"
    break
done

# If no path specified, check for most recent plan in .claude/plans/
if [ -z "$PLAN_PATH" ]; then
    if [ -d "$CLAUDE_DIR/plans" ]; then
        PLAN_PATH=$(find "$CLAUDE_DIR/plans" -name "*.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    fi
fi

# If still no plan, check plan-state.json for active plan
if [ -z "$PLAN_PATH" ] && [ -f "$CLAUDE_DIR/plan-state.json" ]; then
    PLAN_PATH=$(jq -r '.output_file // empty' "$CLAUDE_DIR/plan-state.json" 2>/dev/null || true)
fi

# Validate we have a plan path
if [ -z "$PLAN_PATH" ]; then
    echo "No plan file specified and no recent plan found. Run claudikins-kernel:plans first or specify a plan path." >&2
    exit 2
fi

# Resolve relative paths
if [[ "$PLAN_PATH" != /* ]]; then
    PLAN_PATH="$PROJECT_DIR/$PLAN_PATH"
fi

# Check plan file exists
if [ ! -f "$PLAN_PATH" ]; then
    echo "Plan file not found: $PLAN_PATH" >&2
    exit 2
fi

# Check for EXECUTION_TASKS markers
HAS_START=$(grep -c '<!-- EXECUTION_TASKS_START -->' "$PLAN_PATH" 2>/dev/null || echo "0")
HAS_END=$(grep -c '<!-- EXECUTION_TASKS_END -->' "$PLAN_PATH" 2>/dev/null || echo "0")

if [ "$HAS_START" -eq 0 ] || [ "$HAS_END" -eq 0 ]; then
    echo "Plan missing EXECUTION_TASKS markers. The plan must include:" >&2
    echo "" >&2
    echo "  <!-- EXECUTION_TASKS_START -->" >&2
    echo "  | # | Task | Files | Deps | Batch |" >&2
    echo "  |---|------|-------|------|-------|" >&2
    echo "  | 1 | ... | ... | ... | ... |" >&2
    echo "  <!-- EXECUTION_TASKS_END -->" >&2
    echo "" >&2
    echo "Re-run claudikins-kernel:plans to generate a properly formatted plan." >&2
    exit 2
fi

# Validate markers are in correct order (START before END)
START_LINE=$(grep -n '<!-- EXECUTION_TASKS_START -->' "$PLAN_PATH" | head -1 | cut -d: -f1)
END_LINE=$(grep -n '<!-- EXECUTION_TASKS_END -->' "$PLAN_PATH" | head -1 | cut -d: -f1)

if [ "$START_LINE" -ge "$END_LINE" ]; then
    echo "EXECUTION_TASKS markers are malformed (END before START). Re-run claudikins-kernel:plans." >&2
    exit 2
fi

# Check there's content between markers
TASK_LINES=$((END_LINE - START_LINE - 1))
if [ "$TASK_LINES" -lt 3 ]; then
    echo "EXECUTION_TASKS section appears empty (need at least header + separator + 1 task). Re-run claudikins-kernel:plans." >&2
    exit 2
fi

# Plan is valid - allow execution
exit 0
