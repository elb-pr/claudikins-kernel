#!/bin/bash
# session-startup.sh - SessionStart hook for claudikins-kernel
# Creates .claude directory structure and initialises plan session state
#
# Runs on every session start. Safe to run multiple times (idempotent).
# Does NOT generate session IDs - that happens when /plan is invoked.

set -euo pipefail

# Trap errors and report them
trap 'echo "session-startup.sh failed at line $LINENO" >&2; exit 1' ERR

# Get project directory from environment or fallback
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"

# ============================================================================
# Phase 1: Create directory structure
# ============================================================================

# Core directories used by all claudikins-kernel commands
mkdir -p "$CLAUDE_DIR/agent-outputs/research"
mkdir -p "$CLAUDE_DIR/agent-outputs/tasks"
mkdir -p "$CLAUDE_DIR/agent-outputs/reviews/spec"
mkdir -p "$CLAUDE_DIR/agent-outputs/reviews/code"
mkdir -p "$CLAUDE_DIR/agent-outputs/verification"
mkdir -p "$CLAUDE_DIR/agent-outputs/simplification"
mkdir -p "$CLAUDE_DIR/agent-outputs/docs"
mkdir -p "$CLAUDE_DIR/evidence"
mkdir -p "$CLAUDE_DIR/plans"
mkdir -p "$CLAUDE_DIR/archive"
mkdir -p "$CLAUDE_DIR/errors"
mkdir -p "$CLAUDE_DIR/tmp"

# Ensure .gitkeep exists for empty directories that should be tracked
touch "$CLAUDE_DIR/.gitkeep"

# ============================================================================
# Phase 2: Session context output (added to Claude's context)
# ============================================================================

# Check for existing plan state
PLAN_STATE="$CLAUDE_DIR/plan-state.json"

if [ -f "$PLAN_STATE" ]; then
    # Parse plan state, distinguishing between missing fields and parse failures
    if ! STATUS=$(jq -r '.status // "not_set"' "$PLAN_STATE" 2>&1); then
        echo "session-startup.sh: WARNING - failed to parse plan-state.json" >&2
        STATUS="parse_error"
    fi
    if ! SESSION_ID=$(jq -r '.session_id // "not_set"' "$PLAN_STATE" 2>&1); then
        SESSION_ID="parse_error"
    fi
    if ! PHASE=$(jq -r '.phase // "not_set"' "$PLAN_STATE" 2>&1); then
        PHASE="parse_error"
    fi
    if ! STARTED=$(jq -r '.started_at // "not_set"' "$PLAN_STATE" 2>&1); then
        STARTED="parse_error"
    fi

    # Calculate age if possible
    if [ "$STARTED" != "not_set" ] && [ "$STARTED" != "parse_error" ] && [ "$STARTED" != "null" ]; then
        START_EPOCH=$(date -d "$STARTED" +%s 2>/dev/null || echo "0")
        NOW_EPOCH=$(date +%s)
        AGE_HOURS=$(( (NOW_EPOCH - START_EPOCH) / 3600 ))
    else
        AGE_HOURS=0
    fi

    # Output JSON for Claude's context (SessionStart stdout is added to context)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Existing plan session found: ${SESSION_ID} (status: ${STATUS}, phase: ${PHASE}, age: ${AGE_HOURS}h). Use --session-id to resume or start fresh with claudikins-kernel:outline."
  }
}
EOF
else
    # No existing session - just confirm directories ready
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "claudikins-kernel directories initialised. Ready for claudikins-kernel:outline command."
  }
}
EOF
fi

exit 0
