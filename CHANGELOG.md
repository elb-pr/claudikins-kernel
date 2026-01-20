# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.3] - 2026-01-20

### Changed

- `batch-checkpoint-gate.sh`: improved checkpoint message formatting with proper newline handling via jq

---

## [1.1.2] - 2026-01-19

### Fixed

- babyclaude Stop prompt hook: use `{"ok": true/false}` response format instead of `{"decision": "allow/block"}` (Claude Code expects the former)

## [1.1.1] - 2026-01-19

### Fixed

- `sanitize-bash.sh`: use `"decision": "approve"` instead of invalid `"decision": "allow"`
- `verify-gate.sh`: output to stderr instead of invalid `hookSpecificOutput` JSON (Stop hooks don't support it)

## [1.1.0] - 2026-01-20

### Added

- `homepage`, `repository`, `license`, and `keywords` fields to plugin.json
- `permissionMode` to all 8 agents for proper permission handling
- `once: true` to session-startup hook (prevents duplicate execution)
- `pre-task-gate.sh` hook implementing constraint C-4 (review verdict gate)
- PreToolUse/Task matcher in hooks.json for pre-task validation
- Permission deny rules in settings.local.json for dangerous git operations
- "Next Stage" sections to all 4 commands for workflow continuity
- Frontmatter `hooks.Stop` to 5 agents (babyclaude, catastrophiser, cynic, git-perfectionist, taxonomy-extremist)
- LLM-based Stop hook (`type: "prompt"`) for babyclaude completion evaluation
- `sanitize-bash.sh` PreToolUse hook with `updatedInput` pattern for command sanitization
- `output-schema` to all 4 commands for structured JSON output
- `skill-rules.json` for skill auto-activation with intent/path pattern matching
- `skill-activation-hook.sh` UserPromptSubmit hook for auto-suggesting relevant skills
- Execution tracing with `trace-start.sh` and `trace-end.sh` (SubagentStart/SubagentStop)
- `.claude/traces/` directory for span-based execution timing
- `allowed-tools` to all 4 skills with appropriate tool restrictions

### Changed

- Commands restructured: `flags`, `merge_strategy`, `color` moved from frontmatter to body documentation
- Plugin version bumped from 1.0.0 to 1.1.0
- Author name updated to full name in plugin.json
- Agent-specific SubagentStop hooks moved from hooks.json to agent frontmatter

### Removed

- Invalid `context: fork` field from all agents (skill-only field)
- `color` field from command frontmatter (not a valid field)
- SubagentStop section from hooks.json (replaced by frontmatter hooks + global tracing)

### Fixed

- Agent frontmatter now uses only valid fields per Claude Code spec

## [1.0.0] - 2026-01-18

### Added

- Initial release
- 4 commands: outline, execute, verify, ship
- 8 agents: babyclaude, catastrophiser, cynic, spec-reviewer, code-reviewer, taxonomy-extremist, conflict-resolver, git-perfectionist
- 4 skills: brain-jam-plan, git-workflow, strict-enforcement, shipping-methodology
- Hook infrastructure with hooks.json and shell scripts
