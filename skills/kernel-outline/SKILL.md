---
name: claudikins-kernel:outline
description: Iterative planning with human checkpoints at every phase
argument-hint: <task-description> [--session-id ID] [--skip-research] [--skip-review] [--fast-mode]
agent_outputs:
  - agent: taxonomy-extremist
    capture_to: .claude/agent-outputs/research/
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
  - brain-jam-plan
output-schema:
  type: object
  properties:
    session_id:
      type: string
    status:
      type: string
      enum: [completed, paused, aborted]
    plan_path:
      type: string
    phases_completed:
      type: array
      items:
        type: string
    tasks_count:
      type: integer
    batches_count:
      type: integer
  required: [session_id, status, plan_path]
---

# claudikins-kernel:outline Command

You are orchestrating an iterative planning workflow with human checkpoints at every phase.

## Flags

| Flag              | Effect                                     |
| ----------------- | ------------------------------------------ |
| `--session-id ID` | Resume previous session by ID              |
| `--skip-research` | Skip Phase 2 research                      |
| `--skip-review`   | Skip Phase 5 review                        |
| `--fast-mode`     | 60-second iteration cycles                 |
| `--timing`        | Show phase durations for velocity tracking |
| `--list-sessions` | Show available sessions for resume         |
| `--output PATH`   | Plan destination path                      |
| `--run-verify`    | Run verification anytime                   |

## Merge Strategy

None - outputs are not merged.

## Philosophy

> "Planning is a conversation, not a production line." - Guru Panel consensus

- Human in the loop at every phase
- Verification available anytime (--run-verify flag)
- Pool of tools (unrestricted, not gatekept by phase)
- Defaults ON, skip flags for less
- Non-linear phase access (can jump back/forward)
- 5-7 agents per SESSION, not 30 per batch

## State Management

State file: `.claude/plan-state.json`

```json
{
  "session_id": "plan-YYYY-MM-DD-HHMM",
  "started_at": "ISO timestamp",
  "project_hash": "sha256 of project dir",
  "phase": "brain-jam|research|approaches|draft|review",
  "research_complete": false,
  "human_decisions": [],
  "abandoned": false
}
```

## Phase 0: Session Initialisation

1. Read `$task` from user input
2. Check for existing sessions via `--list-sessions` or `--session-id`
3. If previous session found:
   - If 4+ hours old: WARN "Session is stale. Old research may be outdated."
   - Offer: [Resume] [New Plan] [Review Last]
4. Create new session ID if starting fresh
5. Initialise state file via session-init.sh hook

## Phase 1: Brain-Jam

Load the `brain-jam-plan` skill for methodology.

**Requirements gathering:**

1. Ask ONE question at a time
2. Wait for answer before next question
3. Use AskUserQuestion with specific options
4. Never assume - always clarify

**Key questions to answer:**

- What problem are we solving?
- What constraints apply?
- What's the success criteria?
- What's explicitly OUT of scope?

**Checkpoint:**

```
[Continue to Research] [Revise Requirements] [Abandon Plan]
```

## Phase 2: Research (default ON, skip with --skip-research)

If `--skip-research` flag set:

```
WARNING: Skipping research reduces planning confidence to ~60%
Proceed without research context? [Yes] [No, run research]
```

Otherwise, spawn 2-3 taxonomy-extremist agents in parallel:

```
taxonomy-extremist modes:
- codebase: Use Serena, Glob, Grep for code exploration
- docs: Use Context7, WebFetch for documentation
- external: Use Gemini, WebSearch for external knowledge
```

**Mode selection via AskUserQuestion:**

```
Which research modes should we use?
[Codebase] [Docs] [External] [All three]
```

**Agent spawning:**

```typescript
Task(taxonomy - extremist, {
  prompt: "Research ${topic} for planning ${task}",
  context: "fork", // Isolated context
  mode: "codebase|docs|external",
});
```

**Results collection:**

- SubagentStop hook captures output to `.claude/agent-outputs/research/`
- Merge findings: `jq -s 'add' .claude/agent-outputs/research/*.json`
- Present summarised findings to user

**Empty findings handling:**
If `search_exhausted: true` with no findings:

```
Research found no relevant results.
[Rerun with different query] [Skip research] [Manual input]
```

**Checkpoint:**

```
[Continue to Approaches] [Back to Brain-jam] [Skip] [Abandon]
```

