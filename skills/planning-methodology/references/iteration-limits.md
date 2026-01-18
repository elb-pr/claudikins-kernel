# Iteration Limits (S-2)

Planning is iterative, but iteration must end. This guide helps identify when to stop.

## Hard Limits

These are non-negotiable stopping points:

| Metric | Limit | Rationale |
|--------|-------|-----------|
| Section revision cycles | 5 | Diminishing returns after 5 passes |
| Approach regenerations | 3 | If 3 approaches don't satisfy, problem is unclear |
| Phase transitions | 10 | Prevents infinite looping between phases |
| Research agent spawns | 5 per session | Context cost vs value |
| AskUserQuestion per phase | 7 | User fatigue, decision overload |

When a hard limit is hit:

```
Reached revision limit for this section (5 cycles).
Options: [Finalise as-is] [Klaus review] [Human takes over]
```

## Soft Signals

Watch for these indicators that iteration should end:

### Explicit Signals

| User says | Meaning | Action |
|-----------|---------|--------|
| "Good enough" | Acceptable quality | Finalise |
| "Let's move on" | Impatient with iteration | Finalise |
| "Ship it" | Ready to proceed | Finalise |
| "I'll fix it later" | Not worth more iteration | Finalise with caveat |

### Behavioural Signals

| Behaviour | Meaning | Action |
|-----------|---------|--------|
| User selects first option repeatedly | Decision fatigue | Reduce options, finalise |
| Short responses ("ok", "fine", "sure") | Disengagement | Check in, consider finalising |
| Long pauses between responses | Thinking or distracted | Wait, don't over-iterate |
| User asks unrelated questions | Task switching | Save state, offer to pause |

### Content Signals

| Observation | Meaning | Action |
|-------------|---------|--------|
| Changes are cosmetic (wording, formatting) | Substantive work done | Finalise |
| Same feedback given twice | Not processing revisions | Clarify or finalise |
| Feedback contradicts earlier feedback | Requirements unstable | Stop, re-clarify requirements |
| "Actually, go back to the first version" | Over-iterated | Revert, finalise |

## Heuristics for Each Phase

### Brain-Jam Phase

**Stop when:**
- All key questions answered (problem, success, scope, out-of-scope)
- User confirms understanding with "yes, that's right"
- No new information emerging from questions

**Don't stop when:**
- Core requirements still unclear
- Success criteria not measurable
- Scope boundaries fuzzy

### Research Phase

**Stop when:**
- Sufficient findings to inform approach selection
- Search exhausted with no more relevant results
- User satisfied with research depth

**Don't stop when:**
- Key areas unexplored
- Conflicting information unresolved
- User explicitly wants more research

### Approaches Phase

**Stop when:**
- 2-3 distinct, viable approaches presented
- User has selected one
- Trade-offs clearly articulated

**Don't stop when:**
- User dissatisfied with all options
- Key trade-off missing
- Approaches are too similar to differentiate

### Draft Phase

**Stop when:**
- All sections complete
- User approved each section
- Checklist items satisfied

**Don't stop when:**
- Required sections missing
- EXECUTION_TASKS markers absent
- User has outstanding concerns

### Review Phase

**Stop when:**
- Reviewer feedback addressed
- No blocking issues remain
- User approves final plan

**Don't stop when:**
- Critical issues identified but unfixed
- User hasn't seen reviewer feedback
- Verification checklist incomplete

## Escalation Patterns

When stuck in iteration:

### Level 1: Clarify

```
We've revised this section 3 times. Before continuing:
- Is the core issue clear?
- Are we solving the right problem?
- Should we step back to requirements?
```

### Level 2: Options

```
We've revised this section 4 times. Options:
[Finalise current version] [One more revision] [Get fresh perspective from Klaus]
```

### Level 3: Force Decision

```
Reached iteration limit (5 cycles).
The section must be finalised now.
[Finalise as-is] [Human takes over editing]
```

## Anti-Patterns

### Perfection Paralysis

**Symptom:** Endless refinement of already-good content
**Fix:** Ask "Is this good enough to proceed?" not "Is this perfect?"

### Scope Creep via Iteration

**Symptom:** Each revision adds more requirements
**Fix:** Flag scope changes, require explicit approval for expansion

### Politeness Loops

**Symptom:** "That's better, but could you also..." indefinitely
**Fix:** After 3 cycles, ask "Are we ready to finalise?"

### Analysis Paralysis

**Symptom:** Can't choose between approaches
**Fix:** Make a recommendation, set deadline for decision

## Tracking Iterations

The command should track iteration counts:

```json
{
  "phase": "draft",
  "section_iterations": {
    "problem": 2,
    "scope": 1,
    "criteria": 3,
    "tasks": 0
  },
  "phase_transitions": 4,
  "approach_regenerations": 1
}
```

When approaching limits, warn the user:

```
Note: This is revision 4 of 5 for the Tasks section.
```
