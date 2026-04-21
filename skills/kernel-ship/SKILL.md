---
name: claudikins-kernel:ship
description: Final shipping gate. PR creation, documentation updates, and merge with human approval.
argument-hint: <branch-name> [--target main|develop] [--skip-docs] [--squash|--preserve] [--dry-run]
agent_outputs:
  - agent: git-perfectionist
    capture_to: .claude/agent-outputs/documentation/
    merge_strategy: jq -s 'add'
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Task
  - AskUserQuestion
  - TodoWrite
  - Skill
skills:
  - shipping-methodology
output-schema:
  type: object
  properties:
    session_id:
      type: string
    status:
      type: string
      enum: [shipped, paused, aborted, dry-run]
    source_branch:
      type: string
    target_branch:
      type: string
    pr_url:
      type: string
    merge_strategy:
      type: string
      enum: [squash, preserve, rebase]
    docs_updated:
      type: array
      items:
        type: string
    commit_sha:
      type: string
  required: [session_id, status, source_branch, target_branch]
---

# claudikins-kernel:ship Command

You are orchestrating a shipping workflow that takes verified code to production with human approval at every stage.

## Flags

| Flag              | Effect                                  |
| ----------------- | --------------------------------------- |
| `--branch NAME`   | Ship specific branch (default: current) |
| `--target BRANCH` | Target branch for merge (default: main) |
| `--skip-docs`     | Skip documentation updates (Stage 3)    |
| `--squash`        | Squash commits into single commit       |
| `--preserve`      | Preserve commit history                 |
| `--dry-run`       | Preview ship without merging            |
| `--session-id ID` | Resume previous session by ID           |
| `--resume`        | Resume from last checkpoint             |
| `--status`        | Show current ship status                |
| `--list-sessions` | Show available sessions for resume      |

## Merge Strategy

JQ merge - documentation outputs are combined with `jq -s 'add'`.

## Philosophy

> "Ship with confidence, not hope." - Shipping philosophy

- claudikins-kernel:ship is the final gate after claudikins-kernel:verify passes
- GRFP-style: section-by-section approval at every stage
- Human decides final merge - no auto-merging
- Code integrity validation ensures we ship what was verified
- Documentation is part of shipping, not optional

## State Management

State file: `.claude/ship-state.json`

```json
{
  "session_id": "ship-YYYY-MM-DD-HHMM",
  "verify_session_id": "verify-YYYY-MM-DD-HHMM",
  "verified_commit": "abc123...",
  "target": "main",
  "started_at": "ISO timestamp",
  "status": "initialising|shipping|completed|failed",
  "phases": {
    "pre_ship_review": { "status": "pending|APPROVED|SKIPPED" },
    "commit_strategy": { "status": "pending|APPROVED", "strategy": null },
    "documentation": { "status": "pending|COMPLETED|SKIPPED" },
    "pr_creation": { "status": "pending|CREATED", "pr_number": null },
    "merge": { "status": "pending|MERGED", "sha": null }
  },
  "unlock_merge": false,
  "cleanup": {
    "branches_deleted": []
  }
}
```

## Stage 0: Initialisation

### Flag Handling

Check for flags first:

```
--status → Display current ship status, exit
--resume → Load checkpoint, resume from saved state
--list-sessions → Show available sessions, exit
--dry-run → Run through stages without actual merge
```

### Prerequisite Check (via ship-init.sh hook)

The SessionStart hook validates:

1. verify-state.json exists and unlock_ship is true
2. Code integrity (C-5): verified commit matches current HEAD
3. File integrity (C-7): source file manifest unchanged
4. Creates initial ship-state.json
5. Links to verify session for traceability

**On validation failure:**

```
ERROR: claudikins-kernel:verify gate check failed

Reason: ${FAILURE_REASON}

[Re-run claudikins-kernel:verify] [Abort]
```

**On code integrity failure (C-5, C-7):**

```
ERROR: Code has changed since verification

Verified commit: ${VERIFIED_COMMIT}
Current commit:  ${CURRENT_COMMIT}

Code must not change between claudikins-kernel:verify and claudikins-kernel:ship.

[Re-run claudikins-kernel:verify] [Abort]
```

