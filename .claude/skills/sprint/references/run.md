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

**Note:** `--worktree` on `mcx claude spawn` does NOT create a separate git worktree.
Sessions branch in the main checkout. After every impl session completes, `git branch
--show-current` will show the feature branch. Do NOT switch to main until `mcx claude ls`
confirms that session is idle — switching while the session is mid-commit corrupts the
working tree. The post-impl routine handles this correctly; don't shortcut it.

**Important ordering:** run check #9 BEFORE check #4. A working directory that has drifted
into a sprint worktree (e.g. from a prior `cd .claude/worktrees/sprint-N`) will make the
phantom-commit check (#4) report false positives. Always assert `main` first.

If any check fails, fix it before proceeding. The stale-worktree and phantom-commit
checks are especially important — corrupted state from a prior run is hard to recover from.

## Post-impl routine (run after EVERY impl session goes idle)

Do these steps in order before running the review phase. All are required
every sprint — impl sessions consistently skip them:

```bash
# 1. Verify Closes #N is in the PR body (impl sessions reliably omit it)
gh pr view <prNumber> --json body -q '.body' | grep -i closes
# If empty: gh pr edit <PR> --body "$(gh pr view <PR> --json body -q '.body')\n\nCloses #N"

# 2. SlideshowView.swift testability note — impl sessions reliably omit this.
#    If the PR diff touches SlideshowView.swift, check the PR body mentions tests/testability.
gh pr diff <prNumber> | grep -q "SlideshowView.swift" && \
  gh pr view <prNumber> --json body -q '.body' | grep -qi "test" || \
  echo "MISSING: add testability note to PR body"
# If missing, add: gh pr edit <PR> --body "$(gh pr view <PR> --json body -q '.body')
#
# ## Testing
# No unit tests added — all new code is SwiftUI/AppKit UI wiring with no extractable logic; manual test checklist covers the behaviour."

# 3. Restore main checkout (sessions branch in the main worktree, leaving HEAD on feature branch)
git branch --show-current   # if not "main":
git checkout main

# 4. Re-pair tracked work item so prNumber populates (daemon doesn't auto-link)
mcx untrack N
sleep 10
mcx track N
mcx tracked --json   # prNumber should now be non-null
```

Only then: `mcx phase run review --work-item "#N"`

**If `mcx phase run` fails with "phases only run from branch main"** — the main worktree
drifted while another impl session was still active. Do NOT switch to main while that session
is running (it may be mid-commit). Wait for that session's `session.result`, THEN:

```bash
git checkout main
mcx phase run review --work-item "#N"
```

If the review was already spawned manually before you could restore main, advance the
work item with `--no-execute` + `--from` to unblock the done phase:

```bash
mcx phase run review --work-item "#N" --no-execute   # log the transition, don't re-spawn
mcx phase run done   --work-item "#N" --from review   # then proceed normally
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
mcx monitor --subscribe session,work_item --json 2>&1 \
  | grep --line-buffered -E '"event":"(session\.result|ci\.finished|pr\.merge_state_changed|work_item\.phase_changed)"'
```

**Use the grep filter.** The unfiltered `--subscribe session,work_item` stream emits a
`session.tool_use` event for every tool call in every session — it hits the Monitor
tool's rate-limit suppression within seconds and starts dropping events. The grep filter
passes only the four events the orchestrator actually acts on.

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

## Daemon restart recovery

If the daemon restarts mid-sprint (check `mcx status` — uptime near 0s), work items are wiped
from in-memory state. Re-track every sprint issue before resuming:

```bash
mcx track N   # one call per issue
sleep 12      # wait a poll cycle for prNumber to populate
mcx tracked --json
```

Then re-open the monitor stream and resume where you left off. Branch state in git is unaffected
by daemon restarts — only the in-memory tracking state is lost.

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

**SlideshowView.swift hot-file — deeper conflict check at plan time:** The "distinct files" check is insufficient for SlideshowView. Two branches that each add a new `@ViewBuilder private var` property, or each add a modifier to `coreView`/`overlayViews`, will produce a merge conflict even though they "touch different features." At plan time, inspect which *sections* of SlideshowView each issue adds to: `emptyStateContent`, `imageDisplayContent`, `overlayViews`, `coreView`, `body`. If two issues touch the same section, serialise them with `addBlockedBy`.

**SlideshowView type-checker timeout:** Xcode 16.3 CI fails with "unable to type-check in reasonable time" when `coreView` or `body` accumulates too many modifier levels. The established fix:
1. Extract view sections into `@ViewBuilder private var emptyStateContent/imageDisplayContent/overlayViews`
2. Move the ZStack + onChange/focusable/onKeyPress chain into `private var coreView: some View`
3. Leave only `coreView` + `.onReceive` chain + `.sheet`/`.alert` in `var body`

If CI fails at a line in `body` or `coreView` with "unable to type-check", apply this split. Needs two repair passes if the first extraction doesn't shorten `body` enough.

## Bundle detection (impl session includes files from a sibling issue)

If an impl session's PR includes files that belong to a *different* sprint issue (e.g. #97 session creating pr-size.yml which was #99's work):

1. Check whether the bundled work is correct: read the diff and compare to the sibling issue's acceptance criteria.
2. **If correct:** update the PR description to reference both issues (`Closes #N\nCloses #M`), post a comment explaining the bundle, and advance both issues to done together. Do not split.
3. **If incorrect or partial:** remove the bundled file(s) from the branch, open a note in the sibling issue about what was attempted, and re-spawn that issue's impl session separately.

