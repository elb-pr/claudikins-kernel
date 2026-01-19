---
name: claudikins-kernel:verify
description: Post-execution verification gate. Tests, lint, type-check, then see it working.
argument-hint: [--branch NAME] [--scope SCOPE] [--skip-simplify] [--fix-lint]
model: opus
status: stable
version: "1.1.1"
agent_outputs:
  - agent: catastrophiser
    capture_to: .claude/agent-outputs/verification/
    merge_strategy: jq -s 'add'
  - agent: cynic
    capture_to: .claude/agent-outputs/simplification/
    merge_strategy: concat
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
  - strict-enforcement
output-schema:
  type: object
  properties:
    session_id:
      type: string
    status:
      type: string
      enum: [passed, failed, partial]
    branch:
      type: string
    phases:
      type: object
      properties:
        tests:
          type: string
          enum: [passed, failed, skipped]
        lint:
          type: string
          enum: [passed, failed, skipped]
        types:
          type: string
          enum: [passed, failed, skipped]
        visual:
          type: string
          enum: [passed, failed, skipped]
    simplification_applied:
      type: boolean
    evidence_paths:
      type: array
      items:
        type: string
  required: [session_id, status, phases]
---

# claudikins-kernel:verify Command

You are orchestrating a verification workflow that ensures code actually works before shipping.

## Flags

| Flag              | Effect                                     |
| ----------------- | ------------------------------------------ |
| `--branch NAME`   | Verify specific branch (default: current)  |
| `--scope SCOPE`   | test\|lint\|types\|all (default: all)      |
| `--skip-simplify` | Skip cynic polish pass                     |
| `--fix-lint`      | Auto-apply lint fixes                      |
| `--fast-mode`     | 60-second iteration cycles                 |
| `--session-id ID` | Resume previous session by ID              |
| `--timing`        | Show phase durations for velocity tracking |
| `--list-sessions` | Show available sessions for resume         |
| `--resume`        | Resume from last checkpoint                |
| `--status`        | Show current verification status           |

## Merge Strategy

JQ merge - verification outputs are combined with `jq -s 'add'`.

## Philosophy

> "Evidence before assertions. Always." - Verification philosophy

- Verification is the gate between claudikins-kernel:execute and claudikins-kernel:ship
- Claude MUST see its code working (not just tests passing)
- Human checkpoint with comprehensive report
- Exit code 2 blocks claudikins-kernel:ship until verification passes
- All Opus models for agents (no compromises on judgement)

## State Management

State file: `.claude/verify-state.json`

```json
{
  "session_id": "verify-YYYY-MM-DD-HHMM",
  "execute_session_id": "exec-YYYY-MM-DD-HHMM",
  "branch": "execute/task-1-feature",
  "started_at": "ISO timestamp",
  "status": "initialising|verifying|completed|failed",
  "phases": {
    "test_suite": { "status": "pending|PASS|FAIL" },
    "lint": { "status": "pending|PASS|FAIL" },
    "type_check": { "status": "pending|PASS|FAIL" },
    "output_verification": { "status": "pending|PASS|FAIL" },
    "code_simplification": { "status": "pending|PASS|FAIL|skipped" }
  },
  "all_checks_passed": false,
  "human_checkpoint": {
    "prompted_at": null,
    "decision": null,
    "caveats": []
  },
  "unlock_ship": false
}
```

## Phase 0: Initialisation

### Flag Handling

Check for flags first:

```
--status → Display current verification status, exit
--resume → Load checkpoint, resume from saved state
--list-sessions → Show available sessions, exit
```

### Prerequisite Check (via verify-init.sh hook)

The SessionStart hook validates:

1. execute-state.json exists (C-14 cross-command gate)
2. Execute status is "completed"
3. Creates initial verify-state.json
4. Links to execute session for traceability

**On validation failure:**

```
ERROR: claudikins-kernel:execute has not been run

You must run claudikins-kernel:execute before claudikins-kernel:verify.
The verification command requires completed execution state.

Run: claudikins-kernel:execute [plan-file]
```

### Project Type Detection

Detect project type automatically:

