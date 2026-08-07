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

# Extract agent name
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // ""')

# Only act on babyclaude spawns
if [ "$AGENT_NAME" != "babyclaude" ]; then
    exit 0
fi

# Extract task info from prompt (passed by execute command)
# Format expected: TASK_ID: <id> TASK_SLUG: <slug>
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
# `sed -nE` is used instead of `grep -oP ... \K` because -P (PCRE) is a GNU
# extension that BSD grep (macOS default) does not support.
TASK_ID=$(printf '%s\n' "$PROMPT" | sed -nE 's/.*TASK_ID:[[:space:]]*([^[:space:]]+).*/\1/p' | head -1)
TASK_SLUG=$(printf '%s\n' "$PROMPT" | sed -nE 's/.*TASK_SLUG:[[:space:]]*([^[:space:]]+).*/\1/p' | head -1)
TASK_SLUG="${TASK_SLUG:-unknown}"

# If no task ID, this isn't a task execution - allow spawn
if [ -z "$TASK_ID" ]; then
    exit 0
fi

# Verify we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not in a git repository. Cannot create task branch." >&2
    echo "" >&2
    echo "The claudikins-kernel:execute command requires a git repository to manage task branches." >&2
    echo "Run 'git init' first, or navigate to an existing repository." >&2
    exit 2
fi

# Check for uncommitted changes that would prevent branch creation
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "ERROR: Uncommitted changes detected. Cannot create task branch." >&2
    echo "" >&2
    echo "Please commit or stash your changes before running claudikins-kernel:execute:" >&2
    echo "  git stash        # Temporarily store changes" >&2
    echo "  git commit -am 'WIP'  # Commit changes" >&2
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
if ! git branch "$BRANCH_NAME" 2>/dev/null; then
    # Branch might already exist from a previous failed attempt - that's ok
    if ! git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
        echo "ERROR: Failed to create branch: $BRANCH_NAME" >&2
        exit 2
    fi
fi

# Create worktree for the branch
if GIT_OUTPUT=$(git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1); then
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
