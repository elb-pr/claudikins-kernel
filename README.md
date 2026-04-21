# claudikins-kernel — Mobile Release

**Branch:** `release/mobile`  
**Status:** Structure scaffolded — skills in progress

This is an orphan branch with zero shared history with `main`. It ports claudikins-kernel to claude.ai mobile by replacing Claude Code's runtime (hooks.json, slash commands, agent spawning) with a skills-based event-driven architecture.

## Structure

```
skills/
  kernel-helper/     — Session bootstrap, hook runtime, shared hooks
  kernel-outline/    — Plan creation command
  kernel-execute/    — Task execution command with batch gates
  kernel-verify/     — Verification command
  kernel-ship/       — Merge and ship command
assets/
  banner-mobile.png  — (pending)
```

## Hook Mechanism

| Mechanism | Status |
|-----------|--------|
| `inotifywait` daemon | ✅ Validated |
| `BASH_ENV` | ✅ Validated via daemon pattern |
| `session-startup.sh` | ✅ Runs correctly |
| SubagentStart/Stop | ❌ Skill instruction workaround |
| UserPromptSubmit | ❌ Absorbed into skill constraints |
| PreCompact | ❌ Session-end instruction |

## Status

- [x] Orphan branch created
- [x] Directory structure scaffolded
- [ ] `kernel-helper` SKILL.md
- [ ] `kernel-outline` SKILL.md
- [ ] `kernel-execute` SKILL.md
- [ ] `kernel-verify` SKILL.md
- [ ] `kernel-ship` SKILL.md
- [ ] Hook scripts migrated
- [ ] Agents converted to reference files
- [ ] Skills converted to reference files
- [ ] `assets/banner-mobile.png`
