# mcx claude — Session Management Reference

## Core Commands

```bash
mcx claude spawn --worktree -t "task description" --allow Read Glob Grep Write Edit Bash
mcx claude spawn --model sonnet -t "review task" --allow Read Glob Grep Bash
mcx claude ls                        # List sessions (scoped to this repo)
mcx claude send <id> "message"       # Send follow-up prompt
mcx claude send <id> "/clear"        # Clear context between phases
mcx claude log <id>                  # View session transcript
mcx claude log <id> --full           # Full output (no truncation)
mcx claude log <id> --last 5         # Last 5 turns only
mcx claude bye <id>                  # End session + clean up worktree
mcx claude interrupt <id>            # Interrupt current turn
```

Session IDs support prefix matching — `mcx claude send a3f "msg"` works.

## Spawn shapes for Slidey

```bash
# Implementation session (worktree-isolated, opus)
mcx claude spawn \
  --worktree \
  --model opus \
  --cwd /Users/joe/Projects/xCode/slidey \
  -t "/implement 14" \
  --allow Read Glob Grep Write Edit Bash

# Review session (read-only, sonnet, no worktree needed)
mcx claude spawn \
  --model sonnet \
  --cwd /Users/joe/Projects/xCode/slidey \
  -t "/sprint-review-pr 14" \
  --allow Read Glob Grep Bash

# Repair session (existing worktree, opus)
mcx claude spawn \
  --model opus \
  --cwd <worktree-path> \
  -t "Fix review findings on PR #N. Read the PR comments with: gh pr view N --comments && gh api repos/josephclloyd/Slidey/pulls/N/comments. Address every finding. Push and confirm the build passes." \
  --allow Read Glob Grep Write Edit Bash
```

## Monitoring Signals

- **State**: `active` (working), `idle` (waiting for input), `waiting_permission` (needs approval), `disconnected` (see below), `ended`
- **Cost**: >$15 suggests struggle — intervene
- **Tokens**: stalled count may indicate a stuck session

### JSON field names (`mcx claude ls --json`)
- Session ID: `sessionId` (not `id`)
- Session state: `state` (not `status`) — values: `active`, `idle`, `waiting_permission`, `disconnected`, `ended`
- Cost: `cost` (float, dollars)
- Tokens: `tokens` (integer)

### `disconnected` — treat as immediate bye candidate

A `disconnected` session may continue generating tokens silently. Don't wait for a
`mcx claude wait` event — it may never arrive. `bye` any disconnected session
immediately unless actively investigating.

### Unsticking sessions

1. Check logs: `mcx claude log <id> --last 5`
2. Send a nudge: `mcx claude send <id> "continue"`
3. If stuck: `mcx claude interrupt <id>` then send new instructions

## Safe Cleanup

Before removing a worktree, check for unpushed work:

```bash
git -C <worktree-path> status --porcelain
git -C <worktree-path> log origin/<branch> --oneline 2>/dev/null | head -1
```

Empty status + commit visible on remote = safe to `git worktree remove <path>`.

## Patch Compatibility

`mcx claude spawn` requires a patched claude binary. If `patch-update` fails:

```bash
# Check error
mcx claude patch-update 2>&1

# If "expected N replacement occurrences, found M":
# The strategy doesn't match the active claude version.
# Workaround: patch with the last known-good version:
mcx claude patch-update --source /Users/joe/.local/share/claude/versions/2.1.128

# Downgrade the active symlink to match:
ln -sf /Users/joe/.local/share/claude/versions/2.1.128 ~/.local/bin/claude

# Restart _claude to pick up the new binary (not the full daemon):
mcx restart _claude && sleep 5

# Spawn sessions as normal. After all sessions finish, restore latest:
ln -sf /Users/joe/.local/share/claude/versions/<latest> ~/.local/bin/claude
# Check available versions: ls ~/.local/share/claude/versions/
```

**Note:** The daemon caches the resolved binary version at `_claude` connection time.
Always `mcx restart _claude` after changing the symlink — restarting the full daemon
is not needed and resets other server connections unnecessarily.

## Session Scoping

Sessions are scoped to this repo's git root (`/Users/joe/Projects/xCode/slidey`).
`mcx claude ls` only shows Slidey sessions. Use `--all` to see all repos.

**Sprint orchestrator commands must run from inside the project root.** Running
from the wrong directory makes sessions appear missing when they're running fine.

### Diagnosing "missing" sessions

1. `mcx claude ls --all` — if they appear, you're in the wrong directory
2. Verify `pwd` is at or inside `/Users/joe/Projects/xCode/slidey`
3. `mcx scope ls` — check if a scope is registered

## Concurrency limit

**Max 2 impl sessions in parallel** for Slidey. `SlideshowView.swift` is touched by
most features — concurrent impl sessions will conflict. The plan's `addBlockedBy` edges
enforce serialization on known conflicts, but keep the total low as a general rule.
