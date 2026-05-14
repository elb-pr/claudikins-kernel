#!/bin/bash
# create-task-branch.sh - SubagentStart hook for /execute
# Creates git branch AND worktree when babyclaude spawns for task execution.
# Worktree enables safe parallel execution - each agent gets isolated filesystem.
#
# Matcher: babyclaude (only triggers for this agent type)
# Exit codes:
#   0 - Branch + worktree created successfully (worktree_path in context)
#   2 - Creation failed (blocks agent spawn, informs user)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_DIR/execute-state.json"
WORKTREE_BASE="/tmp/kernel-worktrees"

# Read input JSON from stdin
INPUT=$(cat)

# Diagnostic log — dump ALL keys so we can discover the real ABI
DEBUG_LOG="/tmp/kernel-hooks.log"
{
    echo "=== $(date -u +%FT%TZ) create-task-branch.sh ==="
    echo "FULL_INPUT: $INPUT"
    echo "KEYS: $(echo "$INPUT" | jq -r 'keys | join(",")' 2>/dev/null || echo "?")"
} >> "$DEBUG_LOG" 2>/dev/null || true

# The actual Claude Code SubagentStart hook ABI (empirically discovered, since
# the published docs are wrong) provides these fields in stdin JSON:
#   agent_id, agent_type, cwd, hook_event_name, session_id, transcript_path
# There is NO `prompt` field — so we can't extract TASK_ID from the prompt.
# Identify babyclaude by the `agent_type` field; the value is plugin-namespaced
# (e.g. "claudikins-kernel:babyclaude"), so strip the namespace before checking.
RAW_AGENT=$(echo "$INPUT" | jq -r '.agent_type // .subagent_type // .agent_name // .agentType // ""')
AGENT_NAME="${RAW_AGENT##*:}"

if [ "$AGENT_NAME" != "babyclaude" ]; then
    {
        echo "  -> skipped: agent_type=$RAW_AGENT (not babyclaude)"
    } >> "$DEBUG_LOG" 2>/dev/null || true
    exit 0
fi

# Identify which task is being executed. Since the prompt isn't in hook stdin,
# the orchestrator must write `current_task` to execute-state.json before
# spawning the agent. Read it from there.
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
if [ -n "$HOOK_CWD" ] && [ -f "$HOOK_CWD/.claude/execute-state.json" ]; then
    STATE_FILE="$HOOK_CWD/.claude/execute-state.json"
fi

if [ ! -f "$STATE_FILE" ]; then
    {
        echo "  -> skipped: no execute-state.json found"
    } >> "$DEBUG_LOG" 2>/dev/null || true
    exit 0
fi

TASK_ID=$(jq -r '.current_task // ""' "$STATE_FILE" 2>/dev/null || echo "")
if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
    {
        echo "  -> skipped: current_task not set in state file"
    } >> "$DEBUG_LOG" 2>/dev/null || true
    exit 0
fi

TASK_SLUG=$(jq -r --arg id "$TASK_ID" '(.tasks[] | select(.id == $id)).slug // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")

{
    echo "  -> task work detected: TASK_ID=$TASK_ID TASK_SLUG=$TASK_SLUG agent_type=$RAW_AGENT"
} >> "$DEBUG_LOG" 2>/dev/null || true

# CRITICAL: Hooks may execute with a cwd different from the project root. The
# original script silently no-op'd when that happened (git commands failed,
# exit-2 messages went to stderr nobody read). Force cwd to the project root
# discovered from the hook input.
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
    cd "$HOOK_CWD" || {
        echo "  -> ERROR: cd to HOOK_CWD failed: $HOOK_CWD" >> "$DEBUG_LOG" 2>/dev/null || true
        exit 2
    }
    {
        echo "  -> cd to project: $HOOK_CWD (pwd=$(pwd))"
    } >> "$DEBUG_LOG" 2>/dev/null || true
fi

# Verify we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    {
        echo "  -> ERROR: not a git repository (pwd=$(pwd))"
    } >> "$DEBUG_LOG" 2>/dev/null || true
    echo "ERROR: Not in a git repository. Cannot create task branch." >&2
    echo "  pwd: $(pwd)" >&2
    exit 2
fi

# Check for uncommitted changes that would prevent branch creation
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    {
        echo "  -> ERROR: uncommitted changes detected"
        git status --short 2>&1 | head -5
    } >> "$DEBUG_LOG" 2>/dev/null || true
    echo "ERROR: Uncommitted changes detected. Cannot create task branch." >&2
    exit 2
fi

# Generate UUID suffix for collision prevention (per branch-collision-detection.md)
UUID_SUFFIX=$(uuidgen | cut -d'-' -f1)

# Create branch name: execute/task-{id}-{slug}-{uuid}
BRANCH_NAME="execute/task-${TASK_ID}-${TASK_SLUG}-${UUID_SUFFIX}"

# Create worktree directory
mkdir -p "$WORKTREE_BASE"
WORKTREE_PATH="${WORKTREE_BASE}/task-${TASK_ID}-${UUID_SUFFIX}"

# Create branch first (without checkout - we'll use worktree)
BRANCH_OUTPUT=$(git branch "$BRANCH_NAME" 2>&1) || {
    if ! git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
        {
            echo "  -> ERROR: git branch failed: $BRANCH_OUTPUT"
        } >> "$DEBUG_LOG" 2>/dev/null || true
        echo "ERROR: Failed to create branch: $BRANCH_NAME" >&2
        echo "  git output: $BRANCH_OUTPUT" >&2
        exit 2
    fi
}
{
    echo "  -> branch ready: $BRANCH_NAME"
} >> "$DEBUG_LOG" 2>/dev/null || true

# Create worktree for the branch
if GIT_OUTPUT=$(git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1); then
    {
        echo "  -> worktree created: $WORKTREE_PATH"
    } >> "$DEBUG_LOG" 2>/dev/null || true
    # Update state file with branch and worktree info
    if [ -f "$STATE_FILE" ]; then
        jq --arg branch "$BRANCH_NAME" --arg taskId "$TASK_ID" --arg worktree "$WORKTREE_PATH" \
           '.tasks = [.tasks[] | if .id == $taskId then .branch = $branch | .worktree_path = $worktree else . end]' \
           "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi

    # SubagentStart events don't support hookSpecificOutput — use systemMessage instead
    cat <<EOF
{
  "systemMessage": "WORKTREE_PATH: ${WORKTREE_PATH}\nBRANCH: ${BRANCH_NAME}\n\nYou are working in an isolated worktree. All your file operations happen in: ${WORKTREE_PATH}\n\nDo NOT use git commands - the orchestrator handles all git operations."
}
EOF
    exit 0
else
    # Worktree creation failed - cleanup branch and block
    {
        echo "  -> ERROR: git worktree add failed: $GIT_OUTPUT"
    } >> "$DEBUG_LOG" 2>/dev/null || true
    git branch -D "$BRANCH_NAME" 2>/dev/null || true

    echo "ERROR: Failed to create worktree: $WORKTREE_PATH" >&2
    echo "Git error: $GIT_OUTPUT" >&2
    echo "" >&2
    echo "Possible causes:" >&2
    echo "  - Worktree path already exists (stale from previous run)" >&2
    echo "  - Insufficient permissions on /tmp" >&2
    echo "  - Git worktree limit reached" >&2
    echo "" >&2
    echo "To recover:" >&2
    echo "  1. Clean stale worktrees: git worktree prune" >&2
    echo "  2. Remove manually: rm -rf ${WORKTREE_PATH}" >&2
    echo "  3. List worktrees: git worktree list" >&2
    exit 2
fi
