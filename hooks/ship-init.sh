#!/bin/bash
# ship-init.sh - SessionStart hook for /ship command
# Validates /verify gate passed and code integrity before shipping

set -euo pipefail

trap 'echo "ship-init.sh failed at line $LINENO" >&2; exit 1' ERR

# Get project directory (consistent with other hooks)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
VERIFY_STATE="$CLAUDE_DIR/verify-state.json"
SHIP_STATE="$CLAUDE_DIR/ship-state.json"
MANIFEST_FILE="$CLAUDE_DIR/verify-manifest.txt"

# Create claude dir if needed
mkdir -p "$CLAUDE_DIR"

# ============================================
# Gate Check: /verify must have passed
# ============================================

if [ ! -f "$VERIFY_STATE" ]; then
  echo "ERROR: claudikins-kernel:verify has not been run" >&2
  echo "" >&2
  echo "You must run claudikins-kernel:verify before claudikins-kernel:ship." >&2
  echo "Run: claudikins-kernel:verify" >&2
  exit 2
fi

# Check unlock flag
UNLOCK=$(jq -r '.unlock_ship // false' "$VERIFY_STATE" 2>/dev/null || echo "false")
if [ "$UNLOCK" != "true" ]; then
  echo "ERROR: claudikins-kernel:verify did not pass or was not approved" >&2
  echo "" >&2
  DECISION=$(jq -r '.human_checkpoint.decision // "unknown"' "$VERIFY_STATE" 2>/dev/null || echo "unknown")
  echo "Human checkpoint decision: $DECISION" >&2
  echo "" >&2
  echo "Re-run claudikins-kernel:verify and ensure human approves." >&2
  exit 2
fi

# ============================================
# Code Integrity: C-5 Commit Hash Validation
# ============================================

VERIFY_COMMIT=$(jq -r '.verified_commit_sha // ""' "$VERIFY_STATE" 2>/dev/null || echo "")
CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")

if [ -n "$VERIFY_COMMIT" ] && [ -n "$CURRENT_COMMIT" ]; then
  if [ "$VERIFY_COMMIT" != "$CURRENT_COMMIT" ]; then
    echo "ERROR: Code has changed since verification (C-5)" >&2
    echo "" >&2
    echo "Verified commit: $VERIFY_COMMIT" >&2
    echo "Current commit:  $CURRENT_COMMIT" >&2
    echo "" >&2
    echo "Re-run claudikins-kernel:verify to validate current code." >&2
    exit 2
  fi
fi

# ============================================
# Code Integrity: C-7 File Manifest Validation
# ============================================

if [ -f "$MANIFEST_FILE" ]; then
  VERIFIED_MANIFEST=$(jq -r '.verified_manifest // ""' "$VERIFY_STATE" 2>/dev/null || echo "")

  if [ -n "$VERIFIED_MANIFEST" ]; then
    CURRENT_MANIFEST=$(sha256sum "$MANIFEST_FILE" 2>/dev/null | cut -d' ' -f1 || echo "")

    if [ -n "$CURRENT_MANIFEST" ] && [ "$VERIFIED_MANIFEST" != "$CURRENT_MANIFEST" ]; then
      echo "ERROR: Source files changed after verification (C-7)" >&2
      echo "" >&2
      echo "Verified manifest: $VERIFIED_MANIFEST" >&2
      echo "Current manifest:  $CURRENT_MANIFEST" >&2
      echo "" >&2
      echo "Re-run claudikins-kernel:verify to validate current code." >&2
      exit 2
    fi
  fi
fi

# ============================================
# Initialize Ship State
# ============================================

SESSION_ID="ship-$(date +%Y-%m-%d-%H%M)"
VERIFY_SESSION=$(jq -r '.session_id // "unknown"' "$VERIFY_STATE" 2>/dev/null || echo "unknown")

cat > "$SHIP_STATE" << EOF
{
  "session_id": "$SESSION_ID",
  "verify_session_id": "$VERIFY_SESSION",
  "started_at": "$(date -Iseconds)",
  "verified_commit": "$VERIFY_COMMIT",
  "target": "main",
  "phases": {
    "pre_ship_review": { "status": "pending" },
    "commit_strategy": { "status": "pending" },
    "documentation": { "status": "pending" },
    "pr_creation": { "status": "pending" },
    "merge": { "status": "pending" }
  },
  "unlock_merge": false
}
EOF

echo "Ship session initialized: $SESSION_ID"
echo "Verified commit: ${VERIFY_COMMIT:-"(not tracked)"}"
echo ""
echo "Gate check: PASSED"
echo "Code integrity: VERIFIED"

# Output valid hook JSON for Claude
cat << EOF
{
  "systemMessage": "Ship session initialized. Session: $SESSION_ID, Verify session: $VERIFY_SESSION, Verified commit: $VERIFY_COMMIT, Gate: passed, Integrity: verified"
}
EOF

exit 0
