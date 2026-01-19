<p align="center">
  <img src="assets/banner.png" alt="Claudikins Kernel - Outline, Execute, Verify, Ship">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/anthropics/claude-code"><img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet.svg" alt="Claude Code Plugin"></a>
  <img src="https://img.shields.io/badge/workflow-SRE_enforced-green.svg" alt="Workflow: SRE Enforced">
</p>

<h1 align="center">Claudikins Kernel</h1>

<p align="center"><strong>Industrial-grade guardrails for Claude Code.</strong></p>

<p align="center"><em>A disciplined workflow engine run by a team of neurotic AI agents.<br>We call it Claudikins because "Draconian-AI-Supervisor" was taken.</em></p>

---

## Why?

**You asked for a bug fix. It refactored half your codebase.**

Sound familiar?

claudikins-kernel applies SRE discipline to AI workflows. It enforces a strict 4-stage pipeline with **gates between each step**. You literally cannot skip verification. You cannot ship without the Cynic's approval.

> **Constraint is freedom.** By preventing shortcuts, you get code that actually works.

---

## The Workflow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ /outline │────▶│ /execute │────▶│ /verify  │────▶│  /ship   │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
      │                │                │                │
      ▼                ▼                ▼                ▼
  taxonomy-        babyclaude      catastrophiser   git-perfectionist
  extremist        spec-reviewer       cynic
                   code-reviewer
```

**Each arrow is a gate.** Try to `/ship` without `/verify` passing? Blocked. Try to `/execute` without a plan? Blocked. The system enforces this - not guidelines, guardrails.

---

## Quick Start

```bash
# Prerequisites: jq (JSON processor)
# Ubuntu/Debian: sudo apt install jq
# macOS: brew install jq

# Add the Claudikins marketplace
/marketplace add elb-pr/claudikins-marketplace

# Install the plugin
/plugin install claudikins-kernel
```

Restart Claude Code. Then:

```bash
# Start your first disciplined session
/outline "Add user authentication to the app"
```

---

## Meet the Team

These aren't generic "agents". They're your synthetic staff - each with a job and a personality.

| Agent                  | Role           | Personality                                                                                                                                         |
| ---------------------- | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **taxonomy-extremist** | Researcher     | The librarian. Categorises everything. Reads your codebase, external docs, the web - returns structured findings.                                   |
| **babyclaude**         | Implementer    | The eager junior. Does exactly what you specify. One task, one branch, fresh context. No scope creep.                                               |
| **spec-reviewer**      | Compliance     | The auditor. Did you do what you said you'd do? Mechanical check against acceptance criteria.                                                       |
| **code-reviewer**      | Quality        | The critic. Is it actually any good? Error handling? Edge cases? Naming?                                                                            |
| **catastrophiser**     | Verification   | The QA lead who assumes everything will break. Runs your code, takes screenshots, curls your endpoints. Sees it working, doesn't trust tests alone. |
| **cynic**              | Simplification | The senior engineer who hates complexity. If it can be done in 5 lines, won't let you use 10.                                                       |
| **conflict-resolver**  | Merge Handler  | The diplomat. When branches collide, proposes resolutions.                                                                                          |
| **git-perfectionist**  | Documentation  | The pedant. README not updated? Changelog wrong? Blocked until it's right.                                                                          |

---

## The Four Commands

### `/outline` - "Let's figure out what we're building"

Iterative brainstorming until you have a solid plan.

1. **Brain-jam** - Back and forth with Claude. Pick from options, don't type essays.
2. **Research** - taxonomy-extremist agents dig through your codebase in parallel.
3. **Approaches** - 2-3 ways to solve it. Pros, cons, recommendation. You pick.
4. **Draft** - Plan written section by section. You approve each one.

**Output:** `plan.md` with a task table that `/execute` can parse.

---

### `/execute` - "Let's build it"

Execute the plan task by task with fresh agents and code review.

1. **Batch checkpoint** - "Batch 1/3: [task-1, task-2]. Ready?" You decide.
2. **Per task** - Creates branch, spawns fresh babyclaude, implements, commits.
3. **Two-stage review** - spec-reviewer checks compliance, code-reviewer checks quality.
4. **Merge decision** - You choose: merge all, merge some, or keep branches.

**Key feature:** Each babyclaude gets fresh context. No pollution between tasks.

---

### `/verify` - "Does it actually work?"

Claude must **see** the code working. Not trust. Verify.

1. **Automated checks** - Tests, lint, type check.
2. **Output verification** - catastrophiser runs your code:
   - Web app? Starts server, takes screenshots.
   - API? Curls endpoints, checks responses.
   - CLI? Runs commands, verifies output.
3. **Polish pass** - cynic looks for unnecessary complexity. Changes one thing at a time, tests after each.
4. **Human checkpoint** - Comprehensive report. You decide: ready to ship?

**Output:** `verify-state.json` with `unlock_ship: true` if approved. Plus file hashes so `/ship` can detect tampering.

---

### `/ship` - "Send it"

Merge to main with proper docs and PR.

1. **Gate check** - Won't run unless verify passed AND code hasn't changed.
2. **Commit strategy** - Squash or preserve? Message drafted, you approve.
3. **Documentation** - git-perfectionist updates README, CHANGELOG, version. Section by section.
4. **PR creation** - Draft, approve, create via `gh` CLI.
5. **Merge** - Wait for CI if you want. Merge. Cleanup branches.

**Output:** Code on main. PR merged. Done properly.

---

## The Safety Net

| Protection              | What it does                                                    |
| ----------------------- | --------------------------------------------------------------- |
| **Cross-command gates** | Can't skip steps. Execute needs plan. Ship needs verify.        |
| **State files**         | Each command writes to `.claude/`. Resume if context dies.      |
| **File locking**        | flock prevents race conditions on state writes.                 |
| **Code integrity**      | SHA256 hashes ensure shipped code = verified code.              |
| **Session management**  | Stale session (4+ hours)? Warns you research might be outdated. |
| **Human checkpoints**   | Nothing auto-proceeds. You approve every phase.                 |

---

## Architecture

Industrial-grade patterns adapted for AI workflows.

| Distributed Systems Pattern | Claude Code Adaptation |
| --------------------------- | ---------------------- |
| Circuit breakers            | Stuck agent detection  |
| Distributed tracing         | Execution spans        |
| Load shedding               | Batch size limits      |
| Coordinated checkpoints     | Batch-boundary saves   |
| Deadline propagation        | Task time budgets      |
| Exponential backoff         | Retry with jitter      |

Same principles, different scale. Reliability through structure - not speed through parallelism.

---

## Requirements

### System

- **jq** - Used by hook scripts for JSON processing

```bash
# Ubuntu/Debian
sudo apt install jq

# macOS
brew install jq

# Windows (scoop)
scoop install jq
```

### Recommended Plugins

| Plugin                                 | Purpose                                  |
| -------------------------------------- | ---------------------------------------- |
| `claudikins-tool-executor`             | MCP access for research and verification |
| `claudikins-automatic-context-manager` | Context monitoring at 60%                |

### Optional Plugins

| Plugin             | Purpose                     |
| ------------------ | --------------------------- |
| `claudikins-klaus` | Escalation when truly stuck |

---

## Status

**v1.1.2** - Fully functional. Four commands, eight agents, 27 hooks.

[View the marketplace](https://github.com/elb-pr/claudikins-marketplace) | [Changelog](CHANGELOG.md)

---

## License

MIT

---

<p align="center"><em>We call it Claudikins because "Draconian-AI-Supervisor" was taken.</em></p>
