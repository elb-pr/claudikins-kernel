# Troubleshooting

## Daemon died mid-session

**Symptom:** Hook log shows no recent entries. `ps aux | grep inotifywait` returns nothing.

**Fix:**
```bash
bash skills/kernel-helper/scripts/setup.sh
```

Setup is idempotent. It will restart the daemon without affecting `.claude/` state.

---

## Hooks not firing on file writes

**Symptom:** Claude writes a file but `hook-log.txt` shows no entry.

**Checks:**
```bash
# Is daemon alive?
ps aux | grep inotifywait | grep -v grep

# Is it watching the right directory?
cat /home/claude/daemon.pid

# Is dispatch.sh executable?
ls -la skills/kernel-helper/hooks/dispatch.sh
```

**Most common cause:** Daemon is watching the wrong path. `CLAUDE_PROJECT_DIR` was not set before setup ran. Fix: re-run `setup.sh` from the project root.

---

## jq not found

**Symptom:** Hook scripts fail with `jq: command not found`.

**Fix:**
```bash
apt-get install -y jq
```

---

## inotify-tools not found

**Symptom:** `inotifywait: command not found` when setup runs.

**Fix:**
```bash
apt-get install -y inotify-tools
```

---

## Gate hooks not blocking

**Symptom:** Claude proceeds with a bash command that should have been blocked by `git-branch-guard.sh` or `merge-gate.sh`.

**Explanation:** Pre-bash gates are enforced as skill constraints on mobile, not as intercepted shell events. If Claude is bypassing a gate it means the skill constraint was not in scope or was not read.

**Fix:** Re-read the relevant skill. Gate constraints are in the primacy zone of each kernel-* skill. Running `bash skills/kernel-helper/hooks/git-branch-guard.sh` manually before any git operation is always valid.

---

## State files missing after new session

**Symptom:** `.claude/execute-state.json` or similar is missing at session start.

**Explanation:** The sandbox resets between conversations. State files need to be saved at session end and uploaded at session start.

**Fix:** Check if the user uploaded state files to `/mnt/user-data/uploads/`. If yes, restore them:

```bash
cp /mnt/user-data/uploads/*.json .claude/ 2>/dev/null
```

If no uploads exist, the session starts fresh. This is expected behaviour.

---

## Session-startup.sh reports parse error

**Symptom:** `session-startup.sh: WARNING - failed to parse plan-state.json`

**Fix:**
```bash
cat .claude/plan-state.json | jq .
```

If the file is malformed, remove it and re-run setup:
```bash
rm .claude/plan-state.json
bash skills/kernel-helper/scripts/setup.sh
```
