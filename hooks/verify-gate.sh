#!/bin/bash
# verify-gate.sh - Stop hook for /verify
# Enforces verification gate with exit code 2 pattern.
# Generates file manifest for /ship integrity checking (C-6).
#
# Matcher: /verify
# Exit codes:
#   0 - Verification complete and approved, /ship unlocked
#   2 - Verification incomplete or not approved, /ship blocked

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
VERIFY_STATE="$CLAUDE_DIR/verify-state.json"
MANIFEST_FILE="$CLAUDE_DIR/verify-manifest.txt"

# === Dependency Check (H-3) ===
for cmd in jq git sha256sum find; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: $cmd not installed" >&2
        exit 127
    fi
done

# === Error handling (H-1) ===
trap 'echo "Hook crashed: $?" >&2; exit 1' ERR

# === ENV validation (H-2) ===
if [ "$PROJECT_DIR" = "." ]; then
    echo "WARNING: Using current directory (CLAUDE_PROJECT_DIR unset)" >&2
fi

# Read input JSON from stdin
INPUT=$(cat)
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // "unknown"')

# Check if verify state exists
if [ ! -f "$VERIFY_STATE" ]; then
    # No verify session - silently exit (command wasn't run)
    exit 0
fi

# === File Locking (C-8) ===
LOCK_FILE="${VERIFY_STATE}.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "ERROR: Another process is modifying verify state" >&2
    exit 2
fi
trap 'flock -u 200; rm -f "$LOCK_FILE"' EXIT

# === State File Corruption Check (H-4) ===
if ! jq empty "$VERIFY_STATE" 2>/dev/null; then
    echo "ERROR: verify-state.json corrupted" >&2
    exit 2
fi

# Check verification status
ALL_PASSED=$(jq -r '.all_checks_passed // false' "$VERIFY_STATE")
HUMAN_APPROVED=$(jq -r '.human_checkpoint.decision // ""' "$VERIFY_STATE")
SESSION_ID=$(jq -r '.session_id // "unknown"' "$VERIFY_STATE")

# Get phase statuses for reporting
TEST_STATUS=$(jq -r '.phases.test_suite.status // "pending"' "$VERIFY_STATE")
LINT_STATUS=$(jq -r '.phases.lint.status // "pending"' "$VERIFY_STATE")
TYPE_STATUS=$(jq -r '.phases.type_check.status // "pending"' "$VERIFY_STATE")
OUTPUT_STATUS=$(jq -r '.phases.output_verification.status // "pending"' "$VERIFY_STATE")

# Check if all automated checks passed
if [ "$ALL_PASSED" != "true" ]; then
    cat <<EOF >&2
Verification checks not all passed.

Session: ${SESSION_ID}
Tests:   ${TEST_STATUS}
Lint:    ${LINT_STATUS}
Types:   ${TYPE_STATUS}
Output:  ${OUTPUT_STATUS}

Complete all verification phases before shipping.
EOF
    exit 2
fi

# Check human approval
if [ "$HUMAN_APPROVED" != "ready_to_ship" ]; then
    cat <<EOF >&2
Human has not approved for shipping.

Session: ${SESSION_ID}
Decision: ${HUMAN_APPROVED:-"none"}

Use the human checkpoint to approve:
  [Ready to Ship] - Approve for shipping
  [Needs Work] - Return for fixes
  [Accept with Caveats] - Approve with noted issues
EOF
    exit 2
fi

# === Generate File Hash Manifest (C-6) ===
# Captures SHA256 of all source files for integrity checking in /ship
echo "Generating file manifest for integrity checking..." >&2

find "$PROJECT_DIR" \( \
    -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
    -o -name '*.py' -o -name '*.rs' -o -name '*.go' -o -name '*.java' \
    -o -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \
    -o -name '*.rb' -o -name '*.php' -o -name '*.swift' -o -name '*.kt' \
    \) \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/target/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/.venv/*' \
    -not -path '*/venv/*' \
    -type f \
    2>/dev/null | sort | xargs -r sha256sum > "$MANIFEST_FILE" 2>/dev/null || true

# Generate manifest hash
if [ -s "$MANIFEST_FILE" ]; then
    MANIFEST_SHA=$(sha256sum "$MANIFEST_FILE" | cut -d' ' -f1)
    FILE_COUNT=$(wc -l < "$MANIFEST_FILE")
else
    MANIFEST_SHA="empty"
    FILE_COUNT=0
fi

# Get current commit SHA
COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

# === Atomic Write Pattern (C-9) ===
TEMP_FILE=$(mktemp "${VERIFY_STATE}.XXXXXX")
trap "rm -f '$TEMP_FILE'; flock -u 200; rm -f '$LOCK_FILE'" EXIT

TIMESTAMP=$(date -Iseconds)

# Set unlock flag and manifest hash
if ! jq --arg manifest "$MANIFEST_SHA" \
       --arg commit "$COMMIT_SHA" \
       --arg timestamp "$TIMESTAMP" \
       --argjson fileCount "$FILE_COUNT" \
       '. + {
          "unlock_ship": true,
          "verified_at": $timestamp,
          "verified_manifest": $manifest,
          "verified_commit_sha": $commit,
          "verified_file_count": $fileCount,
          "status": "completed"
        }' \
       "$VERIFY_STATE" > "$TEMP_FILE"; then
    echo "ERROR: Failed to update state (disk full?)" >&2
    exit 2
fi

# Validate JSON before committing
if ! jq empty "$TEMP_FILE" 2>/dev/null; then
    echo "ERROR: State file write incomplete" >&2
    exit 2
fi

mv "$TEMP_FILE" "$VERIFY_STATE"

# Output success
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "VERIFICATION COMPLETE\\n\\nSession: ${SESSION_ID}\\nCommit: ${COMMIT_SHA}\\nFiles verified: ${FILE_COUNT}\\nManifest: ${MANIFEST_SHA}\\n\\nShip unlocked. Run claudikins-kernel:ship when ready."
  }
}
EOF

exit 0
