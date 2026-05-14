---
name: claudikins-kernel:execute
description: Execute validated plans with isolated agents and two-stage review
argument-hint: <plan-path> | --resume | --status [--model opus|sonnet]
model: opus
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

| Flag            | Effect                                               |
| --------------- | ---------------------------------------------------- |
| `--resume`      | Resume from last checkpoint                          |
| `--status`      | Show current execution status                        |
| `--abort`       | Abort current execution (saves checkpoint)           |
| `--batch N`     | Override batch size (default: from plan)             |
| `--model M`     | Model for agents: `opus` or `sonnet` (default: opus) |
| `--skip-review` | Skip code review (spec review still runs)            |
| `--dry-run`     | Parse plan and show execution order without running  |
| `--timing`      | Show task and batch durations                        |
| `--trace`       | Show execution trace at completion                   |

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
--model → Set agent model (opus|sonnet), stored in execute-state.json
```

### Model Selection

If `--model` flag is provided, use the specified model. Otherwise, prompt the user:

```
AskUserQuestion({
  question: "Which model should agents use for this execution?",
  header: "Model Selection",
  options: [
    { label: "Opus", description: "Most capable — best for complex tasks (uses more session quota)" },
    { label: "Sonnet", description: "Fast and capable — good for straightforward tasks (lighter on quota)" }
  ]
})
```

Store the selected model in `execute-state.json` as `"model": "opus"|"sonnet"`. All `Task()` calls for babyclaude, spec-reviewer, and code-reviewer must use this value.

### Pre-flight: gitignore ephemeral state

The `create-task-branch.sh` hook refuses to create a worktree if the working
tree is dirty (`git diff-index --quiet HEAD --`). The orchestrator writes to
`.claude/execute-state.json`, `.claude/traces/`, and `.claude/checkpoints/`
between every spawn, so if those paths are tracked, the hook will block from
the second task onwards.

If `.claude/.gitignore` is missing, create one with:

```
execute-state.json
execute-trace.json
checkpoints/
traces/
task-outputs/
agent-outputs/
reviews/
errors/
evidence/
verification/
tmp/
SCOPE_NOTES.md
```

and commit it (along with `git rm --cached` of any of those paths that are
already tracked) BEFORE Phase 1.

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

### 2.1 Write `current_task` to state (orchestrator, BEFORE spawn)

**CRITICAL — do this before every babyclaude spawn.**

The `SubagentStart` hook (`create-task-branch.sh`) needs to know which task it's
provisioning a worktree for. The Claude Code hook stdin JSON does NOT contain
the spawn prompt, so the hook cannot extract `TASK_ID` from there. Instead the
hook reads `current_task` from `execute-state.json`.

Therefore the orchestrator MUST write the current task ID into state immediately
before calling `Task(babyclaude, ...)`:

```typescript
// MANDATORY: set current_task in state before spawning
const stateFile = `${projectDir}/.claude/execute-state.json`;
const state = JSON.parse(readFileSync(stateFile, "utf8"));
state.current_task = task.id; // string ID, e.g. "1" or "auth-mw"
state.status = "executing"; // hook bails if not "executing"
writeFileSync(stateFile, JSON.stringify(state, null, 2));
```

Skipping this step is the single most common cause of "the worktree wasn't
created" failures. The hook silently exits 0 if `current_task` is null.

### 2.2 Branch + worktree creation (via create-task-branch.sh hook)

```
Branch: execute/task-${id}-${slug}-${uuid}
Worktree: /tmp/kernel-worktrees/task-${id}-${uuid}
```

When you call `Task(babyclaude, ...)`, the SubagentStart hook fires
**synchronously** before the agent starts running. The hook:

1. Reads `agent_type` from stdin; verifies it ends in `:babyclaude`.
2. `cd`s to the project root (from hook input `cwd` field).
3. Verifies a git repository with a clean working tree (`git diff-index --quiet HEAD`).
4. Reads `current_task` from state (this is why step 2.1 is mandatory).
5. Creates `execute/task-<id>-<slug>-<uuid>` branch (no checkout).
6. Creates worktree at `/tmp/kernel-worktrees/task-<id>-<uuid>`.
7. Updates `execute-state.json` with `tasks[i].branch` and `tasks[i].worktree_path`.

If the working tree is dirty, the hook exits 2 and the agent spawn is blocked.
Ensure ephemeral state files (`execute-state.json`, `traces/`, `checkpoints/`,
`task-outputs/`, etc.) are in `.claude/.gitignore` so editing them mid-batch
doesn't trip this guard.

> **Hooks ABI note:** The `systemMessage` JSON output from `create-task-branch.sh`
> is NOT propagated to the spawned subagent on current Claude Code versions.
> The agent learns its worktree path by reading state itself — see
> `agents/babyclaude.md` Step 0. The orchestrator does NOT need to inject the
> worktree path into the spawn prompt.

### 2.3 Agent Spawning

The flow is:

1. Orchestrator writes `current_task` to state (step 2.1).
2. Orchestrator calls `Task(babyclaude, ...)`.
3. SubagentStart hook fires synchronously, creates the worktree, writes
   `worktree_path` back to state (step 2.2).
4. Babyclaude starts running; its system prompt's "Step 0" instructs it to read
   `execute-state.json` and locate its own `worktree_path`. The orchestrator
   does **not** know the worktree path before spawn and does **not** need to
   inject it into the prompt — the hook generates a UUID that the orchestrator
   couldn't predict anyway.

**Test Task Detection:**

Before spawning babyclaude, check if this is a test task:

```typescript
const isTestTask =
  task.name.toLowerCase().includes("test") ||
  task.type === "Test" ||
  task.files.some((f) => f.includes(".test.") || f.includes(".spec."));
