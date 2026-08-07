#!/bin/bash
# merge-gate.sh - PreToolUse hook for Bash
# Blocks "git merge" unless review verdict exists with PASS status.
# This is the HARD GATE that prevents skipping reviews even under context drift.
#
# Matcher: Bash
# Exit codes:
#   0 - Merge allowed (review passed) or not a merge command
#   2 - Merge blocked (no review or review failed)

# Read JSON input from stdin
INPUT=$(cat)

# Extract the command
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Check if this is a git merge command
if ! echo "$COMMAND" | grep -qE '(^git\s+merge|[|;&]\s*git\s+merge)'; then
    # Not a merge command - allow
    exit 0
fi

# Extract branch name being merged (if present)
# Patterns: "git merge branch-name", "git merge origin/branch"
# POSIX awk is used instead of `grep -oP ... \K` because -P (PCRE) is a GNU
# extension that BSD grep (macOS default) does not support.
MERGE_BRANCH=$(printf '%s\n' "$COMMAND" | awk '{
    while (match($0, /git[ \t]+merge[ \t]+[^ \t;|&]+/)) {
        m = substr($0, RSTART, RLENGTH)
        sub(/^git[ \t]+merge[ \t]+/, "", m)
        print m
        $0 = substr($0, RSTART + RLENGTH)
    }
}')

if [ -z "$MERGE_BRANCH" ]; then
    echo "Cannot determine branch being merged. Merge blocked for safety." >&2
    exit 2
fi

# Extract task ID from branch name
# Format: execute/task-{id}-{slug}-{uuid}
# Shell parameter expansion avoids the non-portable `grep -oP ... \K`.
case "$MERGE_BRANCH" in
    *task-*)
        TASK_ID="${MERGE_BRANCH#*task-}"   # strip through the first "task-"
        TASK_ID="${TASK_ID%%-*}"           # keep up to the next "-"
        ;;
    *)
        TASK_ID=""
        ;;
esac

if [ -z "$TASK_ID" ]; then
    # Not a task branch - might be a regular merge, allow it
    # (Only task branches require review)
    exit 0
fi

# Check for review verdict
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
REVIEW_DIR="$PROJECT_DIR/.claude/reviews"
VERDICT_FILE="$REVIEW_DIR/${TASK_ID}/verdict.json"

if [ ! -f "$VERDICT_FILE" ]; then
    echo "MERGE BLOCKED: No review verdict found for task ${TASK_ID}" >&2
    echo "" >&2
    echo "Required: $VERDICT_FILE" >&2
    echo "" >&2
    echo "You MUST run spec-reviewer and code-reviewer before merging." >&2
    echo "Both must PASS for merge to proceed." >&2
    exit 2
fi

# Check verdict status
SPEC_STATUS=$(jq -r '.spec_review // "MISSING"' "$VERDICT_FILE")
CODE_STATUS=$(jq -r '.code_review // "MISSING"' "$VERDICT_FILE")

if [ "$SPEC_STATUS" != "PASS" ]; then
    echo "MERGE BLOCKED: Spec review did not pass" >&2
    echo "" >&2
    echo "Spec review status: $SPEC_STATUS" >&2
    echo "Code review status: $CODE_STATUS" >&2
    echo "" >&2
    echo "Fix the spec review issues before merging." >&2
    exit 2
fi

if [ "$CODE_STATUS" != "PASS" ] && [ "$CODE_STATUS" != "CONCERNS_ACCEPTED" ]; then
    echo "MERGE BLOCKED: Code review did not pass" >&2
    echo "" >&2
    echo "Spec review status: $SPEC_STATUS" >&2
    echo "Code review status: $CODE_STATUS" >&2
    echo "" >&2
    echo "Fix the code review issues or explicitly accept concerns before merging." >&2
    exit 2
fi

# Both reviews passed - allow merge
exit 0
