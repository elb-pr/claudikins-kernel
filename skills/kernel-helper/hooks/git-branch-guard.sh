#!/bin/bash
# git-branch-guard.sh - PreToolUse hook for /execute
# Blocks dangerous git operations during task execution.
#
# Matcher: Bash (only checks bash commands)
# Exit codes:
#   0 - Command allowed
#   2 - Command blocked (dangerous git operation)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
STATE_FILE="$CLAUDE_DIR/execute-state.json"

# Read input JSON from stdin
INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only check Bash tool
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# Check if we're in an active execution session
if [ ! -f "$STATE_FILE" ]; then
    exit 0  # No active session, allow all
fi

STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null || echo "")
if [ "$STATUS" != "executing" ]; then
    exit 0  # Not actively executing, allow all
fi

# Extract the command
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Skip if not a git command
if ! echo "$COMMAND" | grep -qE '^\s*git\s'; then
    exit 0
fi

# ALLOWLIST APPROACH - Only permit known-safe git operations
# Everything else is blocked by default. This is safer than blocklisting
# because new dangerous commands (like cherry-pick) can't slip through.

# Safe git subcommands that agents may use during task execution:
#   add        - Stage changes
#   status     - Check working tree state
#   diff       - View changes
#   log        - View history
#   show       - View commits/objects
#   ls-files   - List tracked files
#   check-ignore - Check gitignore rules
#   rev-parse  - Parse revisions
#   symbolic-ref - Read/modify symbolic refs
#   config     - Read config (--get, --list only)
#   commit     - Commit staged changes

# Extract the git subcommand
GIT_SUBCOMMAND=$(echo "$COMMAND" | sed -n 's/.*git\s\+\([a-z-]\+\).*/\1/p')

# Allowlist of safe git subcommands
case "$GIT_SUBCOMMAND" in
    add|status|diff|log|show|ls-files|check-ignore|rev-parse|symbolic-ref|commit)
        # These are safe - allow them
        exit 0
        ;;
    config)
        # git config is safe only for reading (--get, --list, --get-all, --get-regexp)
        if echo "$COMMAND" | grep -qE 'git\s+config\s+(--get|--list|--get-all|--get-regexp)'; then
            exit 0
        fi
        echo "BLOCKED: git config write operation during task execution" >&2
        echo "" >&2
        echo "Command: $COMMAND" >&2
        echo "" >&2
        echo "Only read operations allowed: git config --get, git config --list" >&2
        exit 2
        ;;
    *)
        # Everything else is blocked
        echo "BLOCKED: Unsafe git operation during task execution" >&2
        echo "" >&2
        echo "Command: $COMMAND" >&2
        echo "Subcommand: $GIT_SUBCOMMAND" >&2
        echo "" >&2
        echo "During claudikins-kernel:execute, only safe git operations are allowed:" >&2
        echo "  - git add, git commit (modify your work)" >&2
        echo "  - git status, git diff, git log, git show (inspect state)" >&2
        echo "  - git ls-files, git check-ignore (query files)" >&2
        echo "  - git rev-parse, git symbolic-ref (query refs)" >&2
        echo "  - git config --get/--list (read config)" >&2
        echo "" >&2
        echo "Blocked operations include: checkout, switch, reset, clean, push," >&2
        echo "pull, fetch, rebase, merge, stash, cherry-pick, revert, tag, branch -d" >&2
        echo "" >&2
        echo "If you need these operations, complete your task first." >&2
        exit 2
        ;;
esac
