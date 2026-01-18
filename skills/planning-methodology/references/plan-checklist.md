# Plan Verification Checklist

Use this checklist before finalising any plan. All items in the "Required" sections must be checked.

## Requirements (Required)

- [ ] Problem statement is clear and specific
- [ ] Success criteria are measurable and testable
- [ ] Scope boundaries explicitly defined (what's IN)
- [ ] Out-of-scope items explicitly listed (what's OUT)
- [ ] User has approved requirements at checkpoint

## Architecture (Required)

- [ ] Approach selection documented with rationale
- [ ] Alternative approaches noted with rejection reasons
- [ ] Dependencies on existing code identified
- [ ] External dependencies listed (libraries, APIs, services)
- [ ] Integration points with existing systems mapped
- [ ] Breaking changes flagged and migration path noted

## Tasks (Required)

- [ ] All tasks have clear, single-sentence deliverables
- [ ] Each task maps to specific files or components
- [ ] Dependencies between tasks are correct
- [ ] No circular dependencies exist
- [ ] Batch assignments group related work logically
- [ ] Tasks are ordered by dependency (deps complete before dependents)

## Risks (Required)

- [ ] Technical risks identified
- [ ] Mitigations proposed for each risk
- [ ] Fallback options available if primary approach fails
- [ ] "What could go wrong" scenarios documented

## Verification (Required)

- [ ] Test strategy included (unit, integration, e2e as appropriate)
- [ ] Acceptance criteria defined for each major deliverable
- [ ] Manual verification steps listed where automated tests insufficient
- [ ] Performance requirements specified if relevant

## Quality (Recommended)

- [ ] Plan is readable by someone unfamiliar with the codebase
- [ ] Technical jargon explained or avoided
- [ ] Assumptions explicitly stated
- [ ] Open questions flagged for resolution

## Execution Readiness (Final Gate)

- [ ] EXECUTION_TASKS markers present and correctly formatted
- [ ] Task table includes all required columns (Task, Files, Deps, Batch)
- [ ] Plan saved to `.claude/plans/` directory
- [ ] User has given explicit approval to proceed

## Red Flags

If any of these are true, DO NOT finalise:

- Requirements still have unresolved questions
- Success criteria are vague ("make it better", "improve performance")
- Task count exceeds 20 without batching strategy
- Dependencies form a cycle
- No verification strategy defined
- User hasn't approved at every phase checkpoint
