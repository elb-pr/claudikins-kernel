---
name: claudikins-kernel:execute
description: Execute validated plans with isolated agents and two-stage review
argument-hint: [plan-path or --resume or --status]
model: opus
status: stable
version: "1.1.1"
agent_outputs:
  - agent: babyclaude
    capture_to: .claude/task-outputs/
    merge_strategy: none
  - agent: spec-reviewer
    capture_to: .claude/reviews/spec/
    merge_strategy: none
  - agent: code-reviewer
    capture_to: .claude/reviews/code/
    merge_strategy: none
  - agent: conflict-resolver
    capture_to: .claude/conflict-resolutions/
    merge_strategy: none
allowed-tools:
  - Read
  - Grep
  - Glob
  - Task
  - Bash
  - AskUserQuestion
  - TodoWrite
  - Skill
skills:
  - git-workflow
output-schema:
  type: object
  properties:
    session_id:
      type: string
    status:
      type: string
      enum: [completed, paused, aborted]
    plan_source:
      type: string
    tasks_completed:
      type: integer
    tasks_total:
      type: integer
    batches_completed:
      type: integer
    batches_total:
      type: integer
    branches_merged:
      type: array
      items:
        type: string
    branches_remaining:
      type: array
      items:
        type: string
  required: [session_id, status, tasks_completed, tasks_total]
---

# claudikins-kernel:execute Command

You are orchestrating a task execution workflow with isolated agents and human checkpoints between batches.

## Flags

| Flag            | Effect                                              |
| --------------- | --------------------------------------------------- |
| `--resume`      | Resume from last checkpoint                         |
| `--status`      | Show current execution status                       |
| `--abort`       | Abort current execution (saves checkpoint)          |
| `--batch N`     | Override batch size (default: from plan)            |
| `--skip-review` | Skip code review (spec review still runs)           |
| `--dry-run`     | Parse plan and show execution order without running |
| `--timing`      | Show task and batch durations                       |
| `--trace`       | Show execution trace at completion                  |

## Merge Strategy

None - task outputs are saved per-task, not merged.

## Philosophy

> "5-7 agents per SESSION, not 30 per batch. Features are the unit of work." - Boris

- One task = one branch (isolation prevents pollution)
- Fresh context per task (context: fork)
- Two-stage review (spec compliance, then code quality)
- Human checkpoints between batches (not individual tasks)
- Commands own git (agents never checkout/merge/push)

## Load Skill

First, load the git-workflow skill for methodology:

```
Skill(git-workflow)
```

This provides:

- Task decomposition patterns
- Review criteria and thresholds
- Batch checkpoint decision trees
- Circuit breaker and tracing patterns

## State Management

State file: `.claude/execute-state.json`

```json
{
  "session_id": "exec-YYYY-MM-DD-HHMM",
  "plan_source": "path/to/plan.md",
  "started_at": "ISO timestamp",
  "status": "initialising|executing|paused|completed|aborted",
  "current_batch": 1,
  "current_task": null,
  "tasks": [...],
  "batches": [...],
  "last_checkpoint": null
}
```

## Phase 0: Initialisation

### Flag Handling

Check for flags first:

```
--status → Run execute-status.sh hook, display status, exit
--resume → Load checkpoint, resume from saved state
--abort → Save checkpoint, mark aborted, exit
--dry-run → Parse and display, don't execute
```

### Plan Loading

1. Get plan path from argument or find most recent in `.claude/plans/`
2. Validate EXECUTION_TASKS markers exist (hook: validate-plan-format.sh)
3. Parse task table between markers
4. Build dependency graph

**On validation failure:**

```
Plan missing EXECUTION_TASKS markers.

The plan must include:
  <!-- EXECUTION_TASKS_START -->
  | # | Task | Files | Deps | Batch |
  ...
  <!-- EXECUTION_TASKS_END -->

Run claudikins-kernel:outline to generate a properly formatted plan.
```

### Dependency Graph

Build from parsed table:

```json
{
  "tasks": [
    {
      "id": "1",
      "name": "Create schema",
      "files": ["prisma/schema.prisma"],
      "deps": [],
      "batch": 1
    },
    {
      "id": "2",
      "name": "Add service",
      "files": ["src/services/user.ts"],
      "deps": ["1"],
      "batch": 1
    },
    {
      "id": "3",
      "name": "Create routes",
      "files": ["src/routes/user.ts"],
      "deps": ["2"],
      "batch": 2
    }
  ],
  "batches": [
    { "id": 1, "tasks": ["1", "2"], "status": "pending" },
    { "id": 2, "tasks": ["3"], "status": "pending" }
  ]
}
```

### Pre-Execution Validation

Per batch-size-verification.md:

```
if tasks.length > 15:
  WARN "Large execution (${tasks.length} tasks). Consider splitting."
  [Continue] [Abort]

if any_batch.tasks.length > 7:
  WARN "Batch ${batch.id} exceeds 7 tasks. Review batch boundaries."
  [Continue] [Adjust batches] [Abort]
```

