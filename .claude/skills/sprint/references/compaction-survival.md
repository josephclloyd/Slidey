# Compaction Survival

What survives context compaction and how to recover the orchestrator's state.

## What survives

- The sprint plan file: `.claude/sprints/sprint-N.md`
- Work item state in the daemon DB: `mcx tracked --json`
- Phase scratchpad keys: `mcx work-item state get "#N" session_id`
- The Monitor tool (mcx monitor stream stays open)
- Task list metadata (TaskList)
- The sprint worktree at `.claude/worktrees/sprint-N/`
- The sprint container PR on GitHub

## What strips

- Per-session "what they're working on right now"
- Which session IDs map to which issues (the session→issue association)
- Recent unread gh pr output
- Deferred tool schemas

## Recovery sequence (5 commands)

```bash
# 1. What sessions are running?
mcx claude ls --short

# 2. What's the state of all tracked work items?
mcx tracked --json | jq 'map({id, issueNumber, prNumber, phase, branch})'

# 3. Is quota OK?
mcx call _metrics quota_status

# 4. What's on GitHub?
gh pr list --json number,title,labels,mergeStateStatus,headRefName,statusCheckRollup

# 5. What does the sprint plan say?
cat .claude/sprints/sprint-N.md
```

## Re-pairing sessions to work items

`mcx tracked` gives you the `session_id` from the phase scratchpad:

```bash
mcx work-item state get "#14" session_id
```

Cross-reference with `mcx claude ls` output. If a session ID in state matches a running
session, it's still in-flight.

## Schema reminders (these bite every time)

- `mcx tracked --json` returns an **array** of work items
- Each item has `.id` (the work-item UUID), `.issueNumber`, `.prNumber`, `.phase`
- Access phase scratchpad: `mcx work-item state get "#<issueNumber>" <key>`
- `.id` is the UUID used for `mcx work-item state`; `.issueNumber` is the GitHub issue number
- Do not confuse them: `mcx work-item state get "#14" session_id` (uses issue number with #)

## If the Monitor stream dropped

Re-open it:

```bash
mcx monitor --subscribe session,work_item --json
```

Any events that fired while it was down are not replayed — do a full recovery-sequence
sweep to catch up on state before resuming the loop.