## Stage 1: Pre-Ship Review

Show what's being shipped. Human confirms ready.

### Display Ship Summary

```
Pre-Ship Review
===============

Verification Session: ${VERIFY_SESSION_ID}
Verified at: ${VERIFY_TIMESTAMP}

Branches to merge:
${BRANCH_LIST}

Changes:
  Files changed: ${FILE_COUNT}
  Lines added:   +${ADDITIONS}
  Lines removed: -${DELETIONS}

Evidence from verification:
  Screenshots: ${SCREENSHOT_COUNT}
  API tests:   ${API_TEST_COUNT}
  CLI tests:   ${CLI_TEST_COUNT}

Ready to proceed?

[Continue to Commit Strategy] [Review Evidence] [Back to Verify] [Abort]
```

### Stage 1 Checkpoint

On "Continue":

- Set `phases.pre_ship_review.status = "APPROVED"`
- Proceed to Stage 2

On "Review Evidence":

- Display evidence from `.claude/evidence/`
- Return to checkpoint

On "Back to Verify":

- Set `status = "aborted"`
- Output: "Run `claudikins-kernel:verify` to re-verify"

## Stage 2: Commit Strategy

Decide how to commit the changes.

### Strategy Selection

```
Commit Strategy
===============

How should we commit these changes?

[Squash into single commit] (Recommended for features)
[Preserve commit history] (For large multi-part work)
```

**If --squash flag set:** Auto-select squash
**If --preserve flag set:** Auto-select preserve

### Commit Message Draft (Squash)

For squash, draft a commit message:

```
Commit message:

feat(${SCOPE}): ${TITLE}

${BODY}

Closes #${ISSUE_NUMBER}

[Accept] [Revise] [Back]
```

Follow conventional commits format:

- `feat:` for new features
- `fix:` for bug fixes
- `chore:` for maintenance
- `feat!:` or `BREAKING CHANGE:` for breaking changes

### Stage 2 Checkpoint

On "Accept":

- Set `phases.commit_strategy.status = "APPROVED"`
- Set `phases.commit_strategy.strategy = "squash|preserve"`
- Record commit message in state
- Proceed to Stage 3

## Stage 3: Documentation (git-perfectionist)

Update documentation to match shipped code. GRFP-style.

**If --skip-docs flag set:**

```
Skipping documentation updates.

[Confirm skip] [Update docs anyway]
```

Otherwise, spawn git-perfectionist:

### Spawn git-perfectionist

```typescript
Task(git - perfectionist, {
  prompt: `
    Update documentation to match the shipped code.

    Changes being shipped:
    ${CHANGE_SUMMARY}

    Files to check:
    - README.md (features, installation, usage)
    - CHANGELOG.md (add version entry)
    - package.json/Cargo.toml/pyproject.toml (version bump)

    GRFP-style: one section at a time, get approval for each.
    Output JSON with files updated and sections approved.
  `,
  context: "fork",
  model: "opus",
});
```

### Stage 3 Checkpoint

```
Documentation updated.

Files changed:
${DOC_FILE_LIST}

Sections updated: ${SECTION_COUNT}

[Accept] [Review changes] [Revise] [Skip docs]
```

On "Accept":

- Set `phases.documentation.status = "COMPLETED"`
- Proceed to Stage 4

## Stage 4: PR Creation

Create the pull request.

### Draft PR

```
Pull Request
============

Title: ${PR_TITLE}

Body:
---
## Summary
${SUMMARY_BULLETS}

## Changes
${CHANGE_DETAILS}

## Testing
${TESTING_SUMMARY}

## Screenshots
${SCREENSHOTS}
---

Target: ${TARGET_BRANCH}

[Create PR] [Revise] [Back]
```

### Create PR via gh

```bash
gh pr create \
  --title "${PR_TITLE}" \
  --body "${PR_BODY}" \
  --base ${TARGET_BRANCH}
```

### External Service Failure (E-6, E-7, E-8)

