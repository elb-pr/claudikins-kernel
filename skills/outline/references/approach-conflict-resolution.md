# Approach Conflict Resolution (S-4)

When generated approaches contradict each other, follow this resolution process.

## Types of Conflicts

### 1. Direct Contradiction

One approach recommends what another prohibits.

**Example:**
- Approach A: "Use server-side rendering for SEO benefits"
- Approach B: "Use client-side rendering for interactivity"

**Conflict:** Can't do both. The approaches are mutually exclusive.

### 2. Assumption Mismatch

Approaches assume different underlying requirements.

**Example:**
- Approach A assumes: "Performance is critical, complexity acceptable"
- Approach B assumes: "Simplicity is critical, some performance loss acceptable"

**Conflict:** Different optimisation targets, neither is "wrong".

### 3. Resource Conflict

Approaches compete for the same limited resource.

**Example:**
- Approach A: "Add Redis for caching"
- Approach B: "Add Redis for session storage"
- Constraint: Only one Redis instance available

**Conflict:** Both valid, but infrastructure limits force a choice.

### 4. Feedback Contradiction

User feedback contradicts their earlier approval.

**Example:**
- Phase 2: User chose Approach A (microservices)
- Phase 4: User says "Actually, I want a simpler monolith"

**Conflict:** Previous decision now invalid.

## Detection Signals

Watch for these indicators:

| Signal | Indicates |
|--------|-----------|
| "But in Approach A you said..." | Direct contradiction |
| Approaches have opposite pros/cons | Assumption mismatch |
| Multiple approaches need same resource | Resource conflict |
| "I changed my mind" | Feedback contradiction |
| Research findings contradict chosen approach | New information conflict |

## Resolution Process

### Step 1: Identify the Specific Conflict

Don't proceed with vague conflict. Pin it down:

```
I notice a conflict between our approaches:

Approach A (REST API): Recommends separate endpoints for each resource
Approach B (GraphQL): Recommends single endpoint with query flexibility

These are fundamentally different paradigms. We need to choose one.
```

### Step 2: Trace to Requirements

Find the root requirement causing the conflict:

```
This conflict stems from unclear requirements around:
- Client flexibility needs
- Backend complexity tolerance
- Team expertise

Let me ask some clarifying questions.
```

### Step 3: Clarify with User

Use AskUserQuestion to resolve the ambiguity:

```
To resolve the REST vs GraphQL conflict:

How important is client query flexibility?
[Critical - clients need to fetch exactly what they want]
[Nice to have - standard REST endpoints are fine]
[Not important - server dictates data shape]
```

### Step 4: Regenerate or Proceed

Based on clarification:

**If one approach now clearly wins:**
```
Based on your answer (client flexibility is critical), GraphQL is the clear choice.
Proceeding with Approach B.
```

**If still ambiguous:**
```
Still unclear. Let me generate a hybrid approach that combines elements of both.
```

## Example: Full Conflict Resolution

### Scenario

**Approach A: Monorepo with Turborepo**
- Pros: Shared code, unified versioning, atomic changes
- Cons: Complex build setup, learning curve

**Approach B: Polyrepo with npm packages**
- Pros: Team autonomy, simpler CI per repo, familiar patterns
- Cons: Dependency management, version drift, cross-repo changes painful

**Conflict detected:** These are opposite philosophies.

### Resolution Flow

```
Claude: I notice these approaches are fundamentally different architectures.
        Before proceeding, I need to understand your priorities.

        Question 1: How often do changes span multiple packages?
        [Frequently - most features touch 3+ packages]
        [Sometimes - maybe once a week]
        [Rarely - packages are independent]

User: Frequently

Claude: Question 2: How important is team autonomy for deployment?
        [Critical - teams must deploy independently]
        [Nice to have - coordinated releases are fine]
        [Not important - we deploy everything together]

User: Not important

Claude: Based on your answers:
        - Frequent cross-package changes → monorepo benefits
        - Coordinated deployment acceptable → monorepo not a blocker

        Recommendation updated: Approach A (Monorepo) is the clear winner.
        Proceeding with Turborepo setup.
```

## Escalation Path

If conflict persists after 2 clarification attempts:

```
We've tried to resolve this conflict twice but it remains unclear.

Options:
[Get Klaus's perspective] - Devil's advocate may spot something we missed
[Present both to stakeholders] - This may need a broader decision
[Prototype both] - Build minimal versions, let reality decide
[User decides] - Make a gut call, we'll adapt
```

## Edge Cases

### New Information Invalidates Chosen Approach

During draft phase, research reveals the chosen approach won't work.

```
Alert: Research findings conflict with chosen approach.

Chosen: Use WebSockets for real-time updates
Finding: Target deployment (AWS Lambda) doesn't support persistent connections

Options:
[Return to Approaches phase] - Regenerate with new constraint
[Modify chosen approach] - Use polling or SSE instead
[Proceed anyway] - Accept deployment limitation
```

### User Changes Mind Mid-Draft

```
You previously chose Approach B, but now prefer Approach A.

Impact:
- 2 draft sections would need revision
- Research findings still valid
- No wasted implementation work yet

[Switch to Approach A] - Revise draft sections
[Stick with Approach B] - Continue current path
[Discuss the change] - What's driving this?
```

### Approaches Were Never Truly Distinct

Sometimes generated "approaches" are variations, not alternatives.

```
On reflection, Approaches A and B are both "use Redis" with minor config differences.
These aren't meaningful choices.

Regenerating approaches with truly distinct options...
```

## Prevention

To reduce conflicts:

1. **Front-load clarification** - Ask key questions in brain-jam
2. **Make assumptions explicit** - State what each approach assumes
3. **Check for mutual exclusivity** - Before presenting, verify approaches can't both be done
4. **Research before approaches** - Let findings inform approach generation
