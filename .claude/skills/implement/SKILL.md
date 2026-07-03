---
name: implement
description: >
  Implement a GitHub issue for Slidey. Fetch the issue, read CLAUDE.md, branch,
  code, verify the build, open a PR with description and manual test checklist.
---

# Implement

Implement a single GitHub issue autonomously. Do not ask for clarification unless
the issue is genuinely ambiguous in a way that requires Joe's input.

## Usage

```
/implement <issue-number>
```

## Steps

### 1. Read the project constitution

```bash
cat /Users/joe/Projects/xCode/slidey/CLAUDE.md
```

Pay attention to: build command, architecture, key patterns, gotchas.

### 1a. Check for a sprint plan with design guidance for this issue

```bash
grep -rl "#<N>" /Users/joe/Projects/xCode/slidey/.claude/sprints/sprint-*.md 2>/dev/null
```

If a sprint plan file references this issue, **read it in full**. Sprint plans are
frequently written after deeper research than the raw issue text (data models, exact
function-by-function change lists, key-binding conflict resolutions, file organization
decisions, explicit scope boundaries) and **supersede the issue body wherever they
conflict**. Two sprints running have had impl sessions redo work or get corrected mid-flight
because this step was skipped — check first, not after a build failure or review round.

### 2. Fetch the issue

```bash
gh issue view <N> --json title,body,labels,comments
```

Read everything. If the issue has an investigation comment with a root cause and fix
plan, read it carefully — it is the implementation spec.

### 3. Understand what you're changing

Read the files the issue will touch. For most Slidey issues this means:
- `slidey/SlideshowView.swift` — main UI
- `slidey/SlideyApp.swift` — entry, menus, AppDelegate
- `slidey/ImageLoader.swift` — file loading, scanning
- `slidey/RecentDirectories.swift` — recent dirs persistence

Read widely enough to understand where your change fits.

### 4. Check the current branch

You're running in a git worktree on a branch created by the sprint orchestrator.
Confirm:

```bash
git branch --show-current
git log --oneline -3
```

The branch name should match the issue (e.g., `issue-14-display-sleep`).
If you're somehow on main, stop and file an issue — do not commit to main.

### 5. Implement

Write the feature. Follow the patterns in CLAUDE.md:
- Menu commands fire via `NotificationCenter` → `SlideshowView` subscribes with `.onReceive`
- Per-image state is keyed by `URL`, not index
- App Sandbox is on — new filesystem access needs entitlement changes
- `SlideshowView.swift` is large — add new features near related existing code
- No new external dependencies without Joe's approval

### 6. Verify the build

```bash
cd /Users/joe/Projects/xCode/slidey
xcodebuild -scheme Slidey -project Slidey.xcodeproj build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Do not open a PR if the build fails.** Fix the build error first.
A passing `** BUILD SUCCEEDED **` is the minimum quality gate.

### 7. Commit

```bash
git add <files>
git commit -m "<short description of what this does>

Closes #<N>"
```

Commit message: one line describing what the feature does (not "implement issue #N").
Include `Closes #N` so GitHub auto-closes the issue on merge.

### 8. Push and open the PR

```bash
git push -u origin <branch>
gh pr create \
  --title "<title matching the issue>" \
  --body "$(cat <<'BODY'
## Summary

<what the feature does — one paragraph>

## Implementation

<key implementation decisions, any non-obvious choices>

## Manual test checklist

- [ ] <specific action to test>
- [ ] <edge case>
- [ ] <another action>

## Notes

<anything Joe should know before reviewing>

Closes #<N>
BODY
)"
```

`Closes #<N>` in the PR body is **required** — the orchestrator checks for it. Without it `mcx tracked` shows `prNumber: null` and the review phase blocks.

The manual test checklist replaces automated tests. Be specific — Joe will follow it
when reviewing the PR. "It works" is not a test item; "Press 'd' key in fullscreen and
confirm display doesn't sleep" is.

### 9. Confirm

Output your result:
```
PR: <URL>
Branch: <branch>
Build: SUCCEEDED
Issue: #<N> — <title>
```

Done. The orchestrator takes it from here.

## Do not

- Commit to main
- Open a PR with a failing build
- Skip the manual test checklist
- Add external Swift package dependencies without checking with Joe
- Modify `.claude/skills/`, `CLAUDE.md`, `.mcx.yaml` or `.github/` — those are
  meta-files; changes to them belong in a separate meta-fix, not in a feature PR
