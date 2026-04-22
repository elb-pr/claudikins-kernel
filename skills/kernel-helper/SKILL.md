---
name: kernel-helper
description: Bootstrap and recovery skill for claudikins-kernel on mobile. Sets up the hooks runtime, installs dependencies, and explains the system to Claude on first use or after context loss.
---

# kernel-helper

You are the orchestration layer for claudikins-kernel on mobile. Your first job in any session is to get the hooks runtime running. Your second job is to know when it has broken and fix it.

## When to activate

- Start of every new session before any kernel-* skill is used
- When a hook is not firing as expected
- When Claude has lost context about how the system works
- When the inotifywait daemon has died

## How this system works

claudikins-kernel on mobile replicates Claude Code's hook system using two mechanisms running in the sandbox:

1. **inotifywait daemon** — watches the project filesystem for file writes and fires the appropriate hook script automatically. This is the PostToolUse equivalent.
2. **session-startup.sh** — runs once at session start to initialise the `.claude/` directory structure and report existing session state.

Pre-bash gates (git-branch-guard, sanitize-bash, merge-gate) are enforced as skill constraints rather than as intercepted shell events. SubagentStart/Stop hooks are not used — on mobile Claude embodies agent reference files directly rather than spawning subagents.

Read `references/CLAUDE.md` for the full system architecture.

## Bootstrap procedure

Run this at the start of every session:

```bash
bash skills/kernel-helper/scripts/setup.sh
```

This script:
1. Installs `jq` and `inotify-tools` if not present
2. Sets `CLAUDE_PROJECT_DIR` and `CLAUDE_PLUGIN_ROOT`
3. Runs `session-startup.sh` to initialise `.claude/` structure
4. Starts the inotifywait daemon
5. Prints a status summary confirming the runtime is live

## Verifying the runtime

```bash
# Check daemon is alive
ps aux | grep inotifywait | grep -v grep

# Check what the daemon is watching
cat /home/claude/daemon.pid

# Check hook log for recent activity
tail -20 /home/claude/hook-log.txt
```

If the daemon is dead, re-run `setup.sh`. It is idempotent.

## References

- `references/CLAUDE.md` — full system architecture and hook map
- `references/setup.md` — setup procedure in detail
- `references/troubleshooting.md` — common failures and fixes

## Hooks owned by kernel-helper

Shared hooks used across multiple skills live in `skills/kernel-helper/hooks/`. Each skill that owns its own hooks keeps them in its own `hooks/` subfolder.

| Hook | Trigger | Owned by |
|---|---|---|
| `session-startup.sh` | Session start | kernel-helper |
| `trace-start.sh` | Agent output dir created | kernel-helper |
| `trace-end.sh` | Agent output written | kernel-helper |
| `execute-tracker.sh` | Any file write | kernel-helper |
| `git-branch-guard.sh` | Skill constraint | kernel-helper |
| `sanitize-bash.sh` | Skill constraint | kernel-helper |
| `preserve-state.sh` | Session end instruction | kernel-helper |
| `task-completion-capture.sh` | Agent output written | kernel-helper |
| `dispatch.sh` | inotifywait callback | kernel-helper |
| `post-write-hook.sh` | inotifywait callback | kernel-helper |
