#!/usr/bin/env bash
# trace-start.sh - Start a trace span when an agent starts
# SubagentStart hook for execution tracing

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TRACES_DIR="${PROJECT_DIR}/.claude/traces"
TRACE_FILE="${TRACES_DIR}/current-trace.json"

# Ensure traces directory exists
mkdir -p "$TRACES_DIR"

# Read hook input
HOOK_INPUT="${CLAUDE_HOOK_INPUT:-}"
if [[ -z "$HOOK_INPUT" ]]; then
    exit 0
fi

# Extract agent info
AGENT_NAME=$(echo "$HOOK_INPUT" | jq -r '.agentType // "unknown"')
AGENT_ID=$(echo "$HOOK_INPUT" | jq -r '.agentId // "unknown"')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get or create session ID
SESSION_ID=""
if [[ -f "${PROJECT_DIR}/.claude/execute-state.json" ]]; then
    SESSION_ID=$(jq -r '.session_id // empty' "${PROJECT_DIR}/.claude/execute-state.json" 2>/dev/null || true)
fi
if [[ -z "$SESSION_ID" ]]; then
    SESSION_ID="trace-$(date +%Y%m%d-%H%M%S)"
fi

# Initialise trace file if it doesn't exist
if [[ ! -f "$TRACE_FILE" ]]; then
    cat > "$TRACE_FILE" << INIT
{
  "session_id": "$SESSION_ID",
  "started_at": "$TIMESTAMP",
  "spans": []
}
INIT
fi

# Create span entry
SPAN=$(jq -n \
    --arg name "$AGENT_NAME" \
    --arg id "$AGENT_ID" \
    --arg start "$TIMESTAMP" \
    '{
        "name": $name,
        "agent_id": $id,
        "start": $start,
        "end": null,
        "duration_ms": null,
        "status": "running"
    }')

# Append span to trace file
jq --argjson span "$SPAN" '.spans += [$span]' "$TRACE_FILE" > "${TRACE_FILE}.tmp" && mv "${TRACE_FILE}.tmp" "$TRACE_FILE"

# Output for debugging (optional)
# echo "Trace span started: $AGENT_NAME ($AGENT_ID)"
