# Sprint Run

Pre-flight checks, the orchestrator event loop, stop conditions.

## Pre-flight (run before spawning anything)

```bash
# 0. claudeBinary config — prevents "claude binary not found on PATH" spawn failure.
#    Check: /Users/joe/.mcp-cli/bin/mcx config get claude-binary
#    Set:   /Users/joe/.mcp-cli/bin/mcx config set claude-binary /Users/joe/.mcp-cli/claude-patched/2.1.128.patched
#    This persists across daemon restarts. Required once; verify it's set before each sprint.

# 1. Daemon health
mcx status

# 2. mcx version matches binary
mcx version

# 3. No stale worktrees from a previous sprint
git worktree list

# 4. No phantom commits on main
git fetch origin main
git log HEAD ^origin/main --oneline   # expect empty

# 5. CI is green on main
gh run list --branch main --limit 3

# 6. No open sessions from a previous sprint
mcx claude ls

# 7. Sprint sentinel not set (no sprint currently running)
cat .claude/sprints/.active 2>/dev/null || echo "no active sprint"

# 8. gh CLI authenticated
gh auth status

# 9. Main checkout is on main (sessions can leave it on a feature branch)
git branch --show-current   # must print "main"; if not: git checkout main
```

If any check fails, fix it before proceeding. The stale-worktree and phantom-commit
checks are especially important — corrupted state from a prior run is hard to recover from.

## Checkout guard after impl

After all impl sessions go `idle`, before running review phases, always restore the main
checkout — sessions can drift it onto a feature branch:

```bash
git branch --show-current   # if not "main":
git checkout main
```

## Write the sprint sentinel

```bash
echo "N" > .claude/sprints/.active
```

This prevents the pre-commit hook from blocking commits in the main checkout during the sprint.

## Open the monitor stream

**Required before spawning any sessions.** The monitor stream is how the orchestrator
receives completion events without polling:

```bash
mcx monitor --subscribe session,work_item --json
```

Leave this running as a background `Monitor` tool. Each ndjson line is a push notification.
Do NOT use `mcx claude wait` as the main loop mechanism — it's one-at-a-time polling.
The monitor stream handles N concurrent sessions with one open connection.

Payloads include: `session.result`, `work_item.phase_changed`, `ci.finished`,
`pr.merge_state_changed`. The `allGreen` field on `ci.finished` is pre-computed —
no follow-up `gh pr checks` needed for the common case.

## Phase graph overview

The pipeline is defined in `.mcx.yaml` + `.claude/phases/*.ts`. Run a phase:

```bash
mcx phase run impl --work-item "#14"
mcx phase run review --work-item "#14"
mcx phase run done --work-item "#14"
```

The handler returns a JSON action. Session-driving phases (impl, review, repair) return:
- `{ action: "spawn", command: [...], prompt, model }` — execute the spawn
- `{ action: "in-flight", sessionId }` — session already running, do nothing
- `{ action: "wait", reason }` — back off, re-enter next tick
- `{ action: "goto", target, reason }` — transition to target phase

Terminal phases (done, needs-attention) return domain outputs; special-case them:
- `done`: `{ merged, prNumber, error? }` — if `error`, surface to Joe, don't retry blindly
- `needs-attention`: record the item's `reason`, surface to Joe

## Tracking issues

Before spawning, track the issue:

```bash
mcx track "#14"   # creates the work_items row, returns work item ID
```

After tracking, confirm:

```bash
mcx tracked --json | jq 'map({id, issueNumber, phase})'
```

If `prNumber` is null after the impl session opens a PR, the daemon hasn't polled GitHub yet.
Wait 10s and re-track:

```bash
mcx untrack <N>
sleep 10
mcx track <N>
mcx tracked --json   # prNumber should now be populated
```

## The main loop

```
for each unblocked issue in sprint plan:
  1. check quota:
       mcx call _metrics quota_status
       ≥ 95%: pause until reset
       ≥ 80%: no new impl sessions; finish in-flight review/repair only

  2. call: mcx phase run <current-phase> --work-item "#N"
     dispatch on action:
       "spawn"      → execute command[], note sessionId, update state
       "in-flight"  → leave idle
       "wait"       → leave idle, re-enter next tick
       "goto"       → transition: mcx work-item transition "#N" <target>
       done domain  → if merged: untrack; if error: surface to Joe
       needs-attn   → surface to Joe, leave item parked

  3. on monitor event:
       session.result for a session you own → re-enter its phase
       work_item.phase_changed             → log transition
       ci.finished (allGreen=true)         → if item is in review/done, advance
       pr.merge_state_changed              → if MERGED, confirm + untrack

  4. repeat until all items are done/needs-attention or stop conditions hit
```

**One task per issue**, not per batch. Tasks track state across the loop:
```bash
TaskCreate "Issue #14: display sleep"
TaskCreate "Issue #15: move to trash"
TaskCreate "Issue #16: auto-open recent"
# addBlockedBy: #16 blocked by #15 (both touch SlideshowView.swift)
```

**Never run #15 and #16 in parallel** — they both modify `SlideshowView.swift` and will
conflict. The `addBlockedBy` edge ensures #16 waits for #15 to merge.

## Per-session bookkeeping

After a `spawn` action:
```bash
# Record the real session ID (impl.ts writes a pending sentinel; replace it)
mcx work-item state set "#N" session_id <real-id>
mcx work-item state set "#N" worktree_path <path>
```

Before calling `bye` on any session, verify the branch was pushed:
```bash
mcx claude log <id> --last 5   # confirm "pushed" or "PR opened" in output
git -C <worktree-path> log origin/<branch> --oneline 2>/dev/null | head -1
```

If the branch wasn't pushed, `send` the session to push before bye-ing it.
Unpushed work is unrecoverable after a daemon restart.

## Build verification

Every PR must have a green "Build" CI check before it can merge. The done phase checks this.
The CI check runs `xcodebuild -scheme Slidey -project Slidey.xcodeproj build CODE_SIGNING_ALLOWED=NO`
and takes ~76 seconds. Do not attempt to merge before CI finishes.

## Comment surfaces to check before done

Before transitioning any item to `done`, verify all four PR comment surfaces are clean:

```bash
gh pr view $PR --comments                                       # PR body comments
gh api repos/josephclloyd/Slidey/pulls/$PR/comments            # inline file:line
gh api repos/josephclloyd/Slidey/pulls/$PR/reviews             # review containers
gh issue view $ISSUE --comments                                # linked issue
```

Every open thread must be addressed (code fix + reply citing commit) or dismissed
(explicit out-of-scope reply). No silent skips.

## Stop conditions

Stop the run and report to Joe when:
- All tracked issues are `done` or `needs-attention`
- Quota ≥ 95% and has been there for > 10 minutes
- Three consecutive sessions failed for the same issue (file a `needs-attention` issue)
- A session exceeds $15 cost (interrupt, file issue about the work)
- Joe sends a stop signal

At wind-down, report:
- Issues merged
- Issues in `needs-attention` and why
- Total cost
- Any open PRs still waiting for CI

Then proceed to review (auto-chain) or stop (run-only).