If PR creation fails:

```
PR creation failed.

Error: ${ERROR_MESSAGE}

Retry ${RETRY_COUNT}/3...

[Retry] [Save as draft] [Manual PR] [Abort]
```

Pattern: Max 3 retries with exponential backoff.

### Stage 4 Checkpoint

```
PR created: #${PR_NUMBER}

URL: ${PR_URL}

CI Status: ${CI_STATUS}

[Wait for CI] [View PR] [Merge now] [Abort]
```

On "Wait for CI":

- Poll CI status every 30 seconds
- Show progress updates
- When complete: return to checkpoint

On "Merge now":

- Proceed to Stage 5

## Stage 5: Final Merge

The final gate. Human approves merge.

### CI Status Check

```
CI Status
=========

${CI_CHECK_LIST}

Overall: ${CI_OVERALL}

[Merge] [Wait for CI] [View logs] [Merge anyway] [Abort]
```

**If CI fails:**

```
CI failed.

Failed checks:
${FAILED_CHECKS}

[View logs] [Fix and retry] [Merge anyway] [Abort]
```

### Merge Confirmation

```
Ready to merge PR #${PR_NUMBER} to ${TARGET_BRANCH}?

This action cannot be undone.

[Merge] [Request review first] [Cancel]
```

### Execute Merge

```bash
# Merge the PR
gh pr merge ${PR_NUMBER} --${MERGE_METHOD}

# Delete feature branches (unless --no-delete-branch)
git push origin --delete ${BRANCH_NAME}
```

**If --dry-run flag set:**

```
DRY RUN: Would merge PR #${PR_NUMBER}
DRY RUN: Would delete branch ${BRANCH_NAME}

No changes made.
```

### Stage 5 Checkpoint

On successful merge:

- Set `phases.merge.status = "MERGED"`
- Set `phases.merge.sha = ${MERGE_SHA}`
- Set `unlock_merge = true`
- Record cleanup actions

## Output

On successful completion:

```
Done! Shipped to ${TARGET_BRANCH}.

PR #${PR_NUMBER} merged ✓
Branches cleaned up ✓
Version: ${OLD_VERSION} → ${NEW_VERSION}

Session: ${SESSION_ID}
Shipped at: ${TIMESTAMP}

Nice work!
```

## Error Recovery

On any failure:

1. Save checkpoint immediately
2. Log error to `.claude/errors/`
3. Offer: [Retry] [Skip] [Manual intervention] [Abort]

Never lose work. Always checkpoint before risky operations.

## Force Push Protection (S-23)

Never force push to protected branches.

If force push detected:

```
ERROR: Cannot force push to ${TARGET_BRANCH}

${TARGET_BRANCH} is a protected branch.

[Use squash merge] [Create new branch] [Abort]
```

## Breaking Change Detection (S-24)

If breaking changes detected:

```
Breaking change detected!

Changes:
${BREAKING_CHANGES}

This requires a MAJOR version bump.

[Acknowledge and continue] [Abort]
```

## Context Collapse Handling

On PreCompact event:

1. preserve-state.sh saves critical state
2. Mark session as "interrupted" (not abandoned)
3. Resume instructions written to state file
4. On resume, offer: [Continue from checkpoint] [Start fresh]

## Resume Handling

On `--resume`:

1. Load last checkpoint from ship-state.json
2. Display resume point
3. Offer: [Continue from stage X] [Restart ship] [Abort]

```
Resuming ship

Last checkpoint: ${CHECKPOINT_ID}
Stage: ${STAGE}
Status: ${STATUS}

[Continue] [Restart] [Abort]
```

## Next Stage

When this command completes, ask:

```
AskUserQuestion({
  question: "Shipped! Ready for next feature?",
  header: "Next",
  options: [
    { label: "Load /claudikins-kernel:outline", description: "Plan the next feature" },
    { label: "Stay here", description: "Review output before continuing" },
    { label: "Done for now", description: "End the workflow" }
  ]
})
```

If user selects "Load /claudikins-kernel:outline", invoke `Skill(claudikins-kernel:outline)`.
