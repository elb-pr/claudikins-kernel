#!/bin/bash
# dispatch.sh - routes file write events to appropriate hooks
# Called by inotifywait daemon with the written file path as $1
# Replaces hooks.json event routing for mobile

set -uo pipefail

FILE="${1:-}"
if [ -z "$FILE" ]; then exit 0; fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
HOOKS="$PLUGIN_ROOT/hooks"
TIMESTAMP=$(date -u +%T)

# ============================================================
# Route by file pattern
# ============================================================

# Always: execute tracker
bash "$HOOKS/execute-tracker.sh" "$FILE" 2>/dev/null
echo "[$TIMESTAMP] execute-tracker: $FILE"

# Source files: autoformat
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md|*.py|*.rs|*.go)
    bash "$PLUGIN_ROOT/../kernel-verify/hooks/autoformat.sh" "$FILE" 2>/dev/null
    echo "[$TIMESTAMP] autoformat: $FILE"
    ;;
esac

# Plan files: validate format
case "$FILE" in
  */.claude/plans/*)
    bash "$PLUGIN_ROOT/../kernel-execute/hooks/validate-plan-format.sh" "$FILE" 2>/dev/null
    echo "[$TIMESTAMP] validate-plan-format: $FILE"
    ;;
esac

# Task output: batch checkpoint gate
case "$FILE" in
  */.claude/agent-outputs/tasks/*)
    bash "$PLUGIN_ROOT/../kernel-execute/hooks/batch-checkpoint-gate.sh" "$FILE" 2>/dev/null
    echo "[$TIMESTAMP] batch-checkpoint-gate: $FILE"
    ;;
esac

# Verification output: verify gate
case "$FILE" in
  */.claude/agent-outputs/verification/*)
    bash "$PLUGIN_ROOT/../kernel-verify/hooks/verify-gate.sh" "$FILE" 2>/dev/null
    echo "[$TIMESTAMP] verify-gate: $FILE"
    ;;
esac

# Agent output: trace end
case "$FILE" in
  */.claude/agent-outputs/*)
    bash "$HOOKS/trace-end.sh" "$FILE" 2>/dev/null
    echo "[$TIMESTAMP] trace-end: $FILE"
    ;;
esac

exit 0
