#!/bin/bash
# capture-perfectionist.sh - SubagentStop hook for git-perfectionist
# Captures documentation update results and merges into ship-state.json
#
# Matcher: git-perfectionist
# Exit codes:
#   0 - Always (capture only, never blocks)

set -euo pipefail

# Get project directory (consistent with other hooks)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
SHIP_STATE="$CLAUDE_DIR/ship-state.json"
BACKUP_DIR="$CLAUDE_DIR/agent-outputs"

# Read input JSON from stdin (SubagentStop provides metadata, not raw output)
INPUT=$(cat)

# Extract agent info
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // ""')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // ""')

# Only act on git-perfectionist completions
if [ "$AGENT_NAME" != "git-perfectionist" ]; then
    exit 0
fi

# Check if we're in an active ship session
if [ ! -f "$SHIP_STATE" ]; then
    echo "Warning: SubagentStop for git-perfectionist but no ship-state.json" >&2
    exit 0
fi

# Create backup dir
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date -Iseconds)
TIMESTAMP_EPOCH=$(date +%s)

# Try to extract perfectionist output from transcript
AGENT_OUTPUT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Extract the last JSON block that looks like perfectionist output
    # Look for files_updated field
    # -oE (POSIX ERE) rather than -oP: PCRE is a GNU extension unavailable in
    # BSD grep (macOS default), and this pattern needs no PCRE features.
    AGENT_OUTPUT=$(tail -100 "$TRANSCRIPT_PATH" | \
        grep -oE '\{[^{}]*"files_updated"[^{}]*\}' | \
        tail -1 || echo "")

    # If simple extraction failed, try multiline JSON extraction.
    # Flattening newlines to spaces gives the same reach as PCRE's (?s)
    # DOTALL flag without needing `grep -Pzo`.
    if [ -z "$AGENT_OUTPUT" ]; then
        AGENT_OUTPUT=$(tail -200 "$TRANSCRIPT_PATH" | tr '\n' ' ' | \
            grep -oE '\{[^{}]*"sections_approved"[^{}]*\}' | \
            tail -1 || echo "")
    fi
fi

# If no structured output found, create a basic record
if [ -z "$AGENT_OUTPUT" ]; then
    AGENT_OUTPUT=$(cat <<EOF
{
  "status": "UNKNOWN",
  "files_updated": [],
  "sections_presented": 0,
  "sections_approved": 0,
  "note": "Output not captured - check transcript",
  "transcript_path": "${TRANSCRIPT_PATH}"
}
EOF
)
fi

# Backup first (A-6 pattern)
BACKUP_FILE="$BACKUP_DIR/perfectionist-${TIMESTAMP_EPOCH}.json"
echo "$AGENT_OUTPUT" > "$BACKUP_FILE"

# Validate JSON (A-7 pattern)
if ! echo "$AGENT_OUTPUT" | jq -e '.' > /dev/null 2>&1; then
    echo "WARNING: git-perfectionist output is not valid JSON" >&2
    echo "Raw output saved to: $BACKUP_FILE" >&2

    # Create minimal valid structure
    AGENT_OUTPUT=$(cat << EOF
{
  "status": "MALFORMED",
  "raw_output_file": "$BACKUP_FILE",
  "error": "Agent output was not valid JSON"
}
EOF
)
fi

# Extract key fields
FILES_UPDATED=$(echo "$AGENT_OUTPUT" | jq -r '.files_updated // []')
SECTIONS_APPROVED=$(echo "$AGENT_OUTPUT" | jq -r '.sections_approved // 0')

# Update ship-state.json
if [ -f "$SHIP_STATE" ]; then
    # Merge perfectionist results into documentation phase
    jq --argjson output "$AGENT_OUTPUT" '
      .phases.documentation = {
        "status": "COMPLETED",
        "agent": "git-perfectionist",
        "files_updated": ($output.files_updated // []),
        "sections_presented": ($output.sections_presented // 0),
        "sections_approved": ($output.sections_approved // 0),
        "completed_at": (now | todate)
      }
    ' "$SHIP_STATE" > "$SHIP_STATE.tmp" && mv "$SHIP_STATE.tmp" "$SHIP_STATE"

    echo "Documentation phase recorded in ship-state.json"
fi

# Output for Claude
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "git-perfectionist completed\\nFiles updated: $FILES_UPDATED\\nSections approved: $SECTIONS_APPROVED\\nBackup: $BACKUP_FILE"
  }
}
EOF

exit 0
