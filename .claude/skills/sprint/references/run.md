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

**Don't trust a single `mcx status` reading right after a daemon restart.** If uptime is
near 0s and any server shows `connecting` instead of `connected` (especially `_claude`,
`_mock`, `_site`), the daemon is still starting up — spawning or calling `mcx monitor`
against it can fail (e.g. `mcx monitor` erroring "Was there a typo in the url or port?").
Hit in Sprint 28: cost several minutes of diagnosis before the fix was found. Re-check
`mcx status` after a few seconds; only proceed once uptime is climbing normally and all 8
servers read `connected`. If a connection error persists despite a stable-looking status,
try `mcx restart` once, then recheck.

**"Protocol mismatch: daemon X, CLI expects Y" means the `mcx` CLI binary and the running
daemon have drifted to different versions** (the CLI auto-updates independently of the
already-running daemon process). This blocks *every* `mcx` command, including read-only
queries like `mcx claude ls` — there's no working around it, the daemon needs
`mcx daemon reload`. That command will refuse if it would orphan active sessions; before
forcing it, confirm via context (not by querying — the mismatch blocks queries too) that
nothing genuinely in-flight would be lost. All real sprint work lives in git/GitHub, not
in the daemon's session list, so orphaning old idle-session bookkeeping is normally safe
to force through (`mcx daemon reload --force`) — but confirm with Joe first regardless,
since the tool's own warning is exactly the kind of "hard to reverse, ask first" situation
this skill's parent instructions call out. Hit in Sprint 30 (daemon auto-upgraded from
1.12.1 to 1.14.6 mid-session). **After reloading, expect `.mcx.lock` to be invalidated
too** — a newer `mcx` computes phase-file content hashes differently, so `mcx phase run`
will report the lock "out of date" even though no phase file content actually changed.
Verify with `git diff .claude/phases/` (should be empty) before treating it as a real
change, then `mcx phase install` and push the `.mcx.lock`-only diff directly to `main` per
the tooling-blocked exception below — this is exactly that exception's use case.

**Never `git pull` in the main checkout — use `git fetch && git merge --ff-only`.** A bare
`git pull` can hit a divergent-branches prompt (the main checkout is being branched from
by spawned sessions throughout the sprint) and leaves HEAD detached at `FETCH_HEAD` instead
of fast-forwarding `main` cleanly. Hit in Sprint 24; recovered with a plain `git checkout
main` since the fetch had already updated the local ref, but `merge --ff-only` fails loudly
instead of prompting for a reconciliation strategy, which is safer given how often this
checkout is switched between branches mid-sprint.

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

**Monitor 90s silence timeout:** `mcx monitor` exits with code 1 and "no events or heartbeat for 90s" when impl sessions produce no daemon events for 90 seconds. This happens reliably during long-running impl sessions (AI work, multi-file changes). Restart the Monitor tool immediately when it dies — but if it dies repeatedly, switch to `mcx claude wait <sessionId>` with `run_in_background: true` as the completion signal for that session. `run_in_background: true` has no timeout and will reliably notify you when the session finishes. Hit 4 times in Sprint 39 for #341's impl session.

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