## Phase 3: Approaches

Using research findings and requirements, generate 2-3 distinct approaches.

**Each approach must include:**

- Summary (1-2 sentences)
- Pros (bullet list)
- Cons (bullet list)
- Estimated effort (relative: low/medium/high)
- Risk level (low/medium/high)

**Format (from approach-template.md):**

```markdown
### Approach A: [Name]

**Summary:** ...
**Pros:** ...
**Cons:** ...
**Effort:** Medium | **Risk:** Low

[Recommended] Reason for recommendation
```

**Present recommendation with reasoning.**

**Checkpoint:**

```
[Approach A] [Approach B] [Approach C] [Revise Approaches] [Back to Research] [Abandon]
```

## Phase 4: Draft

Section-by-section drafting with approval after each section.

**Plan structure (from plan-format.md):**

1. Problem Statement
2. Scope & Boundaries
3. Success Criteria
4. Tasks (with EXECUTION_TASKS markers)
5. Dependencies
6. Risks & Mitigations
7. Verification Checklist

**For each section:**

1. Draft the section
2. Present to user
3. Get approval via AskUserQuestion
4. If revisions needed, iterate
5. Move to next section only after approval

**Task format for claudikins-kernel:execute compatibility:**

```markdown
<!-- EXECUTION_TASKS_START -->

| #   | Task               | Files                | Deps | Batch |
| --- | ------------------ | -------------------- | ---- | ----- |
| 1   | Create user schema | prisma/schema.prisma | -    | 1     |
| 2   | Add user service   | src/services/user.ts | 1    | 1     |
| 3   | Create user routes | src/routes/user.ts   | 2    | 2     |

<!-- EXECUTION_TASKS_END -->
```

**Checkpoint after each section:**

```
[Continue] [Revise section] [Back to Approaches] [Abandon]
```

## Phase 5: Review (default ON, skip with --skip-review)

**Reviewer selection via AskUserQuestion:**

```
Who should review this plan?
[Klaus (opinionated devil's advocate)] [Skip review] [Both perspectives]
```

**If Klaus selected:**

```typescript
Task(klaus, {
  prompt: "Review this plan for ${task}. Be brutally honest about weaknesses.",
  context: "fork",
});
```

**Review criteria:**

- Are requirements clear and complete?
- Is scope well-bounded?
- Are success criteria measurable?
- Are tasks properly decomposed?
- Are dependencies correct?
- Are risks identified?

**Checkpoint:**

```
[Iterate on feedback] [Finalise plan] [Back to Draft] [Abandon]
```

## Output

Save plan to user project path (default: `.claude/kernel-outlines/outline-${session_id}.md`)

Include machine-readable task markers for claudikins-kernel:execute compatibility.

**Final message:**

```
Done! Plan saved to [path]

When you're ready:
  claudikins-kernel:execute [plan-path]
```

## Flag Behaviours

| Flag              | Effect                      |
| ----------------- | --------------------------- |
| `--skip-research` | Phase 1 → Phase 3 (skip)    |
| `--skip-review`   | Jump from Phase 4 to Output |
| `--fast-mode`     | 60-second iteration cycles  |
| `--session-id ID` | Resume previous session     |
| `--timing`        | Show phase durations        |
| `--list-sessions` | Show available sessions     |
| `--output PATH`   | Custom output location      |
| `--run-verify`    | Run verification anytime    |

## Error Recovery

On any phase failure:

1. Save current state to plan-state.json
2. Log error to `.claude/errors/`
3. Offer: [Retry] [Skip phase] [Manual intervention] [Abandon]

## Context Collapse Handling

On PreCompact event:

1. preserve-state.sh saves critical state
2. Mark session as "interrupted" (not abandoned)
3. Resume instructions written to state file
4. On resume, offer: [Continue from checkpoint] [Start fresh]

## Next Stage

When this command completes, ask:

```
AskUserQuestion({
  question: "Plan ready. What next?",
  header: "Next",
  options: [
    { label: "Load /claudikins-kernel:execute", description: "Execute the plan with isolated agents" },
    { label: "Stay here", description: "Review output before continuing" },
    { label: "Done for now", description: "End the workflow" }
  ]
})
```

If user selects "Load /claudikins-kernel:execute", invoke `Skill(claudikins-kernel:execute)`.