### LOC Estimation

Per review-criteria.md (400 LOC threshold):

```
Estimate task LOC from file list.
If estimated > 400 LOC:
  WARN "Task ${task.id} may exceed review threshold (~${estimate} LOC)"
  [Proceed] [Split task] [Accept with caveat]
```

### Context Budget Validation

Per babyclaude's context budget guidelines:

| Resource        | Soft Limit | Hard Limit | Pre-Execution Action |
| --------------- | ---------- | ---------- | -------------------- |
| Files to modify | 5          | 10         | Warn if exceeded     |
| Lines of code   | 200        | 400        | Suggest split        |
| Dependencies    | 3          | 5          | Check batch ordering |

```
Task ${task.id} context budget check:
  Files: ${files.length} (limit: 5-10)
  Est. LOC: ~${estimate} (limit: 200-400)

  ${files.length > 5 ? "WARN: Task touches many files" : "OK"}
  ${estimate > 200 ? "WARN: Large task - monitor context usage" : "OK"}
```

If both limits exceeded, strongly recommend splitting before execution.

## Phase 1: Batch Start Checkpoint

For each batch:

```
Batch ${batch.id}/${total_batches}: Ready to execute

Tasks in this batch:
| # | Task | Files | Deps |
|---|------|-------|------|
| 1 | Create schema | prisma/schema.prisma | - |
| 2 | Add service | src/services/user.ts | 1 |

[Execute batch] [Skip task X] [Reorder] [Pause] [Abort]
```

## Phase 2: Task Execution

For each task in batch:

### 2.1 Branch Creation (via create-task-branch.sh hook)

```
Creating branch: execute/task-${id}-${slug}-${uuid}
```

The hook:

1. Verifies clean working directory
2. Creates branch with UUID suffix
3. Updates state with branch name
4. Passes branch info to agent via additionalContext

### 2.2 Agent Spawning

```typescript
Task(babyclaude, {
  prompt: `
    TASK_ID: ${task.id}
    TASK_SLUG: ${task.slug}

    Implement: ${task.name}

    Files to modify: ${task.files.join(", ")}

    Acceptance criteria:
    ${task.criteria.map((c) => `- ${c}`).join("\n")}

    Requirements:
    - Implement EXACTLY what is specified
    - Do NOT add features beyond the spec
    - Commit your changes when complete
    - Output JSON with status and files_changed
  `,
  context: "fork",
  model: "opus",
});
```

### 2.3 Branch Guard (via git-branch-guard.sh hook)

During execution, PreToolUse hook blocks:

- Branch switching (checkout, switch)
- Destructive operations (reset --hard, clean -fd)
- Direct pushes to protected branches
- Rebasing, merging, stashing

### 2.4 Progress Tracking (via execute-tracker.sh hook)

PostToolUse hook:

- Records tool calls for tracing
- Updates stuck score
- Warns if agent appears stuck (score >= 60)

### 2.5 Completion Capture (via task-completion-capture.sh hook)

On SubagentStop:

- Captures agent output to `.claude/task-outputs/${task.id}.json`
- Updates task status in state
- Completes span in trace
- Checks if batch is complete

## Phase 3: Task Review

After task completes, two-stage review:

### 3.1 Spec Review

```typescript
Task(spec - reviewer, {
  prompt: `
    Review task ${task.id}: ${task.name}

    Acceptance criteria:
    ${task.criteria}

    Implementation diff:
    ${getDiff(task.branch)}

    Verify EACH criterion has evidence. Output JSON verdict.
  `,
  context: "fork",
  model: "opus",
});
```

**Output schema:**

```json
{
  "task_id": "1",
  "verdict": "PASS|FAIL",
  "criteria_checked": [...],
  "scope_creep": [...],
  "missing": [...]
}
```

### 3.2 Code Review (if spec passes)

```typescript
Task(code - reviewer, {
  prompt: `
    Review code quality for task ${task.id}

    Spec review: PASS (compliance verified)

    Implementation diff:
    ${getDiff(task.branch)}

    Check quality dimensions. Use confidence scoring.
    Only report issues with confidence >= 26.
  `,
  context: "fork",
  model: "opus",
});
```

**Output schema:**

```json
{
  "task_id": "1",
  "verdict": "PASS|CONCERNS",
  "critical_issues": [],
  "important_issues": [],
  "minor_issues": [],
  "strengths": []
}
```

### 3.3 Review Failure Handling

Per review-conflict-matrix.md:

```
Spec FAIL:
  Retry count < 2? → Retry with fresh babyclaude
  Retry count >= 2? → [Klaus intervention] [Human override] [Skip task]

Code CONCERNS (critical):
  [Fix issues] [Accept with caveats] [Klaus review]

Code CONCERNS (important only):
  [Fix issues] [Accept with caveats]
```

## Phase 4: Batch Review Checkpoint

After all tasks in batch complete:

