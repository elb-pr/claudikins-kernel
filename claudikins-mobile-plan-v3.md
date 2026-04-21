# claudikins-kernel — Mobile Release Plan

**Branch:** `release/mobile` (orphan from main)  
**Status:** Draft v3 — Ethan reviewed, pending hook experimentation

---

## Problem Statement

claudikins-kernel currently depends on Claude Code's runtime (hooks.json, slash commands, agent spawning) which is unavailable on claude.ai mobile. We need a port that replicates the same event-driven, hook-gated behaviour inside of Claude's sandbox environment.

---

## Scope

### In Scope

- Orphan branch `release/mobile` — zero impact on main
- Skills structure: `kernel-helper`, `kernel-outline`, `kernel-execute`, `kernel-verify`, `kernel-ship`
- Hooks runtime built from `inotifywait` + `BASH_ENV` as a drop-in for Claude Code's event dispatcher
- Conversion of existing commands → `SKILL.md` files
- Conversion of existing skills + agents → reference files (no standalone activation)
- Template extraction from skill body content
- `assets/banner-mobile.png`

### Out of Scope

- Changes to `main` branch
- `hooks/hooks.json` (meaningless without Claude Code runtime)
- Agent YAML frontmatter and agent spawning
- `release/desktop` branch (decision deferred — see open items)
- Claude Code itself as a dependency

---

## Success Criteria

- [ ] `release/mobile` exists as an orphan branch with no shared history with main
- [ ] `kernel-helper` bootstraps the hook runtime cleanly in a fresh mobile session
- [ ] `inotifywait` daemon reliably detects file writes in the correct watched path
- [ ] `BASH_ENV` hook fires on every bash_tool invocation (cross-invocation persistence confirmed or workaround documented)
- [ ] Gate hooks return exit codes that visibly block Claude from proceeding when triggered from skill constraints
- [ ] All four kernel commands (`outline`, `execute`, `verify`, `ship`) are reachable as slash commands on mobile
- [ ] All existing agents and skills are converted to reference files with YAML frontmatter stripped
- [ ] `assets/banner-mobile.png` exists in the branch

---

## Tasks

<!-- EXECUTION_TASKS_START -->

| #  | Task                                                                 | Files                                                                 | Deps    | Batch |
|----|----------------------------------------------------------------------|-----------------------------------------------------------------------|---------|-------|
| 1  | Create orphan branch `release/mobile` from scratch                  | `.`                                                                   | -       | 1     |
| 2  | Experiment: test BASH_ENV persistence across separate bash_tool calls | `kernel-helper/hooks/pre-bash-hook.sh`                               | 1       | 2     |
| 3  | Experiment: confirm inotifywait watched path scope and reliability   | `kernel-helper/hooks/post-write-hook.sh`                              | 1       | 2     |
| 4  | Experiment: verify gate hook exit codes block Claude from skill constraints | `kernel-execute/hooks/pre-task-gate.sh`                        | 1       | 2     |
| 5  | Create `kernel-helper` skill: SKILL.md, setup.sh, setup.md, troubleshooting.md, CLAUDE.md | `skills/kernel-helper/`                          | 2,3,4   | 3     |
| 6  | Implement all shared hooks in `kernel-helper/hooks/`                 | `skills/kernel-helper/hooks/` (11 scripts)                            | 5       | 3     |
| 7  | Create `kernel-outline` skill + convert outline references           | `skills/kernel-outline/`                                              | 5       | 3     |
| 8  | Create `kernel-execute` skill + hooks + convert references           | `skills/kernel-execute/`                                              | 5       | 3     |
| 9  | Create `kernel-verify` skill + hooks + templates + convert references | `skills/kernel-verify/`                                              | 5       | 3     |
| 10 | Create `kernel-ship` skill + hooks + convert references              | `skills/kernel-ship/`                                                 | 5       | 3     |
| 11 | Convert agents to reference files (strip YAML frontmatter)           | `skills/*/references/` (8 agent files)                                | 7,8,9,10 | 4    |
| 12 | Convert remaining skills to reference files                          | `skills/*/references/` (shipping-methodology, git-workflow, etc.)     | 7,8,9,10 | 4    |
| 13 | Produce `assets/banner-mobile.png`                                   | `assets/banner-mobile.png`                                            | 1       | 2     |
| 14 | Decide and document desktop strategy (separate branch vs shared)     | `README.md` or equivalent                                             | -       | 1     |

<!-- EXECUTION_TASKS_END -->

---

## Dependencies

### External

- `inotifywait` (inotify-tools) — must be available in the mobile bash environment
- `BASH_ENV` — standard bash feature, availability in bash_tool confirmed in sandbox

### Internal

- Existing `main` branch skills and commands as source material for conversion
- Sandbox validation results from hook mechanism experiments (tasks 2–4)

### New

