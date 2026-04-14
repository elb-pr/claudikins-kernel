#!/usr/bin/env bash
# sanitize-bash.sh - Sanitize bash commands using updatedInput pattern
# This is a PreToolUse/Bash hook that demonstrates the updatedInput capability
# It can modify the command before execution (e.g., add safety flags)

set -euo pipefail

# Read hook input
HOOK_INPUT="${CLAUDE_HOOK_INPUT:-}"
if [[ -z "$HOOK_INPUT" ]]; then
    # No input, allow
    echo '{"decision": "approve"}'
    exit 0
fi

# Parse the command from input
COMMAND=$(echo "$HOOK_INPUT" | jq -r '.toolInput.command // empty')
if [[ -z "$COMMAND" ]]; then
    echo '{"decision": "approve"}'
    exit 0
fi

# Example sanitizations (extend as needed):

# 1. Add --no-edit to git commit if not present (prevents interactive editor)
if [[ "$COMMAND" =~ ^git[[:space:]]+commit && ! "$COMMAND" =~ --no-edit ]]; then
    # Don't modify if it already has -m (message provided)
    if [[ ! "$COMMAND" =~ -m[[:space:]] ]]; then
        SANITIZED="${COMMAND} --no-edit"
        # updatedInput must be inside hookSpecificOutput for PreToolUse events
        jq -n --arg cmd "$SANITIZED" '{
          "decision": "approve",
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "updatedInput": {"command": $cmd}
          }
        }'
        exit 0
    fi
fi

# 2. Prevent rm -rf on dangerous paths
if [[ "$COMMAND" =~ rm[[:space:]]+-rf?[[:space:]]+(\/|~|\$HOME) ]]; then
    echo '{"decision": "block", "reason": "Refusing to rm -rf on root, home, or $HOME"}'
    exit 0
fi

# 3. Add -n (dry-run) to rsync if --delete is used without explicit confirmation
# (This is an example - in practice you might want different behavior)

# Default: allow without modification
echo '{"decision": "approve"}'
