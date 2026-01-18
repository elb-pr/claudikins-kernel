---
name: strict-enforcement
description: Use when running claudikins-kernel:verify, checking implementation quality, deciding pass/fail verdicts, or enforcing cross-command gates — requires actual evidence of code working, not just passing tests
---

# Strict Enforcement Verification Methodology

## When to use this skill

Use this skill when you need to:

- Run the `claudikins-kernel:verify` command
- Validate implementation before shipping
- Decide pass/fail verdicts
- Check code integrity after changes
- Enforce cross-command gates

## Core Philosophy

> "Evidence before assertions. Always." - Verification philosophy

Never claim code works without seeing it work. Tests passing is not enough. Claude must SEE the output.

### The Three Laws

1. **See it working** - Screenshots, curl responses, CLI output. Actual evidence.
2. **Human checkpoint** - No auto-shipping. Human reviews evidence and decides.
3. **Exit code 2 gates** - Verification failures block claudikins-kernel:ship. No exceptions.

## Verification Phases

### Phase 1: Automated Quality Checks

Run the automated checks first. Fast feedback.

| Check | Command Pattern                      | What It Catches                     |
| ----- | ------------------------------------ | ----------------------------------- |
| Tests | `npm test` / `pytest` / `cargo test` | Logic errors, regressions           |
| Lint  | `npm run lint` / `ruff` / `clippy`   | Style issues, common bugs           |
| Types | `tsc` / `mypy` / `cargo check`       | Type mismatches, interface drift    |
| Build | `npm run build` / `cargo build`      | Compilation errors, bundling issues |

**Flaky Test Detection (C-12):**

```
Test fails?
├── Re-run failed tests
├── Pass 2nd time?
│   └── Yes → STOP: [Accept flakiness] [Fix tests] [Abort]
└── Fail 2nd time?
    ├── Run isolated
    └── Still fail? → STOP: [Fix] [Skip] [Abort]
```

### Phase 2: Output Verification (catastrophiser)

This is the feedback loop that makes Claude's code actually work.

| Project Type | Verification Method                  | Evidence                       |
| ------------ | ------------------------------------ | ------------------------------ |
| Web app      | Start server, screenshot, test flows | Screenshots, console logs      |
| API          | Curl endpoints, check responses      | Status codes, response bodies  |
| CLI          | Run commands, capture output         | stdout, stderr, exit codes     |
| Library      | Run examples, check results          | Output values, test coverage   |
| Service      | Check logs, verify health endpoint   | Log patterns, health responses |

**Fallback Hierarchy (A-3):**

If primary method unavailable, fall back:

1. Start server + screenshot (preferred for web)
2. Curl endpoints (preferred for API)
3. Run CLI commands (preferred for CLI)
4. Run tests only (fallback)
5. Code review only (last resort)

**Timeout:** 30 seconds per verification method (CMD-30).

### Phase 3: Code Simplification (Optional)

After verification passes, optionally run cynic for polish.

**Prerequisites:**

- Phase 2 (catastrophiser) must PASS
- Human approves: "Run cynic for polish pass?"

**cynic Rules:**

- Preserve exact behaviour (tests MUST still pass)
- Remove unnecessary abstraction
- Improve naming clarity
- Delete dead code
- Flatten nested conditionals

**If tests fail after simplification:**

- Log failure reasons
- Show human
- Proceed anyway (A-5) with caveat

See [cynic-rollback.md](references/cynic-rollback.md) for recovery patterns.

### Phase 4: Klaus Escalation

If stuck during verification:

```
Is mcp__claudikins-klaus available? (E-16)
├── No →
│   Offer: [Manual review] [Ask Claude differently] (E-17)
│   Fallback: [Accept with uncertainty] [Max retries, abort] (E-18)
└── Yes →
    Spawn klaus via SubagentStop hook
```

### Phase 5: Human Checkpoint

The final gate. Present comprehensive evidence.

```
Verification Report
-------------------
Tests:  ✓ 47/47 passed
Lint:   ✓ 0 issues
Types:  ✓ 0 errors
Build:  ✓ success

Evidence:
- Screenshot: .claude/evidence/login-flow.png
- API test: POST /api/auth → 200 OK
- CLI test: mycli --help → exit 0

[Ready to Ship] [Needs Work] [Accept with Caveats]
```

Human decides. If approved, set `unlock_ship = true`.

## Rationalizations to Resist

Agents under pressure find excuses. These are all violations:

| Excuse                                     | Reality                                                               |
| ------------------------------------------ | --------------------------------------------------------------------- |
| "Tests pass, that's good enough"           | Tests aren't enough. SEE it working. Screenshots, curl, output.       |
| "I'll verify after shipping"               | Verify BEFORE ship. That's the whole point.                           |
| "The type checker caught everything"       | Types don't catch runtime issues. Get evidence.                       |
| "Screenshot failed but it probably works"  | "Probably" isn't evidence. Fix the screenshot or use fallback.        |
| "Human checkpoint is just a formality"     | Human checkpoint is the gate. No auto-shipping.                       |
| "Code review is enough for this change"    | Code review is last resort fallback. Try harder.                      |
| "Tests are flaky, I'll ignore the failure" | Flaky tests hide real failures. Fix or explicitly accept with caveat. |
| "Exit code 2 is too strict"                | Exit code 2 exists to block bad ships. Pass properly.                 |

