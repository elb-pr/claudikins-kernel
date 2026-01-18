# Plan Output Format

Plans must follow this structure to be compatible with `claudikins-kernel:execute`.

## Required Sections

Every plan must include these sections in order:

### 1. Problem Statement

What problem are we solving? Be specific.

```markdown
## Problem Statement

Users cannot reset their passwords. When they click "Forgot Password",
nothing happens because the email service isn't configured.
```

### 2. Scope & Boundaries

What's IN scope and what's OUT.

```markdown
## Scope

### In Scope

- Password reset email functionality
- Reset token generation and validation
- Password update endpoint

### Out of Scope

- Password strength requirements (separate task)
- Rate limiting (future enhancement)
- SMS-based reset (not requested)
```

### 3. Success Criteria

Measurable conditions that define "done".

```markdown
## Success Criteria

- [ ] User can request password reset email
- [ ] Email arrives within 30 seconds
- [ ] Reset link expires after 1 hour
- [ ] User can set new password via link
- [ ] Old password no longer works after reset
```

### 4. Tasks

The work broken down into executable units.

**CRITICAL: Use the EXECUTION_TASKS markers exactly as shown.**

```markdown
## Tasks

<!-- EXECUTION_TASKS_START -->

| #   | Task                               | Files                        | Deps | Batch |
| --- | ---------------------------------- | ---------------------------- | ---- | ----- |
| 1   | Add password reset token to schema | prisma/schema.prisma         | -    | 1     |
| 2   | Create reset token service         | src/services/resetToken.ts   | 1    | 1     |
| 3   | Add forgot-password endpoint       | src/routes/auth.ts           | 2    | 2     |
| 4   | Create reset-password endpoint     | src/routes/auth.ts           | 2    | 2     |
| 5   | Add email template                 | src/emails/passwordReset.tsx | -    | 1     |
| 6   | Wire up email sending              | src/services/email.ts        | 5    | 2     |
| 7   | Add tests                          | src/tests/auth.test.ts       | 3,4  | 3     |

<!-- EXECUTION_TASKS_END -->
```

**Column definitions:**

| Column | Description                                               |
| ------ | --------------------------------------------------------- |
| #      | Task number (sequential)                                  |
| Task   | Single-sentence description                               |
| Files  | Primary file(s) affected                                  |
| Deps   | Task numbers this depends on, or `-` for none             |
| Batch  | Execution batch (tasks in same batch can run in parallel) |

### 5. Dependencies

External dependencies and integration points.

```markdown
## Dependencies

### External

- Resend API for email sending (already configured)
- Prisma for database access

### Internal

- Existing User model
- Existing email service wrapper

### New

- None required
```

### 6. Risks & Mitigations

What could go wrong and how to handle it.

```markdown
## Risks & Mitigations

| Risk                  | Likelihood | Impact | Mitigation                            |
| --------------------- | ---------- | ------ | ------------------------------------- |
| Email delivery delays | Medium     | Medium | Add retry logic, notify user of delay |
| Token collision       | Low        | High   | Use UUID v4, check uniqueness         |
| Brute force attacks   | Medium     | High   | Rate limit endpoint (future task)     |
```

### 7. Verification Checklist

How to verify the implementation works.

```markdown
## Verification

### Automated

- [ ] Unit tests for token service pass
- [ ] Integration tests for endpoints pass
- [ ] Email template renders correctly

### Manual

- [ ] Request reset for existing user - email received
- [ ] Request reset for non-existent user - no email, no error shown
- [ ] Use valid token - password updated
- [ ] Use expired token - appropriate error shown
- [ ] Use invalid token - appropriate error shown
```

## File Naming

Save plans to: `.claude/plans/plan-{session-id}.md`

Example: `.claude/plans/plan-2026-01-16-1430.md`

## Machine-Readable Markers

The `<!-- EXECUTION_TASKS_START -->` and `<!-- EXECUTION_TASKS_END -->` markers are **required**. The `claudikins-kernel:execute` command parses these to extract the task table.

If markers are missing or malformed, `claudikins-kernel:execute` will fail with an error.
