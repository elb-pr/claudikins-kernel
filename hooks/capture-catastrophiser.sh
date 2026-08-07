#!/bin/bash
# capture-catastrophiser.sh - SubagentStop hook for /verify
# Captures catastrophiser verification output and updates verify state.
#
# Matcher: catastrophiser
# Exit codes:
#   0 - Always (capture only, never blocks)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
VERIFY_STATE="$CLAUDE_DIR/verify-state.json"
OUTPUTS_DIR="$CLAUDE_DIR/agent-outputs/verification"

# Read input JSON from stdin
INPUT=$(cat)

# Extract agent info
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // ""')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // ""')

# Only act on catastrophiser completions
if [ "$AGENT_NAME" != "catastrophiser" ]; then
    exit 0
fi

# Check if we're in an active verify session
if [ ! -f "$VERIFY_STATE" ]; then
    echo "Warning: SubagentStop for catastrophiser but no verify-state.json" >&2
    exit 0
fi

# Create outputs directory if needed
mkdir -p "$OUTPUTS_DIR"

TIMESTAMP=$(date -Iseconds)
TIMESTAMP_EPOCH=$(date +%s)

# Try to extract verification output from transcript
VERIFICATION_OUTPUT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Extract the last JSON block that looks like catastrophiser output
    # Look for status field (PASS/FAIL) and evidence field
    # -oE (POSIX ERE) rather than -oP: PCRE is a GNU extension unavailable in
    # BSD grep (macOS default). \s is spelled [[:space:]] for portability.
    VERIFICATION_OUTPUT=$(tail -100 "$TRANSCRIPT_PATH" | \
        grep -oE '\{[^{}]*"status"[[:space:]]*:[[:space:]]*"(PASS|FAIL)"[^{}]*\}' | \
        tail -1 || echo "")

    # If simple extraction failed, try multiline JSON extraction.
    # Flattening newlines to spaces gives the same reach as PCRE's (?s)
    # DOTALL flag without needing `grep -Pzo`.
    if [ -z "$VERIFICATION_OUTPUT" ]; then
        VERIFICATION_OUTPUT=$(tail -200 "$TRANSCRIPT_PATH" | tr '\n' ' ' | \
            grep -oE '\{[^{}]*"verified_at"[^{}]*"status"[^{}]*\}' | \
            tail -1 || echo "")
    fi
fi

# If no structured output found, create a basic record
if [ -z "$VERIFICATION_OUTPUT" ]; then
    VERIFICATION_OUTPUT=$(cat <<EOF
{
  "verified_at": "${TIMESTAMP}",
  "project_type": "unknown",
  "verification_method": "unknown",
  "status": "UNKNOWN",
  "note": "Output not captured - check transcript",
  "transcript_path": "${TRANSCRIPT_PATH}"
}
EOF
)
fi

# Save verification output to file
OUTPUT_FILE="$OUTPUTS_DIR/catastrophiser-${TIMESTAMP_EPOCH}.json"
echo "$VERIFICATION_OUTPUT" > "$OUTPUT_FILE"

# Backup in case of failure (per A-6 pattern)
BACKUP_FILE="$OUTPUTS_DIR/.backup-catastrophiser-${TIMESTAMP_EPOCH}.json"
echo "$VERIFICATION_OUTPUT" > "$BACKUP_FILE"

# Extract status from output
VERIFICATION_STATUS=$(echo "$VERIFICATION_OUTPUT" | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")

# Count evidence items
SCREENSHOT_COUNT=$(echo "$VERIFICATION_OUTPUT" | jq -r '.evidence.screenshots | length // 0' 2>/dev/null || echo "0")
CURL_COUNT=$(echo "$VERIFICATION_OUTPUT" | jq -r '.evidence.curl_responses | length // 0' 2>/dev/null || echo "0")
CMD_COUNT=$(echo "$VERIFICATION_OUTPUT" | jq -r '.evidence.command_outputs | length // 0' 2>/dev/null || echo "0")
EVIDENCE_COUNT=$((SCREENSHOT_COUNT + CURL_COUNT + CMD_COUNT))

# Update verify state with catastrophiser results
jq --arg status "$VERIFICATION_STATUS" \
   --arg outputFile "$OUTPUT_FILE" \
   --arg timestamp "$TIMESTAMP" \
   --argjson evidenceCount "$EVIDENCE_COUNT" \
   '.phases.output_verification = {
      "status": $status,
      "agent": "catastrophiser",
      "output_file": $outputFile,
      "completed_at": $timestamp,
      "evidence_count": $evidenceCount
    }' \
   "$VERIFY_STATE" > "${VERIFY_STATE}.tmp" && mv "${VERIFY_STATE}.tmp" "$VERIFY_STATE"

# Output context for logging
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "catastrophiser completed: ${VERIFICATION_STATUS}\\nEvidence items: ${EVIDENCE_COUNT}\\nOutput saved to: ${OUTPUT_FILE}"
  }
}
EOF

exit 0