**All of these mean: Get evidence. Human decides. No shortcuts.**

## Red Flags — STOP and Reassess

If you're thinking any of these, you're about to violate the methodology:

- "It should work because..."
- "The tests pass so..."
- "I'm confident that..."
- "It worked before..."
- "The types check so..."
- "I'll just skip verification this once"
- "Human will approve anyway"
- "Evidence isn't necessary for this change"

**All of these mean: STOP. Get evidence. Present to human. Let them decide.**

## Exit Code 2 Pattern (CRITICAL)

The verify-gate.sh hook enforces the gate:

```bash
# Both conditions MUST be true
ALL_PASSED=$(jq -r '.all_checks_passed' "$STATE")
HUMAN_APPROVED=$(jq -r '.human_checkpoint.decision' "$STATE")

if [ "$ALL_PASSED" != "true" ]; then
  exit 2  # Blocks claudikins-kernel:ship
fi

if [ "$HUMAN_APPROVED" != "ready_to_ship" ]; then
  exit 2  # Blocks claudikins-kernel:ship
fi
```

**File Manifest (C-6):**

At verification completion, generate SHA256 hashes of all source files:

```bash
find . \( -name '*.ts' -o -name '*.py' -o -name '*.rs' \) \
  | xargs sha256sum > .claude/verify-manifest.txt
```

This lets claudikins-kernel:ship detect if code was modified after verification.

## Cross-Command Gate (C-14)

claudikins-kernel:verify requires claudikins-kernel:execute to have completed:

```bash
if [ ! -f "$EXECUTE_STATE" ]; then
  echo "ERROR: claudikins-kernel:execute has not been run"
  exit 2
fi
```

This enforces the claudikins-kernel:plans → claudikins-kernel:execute → claudikins-kernel:verify → claudikins-kernel:ship flow.

## Agent Integration

| Agent          | Role             | When                               |
| -------------- | ---------------- | ---------------------------------- |
| catastrophiser | See code working | Phase 2: Output verification       |
| cynic          | Polish pass      | Phase 3: Simplification (optional) |

Both agents run with `context: fork` and `background: true`.

See [agent-integration.md](references/agent-integration.md) for coordination patterns.

## State Tracking

### verify-state.json

```json
{
  "session_id": "verify-2026-01-16-1100",
  "execute_session_id": "execute-2026-01-16-1030",
  "branch": "execute/task-1-auth-middleware",
  "phases": {
    "test_suite": { "status": "PASS", "count": 47 },
    "lint": { "status": "PASS", "issues": 0 },
    "type_check": { "status": "PASS", "errors": 0 },
    "output_verification": { "status": "PASS", "agent": "catastrophiser" },
    "code_simplification": { "status": "PASS", "agent": "cynic" }
  },
  "all_checks_passed": true,
  "human_checkpoint": {
    "decision": "ready_to_ship",
    "caveats": []
  },
  "unlock_ship": true,
  "verified_manifest": "sha256:...",
  "verified_commit_sha": "abc123..."
}
```

## Anti-Patterns

**Don't do these:**

- Trusting test results without seeing code run
- Skipping output verification because "tests pass"
- Auto-approving verification without human checkpoint
- Modifying code after verification passes
- Ignoring flaky test warnings
- Proceeding when lint/type checks fail

## Edge Case Handling

| Situation                  | Reference                                                                     |
| -------------------------- | ----------------------------------------------------------------------------- |
| Tests hang or timeout      | [test-timeout-handling.md](references/test-timeout-handling.md)               |
| Auto-fix breaks code       | [lint-fix-validation.md](references/lint-fix-validation.md)                   |
| Primary verification fails | [verification-method-fallback.md](references/verification-method-fallback.md) |
| Type-check results unclear | [type-check-confidence.md](references/type-check-confidence.md)               |
| cynic breaks tests         | [cynic-rollback.md](references/cynic-rollback.md)                             |
| Large project state        | [verify-state-compression.md](references/verify-state-compression.md)         |

## References

Full documentation in this skill's references/ folder:

- [verification-checklist.md](references/verification-checklist.md) - Complete verification checklist
- [red-flags.md](references/red-flags.md) - Common rationalisation patterns
- [agent-integration.md](references/agent-integration.md) - How catastrophiser and cynic coordinate
- [advanced-verification.md](references/advanced-verification.md) - Complex verification scenarios
- [test-timeout-handling.md](references/test-timeout-handling.md) - When tests hang (S-13)
- [lint-fix-validation.md](references/lint-fix-validation.md) - Validating auto-fix safety (S-14)
- [verification-method-fallback.md](references/verification-method-fallback.md) - Fallback strategies (S-15)
- [type-check-confidence.md](references/type-check-confidence.md) - Interpreting type results (S-16)
- [cynic-rollback.md](references/cynic-rollback.md) - Rolling back failed simplifications (S-17)
- [verify-state-compression.md](references/verify-state-compression.md) - State management for large projects (S-18)