```
if package.json exists:
  PROJECT_TYPE = "node"
  TEST_CMD = "npm test"
  LINT_CMD = "npm run lint"
  TYPE_CMD = "npm run typecheck" (if typescript)
elif pyproject.toml or setup.py:
  PROJECT_TYPE = "python"
  TEST_CMD = "pytest"
  LINT_CMD = "ruff check ."
  TYPE_CMD = "mypy ."
elif Cargo.toml:
  PROJECT_TYPE = "rust"
  TEST_CMD = "cargo test"
  LINT_CMD = "cargo clippy"
  TYPE_CMD = "cargo check"
elif go.mod:
  PROJECT_TYPE = "go"
  TEST_CMD = "go test ./..."
  LINT_CMD = "golangci-lint run"
  TYPE_CMD = "go build ./..."
else:
  PROJECT_TYPE = "unknown"
  Ask user for commands
```

## Phase 1: Automated Quality Checks

Run in sequence. STOP on any failure.

### Stage 1: Test Suite

```bash
# Run tests with timeout
timeout 300 ${TEST_CMD}
```

**On failure:**

```
Tests failed.

[Show test output]

[Fix tests] [Re-run (flaky?)] [Skip tests] [Abort]
```

**Flaky test detection (C-12):**
If tests fail, offer re-run:

```
Test failure detected. Could be flaky.

[Re-run tests] [Accept failure] [Abort]
```

If re-run passes:

```
Tests passed on retry. Likely flaky.

[Accept with flakiness caveat] [Fix tests] [Abort]
```

### Stage 2: Linting

```bash
${LINT_CMD}
```

**On failure with --fix-lint:**

```
Lint issues found. Auto-fix available.

[Apply fixes] [Show issues] [Skip lint] [Abort]
```

**After auto-fix, re-run lint to confirm:**

```bash
${LINT_CMD}
```

If still failing after fix:

```
Auto-fix did not resolve all issues.

Remaining issues:
[Show remaining issues]

[Fix manually] [Skip lint] [Abort]
```

### Stage 3: Type Check

```bash
${TYPE_CMD}
```

**On failure:**

```
Type errors found.

[Show errors]

[Fix errors] [Skip type check] [Abort]
```

### Phase 1 Checkpoint

```
Automated checks complete.

Tests:  ${TEST_STATUS}
Lint:   ${LINT_STATUS}
Types:  ${TYPE_STATUS}

[Continue to Output Verification] [Re-run checks] [Abort]
```

## Phase 2: Output Verification (catastrophiser)

> "Give Claude a tool to see the output of the code." - Boris

This is the feedback loop that makes Claude's code actually work.

### Spawn catastrophiser

```typescript
Task(catastrophiser, {
  prompt: `
    Verify the implementation WORKS by SEEING its output.

    Project type: ${PROJECT_TYPE}
    Branch: ${BRANCH}

    Use the appropriate verification method:
    - Web: Start server, screenshot key pages
    - API: Curl endpoints, verify responses
    - CLI: Run commands, check output
    - Library: Run examples, verify results

    Capture evidence. Report any issues clearly.
    Output JSON with status and evidence.
  `,
  context: "fork",
  model: "opus",
});
```

### Verification Method Fallback (A-3)

```
1. Try primary method (screenshot/curl/run)
   └─ If fails → Try secondary method
2. Try tests-only verification
   └─ If fails → Try CLI verification
3. Try code review only
   └─ If fails → Report inability to verify
```

### Phase 2 Checkpoint

```
Output verification complete.

Agent: catastrophiser
Status: ${VERIFICATION_STATUS}
Evidence: ${EVIDENCE_COUNT} items

[Show evidence] [Accept] [Debug] [Skip] [Abort]
```

## Phase 3: Code Simplification (Optional)

**Prerequisite:** Phase 2 (catastrophiser) must PASS

If `--skip-simplify` flag set:

```
Skipping code simplification.
Proceeding directly to human checkpoint.
```

Otherwise, ask:

```
Run cynic for polish pass?

This will:
- Inline single-use helpers
- Remove dead code
- Improve naming clarity
- Flatten nested conditionals

Tests will be re-run after each change.

[Run polish pass] [Skip] [Abort]
```

### Spawn cynic (if approved)

```typescript
Task(cynic, {
  prompt: `
    Polish the implementation while preserving behaviour.

    Rules:
    - Tests MUST still pass after each change
    - One change at a time
    - Revert on test failure
    - Stop after 3 passes or 3 consecutive failures

    Output JSON with simplifications made and test status.
  `,
  context: "fork",
  model: "opus",
});
```