Never silently accept a bundle — always update the PR body so both issues are linked and closed.

## Quota-hit recovery (session exits with "You're out of extra usage")

When a session hits the usage quota mid-work, the branch may not exist yet and changes are
uncommitted in the main worktree.

**Zero-progress case (most common when quota hits early):** If multiple sessions all hit quota simultaneously, they typically made no commits and created no remote branches. Check with `git log <branch> ^main --oneline` — if empty, the session left nothing useful. If the build also fails, discard without further investigation:

```bash
git checkout main
git branch -D <branch-name>
git checkout -- <modified-files>   # restore any partial edits
```

Re-spawn after the quota resets. Do not attempt recovery of a zero-commit, failing-build branch — the session had made no meaningful progress.

**Partial-progress case:** Do not discard — the work is usually complete.

```bash
# 1. Check what the session left behind
git status --short
git branch --show-current
# Look for: new untracked source files, modified SlideshowView.swift / project.pbxproj, etc.

# 2. Verify the build passes with the uncommitted changes
xcodebuild -scheme Slidey -project Slidey.xcodeproj build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3

# 3a. If the branch already exists (session branched but didn't commit):
#     Switch to it (changes carry over since branch is at same SHA as main)
git checkout <branch-name>
git add <file1> <file2> ...
git commit -m "<description>

Closes #N"
git push -u origin <branch-name>

# 3b. If the branch does NOT exist yet:
#    Stash only the relevant files (not files from other sessions' branches)
git stash push -u -m "recovery" -- <file1> <file2> ...

#    Create the correct branch from main
git checkout main
git checkout -b <branch-name>

#    Apply the stash (resolve any project.pbxproj conflicts — keep both sides)
git stash pop

#    Commit, push, and create the PR manually
git add -A
git commit -m "<description>\n\nCloses #N"
git push -u origin <branch-name>
gh pr create --title "..." --body "..."

# 4. Note: the stash may include project.pbxproj entries from ANOTHER session's branch
#    if the main worktree was on that branch when the quota hit. Strip those entries
#    from project.pbxproj before committing (keep only entries for THIS issue's new files).
```

The quota resets at the time shown in the error message. If the build does NOT pass, wait for
the reset and re-spawn the session to complete the work.

**After a long quota wait (>1h), the gh auth token may expire.** `gh pr view --json` will
return HTTP 401. Fall back to the REST API:
```bash
gh api repos/josephclloyd/Slidey/pulls/N --jq '{state: .state, merged: .merged, merged_at: .merged_at}'
```
If that also fails, prompt Joe: `! gh auth refresh -h github.com` (requires interactive
browser flow — cannot be automated).

## Ambiguous test result in impl session output

When the impl session result text says "Build: SUCCEEDED" without an explicit "N passed" test count, the Test CI job may not have been checked. Verify before spawning review:

```bash
gh pr checks <prNumber>   # both Build and Test jobs must be green
```

Do not rely solely on the session's self-reported result — impl sessions do not always wait for the Test job to finish before exiting.

## Binary-invoked features (realesrgan, external tools)

CI cannot execute the bundled `realesrgan-ncnn-vulkan` binary — it only confirms the Swift code compiles. For any PR that changes how the binary is invoked (new flags like `-s 2`, new model selection, different output paths), the review phase cannot catch runtime regressions. Add a note in the review spawn prompt for such PRs:

> This PR changes binary invocation parameters. The reviewer should confirm: (1) the flag is passed correctly in the spawn call, (2) the output file is loaded back into the view using the same code path as the previously working invocation, and (3) the manual test checklist explicitly requires running the binary on a real image and inspecting the result.

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

Every PR must have green **Build** and **Test** CI checks before it can merge (as of sprint 8,
`xcodebuild test` runs in a separate `Test` job). The done phase checks this.
CI takes ~2.5 minutes (Build + Test run in parallel). Do not attempt to merge before both finish.

**`mcx pr merge --auto` is broken for this repo** (GitHub auto-merge is disabled). Always use:
```bash
# Wait for CI, then:
mcx pr merge <PR> --squash
```
Never pass `--auto`. If the done phase returns `merged: false` with a merge error, check CI
status first, then retry `mcx phase run done --work-item "#N" --from review`.

**If GitHub Actions stops triggering** (check-suites returns 0 for the PR's HEAD commit):
- Empty commit and close/reopen PR do NOT reliably re-arm webhooks.
- Pushing a **real merge commit** (e.g. `git merge origin/main`) does — the merge creates a fresh SHA that always triggers a new run.
- Last resort: wait for the next organic push (repair, fix, etc.) which will also trigger.

**Ensure every PR has `Closes #N` in the body.** Without it, `mcx tracked` shows `prNumber: null` and the review phase blocks waiting for a PR that already exists. If missing, add it with `gh pr edit <N> --body "$(gh pr view <N> --json body -q '.body')\n\nCloses #ISSUE"`.

**After every impl session goes idle, verify `Closes #N` before running review:**
```bash
gh pr view <prNumber> --json body -q '.body' | grep -i closes
# If empty: add it (see above) before proceeding to review phase
```
Impl sessions reliably omit this — make the check a routine step, not a recovery action.

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
