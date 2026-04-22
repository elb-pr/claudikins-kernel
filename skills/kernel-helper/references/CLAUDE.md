# claudikins-kernel — Mobile Architecture

## The core insight

claude.ai spins up a persistent Linux sandbox per conversation. It is not per-message. Files written in turn 1 are readable in turn 20. Background daemons started in turn 1 keep running in turn 20. This is what makes a hooks runtime possible without Claude Code.

## Hook mechanism map

| Claude Code hook | Mobile equivalent | Status |
|---|---|---|
| `SessionStart` | `session-startup.sh` run by `setup.sh` | ✅ Full equivalent |
| `PostToolUse (Edit/Write)` | `inotifywait` daemon → `dispatch.sh` | ✅ Full equivalent |
| `PreToolUse (Bash)` | Skill constraint (explicit gate instruction) | ⚠️ Voluntary, not intercepted |
| `SubagentStart/Stop` | Not used — no subagents on mobile | ➖ Dropped |
| `PreCompact` | Session-end instruction in skill | ⚠️ Best-effort |
| `UserPromptSubmit` | Skill entry condition | ⚠️ Voluntary |

## inotifywait daemon

The daemon watches the project directory recursively for `close_write` events. Every time Claude writes a file, `dispatch.sh` is called with the file path.

```
inotifywait -m -r -e close_write $PROJECT_DIR \
  --format '%w%f' | while read FILE; do
  bash skills/kernel-helper/hooks/dispatch.sh "$FILE"
done &
```

`dispatch.sh` routes the event to the correct hook based on the file path:

| File pattern | Hook fired |
|---|---|
| Source files (`.ts`, `.js`, `.py` etc) | `autoformat.sh` |
| Any file | `execute-tracker.sh` |
| `.claude/plans/*` | `validate-plan-format.sh` |
| `.claude/agent-outputs/verification/*` | `verify-gate.sh` |
| `.claude/agent-outputs/tasks/*` | `batch-checkpoint-gate.sh` |
| `.claude/agent-outputs/*` | `trace-end.sh` |

## No subagents

On mobile, Claude Code's `Task()` spawning is unavailable. The agent files (`code-reviewer`, `cynic`, `catastrophiser` etc) have had their YAML frontmatter stripped and exist as pure reference documents. When a kernel-* skill requires agent behaviour, it instructs Claude to read the reference file and embody that persona directly.

## Pre-bash gates

`git-branch-guard.sh`, `sanitize-bash.sh`, and `merge-gate.sh` cannot be automatically intercepted in the mobile sandbox. They are enforced as explicit constraints in the skill primacy zone. Before running any bash command in a gated context, the skill instructs Claude to check the relevant gate conditions manually.

## State persistence across sessions

Hook scripts write to `.claude/` subdirectories in the sandbox. At natural session end points, kernel-* skills present key output files to the user as markdown or JSON. The user saves these and uploads them at the next session start. `setup.sh` detects uploaded files and restores state.

## Directory structure

```
.claude/
├── plans/                    # outline session plans
├── execute-state.json        # execute session state
├── ship-state.json           # ship session state
├── verify-state.json         # verify session state
├── agent-outputs/
│   ├── tasks/                # task completion output
│   ├── reviews/spec/         # spec-reviewer output
│   ├── reviews/code/         # code-reviewer output
│   └── verification/         # catastrophiser output
├── traces/                   # execution traces
├── evidence/                 # screenshots, curl responses
├── errors/                   # error logs
└── tmp/                      # scratch space
```