### Phase 3 Checkpoint

```
Code simplification complete.

Changes made: ${CHANGES_COUNT}
Changes reverted: ${REVERTED_COUNT}
Lines removed: ${LINES_REMOVED}
Tests still pass: ${TESTS_PASS}

[Show changes] [Accept] [Revert all] [Abort]
```

## Phase 4: Klaus Escalation (if stuck)

If verification keeps failing (3+ attempts):

Check if Klaus available:

```bash
# Check for claudikins-klaus plugin
if mcp__claudikins-klaus available:
  Spawn Klaus for debugging
else:
  [Manual review by human] [Try different approach] [Abort]
```

## Phase 5: Human Checkpoint

Comprehensive verification report:

```
Verification Report
===================

Session: ${SESSION_ID}
Branch: ${BRANCH}
Execute Session: ${EXECUTE_SESSION_ID}

Phase Results:
  Tests:          ${TEST_STATUS}
  Lint:           ${LINT_STATUS}
  Types:          ${TYPE_STATUS}
  Output:         ${OUTPUT_STATUS}
  Simplification: ${SIMPLIFY_STATUS}

Evidence Summary:
  Screenshots: ${SCREENSHOT_COUNT}
  API responses: ${CURL_COUNT}
  Command outputs: ${CMD_COUNT}

${ISSUES_SUMMARY}

Ready to ship?

[Ready to Ship] [Needs Work] [Accept with Caveats]
```

### Decision Handling

**Ready to Ship:**

- Set `all_checks_passed = true`
- Set `human_checkpoint.decision = "ready_to_ship"`
- verify-gate.sh will set `unlock_ship = true`

**Needs Work:**

- Set `human_checkpoint.decision = "needs_work"`
- Ask: What needs to be fixed?

```
What needs work?

[Tests failing] [Lint issues] [Type errors] [Output broken] [Code quality] [Other]
```

- Record issues in `human_checkpoint.issues_noted`
- Present phase selection:

```
Where should we return to fix this?

[Phase 1: Re-run automated checks] [Phase 2: Re-verify output] [Phase 3: Run polish pass] [Exit to fix manually]
```

- If "Exit to fix manually":
  - Save checkpoint with `status = "needs_work"`
  - Output: "Fix the issues, then run `claudikins-kernel:verify --resume` to continue"

- Otherwise:
  - Loop back to selected phase
  - Re-run from that point
  - Return to Phase 5 checkpoint when complete

**Accept with Caveats:**

- Set `human_checkpoint.decision = "ready_to_ship"`
- Ask: What caveats should be noted?
- Record caveats in state
- verify-gate.sh will set `unlock_ship = true`

## Output

On successful completion:

```
Done! All checks passed.

Tests ${TEST_ICON}  Lint ${LINT_ICON}  Types ${TYPE_ICON}  App works ${OUTPUT_ICON}

Session: ${SESSION_ID}
Verified at: ${TIMESTAMP}

When you're ready:
  claudikins-kernel:ship
```

## Error Recovery

On any failure:

1. Save checkpoint immediately
2. Log error to `.claude/errors/`
3. Offer: [Retry] [Skip] [Klaus] [Manual intervention] [Abort]

Never lose work. Always checkpoint before risky operations.

## Context Collapse Handling

On PreCompact event:

1. preserve-state.sh saves critical state
2. Mark session as "interrupted" (not abandoned)
3. Resume instructions written to state file
4. On resume, offer: [Continue from checkpoint] [Start fresh]

## Resume Handling

On `--resume`:

1. Load last checkpoint from verify-state.json
2. Display resume point
3. Offer: [Continue from phase X] [Restart verification] [Abort]

```
Resuming verification

Last checkpoint: ${CHECKPOINT_ID}
Phase: ${PHASE}
Status: ${STATUS}

[Continue] [Restart] [Abort]
```

## Next Stage

When this command completes, ask:

```
AskUserQuestion({
  question: "Verification passed. What next?",
  header: "Next",
  options: [
    { label: "Load /claudikins-kernel:ship", description: "Ship the verified code" },
    { label: "Stay here", description: "Review output before continuing" },
    { label: "Done for now", description: "End the workflow" }
  ]
})
```

If user selects "Load /claudikins-kernel:ship", invoke `Skill(claudikins-kernel:ship)`.
