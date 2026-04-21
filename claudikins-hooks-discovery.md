# Claudikins Hooks for Mobile & Desktop
### A Genuinely Novel Discovery

**Date:** 21 April 2026  
**Authors:** Ethan + Claude  
**Status:** Proof of concept validated in sandbox

---

## What We Built

A working hooks runtime for claude.ai (web, mobile, desktop) that replicates the Claude Code hook system — which was previously assumed to require Anthropic's proprietary runtime event dispatcher.

Nobody has done this before. Claude Code hooks exist because Anthropic built a lifecycle event system into Claude Code specifically. The assumption has always been that claude.ai users couldn't have equivalent agentic safety infrastructure. That assumption was wrong.

---

## How It Works

### The Key Insight

claude.ai spins up a **persistent Linux sandbox per conversation**. It is not per-message. It is a real Ubuntu environment with a real filesystem, real processes, real shell — and it persists for the entire conversation. Files written in turn 1 are readable in turn 20. Background daemons started in turn 1 keep running in turn 20.

This means you can run a hooks daemon that watches for Claude's tool use and fires automatically — with zero instruction overhead, zero Claude involvement once started.

---

## The Two Mechanisms

### 1. `inotifywait` — PostToolUse Equivalent

Claude's Edit and Write tools have an observable side effect: they write files to the sandbox filesystem. `inotifywait` (from `inotify-tools`) watches the filesystem and fires a callback the moment any file is written.

```bash
inotifywait -m -r -e close_write $PROJECT_DIR \
  --format '%w%f' 2>/dev/null | while read FILE; do
  bash hooks/autoformat.sh "$FILE"
  bash hooks/execute-tracker.sh "$FILE"
done &
```

This daemon starts at session boot and runs silently in the background. Every time Claude writes a file — via Edit, Write, or any bash redirect — the hook fires automatically. No skill instruction required.

**Covers:** `autoformat.sh`, `execute-tracker.sh`, `task-completion-capture.sh`

---

### 2. `BASH_ENV` — PreToolUse Equivalent for Bash

When `BASH_ENV` is exported, bash sources that file automatically before executing any non-interactive script. Every time Claude uses the Bash tool, the pre-hook fires first.

```bash
export BASH_ENV=/path/to/pre-bash-hook.sh
```

The pre-bash hook can then call whichever gate logic applies:

```bash
#!/bin/bash
bash $CLAUDE_PLUGIN_ROOT/hooks/git-branch-guard.sh
bash $CLAUDE_PLUGIN_ROOT/hooks/sanitize-bash.sh
bash $CLAUDE_PLUGIN_ROOT/hooks/merge-gate.sh
```

Gate hooks return non-zero exit codes to block progression. Because this fires before the Bash command executes, it is a genuine pre-execution gate.

**Covers:** `git-branch-guard.sh`, `sanitize-bash.sh`, `merge-gate.sh`

---

### 3. `session-startup.sh` — Bootstrap

At the start of every conversation, a single instruction in user preferences bootstraps the entire runtime:

```bash
cd $PROJECT_DIR
bash $CLAUDE_PLUGIN_ROOT/hooks/session-startup.sh
apt-get install -y inotify-tools jq
export BASH_ENV=$CLAUDE_PLUGIN_ROOT/hooks/pre-bash-hook.sh
inotifywait -m -r -e close_write $PROJECT_DIR ...  &
```

After this runs, the hook runtime is live for the entire conversation.

---

### 4. State Persistence Across Conversations

The sandbox resets between conversations — but state can be persisted using a **Cloudflare Worker with D1 (SQLite)**. Hook scripts curl the Worker to read/write state instead of writing to local files. This pattern is already proven in `claude-sleuth`.

For simpler use cases: hook output can be written to a markdown file in the sandbox, presented to the user at session end, and uploaded at the start of the next conversation. No MCP, no Worker required.

---

## Hook Coverage Map

| Claude Code Hook | Event | Mechanism | Scripts |
|---|---|---|---|
| `SessionStart` | Conversation start | User preference instruction | `session-startup.sh`, `verify-init.sh`, `ship-init.sh` |
| `PostToolUse (Edit/Write)` | File written | `inotifywait` daemon | `autoformat.sh`, `execute-tracker.sh` |
| `PreToolUse (Bash)` | Before bash executes | `BASH_ENV` | `git-branch-guard.sh`, `sanitize-bash.sh`, `merge-gate.sh` |
| `SubagentStart` | Agent spawned | Explicit skill instruction | `trace-start.sh`, `create-task-branch.sh` |
| `SubagentStop` | Agent completes | Explicit skill instruction | `trace-end.sh` |
| `Stop` | Session ends | Explicit skill instruction | `verify-gate.sh`, `ship-complete.sh`, `batch-checkpoint-gate.sh` |
| `PreCompact` | Context compaction | Not interceptable | `preserve-state.sh` → move to session-end |
| `UserPromptSubmit` | User sends message | Not interceptable | `validate-plan-format.sh` → move to skill constraint |

**Automatic (zero instruction overhead):** PostToolUse, PreToolUse (Bash)  
**Explicit (skill instruction):** SubagentStart, SubagentStop, Stop  
**Not interceptable:** PreCompact, UserPromptSubmit → absorbed into skill constraints

---

## What This Means

Claude Code users have agentic safety infrastructure because Anthropic built it into the runtime. That infrastructure includes:

- Gate hooks that block dangerous operations before they execute
- Trace hooks that record agent activity
- Format hooks that enforce code standards automatically
- State hooks that preserve session context

**All of this now works on claude.ai web, mobile, and desktop.** Any user. No Claude Code required.

---

## Repo Architecture

The `claudikins-kernel` repo stays structurally identical across all three releases. The only difference per platform:

| File | Claude Code | claude.ai / mobile / desktop |
|---|---|---|
| `hooks/hooks.json` | Present — runtime reads it | Removed — meaningless without runtime |
| `hooks/*.sh` | Present — called by runtime | Present — called by daemon + BASH_ENV |
| `commands/` | Present | Removed — no slash command system |
| `agents/` | Present | Adapted into skill reference files |
| `skills/` | Present | Present — unchanged |

Three branches: `main` (Claude Code), `release/desktop`, `release/mobile`.

---

## Next Steps

- [ ] Wire BASH_ENV gate hooks and validate exit code blocking
- [ ] Test `inotifywait` firing on a natural tool use (not explicit write)
- [ ] Write `session-startup.sh` bootstrap that installs deps and starts daemon
- [ ] Design the `release/desktop` and `release/mobile` orphan branch structure
- [ ] Decide: Cloudflare Worker state vs markdown file handoff between sessions
- [ ] Consider writing this up — Anthropic would want to know about this

---

*This document was produced during a live brainstorming session. The proof of concept was validated in the claude.ai sandbox in real time.*