```

**Implementation Source Injection (for test tasks):**

If `isTestTask` is true, the orchestrator MUST inject dependency implementation
files into the prompt. Test tasks run against a worktree branched off `master`,
so the dependency's output is NOT in the worktree (its branch hasn't been merged
yet). The orchestrator needs to either inline the source contents or include a
`cp` command for the test to access them.

```typescript
let implementationSources = "";

if (isTestTask && task.deps.length > 0) {
  const depTasks = task.deps
    .map((depId) => state.tasks.find((t) => t.id === depId))
    .filter((t) => t && t.status === "completed");

  // Read each dependency's output files from the dependency's worktree
  const sources = depTasks.flatMap((dep) =>
    (dep.files || []).map((f) => ({
      file: f,
      contents: readFileSync(`${dep.worktree_path}/${f}`, "utf8"),
    })),
  );

  implementationSources = `
## Implementation Sources to Test (from dependency tasks)

The following files are produced by your dependency tasks. They are NOT yet in
your worktree (deps aren't merged). Copy them in from the dependency worktrees
before running tests, e.g.:

${depTasks.map((d) => `cp ${d.worktree_path}/*.{py,ts,js} <your-worktree>/`).join("\n")}

File contents follow so you can write the test without assuming an interface:

${sources.map((s) => `### ${s.file}\n\`\`\`\n${s.contents}\n\`\`\``).join("\n\n")}
`;
}
```

**Spawning babyclaude:**

```typescript
// Step 2.1 — write current_task FIRST (mandatory)
state.current_task = task.id;
state.status = "executing";
writeFileSync(stateFile, JSON.stringify(state, null, 2));

// Step 2.3 — call Agent. The SubagentStart hook will provision the worktree
// synchronously before babyclaude starts. The agent reads its worktree path
// from execute-state.json (per agents/babyclaude.md Step 0).
Task(babyclaude, {
  prompt: `
    TASK_ID: ${task.id}
    TASK_SLUG: ${task.slug}

    Step 0 of your system prompt applies: locate your worktree by reading
    \`current_task\` and \`tasks[].worktree_path\` from
    ${projectDir}/.claude/execute-state.json. ALL file operations MUST happen
    inside that worktree, not the main repo.

    Implement: ${task.name}

    Files to create/modify: ${task.files.join(", ")}

    Acceptance criteria:
    ${task.criteria.map((c) => `- ${c}`).join("\n")}
    ${implementationSources}

    Requirements:
    - Implement EXACTLY what is specified
    - Do NOT add features beyond the spec
    - Do NOT run git operations — the orchestrator owns git
    - Output JSON with status and files_changed
  `,
  // NOTE: do NOT set cwd here — the hook can't communicate the worktree path
  // back to the Agent tool before it starts the subagent. The subagent reads
  // its worktree path from state and uses absolute paths / cd internally.
  subagent_type: "claudikins-kernel:babyclaude",
  model: state.model || "opus",
});

// Step 2.6 — after Agent returns, the worktree_path is in state. Read it for
// the review phase (which needs the diff from the task branch).
const completed = JSON.parse(readFileSync(stateFile, "utf8"));
const worktreePath = completed.tasks.find(
  (t) => t.id === task.id,
)?.worktree_path;
if (!worktreePath) {
  throw new Error(
    `No worktree for task ${task.id} after Agent returned. Check /tmp/kernel-hooks.log.`,
  );
}
```

**Why this flow:** The original design assumed the SubagentStart hook could pass
the worktree path to the spawned subagent via a `systemMessage` JSON response.
Empirically that does not propagate to the subagent's context on current Claude
Code versions. The state-file-as-side-channel pattern works reliably and has the
side benefit of letting the orchestrator inspect `worktree_path`, `branch`, and
`stuck_score` at any time without parsing hook outputs.

### 2.4 Branch Guard (via git-branch-guard.sh hook)

During execution, PreToolUse hook blocks:

- Branch switching (checkout, switch)
- Destructive operations (reset --hard, clean -fd)
- Direct pushes to protected branches
- Rebasing, merging, stashing

### 2.5 Progress Tracking (via execute-tracker.sh hook)

PostToolUse hook (fires on every tool call inside the subagent):

- Records tool calls for tracing
- Updates `tasks[i].tool_calls`, `last_tool`, `last_activity`, `stuck_score`
- Warns if `stuck_score >= 60`

**Atomicity note:** The hook updates state via `jq ... > state.tmp && mv state.tmp state`. Earlier versions of the hook ran `mv` unconditionally even when `jq` failed, which silently truncated `execute-state.json` to 0 bytes. The current hook validates the `.tmp` is non-empty and parses as JSON before swapping it in. If you see state vanish mid-batch, check `/tmp/kernel-hooks.log` for `execute-tracker: WARNING` lines.

### 2.6 Completion Capture (via task-completion-capture.sh hook)

On SubagentStop:

- Captures agent output to `.claude/task-outputs/${task.id}.json`
- Updates task status in state
- Completes span in trace
- Checks if batch is complete

## Phase 3: Task Review

After task completes, two-stage review:

### CRITICAL: Review Enforcement

**You MUST spawn the reviewer agents. Inline reviews are VIOLATIONS.**

| ✅ CORRECT                            | ❌ VIOLATION                       |
| ------------------------------------- | ---------------------------------- |
| `Task(spec-reviewer, {...})`          | Creating your own compliance table |
| `Task(code-reviewer, {...})`          | "Let me verify the implementation" |
| Reading `.claude/reviews/spec/*.json` | Writing "Verdict: PASS" yourself   |

**The orchestrator does NOT review. The orchestrator SPAWNS reviewers.**

Before proceeding to Phase 4 (Batch Review), verify:

```
□ .claude/reviews/spec/{task_id}.json EXISTS
□ .claude/reviews/code/{task_id}.json EXISTS
□ Files contain valid JSON with "verdict" field
```

If files are missing: **STOP. You skipped the review. Go back and spawn the agents.**

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

After each batch's reviews pass and the human accepts, merge the task branches
into the base (master/main) BEFORE starting the next batch. Tasks in later
batches depend on outputs from earlier batches — if you don't merge, the next
batch's worktrees won't see those files.

```
Ready to merge approved tasks.

Branches:
- execute/task-1-create-schema-abc123 → main
- execute/task-2-add-service-def456 → main

Conflict check: None detected

[Merge all] [Merge task 1 only] [Keep separate] [Squash merge]
```

### Between-batch state cleanup (orchestrator)

After merging and before starting the next batch, the orchestrator must:

```typescript
// 1. Clear current_task so the SubagentStart hook doesn't try to provision
//    a worktree on an unrelated subagent spawn (e.g. spec-reviewer).
state.current_task = null;
// 2. Advance current_batch.
state.current_batch = nextBatch.id;
// 3. (Optional) Remove the merged tasks' worktrees to free disk.
//    `git worktree remove <path>` is BLOCKED by git-branch-guard.sh while
//    status === "executing"; cleanup must happen after Phase 6 sets status
//    to "completed", or via direct `rm -rf` of the worktree path + a follow-up
//    `git worktree prune`.
writeFileSync(stateFile, JSON.stringify(state, null, 2));
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
