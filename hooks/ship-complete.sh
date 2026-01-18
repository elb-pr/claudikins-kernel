#!/bin/bash
# ship-complete.sh - Stop hook for /ship command
# Final gate: validates all phases complete and human approved merge

set -euo pipefail

# Get project directory (consistent with other hooks)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
SHIP_STATE="$CLAUDE_DIR/ship-state.json"

# ============================================
# Check ship-state exists
# ============================================

if [ ! -f "$SHIP_STATE" ]; then
  # No ship session - silently exit (command wasn't run)
  exit 0
fi

# ============================================
# Validate All Phases Complete
# ============================================

# Check each phase status
PRE_SHIP=$(jq -r '.phases.pre_ship_review.status // "pending"' "$SHIP_STATE")
COMMIT=$(jq -r '.phases.commit_strategy.status // "pending"' "$SHIP_STATE")
DOCS=$(jq -r '.phases.documentation.status // "pending"' "$SHIP_STATE")
PR=$(jq -r '.phases.pr_creation.status // "pending"' "$SHIP_STATE")
MERGE=$(jq -r '.phases.merge.status // "pending"' "$SHIP_STATE")

INCOMPLETE=()

[ "$PRE_SHIP" != "APPROVED" ] && [ "$PRE_SHIP" != "COMPLETED" ] && INCOMPLETE+=("pre_ship_review")
[ "$COMMIT" != "APPROVED" ] && [ "$COMMIT" != "COMPLETED" ] && INCOMPLETE+=("commit_strategy")
[ "$DOCS" != "APPROVED" ] && [ "$DOCS" != "COMPLETED" ] && [ "$DOCS" != "SKIPPED" ] && INCOMPLETE+=("documentation")
[ "$PR" != "CREATED" ] && [ "$PR" != "COMPLETED" ] && INCOMPLETE+=("pr_creation")
[ "$MERGE" != "MERGED" ] && [ "$MERGE" != "COMPLETED" ] && INCOMPLETE+=("merge")

if [ ${#INCOMPLETE[@]} -gt 0 ]; then
  echo "Ship incomplete. Phases not finished:" >&2
  for phase in "${INCOMPLETE[@]}"; do
    echo "  - $phase" >&2
  done
  echo "" >&2
  echo "Continue the claudikins-kernel:ship workflow to complete remaining phases." >&2

  # Not exit 2 - this is informational, not a gate block
  # The ship is in progress, not failed
  exit 0
fi

# ============================================
# Check Human Approval for Merge
# ============================================

UNLOCK_MERGE=$(jq -r '.unlock_merge // false' "$SHIP_STATE")

if [ "$UNLOCK_MERGE" != "true" ]; then
  echo "WARNING: Merge not yet approved by human" >&2
  echo "Human must approve final merge before completing claudikins-kernel:ship." >&2
  exit 0
fi

# ============================================
# Ship Complete - Record Success
# ============================================

# Update ship-state with completion
jq '.shipped_at = (now | todate) | .status = "SHIPPED"' "$SHIP_STATE" > "$SHIP_STATE.tmp" \
  && mv "$SHIP_STATE.tmp" "$SHIP_STATE"

# Get summary info
PR_NUMBER=$(jq -r '.phases.pr_creation.pr_number // "unknown"' "$SHIP_STATE")
TARGET=$(jq -r '.target // "main"' "$SHIP_STATE")
SESSION_ID=$(jq -r '.session_id // "unknown"' "$SHIP_STATE")

echo ""
echo "=========================================="
echo "  SHIP COMPLETE"
echo "=========================================="
echo ""
echo "Session: $SESSION_ID"
echo "PR: #$PR_NUMBER"
echo "Target: $TARGET"
echo "Status: SHIPPED"
echo ""

# Output JSON for Claude
cat << EOF
{
  "hook": "ship-complete",
  "status": "success",
  "session_id": "$SESSION_ID",
  "pr_number": "$PR_NUMBER",
  "target": "$TARGET",
  "shipped": true
}
EOF

exit 0
