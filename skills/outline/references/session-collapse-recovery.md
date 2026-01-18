# Session Collapse Recovery (S-1)

When context collapses mid-planning, follow this procedure to recover gracefully.

## Detection Signals

Context collapse can happen in several ways:

| Signal               | Source                               | Meaning                          |
| -------------------- | ------------------------------------ | -------------------------------- |
| PreCompact event     | Claude Code                          | Context window approaching limit |
| ACM 60% threshold    | claudikins-automatic-context-manager | Recommended handoff point        |
| Session timeout      | Claude Code                          | Idle timeout or connection lost  |
| User closes terminal | System                               | Unexpected termination           |

## State Preservation (PreCompact Hook)

When `preserve-state.sh` fires, it captures:

```json
{
  "session_id": "plan-2026-01-16-1430",
  "interrupted_at": "2026-01-16T14:45:00Z",
  "status": "interrupted",
  "phase": "draft",
  "phase_progress": {
    "brain_jam": "complete",
    "research": "complete",
    "approaches": "complete",
    "draft": {
      "sections_complete": ["problem", "scope", "criteria"],
      "current_section": "tasks",
      "section_draft": "partial content here..."
    },
    "review": "pending"
  },
  "human_decisions": [
    { "phase": "brain_jam", "decision": "Confirmed requirements" },
    { "phase": "research", "decision": "Selected codebase mode" },
    { "phase": "approaches", "decision": "Chose Approach B" }
  ],
  "research_findings": ".claude/agent-outputs/research/merged.json",
  "resume_instructions": "Continue from 'Tasks' section draft. User chose Approach B."
}
```

## Recovery Flow

### Step 1: Detect Previous Session

On `claudikins-kernel:outline` invocation, check for existing state:

```bash
STATE_FILE=".claude/plan-state.json"
if [ -f "$STATE_FILE" ]; then
  STATUS=$(jq -r '.status' "$STATE_FILE")
  if [ "$STATUS" = "interrupted" ]; then
    # Previous session exists
  fi
fi
```

### Step 2: Present Recovery Options

Use AskUserQuestion:

```
Found interrupted planning session from 2 hours ago.
Phase: Draft (Tasks section in progress)
Approach selected: B - JWT with HttpOnly Cookies

[Resume from checkpoint] [Start fresh] [Review session state]
```

### Step 3: Resume from Checkpoint

If user chooses to resume:

1. **Load state file**

   ```
   Read .claude/plan-state.json
   ```

2. **Restore context**
   - Load research findings from saved path
   - Restore human decisions made
   - Load partial draft content

3. **Summarise for user**

   ```
   Resuming planning session plan-2026-01-16-1430.

   Previously completed:
   - Requirements gathering (approved)
   - Research (codebase mode, 12 findings)
   - Approach selection (Approach B chosen)
   - Draft sections: Problem, Scope, Criteria

   Continuing from: Tasks section
   ```

4. **Continue from exact point**
   - Don't re-ask questions already answered
   - Don't regenerate content already approved
   - Pick up mid-section if partial draft exists

### Step 4: Start Fresh

If user chooses fresh start:

1. Archive old state

   ```bash
   mv .claude/plan-state.json .claude/archive/plan-state-{timestamp}.json
   ```

2. Clear research cache

   ```bash
   rm -rf .claude/agent-outputs/research/*
   ```

3. Begin new session with fresh ID

## Edge Cases

### Stale Session (4+ hours old)

```
WARNING: Session is 6 hours old. Research findings may be outdated.

[Resume anyway] [Rerun research] [Start fresh]
```

If resuming stale session:

- Flag research as "potentially outdated"
- Offer to rerun taxonomy-extremist before continuing

### Corrupted State File

If state file fails to parse:

```
ERROR: Could not read previous session state.
File may be corrupted: .claude/plan-state.json

[Start fresh] [Manual recovery]
```

For manual recovery:

- Show raw file content
- Let user extract useful info
- Begin new session

### Multiple Interrupted Sessions

If multiple state files exist:

```
Found 3 interrupted planning sessions:
1. plan-2026-01-16-1430 (Draft phase, 2 hours ago)
2. plan-2026-01-15-0900 (Research phase, 1 day ago)
3. plan-2026-01-14-1600 (Brain-jam phase, 2 days ago)

[Resume #1] [Resume #2] [Resume #3] [Start fresh]
```

### Different Project

If state file is from a different project:

```
ERROR: Plan state is for different project.
State project: /home/user/other-project
Current project: /home/user/this-project

[Start fresh] [Cancel]
```

## State File Locations

| File                                    | Purpose                      |
| --------------------------------------- | ---------------------------- |
| `.claude/plan-state.json`               | Current/latest session state |
| `.claude/archive/plan-state-*.json`     | Archived sessions            |
| `.claude/agent-outputs/research/*.json` | Research findings            |
| `.claude/plans/plan-*.md`               | Completed plans              |

## Testing Recovery

Before deploying, verify these scenarios:

1. Interrupt mid-brain-jam, resume - should continue requirements
2. Interrupt mid-research, resume - should not re-spawn agents
3. Interrupt mid-draft, resume - should continue from section
4. Stale session warning appears after 4 hours
5. Corrupted state file handled gracefully
6. Fresh start properly archives old state
