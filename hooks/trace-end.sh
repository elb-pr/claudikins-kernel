#!/usr/bin/env bash
# trace-end.sh - Complete a trace span when an agent stops
# SubagentStop hook for execution tracing

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TRACES_DIR="${PROJECT_DIR}/.claude/traces"
TRACE_FILE="${TRACES_DIR}/current-trace.json"

# Read hook input from stdin (documented ABI); fall back to env var for compat.
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
    echo "=== $(date -u +%FT%TZ) trace-end.sh ==="
    echo "$HOOK_INPUT" | jq -c '. | {hook_event_name, subagent_type, agentId, agent_id}' 2>/dev/null || echo "raw: $HOOK_INPUT"
} >> "$DEBUG_LOG" 2>/dev/null || true

# Check trace file exists
if [[ ! -f "$TRACE_FILE" ]]; then
    exit 0
fi

# Extract agent info. Empirical ABI uses snake_case: `agent_id`.
AGENT_ID=$(echo "$HOOK_INPUT" | jq -r '.agent_id // .agentId // "unknown"')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_MS=$(date +%s%3N)

# Find and update the matching span
# Calculate duration from start time
jq --arg id "$AGENT_ID" --arg end "$TIMESTAMP" '
    .spans |= map(
        if .agent_id == $id and .status == "running" then
            .end = $end |
            .status = "completed" |
            .duration_ms = (
                # Calculate duration - simplified, assumes same day
                (($end | split("T")[1] | split("Z")[0] | split(":") | (.[0] | tonumber) * 3600000 + (.[1] | tonumber) * 60000 + (.[2] | tonumber) * 1000) -
                 (.start | split("T")[1] | split("Z")[0] | split(":") | (.[0] | tonumber) * 3600000 + (.[1] | tonumber) * 60000 + (.[2] | tonumber) * 1000))
            )
        else .
        end
    )
' "$TRACE_FILE" > "${TRACE_FILE}.tmp" && mv "${TRACE_FILE}.tmp" "$TRACE_FILE"

# Check if all spans are complete
ALL_COMPLETE=$(jq '[.spans[].status] | all(. == "completed")' "$TRACE_FILE")

if [[ "$ALL_COMPLETE" == "true" ]]; then
    # Archive completed trace
    SESSION_ID=$(jq -r '.session_id' "$TRACE_FILE")
    ARCHIVE_FILE="${TRACES_DIR}/${SESSION_ID}.json"
    
    # Add completion timestamp
    jq --arg end "$TIMESTAMP" '.completed_at = $end' "$TRACE_FILE" > "$ARCHIVE_FILE"
    
    # Keep current trace for reference but mark as archived
    jq '.archived = true' "$TRACE_FILE" > "${TRACE_FILE}.tmp" && mv "${TRACE_FILE}.tmp" "$TRACE_FILE"
fi