**Execute the returned `spawn` command's `prompt` verbatim — don't hand-rewrite it.**
`review.ts` builds a review prompt that already includes strict verdict-token instructions
on every round (round number only affects internal state tracking, not the prompt text
itself). When you want to add round-specific context for a repair-loop re-review (e.g. "this
is round 2, confirm the fix for finding X"), **append** it to the returned prompt rather than
composing a new prompt by hand from scratch. Sprint 25 saw inconsistent verdict-token
compliance from hand-authored re-review prompts that shortened or dropped the original
instruction wording — the phase-generated prompt is the reliable source of that instruction.

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
mcx track 14   # creates the work_items row, returns work item ID
```

**Bare number, no `#` prefix** — `mcx track "#14"` fails with `Error: Invalid number: #14`.
Hit in both Sprint 7 and Sprint 23; this is the corrected form.

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

## Flag plan-time risks to the impl session directly

If the sprint plan's per-issue notes call out a specific risk — a stale suggestion in the
issue text (e.g. a key binding that predates the current registry), an interaction hazard
with existing code (e.g. a gesture layer the new feature must not collide with), or anything
else the plan author already anticipated — send it to the impl session as a `mcx claude send`
follow-up immediately after spawning, in your own words with the specific file/symbol names.
Don't rely on the session reading the plan file itself or re-deriving the risk from the issue
text alone. Sprint 24 did this for two issues (a stale key-binding suggestion, a gesture-
precedence hazard) and both landed with 0 repair rounds.

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

**SwiftLint `cyclomatic_complexity` in `handleCharacterKeyPress`:** This function is extracted from `handleKeyPress` specifically to manage complexity. SwiftLint's error threshold is ~50. After adding any new `case` to `handleCharacterKeyPress`, check the complexity stays green:
```bash
xcodebuild -scheme Slidey -project Slidey.xcodeproj build CODE_SIGNING_ALLOWED=NO 2>&1 | grep cyclomatic
```
If it fails, extract a sub-helper (e.g. `handleEditKeyPress`) or add `// swiftlint:disable:next cyclomatic_complexity` only if extraction is genuinely worse. Also check the key binding registry in CLAUDE.md before picking a new key — several single-letter keys are already taken.

**SwiftLint `file_length`/`type_body_length` — extract, never raise the threshold:** When an impl session's new feature pushes `SlideshowView.swift` near the 3500-line (or 3000 type-body) error threshold, the fix is to extract to `SlideshowView+AIEdits.swift` (change `private` to internal on anything the extension needs), not to raise the numbers in `.swiftlint.yml`. This happened in Sprint 20: an impl session bumped both thresholds instead of extracting, even though the sprint plan had explicitly flagged the imminent breach and named the extraction as the required fix. It was caught in review and repaired. Raising the threshold is a one-way ratchet that just gets re-breached by the next feature — treat any diff that touches `.swiftlint.yml`'s `file_length`/`type_body_length` values as a repair-worthy finding during review.

**New `.swift` files under `slidey/` must be registered in `project.pbxproj`:** unlike `Resources/` (a `PBXFileSystemSynchronizedRootGroup` that auto-discovers new files), `slidey/` is a traditional Xcode group with explicit `PBXFileReference`/`PBXBuildFile` entries. A new source file (a new extension, a new controller class) compiles fine in isolation but fails the full build with "cannot find type/symbol in scope" until it's added to the Sources build phase. This has cost a build-failure cycle in two sprints running (Sprint 20's `SlideshowView+AIEdits.swift`, Sprint 21's `CropController.swift`/`SlideshowView+Crop.swift`/`EditStack.swift`). If a sprint issue's plan calls for a new source file, flag this explicitly in the impl spawn/redirect message so the session registers it immediately rather than discovering it via a failed build.

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

**A quota-failed review/repair spawn no longer consumes a phase round (fixed in Sprint 27's
retro, `review.ts`/`repair.ts`) — but you must set the retry flag.** These phases increment
`review_round`/`repair_round` at spawn time, before the session's actual outcome is known.
If the spawned session dies instantly with 0 tokens/0 cost and no verdict (a genuine quota
failure, not a real review or repair attempt), tell the phase engine this retry doesn't
count as a new round by setting `review_round_retry`/`repair_round_retry` to `true` before
re-running `mcx phase run`:
```bash
mcx call _work_items phase_state_set '{"workItemId":"#N","repoRoot":"/Users/joe/Projects/xCode/slidey","key":"review_round_retry","value":true}'
# or repair_round_retry, matching whichever phase failed
```
Also clear the stale `review_session_id`/`repair_session_id` (it still points at the dead
session) before re-running `mcx phase run`, or the phase engine will report `in-flight`
against a session that already exited:
```bash
mcx call _work_items phase_state_delete '{"workItemId":"#N","repoRoot":"/Users/joe/Projects/xCode/slidey","key":"review_session_id"}'
```
(This flag-based fix landed in Sprint 27's retro. Before that, the workaround was manually
recomputing and setting `review_round`/`repair_round` back down by one — still works as a
fallback if the flag mechanism itself ever needs bypassing, but prefer the flag.)

**Non-quota `pending:` sentinel: session never spawned.** A `pending:...` session ID can also
get stuck when the review phase was called but the orchestrator did not execute the resulting
spawn command (e.g., due to a mid-session interruption or context compaction). The symptom is
`mcx phase run review` returning `in-flight` with `sessionId: "pending:..."` while `mcx claude
ls` shows no corresponding session. Fix: clear `review_session_id`, then re-run. If the second
run returns `action: "spawn"` (with a full `command` array), execute the spawn manually:
```bash
mcx call _work_items phase_state_delete '{"workItemId":"#N","repoRoot":"/Users/joe/Projects/xCode/slidey","key":"review_session_id"}'
mcx phase run review --work-item "#N"
# If result is action:"spawn", execute:
mcx claude spawn --model sonnet --cwd /Users/joe/Projects/xCode/slidey \
  --allow Read Glob Grep Bash \
  -t "<prompt-from-spawn-output>"
```
The session ID returned by `mcx claude spawn` must then be recorded via `phase_state_set` if
the phase engine doesn't pick it up automatically. Hit in Sprint 31 for #290's review.

**Stale `pending:` sentinel when verdict IS known — go to repair directly, do NOT re-run review.** If a review session completed and you know the verdict from `mcx claude log <id>` or the monitor event, but the sentinel was left stale, clearing it and re-running `mcx phase run review` increments `review_round` even though no real review runs — this can falsely hit the max-round cap and route the item to `needs-attention`. Correct path when verdict is `has-issues` and verdict is known:
```bash
mcx call _work_items phase_state_delete '{"workItemId":"#N","repoRoot":"/Users/joe/Projects/xCode/slidey","key":"review_session_id"}'
# Do NOT re-run: mcx phase run review  ← increments review_round wastefully
# Instead, go directly to repair:
mcx phase run repair --work-item "#N" --from review
```
If the round counter was already inflated by the accidental re-run, set `review_round_retry=true` before re-entering review after repair so the re-review doesn't count as another round. Hit in Sprint 39 for #340.

**Verify the retry flag actually held** before re-spawning — don't just trust that the
returned action came back as `spawn` and move on:
```bash
mcx call _work_items phase_state_get '{"workItemId":"#N","repoRoot":"/Users/joe/Projects/xCode/slidey","key":"review_round"}'
# or repair_round — confirm the value is unchanged from before the quota-failed attempt
```
Cheap to check, and catches a silent regression in the fix itself immediately (e.g. a
future edit to `review.ts`/`repair.ts` that breaks the flag logic) rather than only
discovering it two rounds later when an item unexpectedly lands in `needs-attention`.
Validated working correctly in Sprint 28 (`#259` hit two genuine quota failures; the round
counter stayed at 1 through both, confirmed via this exact check).

**Quota status can lag the actual reset by ~10-15 minutes.** `mcx status`/`mcx call _metrics
quota_status` occasionally report a `resetsAt` timestamp that has already passed while
`utilization` still reads 100%. This happened twice in Sprint 21. Do not retry-spawn against
a stale 100%-with-past-reset-time reading — wait ~10-15 minutes and recheck; it resolves
itself without any other intervention.

**A quota wait expected to exceed ~1 hour will outlast the persistent Monitor task's own
timeout — restart it, don't just `ScheduleWakeup` and assume events will still arrive.**
`ScheduleWakeup` correctly re-invokes the orchestrator at the right time, but the
background `Monitor` task backing the event stream has its own independent timeout
(typically 3600000ms) and silently stops delivering events if the wait runs longer. Hit in
Sprint 29: a ~3h five-hour-window wait outlasted the monitor, and this wasn't caught until
a manual `mcx status` check well after the wait began — a `session.result` event could
have been missed entirely. Before or immediately after scheduling a wakeup for a wait that
could plausibly exceed an hour, restart the Monitor task proactively; don't wait to notice
a gap.

**Zero-progress case (most common when quota hits early):** If multiple sessions all hit quota simultaneously, they typically made no commits and created no remote branches. Check with `git log <branch> ^main --oneline` — if empty, the session left nothing useful. If the build also fails, discard without further investigation:

```bash
git checkout main
git branch -D <branch-name>
git checkout -- <modified-files>   # restore any partial edits
```

**Mid-work quota hit (session left staged changes but no commit):** The most common recovery is `mcx claude send` to the idle session after quota resets — the session retains its context and can continue from where it stopped:
```bash
mcx call _metrics quota_status   # confirm available: true
mcx claude log <sessionId> | tail -20   # see exactly where it stopped
mcx claude send <sessionId> "Quota has reset. [Brief summary of where you left off and what remains.] Continue where you stopped."
```
This is faster than re-spawning and avoids re-deriving all context. The session goes from `idle` → `active` automatically. Hit in Sprint 32: session `bc292e96` stopped mid-pbxproj-registration; the send resume worked without losing any created files. Only re-spawn if the session left no useful state or if the quota hit was so early the branch itself doesn't exist.

## Worktree cd-path persistence hazard

**The Bash tool's working directory persists across calls.** A `cd /path/to/sprint-N-worktree` from one Bash call leaves all subsequent calls running inside that worktree. This causes silent failures: `sed` updates the worktree's files (not main's), `git` operations run against the sprint branch instead of main, and `git checkout main` fails with "already used by worktree."

Two safe patterns:
1. Always `cd` back to the main checkout in the same compound command: `cd /path/to/worktree && <operations> && cd /Users/joe/Projects/xCode/slidey`
2. Use absolute paths throughout rather than `cd`ing at all: `sed -i '' ... "$WORKTREE/Slidey.xcodeproj/project.pbxproj"` rather than `cd "$WORKTREE" && sed -i '' ... Slidey.xcodeproj/project.pbxproj`

Hit in Sprint 32: version-bump `sed` ran in the main worktree instead of the sprint worktree; required reverting main's `project.pbxproj` and re-running with an absolute path.

Re-spawn after the quota resets. Do not attempt recovery of a zero-commit, failing-build branch — the session had made no meaningful progress.

**Partial-progress case:** Do not discard — the work is usually complete.

```bash
# 1. Check what the session left behind
git status --short
git branch --show-current
# Look for: new untracked source files, modified SlideshowView.swift / project.pbxproj, etc.

# 2. Verify the build passes with the uncommitted changes
xcodebuild -scheme Slidey -project Slidey.xcodeproj build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

**Before committing, check for unused/unwired code the interrupted session left behind.**
Building successfully does not mean the diff is complete — Sprint 23's #206 session was cut
off after adding `@FocusedValue`/computed-property plumbing to a second `Commands` struct
that was never wired to any `.disabled()` call and was out of the issue's stated scope.
`grep` for each new symbol's usages; if a new property/binding has zero call sites, remove
it rather than committing dead code or trying to guess what the session intended to do with
it. Re-run the build (and full test suite) after trimming.

```bash
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

## mcx session auth failure fallback (direct implementation)

If `mcx claude spawn` returns **"Not logged in · Please run /login"** for all sessions,
the spawn infrastructure is broken. Do not retry; implement all sprint issues directly
in the main conversation:

1. Skip `mcx track / mcx phase run / monitor stream` — manage state via TaskCreate/TaskUpdate.
2. Implement each issue inline (branch → implement → build → commit → push → PR), one at a time.
3. After each PR is opened, re-pair with `mcx untrack N && sleep 10 && mcx track N` so `prNumber` populates for the merge step.
4. Review each PR inline (read the diff, spot-check correctness, leave a review comment). Don't skip review.
5. Merge via `mcx pr merge <PR> --squash` as usual.
6. After the sprint, note the auth failure in the diary and update `mcx-patch-compat.md` in memory.

**This is a full fallback, not a shortcut.** Serialization (SlideshowView.swift hot-file), review, and CI gates still apply. The only thing bypassed is session spawning — the quality bar stays the same.

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
# `mcx work-item state set` is not a real CLI command (hit in Sprint 7 and Sprint 23) —
# the actual mechanism is the _work_items virtual server's phase_state_set tool:
mcx call _work_items phase_state_set '{"workItemId":"#N","repoRoot":"/Users/joe/Projects/xCode/slidey","key":"session_id","value":"<real-id>"}'
mcx call _work_items phase_state_set '{"workItemId":"#N","repoRoot":"/Users/joe/Projects/xCode/slidey","key":"worktree_path","value":"<path>"}'
```

Before calling `bye` on any session, verify the branch was pushed:
```bash
mcx claude log <id> --last 5   # confirm "pushed" or "PR opened" in output
git -C <worktree-path> log origin/<branch> --oneline 2>/dev/null | head -1
```

If the branch wasn't pushed, `send` the session to push before bye-ing it.
Unpushed work is unrecoverable after a daemon restart.

## Prefer --body-file over inline heredocs for gh issue/pr create

Hit a bash heredoc quoting failure twice in Sprint 24 — once for the orchestrator itself
(filing GitHub issues whose body text contained apostrophes) and once for a spawned impl
session's own `gh pr create` (`bad substitution: no closing ')'`, a bash parse error, not a
quota or logic issue). Both recovered fine (the session had already committed and pushed;
only PR creation failed), but this is a repeatable, avoidable failure mode.

Write the body to a file first, then pass `--body-file`:
```bash
# Orchestrator: use the Write tool to create the body file, then:
gh pr create --title "..." --body-file /path/to/body.md --base main
gh issue create --title "..." --label "..." --body-file /path/to/body.md
```
This sidesteps shell quoting entirely — no escaping needed for apostrophes, backticks, or
embedded double quotes in the body text. Prefer this over `--body "$(cat <<'EOF' ... EOF)"`.

**The same quoting hazard applies to `mcx claude send`.** Backticks and `${...}` inside
double-quoted arguments are expanded by bash before the argument reaches `mcx`. Write
risk-note or long-form send messages to a temp file first:
```bash
# Write the message body to a temp file (using the Write tool or a heredoc):
cat > /tmp/send-msg.txt << 'MSGEOF'
message text with backticks and ${braces} safe here
MSGEOF
# Then send:
mcx claude send <sessionId> "$(cat /tmp/send-msg.txt)"
```
Hit in Sprint 38: the first `mcx claude send` with plan-time risk notes contained backtick
expressions that bash executed as subshell commands; fixed by writing to a temp file.

## Direct push to main: only when CI/tooling itself is what's broken

The normal flow (branch → PR → passing CI → `mcx pr merge`) requires CI to pass before
anything lands on `main`. That flow cannot fix CI or tooling infrastructure that is itself
broken — a PR fixing a broken required check can never pass that same check. Sprint 25 hit
this twice: a stale `.mcx.lock` blocking `mcx phase run` for every work item, and a GitHub
Git LFS bandwidth exhaustion blocking Build/Test account-wide.

Direct push to `main` (bypassing the PR flow) is allowed **only** when all of these hold:
- The change is confined to `.mcx.lock`, `.claude/phases/*.ts`, `.claude/skills/**`, or
  `.github/workflows/*.yml` — never application code (`slidey/`, `SlideyTests/`).
- The normal PR flow is **verifiably** blocked by the exact thing being fixed — not just
  inconvenient or slow. Confirm this before pushing (e.g. reproduce the `mcx phase run`
  error, or see the actual CI failure log), don't assume.
- The push is noted in the sprint plan's Results/Deviations section when the results are
  written, every time — this is a deviation from the standard workflow, not routine
  practice, and needs to stay visible even though it's sometimes necessary.

Never extend this exception to application code, no matter how small or "obviously correct"
the change seems — application code always goes through the normal review + CI flow.

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

## Git LFS checklist (when a sprint adds large binary assets)

If any issue adds a file that should be tracked by Git LFS (CoreML models, large binaries, etc.):

1. Run `git lfs track "<pattern>"` to add the tracking rule.
2. **Immediately** commit `.gitattributes` to the feature branch — not just the worktree.
3. Add `lfs: true` to all `actions/checkout` steps in `.github/workflows/build.yml` at the same time.
4. If the model is >50 MB or sourced from a pre-built binary (not Xcode-compiled), use
   `MLModel(contentsOf:configuration:) + MLDictionaryFeatureProvider` instead of Xcode's
   auto-generated Swift wrapper classes. Auto-generated classes require `coremlc generate`
   to run at build time, which the Xcode project's `PBXFileSystemSynchronizedRootGroup`
   does not trigger for new additions.

Failure mode: CI receives LFS pointer files (43 bytes) instead of the real weights, and the
model either fails to load at runtime or `coremlc` emits a build error for the auto-generated
class that references the corrupt weight file.