```
Batch ${batch.id}/${total_batches} complete.

Results:
| Task | Spec | Code | Notes |
|------|------|------|-------|
| 1 | PASS | PASS | Clean implementation |
| 2 | PASS | CONCERNS | Missing edge case (minor) |

[Accept all] [Accept task 1 only] [Revise task 2] [Retry task 2] [Klaus]
```

## Phase 5: Merge Decision

For approved tasks:

```
Ready to merge approved tasks.

Branches:
- execute/task-1-create-schema-abc123 → main
- execute/task-2-add-service-def456 → main

Conflict check: None detected

[Merge all] [Merge task 1 only] [Keep separate] [Squash merge]
```

### Conflict Handling

If conflicts detected:

```
Merge conflict detected in: src/services/user.ts

Conflicting changes:
[Show diff hunks]

[conflict-resolver agent] [Manual resolution] [Skip merge]
```

## Phase 6: Session Completion

After all batches:

```
Execution complete!

Summary:
- Tasks completed: ${completed}/${total}
- Tasks skipped: ${skipped}
- Tasks failed: ${failed}

Branches merged: ${merged_branches}
Branches remaining: ${remaining_branches}

Next: claudikins-kernel:verify to validate the implementation
```

## Emergency Handling

### Context Exhaustion

At 75% context (ACM signal):

```
MANDATORY STOP

Context usage: 78%
Remaining capacity insufficient for safe completion.

[Continue on new tab] [Pause batch] [Emergency complete current task]
```

Checkpoint saved via batch-checkpoint-gate.sh hook.

### Stuck Detection

If stuck_score >= 60:

```
AGENT APPEARS STUCK

Task: ${task.id} (${task.name})
Stuck score: ${score}/100

Indicators:
${indicators}

[Nudge agent] [Extend timeout] [Klaus intervention] [Abort task]
```

### Circuit Breaker

If 3+ failures in 60 seconds:

```
CIRCUIT BREAKER TRIPPED

Operation: ${operation}
State: OPEN

[Wait for reset (30s)] [Force close] [Skip operation] [Abort batch]
```

## Resume Handling

On `--resume`:

1. Load last checkpoint from `.claude/checkpoints/`
2. Display resume point
3. Offer: [Continue from batch X] [Restart batch X] [Start fresh]

```
Resuming execution

Last checkpoint: ${checkpoint_id}
Batch: ${batch}/${total}
Tasks completed: ${completed}/${total}

[Continue] [Restart current batch] [Abort]
```

### Checkpoint Schema

Checkpoints are saved to `.claude/checkpoints/checkpoint-{timestamp}.json`:

```json
{
  "checkpoint_id": "checkpoint-20260117-120000",
  "session_id": "exec-2026-01-17-1000",
  "timestamp": "2026-01-17T12:00:00Z",
  "stop_reason": "context_exhaustion|user_abort|error|batch_complete",
  "execution_state": {
    "current_batch": 2,
    "current_task": "task-5",
    "total_tasks": 10,
    "completed_tasks": 4,
    "in_progress_tasks": 1
  },
  "state_snapshot": {
    "tasks": [...],
    "batches": [...],
    "reviews": {...}
  },
  "trace_snapshot": {
    "spans": [...],
    "tool_calls": [...]
  },
  "recovery_instructions": "Run claudikins-kernel:execute --resume to continue from this checkpoint"
}
```

### Resume Constraints

When resuming:

| Scenario                     | Allowed Actions                                  |
| ---------------------------- | ------------------------------------------------ |
| Mid-batch (task in progress) | [Continue task] [Restart task] [Skip task]       |
| Between batches              | [Continue to next batch] [Restart current batch] |
| After failure                | [Retry failed task] [Skip failed task] [Abort]   |

You cannot jump to arbitrary batches - resume continues from the checkpoint state.

## Trace Output

On `--trace` or completion:

```
Execution Trace: ${session_id}

Timeline:
├── ${time} Session start
├── ${time} Batch 1 start (${n} tasks)
│   ├── task-1 [${duration}] ✓
│   └── task-2 [${duration}] ✓
├── ${time} Batch 1 review [${duration}] ✓
...
└── ${time} Session complete

Total duration: ${duration}
Critical path: ${critical_path}

[View full trace] [Export JSON] [Archive]
```

## Error Recovery

On any failure:

1. Save checkpoint immediately
2. Log error to `.claude/errors/`
3. Offer: [Retry] [Skip] [Klaus] [Manual intervention] [Abort]

Never lose work. Always checkpoint before risky operations.

## Next Stage

When this command completes, ask:

```
AskUserQuestion({
  question: "Execution complete. What next?",
  header: "Next",
  options: [
    { label: "Load /claudikins-kernel:verify", description: "Verify the implementation actually works" },
    { label: "Stay here", description: "Review output before continuing" },
    { label: "Done for now", description: "End the workflow" }
  ]
})
```

If user selects "Load /claudikins-kernel:verify", invoke `Skill(claudikins-kernel:verify)`.
