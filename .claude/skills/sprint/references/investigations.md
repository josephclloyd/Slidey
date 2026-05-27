# Investigations — Nerd-Snipe Gate

For issues where the mechanism is unclear: build failures with non-obvious cause,
UI bugs that are hard to reproduce, performance regressions, or anything where
"just try to fix it" has failed once already.

## When to use this gate

**Required before spawning impl for:**
- Any issue labelled `flaky` or `investigation-needed`
- Any issue where a previous impl session failed without a clear fix plan
- Build failures that aren't obvious Swift errors
- Entitlement or App Sandbox violations (these require understanding the exact
  permission model before trying to fix)

**Not needed for:**
- Well-specified feature additions (the README TODO items)
- Clear bug fixes with a known cause
- Documentation or tooling changes

## How to run an investigation

Spawn a dedicated nerd-snipe session using `mcx claude spawn`, **not** the Agent tool.
Agent-tool sub-contexts give the orchestrator no progress visibility.

```bash
mcx claude spawn \
  --model opus \
  --cwd /Users/joe/Projects/xCode/slidey \
  -t "Investigate issue #N: [title]. Find the root cause. Produce a concrete fix plan as a GitHub issue comment on #N. Do NOT write any code. Read the source, read the error, understand the mechanism. Your output is a comment on the issue with: (1) root cause, (2) exact files/lines to change, (3) acceptance criteria for the fix." \
  --allow Read Grep Glob Bash
```

The investigation session must produce a GitHub issue comment with:
1. Root cause (file:line, exact mechanism)
2. Concrete fix plan (what to change, not how to implement it)
3. Acceptance criteria

**Hard gate:** if the investigator cannot produce both a root cause AND a concrete fix
plan, the issue does **not** proceed to implementation — it transitions to `needs-attention`.
No "spawn opus and hope."

## After investigation

Once the issue comment exists with root cause + fix plan:
- Tag the issue with `ready-to-implement` or equivalent
- Proceed to normal `impl` phase — the worker reads the investigation comment

The extra spawned session cost ($3-5) prevents a $30-50 failed impl session that masks
symptoms rather than fixing them.
