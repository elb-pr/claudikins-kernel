#!/usr/bin/env bash
# trace-start.sh - Start a trace span when an agent starts
# SubagentStart hook for execution tracing

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TRACES_DIR="${PROJECT_DIR}/.claude/traces"
TRACE_FILE="${TRACES_DIR}/current-trace.json"

# Ensure traces directory exists
mkdir -p "$TRACES_DIR"

# Read hook input. Claude Code delivers hook input via stdin as JSON; the env-var
# form (CLAUDE_HOOK_INPUT) is not part of the documented ABI, so prefer stdin and
# fall back to the env var only if stdin is empty (for forward/backward compat).
if [[ -t 0 ]]; then
    HOOK_INPUT="${CLAUDE_HOOK_INPUT:-}"
else
    HOOK_INPUT="$(cat)"
    if [[ -z "$HOOK_INPUT" ]]; then
        HOOK_INPUT="${CLAUDE_HOOK_INPUT:-}"
    fi
fi
if [[ -z "$HOOK_INPUT" ]]; then
    exit 0
fi

# Diagnostic log
DEBUG_LOG="/tmp/kernel-hooks.log"
{
    echo "=== $(date -u +%FT%TZ) trace-start.sh ==="
    echo "$HOOK_INPUT" | jq -c '. | {hook_event_name, subagent_type, agent_name, agentType, agentId}' 2>/dev/null || echo "raw: $HOOK_INPUT"
} >> "$DEBUG_LOG" 2>/dev/null || true

# Extract agent info. Empirical ABI: field is `agent_type` (snake_case),
# plugin-namespaced (e.g. "claudikins-kernel:babyclaude").
RAW_AGENT=$(echo "$HOOK_INPUT" | jq -r '.agent_type // .subagent_type // .agentType // .agent_name // "unknown"')
AGENT_NAME="${RAW_AGENT##*:}"
AGENT_ID=$(echo "$HOOK_INPUT" | jq -r '.agent_id // .agentId // "unknown"')
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
