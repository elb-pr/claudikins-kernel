# Setup Procedure

## Quick start

```bash
bash skills/kernel-helper/scripts/setup.sh
```

That's it for most sessions. The rest of this document explains what it does and how to run steps manually if needed.

---

## What setup.sh does

### Step 1 — Dependencies

```bash
apt-get install -y jq inotify-tools 2>/dev/null
```

Both are idempotent. Safe to run if already installed.

### Step 2 — Environment

```bash
export CLAUDE_PROJECT_DIR=$(pwd)
export CLAUDE_PLUGIN_ROOT=$(pwd)/skills/kernel-helper
```

`CLAUDE_PROJECT_DIR` is where `.claude/` lives.
`CLAUDE_PLUGIN_ROOT` is where shared hooks live.

### Step 3 — Directory structure

```bash
bash skills/kernel-helper/hooks/session-startup.sh
```

Creates `.claude/` subdirectories if they don't exist. Idempotent. Reports any existing session state.

### Step 4 — inotifywait daemon

```bash
inotifywait -m -r -e close_write "$CLAUDE_PROJECT_DIR" \
  --format '%w%f' 2>/dev/null | while read FILE; do
  bash "$CLAUDE_PLUGIN_ROOT/hooks/dispatch.sh" "$FILE"
done &
echo $! > /home/claude/daemon.pid
```

Starts the file-write watcher. Runs in background for the entire session.

### Step 5 — Status summary

Prints which session state files exist, daemon PID, and confirms the runtime is live.

---

## Restoring state from previous session

If the user uploads files from a previous session:

```bash
# Uploaded files land at /mnt/user-data/uploads/
ls /mnt/user-data/uploads/

# Restore state files to .claude/
cp /mnt/user-data/uploads/execute-state.json .claude/execute-state.json
cp /mnt/user-data/uploads/ship-state.json .claude/ship-state.json
# etc.
```

`setup.sh` checks for uploads automatically and offers to restore them.

---

## Manual dependency check

```bash
which jq && jq --version
which inotifywait && inotifywait --version
```

---

## Verifying the daemon

```bash
# Is it running?
ps aux | grep inotifywait | grep -v grep

# What is it watching?
cat /home/claude/daemon.pid

# Recent hook activity
tail -20 /home/claude/hook-log.txt
```
