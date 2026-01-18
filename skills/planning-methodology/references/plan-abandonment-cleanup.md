# Plan Abandonment Cleanup (S-5)

When a user abandons a planning session, clean up gracefully while preserving recovery options.

## Abandonment Triggers

### Explicit Abandonment

User selects [Abandon] at any checkpoint:

```
Are you sure you want to abandon this planning session?
Research and draft work will be archived (recoverable for 7 days).

[Confirm abandon] [Continue planning]
```

### Implicit Abandonment

- Session timeout (30 minutes idle without checkpoint)
- User closes terminal without completing
- Context collapses without graceful handoff

### Verbal Abandonment

User says something like:

- "Forget this"
- "Never mind"
- "Let's do something else"
- "This isn't working"

Detect and confirm:

```
It sounds like you want to stop planning. Is that right?
[Yes, abandon this plan] [No, continue]
```

## Cleanup Actions

### Step 1: Mark State as Abandoned

```json
{
  "session_id": "plan-2026-01-16-1430",
  "status": "abandoned",
  "abandoned_at": "2026-01-16T15:45:00Z",
  "abandoned_phase": "draft",
  "abandoned_reason": "user_request",
  "recovery_until": "2026-01-23T15:45:00Z"
}
```

### Step 2: Archive Research Findings

Move, don't delete:

```bash
# Archive research
mv .claude/agent-outputs/research/*.json \
   .claude/archive/research-${SESSION_ID}/

# Archive partial drafts
mv .claude/plans/draft-${SESSION_ID}.md \
   .claude/archive/drafts/
```

### Step 3: Clear Work-in-Progress

Remove temporary files that won't be useful:

```bash
# Clear lock files
rm -f .claude/session-lock-*

# Clear temp files
rm -f .claude/tmp/*
```

### Step 4: Notify User

```
Planning session abandoned.

Archived (recoverable for 7 days):
- Research findings (3 files)
- Partial draft (2 sections)

To recover: claudikins-kernel:outline --session-id plan-2026-01-16-1430
```

## Recovery Option

Abandoned plans can be resumed within 7 days:

```bash
claudikins-kernel:outline --session-id plan-2026-01-16-1430
```

Recovery flow:

```
Found abandoned planning session from 2 days ago.
Phase: Draft (Problem and Scope sections complete)
Reason abandoned: User request

[Resume from checkpoint] [Start fresh with same research] [Start completely fresh]
```

After 7 days, archived content is eligible for deletion on next cleanup.

## Retention Policy

| Content           | Retention        | Reason                  |
| ----------------- | ---------------- | ----------------------- |
| plan-state.json   | 7 days           | Recovery reference      |
| Research findings | 7 days           | May inform future plans |
| Partial drafts    | 7 days           | Effort preservation     |
| Lock files        | Immediate delete | No value                |
| Temp files        | Immediate delete | No value                |

## Cleanup Script

The cleanup can be run manually or via scheduled task:

```bash
#!/bin/bash
# cleanup-abandoned.sh

ARCHIVE_DIR=".claude/archive"
RETENTION_DAYS=7

# Find and remove old archives
find "$ARCHIVE_DIR" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} +

echo "Cleaned archives older than $RETENTION_DAYS days"
```

## Edge Cases

### Abandon with Uncommitted Research

If research agents are still running when user abandons:

```
Note: Research agent still running in background.
[Wait for completion then archive] [Kill agent and abandon immediately]
```

### Abandon with Valuable Partial Work

If significant work has been done:

```
Warning: You've completed 4 of 6 sections.
This represents significant effort.

[Confirm abandon] [Save partial plan as draft] [Continue]
```

### Repeated Abandonment

If user abandons 3+ sessions in a row:

```
This is your 3rd abandoned session recently.
Common causes:
- Requirements unclear at start
- Planning scope too large
- Wrong approach to problem

Would you like to discuss what's making planning difficult?
[Yes, let's talk] [No, just abandon]
```

## Metrics (Optional)

Track abandonment patterns to improve:

```json
{
  "abandonments_last_30_days": 5,
  "most_common_phase": "approaches",
  "average_time_before_abandon": "12 minutes",
  "recovery_rate": "20%"
}
```

If many abandonments happen at the same phase, the phase might need improvement.
