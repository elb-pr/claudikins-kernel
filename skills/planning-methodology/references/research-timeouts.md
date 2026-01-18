# Research Timeouts (S-3)

How to handle taxonomy-extremist agent timeouts gracefully.

## Default Timeouts

| Mode | Default Timeout | Fast Mode (--fast-mode) |
|------|-----------------|-------------------------|
| Codebase | 60 seconds | 30 seconds |
| Docs | 90 seconds | 45 seconds |
| External | 120 seconds | 60 seconds |
| Dual Research | 180 seconds | 90 seconds |

These timeouts apply to each individual agent spawn, not the total research phase.

## Timeout Detection

The command monitors agent execution time:

```bash
AGENT_START=$(date +%s)
# ... agent runs ...
AGENT_END=$(date +%s)
DURATION=$((AGENT_END - AGENT_START))

if [ "$DURATION" -ge "$TIMEOUT" ]; then
  # Handle timeout
fi
```

## Timeout Handling Flow

### Step 1: Capture Partial Results

Even on timeout, attempt to capture what the agent found:

```json
{
  "status": "timeout",
  "partial": true,
  "findings": [
    // whatever was found before timeout
  ],
  "search_exhausted": false,
  "timed_out_at": "2026-01-16T14:30:00Z",
  "timeout_duration_seconds": 60
}
```

### Step 2: Present Options

```
Research agent timed out after 60 seconds.
Partial results captured: 3 findings (normally expect 8-12)

[Retry with extended timeout] [Continue with partial results] [Skip research] [Different mode]
```

### Step 3: Process User Choice

| Choice | Action |
|--------|--------|
| Retry with extended timeout | Double the timeout, re-spawn agent |
| Continue with partial | Mark research as incomplete, proceed |
| Skip research | Set `research_complete: false`, jump to approaches |
| Different mode | Ask for new mode, spawn fresh agent |

## Retry Logic

### Retry Limits

| Retry | Timeout Multiplier | Notes |
|-------|-------------------|-------|
| 1st retry | 2x | Double original timeout |
| 2nd retry | 3x | Triple original timeout |
| 3rd retry | N/A | No more retries, escalate |

### Backoff Strategy

Wait before retrying to allow external services to recover:

```
Retry 1: Wait 5 seconds, then retry with 2x timeout
Retry 2: Wait 15 seconds, then retry with 3x timeout
Retry 3: No retry, escalate to user
```

### Retry with Different Parameters

If retrying, consider modifying the search:

```
Research timed out. This might help:
- Narrow the search scope
- Use different keywords
- Try a different mode

Retry with: [Same query] [Narrower scope] [Different mode] [Give up]
```

## Mode-Specific Timeout Causes

### Codebase Mode

**Common causes:**
- Very large codebase (>100k files)
- Serena indexing slow
- Complex regex patterns in Grep

**Mitigations:**
- Narrow file patterns (specific directories)
- Simpler search terms
- Use Glob before Grep to reduce file set

### Docs Mode

**Common causes:**
- Context7 library fetch slow
- WebFetch hitting rate limits
- Large documentation sites

**Mitigations:**
- Target specific docs sections
- Use cached results if available
- Skip WebFetch, use only Context7

### External Mode

**Common causes:**
- Gemini API latency
- WebSearch rate limits
- Large response processing

**Mitigations:**
- Reduce Gemini prompt complexity
- Fewer WebSearch queries
- Process results in batches

## Fast Mode Behaviour

With `--fast-mode`:

1. All timeouts halved
2. Retry limit reduced to 1
3. Backoff shortened (2 seconds, 5 seconds)
4. Partial results accepted more readily

Warning shown when using fast mode:

```
Fast mode: Research timeouts reduced by 50%
Research quality may be lower. For thorough research, omit --fast-mode.
```

## Tracking Timeout State

Store timeout information in state:

```json
{
  "research": {
    "agents_spawned": 3,
    "agents_completed": 2,
    "agents_timed_out": 1,
    "timeout_details": [
      {
        "mode": "external",
        "timeout_at": 120,
        "retries": 2,
        "final_status": "partial"
      }
    ],
    "overall_status": "partial"
  }
}
```

## Escalation Path

If all retries exhausted:

```
Research agent failed after 3 attempts.
Mode: External | Total time spent: 6 minutes

Options:
[Continue without external research]
[Manual research input]
[Abandon planning session]
```

## Testing Timeout Handling

Verify these scenarios:

1. Agent times out, partial results captured correctly
2. Retry with extended timeout succeeds
3. All retries fail, escalation message shown
4. Fast mode reduces timeouts appropriately
5. Partial results correctly marked in state
6. User can continue with incomplete research