- None — no new libraries or services required

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `BASH_ENV` does not persist across separate bash_tool invocations | High | High | If confirmed, absorb pre-bash behaviour into skill constraints as explicit instructions |
| `inotifywait` cannot watch `/mnt/user-data/outputs/` reliably | Medium | High | Test alternative watched paths; fall back to polling if necessary |
| Gate hook exit codes do not block Claude when called from skill constraints | Medium | High | If unblockable, convert gates to explicit pre-condition checklists in skill instructions |
| SubagentStart/Stop not interceptable | Confirmed | Medium | Absorbed — handled via skill instruction workarounds |
| UserPromptSubmit not interceptable | Confirmed | Low | Absorbed into skill constraints as entry conditions |
| PreCompact not interceptable | Confirmed | Low | Moved to session-end instruction in kernel-helper |
| Scope creep into `release/desktop` | Low | Medium | Decision explicitly deferred; desktop work blocked until mobile is stable |

---

## Hook Mechanism Status

| Mechanism | Status | Covers |
|-----------|--------|--------|
| `inotifywait` daemon | ✅ Validated in sandbox | PostToolUse — file writes |
| `BASH_ENV` | ⚠️ Needs cross-shell persistence test | PreToolUse — bash invocations |
| `session-startup.sh` | ✅ Runs correctly in sandbox | SessionStart |
| SubagentStart/Stop | ❌ Not interceptable | Skill instruction workaround |
| UserPromptSubmit | ❌ Not interceptable | Absorbed into skill constraints |
| PreCompact | ❌ Not interceptable | Moved to session-end instruction |

---

## Hook Placement Reference

| Hook | Owner |
|------|-------|
| `dispatch.sh` | kernel-helper |
| `pre-bash-hook.sh` | kernel-helper |
| `post-write-hook.sh` | kernel-helper |
| `session-startup.sh` | kernel-helper |
| `trace-start.sh` | kernel-helper |
| `trace-end.sh` | kernel-helper |
| `execute-tracker.sh` | kernel-helper |
| `git-branch-guard.sh` | kernel-helper |
| `sanitize-bash.sh` | kernel-helper |
| `preserve-state.sh` | kernel-helper |
| `task-completion-capture.sh` | kernel-helper |
| `batch-checkpoint-gate.sh` | kernel-execute |
| `validate-plan-format.sh` | kernel-execute |
| `pre-task-gate.sh` | kernel-execute |
| `verify-init.sh` | kernel-verify |
| `verify-gate.sh` | kernel-verify |
| `autoformat.sh` | kernel-verify |
| `ship-init.sh` | kernel-ship |
| `ship-complete.sh` | kernel-ship |
| `merge-gate.sh` | kernel-ship |
| `validate-plan-completion.sh` | kernel-ship |

---

## Conversion Rules (Reference)

**Commands → Skills**: Each command becomes a `SKILL.md` inside a `kernel-*` named folder. Slash command on mobile invokes the skill. File must be named `SKILL.md`.

**Existing skills → Reference files**: Strip frontmatter. Content stays verbatim. No standalone activation — pointed at by the kernel-* command skills.

**Templates**: Any inline templates found inside skill body content get extracted to a `/templates` subfolder within that skill.

**Agents → Reference files**: Strip all YAML frontmatter (name, description, model, permissionMode, color, tools, disallowedTools, hooks). Rich behavioural content stays intact. Command skills instruct Claude to embody them rather than spawn them.

---

## Verification

### Per Experiment (Tasks 2–4 — gate before proceeding to Task 5)

- [ ] BASH_ENV: does the hook fire on a fresh bash_tool invocation in the same session?
- [ ] BASH_ENV: does it fire across *separate* bash_tool calls (not just within one shell)?
- [ ] inotifywait: does the daemon detect writes to the correct path without false positives?
- [ ] inotifywait: does it survive across multiple Claude tool calls within a session?
- [ ] Gate hooks: does a non-zero exit code halt execution when called from within a skill constraint?

### Per Skill (Tasks 7–10)

- [ ] Skill is reachable as a slash command on mobile
- [ ] All reference files are present and linked correctly from SKILL.md
- [ ] Skill-specific hooks are co-located in `[skill]/hooks/` and not duplicated in kernel-helper

### End-to-End

- [ ] Fresh mobile session: kernel-helper boots, hook runtime starts, no errors
- [ ] `kernel-execute` task runs through a batch with gate hooks active
- [ ] `kernel-verify` catches a known format violation and blocks ship
- [ ] `kernel-ship` completes a merge with all gates passing

---

## Open Items

- [ ] Complete BASH_ENV persistence experiment (blocks Task 5+)
- [ ] Confirm inotifywait watched path scope (blocks Task 5+)
- [ ] Verify gate hook exit code blocking behaviour (blocks Task 5+)
- [ ] Ethan: produce `assets/banner-mobile.png` (Task 13)
- [ ] Decide: separate `release/desktop` branch or desktop = mobile branch? (Task 14)
