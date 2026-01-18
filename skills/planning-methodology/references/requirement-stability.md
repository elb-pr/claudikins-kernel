# Requirement Stability (S-6)

Detecting and handling scope creep during planning.

## Scope Creep Metrics

Track these quantitative indicators:

| Metric | Green | Yellow | Red |
|--------|-------|--------|-----|
| New requirements after brain-jam | 0-1 | 2-3 | 4+ |
| Success criteria count growth | 0-10% | 11-25% | 26%+ |
| Out-of-scope items moved in | 0 | 1 | 2+ |
| Task count growth | 0-15% | 16-30% | 31%+ |
| Phase revisits due to new requirements | 0 | 1 | 2+ |

### Calculation Examples

**Success criteria growth:**
```
Original criteria: 5 items
Current criteria: 7 items
Growth: (7-5)/5 = 40% → RED
```

**Task count growth:**
```
Original estimate: 8 tasks
Current count: 12 tasks
Growth: (12-8)/8 = 50% → RED
```

## Detection Triggers

### Trigger 1: New Requirements After Brain-Jam

**Scenario:** During approaches phase, user says "Oh, it also needs to support mobile."

**Detection:**
```json
{
  "phase": "approaches",
  "new_requirement": "mobile support",
  "original_requirements_hash": "abc123",
  "current_requirements_hash": "def456",
  "delta": "+1 requirement"
}
```

**Response:**
```
New requirement detected: "mobile support"

This wasn't in our original requirements from brain-jam.
Impact: May affect approach selection and task estimates.

[Add to scope] [Add to out-of-scope] [Return to brain-jam]
```

### Trigger 2: Success Criteria Expansion

**Scenario:** Originally "user can log in", now "user can log in with SSO, MFA, and remember-me".

**Detection:**
```json
{
  "original_criteria": ["user can log in"],
  "current_criteria": ["user can log in with SSO", "user can enable MFA", "remember-me works"],
  "growth": "200%"
}
```

**Response:**
```
Success criteria has grown significantly (200%).

Original: 1 criterion
Current: 3 criteria

This changes the scope of the plan substantially.

[Accept expanded scope] [Revert to original] [Split into phases]
```

### Trigger 3: Out-of-Scope Items Moving In

**Scenario:** "Rate limiting" was explicitly out of scope, now user wants it included.

**Detection:**
```json
{
  "originally_out_of_scope": ["rate limiting", "admin dashboard"],
  "now_requested": "rate limiting",
  "reason": "user changed mind"
}
```

**Response:**
```
"Rate limiting" was explicitly marked out-of-scope in brain-jam.

Why it was excluded: "Future enhancement, not needed for MVP"

Including it now will:
- Add 2-3 tasks
- Require additional research
- Potentially affect other tasks

[Include in scope] [Keep out-of-scope] [Discuss trade-offs]
```

## Concrete Scenarios

### Scenario A: The Growing Login Feature

**Brain-jam output:**
```markdown
## Requirements
- User can log in with email/password
- User can log out

## Out of Scope
- Social login
- MFA
- Password reset
```

**During approaches, user says:**
"Actually, we need Google login too."

**Scope creep detected:**
- New requirement: social login
- Was explicitly out-of-scope
- Affects authentication architecture

**Response flow:**
```
Alert: "Google login" was marked out-of-scope.

Impact assessment:
- Adds OAuth integration complexity
- Requires new dependencies (passport-google)
- Adds 3-4 tasks to the plan
- May change recommended approach

Options:
[Include now] - Return to brain-jam, update requirements
[Defer to v2] - Keep out-of-scope, note for future
[Discuss] - Understand priority before deciding
```

### Scenario B: The Expanding API

**Original task estimate:** 6 endpoints

**During drafting, user requests:**
- Pagination on all list endpoints (+3 tasks)
- Filtering on 2 endpoints (+2 tasks)
- Sorting options (+2 tasks)
- Rate limiting (+2 tasks)

**Scope creep detected:**
- Task count growth: 150%
- 9 new tasks from "enhancements"

**Response flow:**
```
Task count has grown 150% during drafting.

Original estimate: 6 tasks
Current estimate: 15 tasks

This suggests requirements were incomplete during brain-jam.

Options:
[Accept expanded scope] - Update plan with new tasks
[Prioritise ruthlessly] - Which of these are truly MVP?
[Split into phases] - Core now, enhancements later
[Return to brain-jam] - Requirements need more work
```

### Scenario C: The Moving Target

**Pattern:** User approves each section, then asks to change earlier sections.

**Sequence:**
1. Problem statement approved
2. Scope approved
3. Success criteria approved
4. During tasks: "Actually, can we add real-time updates to the scope?"

**Scope creep detected:**
- Phase revisit requested
- Would invalidate 2 approved sections
- 3rd time this has happened

**Response flow:**
```
This is the 3rd request to modify approved sections.

Pattern detected: Requirements are unstable.

This suggests we may have moved too quickly through brain-jam.

Options:
[Return to brain-jam] - Spend more time on requirements
[Freeze scope] - No more changes, plan with current scope
[Accept this change only] - One more modification, then freeze
```

### Scenario D: The Implicit Expectation

**User didn't mention it, but seems to expect it:**

During review: "Where's the admin dashboard? I assumed that was included."

**Detection:**
- New requirement
- Not discussed in brain-jam
- User assumed it was implicit

**Response flow:**
```
"Admin dashboard" wasn't discussed during requirements.

Clarifying questions:
- What admin functions are needed?
- Who are the admin users?
- What's the priority vs user features?

This may indicate incomplete requirements gathering.

[Add to scope with details] [Add to out-of-scope] [Return to brain-jam]
```

## Prevention Strategies

### 1. Explicit Out-of-Scope List

During brain-jam, actively populate out-of-scope:

```
What are we explicitly NOT doing in this plan?
[User provides items]

Confirming out-of-scope:
- Admin dashboard
- Mobile app
- Rate limiting
- Multi-tenancy

If any of these become needed, we'll treat it as scope change.
```

### 2. Requirements Snapshot

Take a snapshot at end of brain-jam:

```json
{
  "snapshot_at": "end_of_brain_jam",
  "requirements_hash": "sha256...",
  "requirement_count": 5,
  "criteria_count": 4,
  "out_of_scope_count": 6
}
```

Reference this snapshot when changes occur.

### 3. Change Impact Assessment

Before accepting any scope change:

```
Change: Add rate limiting
Impact:
- Tasks: +3
- Complexity: +Medium
- Dependencies: +1 (Redis)
- Timeline: +20%

Accept this change? [Yes with impact] [No, keep out-of-scope]
```

### 4. Scope Freeze Option

Offer to freeze scope at any point:

```
Would you like to freeze scope at this point?
No further requirements will be added to this plan.
New ideas will be captured for a future plan.

[Freeze scope] [Keep flexible]
```

## Metrics Dashboard

Track across sessions:

```json
{
  "sessions_last_30_days": 10,
  "average_scope_growth": "23%",
  "sessions_with_red_metrics": 3,
  "most_common_creep_type": "new_requirements_post_brainjam",
  "average_phase_revisits": 1.2
}
```

Use this to identify if brain-jam phase needs improvement.
