# Approach Presentation Template

When presenting approaches to the user, follow this format to ensure clear comparison and informed decision-making.

## Template Format

```markdown
### Approach A: [Descriptive Name]

**Summary:** 1-2 sentence overview of what this approach does.

**Pros:**
- Benefit 1
- Benefit 2
- Benefit 3

**Cons:**
- Drawback 1
- Drawback 2

**Effort:** Low/Medium/High | **Risk:** Low/Medium/High

[If this is the recommended option:]
> **Recommended** - Brief reason why this is the best choice given the requirements.
```

## Guidelines

1. **Always present 2-3 options** - Never just one
2. **Be honest about trade-offs** - Users appreciate candour
3. **Recommend one** - Don't be wishy-washy, make a call
4. **Explain your reasoning** - Why is the recommended one best?
5. **Let user decide** - Your recommendation is advice, not a directive

## Effort and Risk Definitions

| Rating | Effort Meaning | Risk Meaning |
|--------|----------------|--------------|
| Low | < 1 day, straightforward | Unlikely to cause issues |
| Medium | 1-3 days, some complexity | Moderate chance of issues |
| High | 3+ days, significant work | High chance of complications |

## Example: Authentication Feature

### Approach A: JWT with HttpOnly Cookies

**Summary:** Store JWT tokens in HttpOnly cookies for automatic inclusion in requests and XSS protection.

**Pros:**
- XSS-resistant (JavaScript can't access tokens)
- Automatic inclusion in requests (no manual header management)
- Well-established pattern with good library support

**Cons:**
- Requires CSRF protection (adds complexity)
- Slightly harder to debug (can't inspect token in browser)
- Cookie size limits apply

**Effort:** Medium | **Risk:** Low

> **Recommended** - Best security posture for web apps with minimal trade-offs.

---

### Approach B: JWT in localStorage

**Summary:** Store JWT in browser localStorage and include in Authorization header manually.

**Pros:**
- Simple to implement
- Easy to debug (visible in browser dev tools)
- No CSRF concerns

**Cons:**
- Vulnerable to XSS attacks
- Requires manual header management in every request
- Token persists until manually cleared

**Effort:** Low | **Risk:** Medium

---

### Approach C: Session-based Authentication

**Summary:** Server-side sessions with session ID cookies. No tokens stored client-side.

**Pros:**
- Simpler mental model
- Easy to revoke sessions instantly
- No token management client-side

**Cons:**
- Requires session storage (Redis, database)
- Not stateless (harder to scale horizontally)
- Doesn't work well for mobile/API-first architectures

**Effort:** Medium | **Risk:** Low

---

## Example: Database Migration

### Approach A: Prisma Migrate

**Summary:** Use Prisma's built-in migration system for schema changes.

**Pros:**
- Already using Prisma, no new tooling
- Type-safe migrations
- Automatic migration generation from schema changes

**Cons:**
- Less control over raw SQL
- Some complex migrations require manual SQL

**Effort:** Low | **Risk:** Low

> **Recommended** - Native to your stack, lowest friction.

---

### Approach B: Raw SQL Migrations

**Summary:** Write SQL migration files manually, run with a migration runner.

**Pros:**
- Full control over migration SQL
- Database-agnostic patterns
- Can handle complex data transformations

**Cons:**
- More manual work
- No type safety
- Must keep Prisma schema in sync manually

**Effort:** Medium | **Risk:** Medium

---

## Presenting to User

After presenting approaches, use AskUserQuestion:

```
Which approach should we proceed with?
[A: JWT Cookies (Recommended)] [B: JWT localStorage] [C: Sessions] [Revise approaches]
```

Never proceed without explicit user selection.
