#!/usr/bin/env bash
# Portability regression tests for the hooks in hooks/.
#
# These hooks run under /bin/bash with whatever `grep`/`sed`/`awk` the host
# provides. GNU-only extensions (notably `grep -P`) are therefore forbidden:
# BSD grep, the macOS default, rejects them and the hook fails.
#
# Run locally:  bash tests/test-hook-portability.sh
# CI runs this on both ubuntu-latest (GNU) and macos-latest (BSD).

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOKS="$REPO_ROOT/hooks"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

echo "grep:  $(grep --version 2>/dev/null | head -1 || echo 'BSD grep')"
echo "sed:   $(sed --version 2>/dev/null | head -1 || echo 'BSD sed')"
echo "awk:   $(awk --version 2>/dev/null | head -1 || echo 'BSD awk')"
echo

ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n          %s\n' "$1" "$2"; }

# ---------------------------------------------------------------------------
# 1. Static scan: no GNU-only grep flags in any hook (ignoring comments).
# ---------------------------------------------------------------------------
echo "=== no GNU-only grep flags ==="
OFFENDERS=$(grep -rn -e 'grep -oP' -e 'grep -Pzo' -e 'grep -P ' "$HOOKS/" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')
if [ -z "$OFFENDERS" ]; then
    ok "no 'grep -P' usages in hooks/"
else
    bad "GNU-only 'grep -P' found" "$OFFENDERS"
fi

# ---------------------------------------------------------------------------
# 2. Every hook parses under bash -n.
# ---------------------------------------------------------------------------
echo
echo "=== syntax ==="
for f in "$HOOKS"/*.sh; do
    if bash -n "$f" 2>/dev/null; then
        ok "bash -n $(basename "$f")"
    else
        bad "bash -n $(basename "$f")" "syntax error"
    fi
done

# ---------------------------------------------------------------------------
# 3. merge-gate.sh behaviour — the gate must allow ordinary merges and block
#    unreviewed task-branch merges. A parsing failure that blocks everything
#    (the -P bug) is caught by the "allowed" cases below.
# ---------------------------------------------------------------------------
echo
echo "=== merge-gate.sh ==="
export CLAUDE_PROJECT_DIR="$TMP/proj"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude/reviews"

expect_gate() { # <desc> <command> <want_rc> [want_substring]
    local out rc
    out=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$2" | jq -Rs .)" \
        | bash "$HOOKS/merge-gate.sh" 2>&1)
    rc=$?
    if printf '%s' "$out" | grep -q 'invalid option'; then
        bad "$1" "portability error leaked: $out"
        return
    fi
    if [ "$rc" != "$3" ]; then
        bad "$1" "exit $rc (want $3): $out"
        return
    fi
    if [ -n "${4:-}" ] && ! printf '%s' "$out" | grep -qF "$4"; then
        bad "$1" "missing '$4' in: $out"
        return
    fi
    ok "$1"
}

AMP='&&'
expect_gate "non-merge command allowed"       "echo hello"                             0
expect_gate "plain branch merge allowed"      "git merge main"                         0
expect_gate "merge --abort allowed"           "git merge --abort"                      0
expect_gate "chained non-task merge allowed"  "cd x $AMP git merge origin/feature-1"   0
expect_gate "unreviewed task merge blocked"   "git merge execute/task-3-slug-abcd"     2 "task 3"
expect_gate "chained task merge blocked"      "cd x $AMP git merge execute/task-7-a-b" 2 "task 7"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude/reviews/3"
V="$CLAUDE_PROJECT_DIR/.claude/reviews/3/verdict.json"

echo '{"spec_review":"PASS","code_review":"PASS"}' > "$V"
expect_gate "reviewed task merge allowed"     "git merge execute/task-3-slug-abcd"     0

echo '{"spec_review":"PASS","code_review":"CONCERNS_ACCEPTED"}' > "$V"
expect_gate "concerns-accepted allowed"       "git merge execute/task-3-slug-abcd"     0

echo '{"spec_review":"FAIL","code_review":"PASS"}' > "$V"
expect_gate "spec FAIL blocked"               "git merge execute/task-3-slug-abcd"     2 "Spec review did not pass"

echo '{"spec_review":"PASS","code_review":"FAIL"}' > "$V"
expect_gate "code FAIL blocked"               "git merge execute/task-3-slug-abcd"     2 "Code review did not pass"

# ---------------------------------------------------------------------------
# 4. Transcript JSON extraction used by the capture-* hooks.
# ---------------------------------------------------------------------------
echo
echo "=== transcript JSON extraction ==="
T="$TMP/transcript.jsonl"

extract_ok() { # <desc> <expected-nonempty-result>
    if [ -n "$2" ]; then ok "$1"; else bad "$1" "extracted nothing"; fi
}

printf 'noise\n{"task_id":"3","status":"completed"}\nmore\n' > "$T"
extract_ok "task-completion: single-line" \
    "$(tail -50 "$T" | grep -oE '\{[^{}]*"status"[^{}]*\}' | tail -1)"

printf 'x\n{"a":1,"tests_still_pass":true}\n' > "$T"
extract_ok "cynic: single-line" \
    "$(tail -100 "$T" | grep -oE '\{[^{}]*"tests_still_pass"[^{}]*\}' | tail -1)"

printf 'x\n{\n "simplifications_made": [],\n "tests_still_pass": true\n}\ny\n' > "$T"
CY=$(tail -200 "$T" | tr '\n' ' ' \
    | grep -oE '\{[^{}]*"simplifications_made"[^{}]*"tests_still_pass"[^{}]*\}' | tail -1)
extract_ok "cynic: multiline" "$CY"
if printf '%s' "$CY" | jq . >/dev/null 2>&1; then
    ok "cynic: multiline result is valid JSON"
else
    bad "cynic: multiline JSON" "not parseable: $CY"
fi

printf 'x\n{"status" : "PASS","evidence":"ok"}\n' > "$T"
extract_ok "catastrophiser: spaced colon" \
    "$(tail -100 "$T" | grep -oE '\{[^{}]*"status"[[:space:]]*:[[:space:]]*"(PASS|FAIL)"[^{}]*\}' | tail -1)"

printf 'x\n{\n "verified_at":"now",\n "status":"FAIL"\n}\n' > "$T"
extract_ok "catastrophiser: multiline" \
    "$(tail -200 "$T" | tr '\n' ' ' | grep -oE '\{[^{}]*"verified_at"[^{}]*"status"[^{}]*\}' | tail -1)"

printf 'x\n{"files_updated":["README.md"]}\n' > "$T"
extract_ok "perfectionist: single-line" \
    "$(tail -100 "$T" | grep -oE '\{[^{}]*"files_updated"[^{}]*\}' | tail -1)"

printf 'x\n{\n "sections_approved": 3\n}\n' > "$T"
extract_ok "perfectionist: multiline" \
    "$(tail -200 "$T" | tr '\n' ' ' | grep -oE '\{[^{}]*"sections_approved"[^{}]*\}' | tail -1)"

# ---------------------------------------------------------------------------
# 5. create-task-branch.sh prompt parsing.
# ---------------------------------------------------------------------------
echo
echo "=== create-task-branch.sh prompt parsing ==="
PROMPT='Do the thing.
TASK_ID: 12 TASK_SLUG: add-auth-middleware
Go.'
TID=$(printf '%s\n' "$PROMPT" | sed -nE 's/.*TASK_ID:[[:space:]]*([^[:space:]]+).*/\1/p' | head -1)
TSLUG=$(printf '%s\n' "$PROMPT" | sed -nE 's/.*TASK_SLUG:[[:space:]]*([^[:space:]]+).*/\1/p' | head -1)
[ "$TID" = "12" ] && ok "TASK_ID extracted" || bad "TASK_ID" "got '$TID'"
[ "$TSLUG" = "add-auth-middleware" ] && ok "TASK_SLUG extracted" || bad "TASK_SLUG" "got '$TSLUG'"

NONE=$(printf '%s\n' "no markers here" | sed -nE 's/.*TASK_ID:[[:space:]]*([^[:space:]]+).*/\1/p' | head -1)
[ -z "$NONE" ] && ok "absent TASK_ID yields empty" || bad "absent TASK_ID" "got '$NONE'"

echo
echo "================================"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
