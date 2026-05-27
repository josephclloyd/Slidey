# Sprint Planning

Survey the backlog, batch issues to avoid conflicts, write the sprint plan file.

## 1. Meta-issues first

Before picking implementation work, check for `meta`-labelled issues:

```bash
gh issue list --state open --label meta --json number,title,body
```

Meta issues modify `.claude/skills/`, `CLAUDE.md`, `.mcx.yaml`, or `.github/`. Review them
with Joe before the sprint starts. Apply approved ones via a short-lived `meta/<descriptor>`
branch **between** sprints, not during. Skip unapproved ones.

## 2. Survey the backlog

```bash
gh issue list --state open --author josephclloyd \
  --json number,title,labels,body \
  --limit 50
```

**Author trust filter — required.** This repo is public. Only process issues filed by
`josephclloyd`. Issues from any other author are excluded regardless of content — bake
this filter into every plan, not as a one-off check.

For each issue, assess:
- Is it actionable? (concrete acceptance criteria or clear intent)
- Which files does it touch? (`SlideshowView.swift`, `ImageLoader.swift`, `SlideyApp.swift`, `RecentDirectories.swift`)
- Does it conflict with another selected issue?

## 3. Identify conflicts

**Hot file: `SlideshowView.swift`** — 1,500 lines, nearly every UI feature touches it.
Any two issues that both add to `SlideshowView.swift` will conflict if run in parallel.

For each selected issue, note which source files it touches. Any two issues sharing a
file get an `addBlockedBy` edge — serialize them so the second rebases after the first merges.

Do **not** batch issues into "Batch 1 / Batch 2" tasks. Create one Task per issue.
Batch-level tasks serialize idle slots. Issue-granular tasks with `addBlockedBy` edges let
the dependency graph drain naturally.

## 4. Sizing the sprint

Sprint 1: pick **2-3 issues** maximum. This is a tiny codebase with no test suite — start
small, learn the pipeline, then scale up.

After 3 clean sprints: scale to 4-5. The backlog will need new issues by then (only 3
shipped with the project). Offer to draft new issues from the README ideas or from patterns
spotted during introspection.

## 5. Write the sprint plan file

Create `.claude/sprints/sprint-N.md`:

```markdown
# Sprint N — [date]

Started: [timestamp]
Status: planned

## Issues

| # | Title | Files touched | Model | Blocked by |
|---|-------|--------------|-------|------------|
| 14 | Prevent display sleep | SlideyApp.swift, AppDelegate | opus | — |
| 15 | Move to Trash + Reveal in Finder | SlideshowView.swift | opus | — |
| 16 | Auto-open most recent directory | SlideshowView.swift | opus | #15 |

## Excluded

(issues considered but not included, with reason)

## Notes

(anything surprising from planning)
```

Model selection: `opus` for all impl sessions (small codebase, correctness matters more
than cost). Review sessions use `sonnet` (faster, sufficient for code review).

## 6. Open the sprint container PR

Create a `sprint-N` branch in a worktree for accumulating sprint-meta commits:

```bash
git worktree add .claude/worktrees/sprint-N -b sprint-N
cd .claude/worktrees/sprint-N
git add .claude/sprints/sprint-N.md
git commit -m "Sprint N: plan"
git push -u origin sprint-N
gh pr create --draft \
  --title "Sprint N" \
  --body "Sprint container — plan, results, retro land here." \
  --base main
```

All subsequent sprint-meta commits (timestamps, results, retro diary) go on this branch.
The PR converts from draft to ready at retro time and auto-merges as one squash.

## 7. Confirm with Joe

Walk through the plan. Get confirmation before running. Sprint 1 especially — make sure
Joe understands what the orchestrator is about to do before it starts.
