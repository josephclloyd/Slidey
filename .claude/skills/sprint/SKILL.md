---
name: sprint
description: >
  Sprint lifecycle for Slidey: plan, run, review, retro. Autonomous issue
  resolution for a macOS SwiftUI app — no test suite, CI is xcodebuild build,
  Claude merges after review clears.
---

# Sprint

Route based on arguments:

| Input | Action |
|-------|--------|
| `/sprint plan` | → Read `references/plan.md` |
| `/sprint` (plan exists) or `/sprint <N>` | → **Auto-chain**: run → review → retro in one session |
| `/sprint run` | → Run-only: read `references/run.md`, stop at wind-down |
| `/sprint <issue-numbers>` | → Run those specific issues only (no auto-chain) |
| `/sprint` (no plan, no issues) | → Offer: "No sprint plan found. Run `/sprint plan` first, or pass issue numbers." |
| `/sprint review` | → Read `references/review.md` |
| `/sprint retro` | → Read `references/retro.md` |

**Why auto-chain:** the post-run context carries valuable signal for the retro. Splitting into separate sessions wastes it and pays a full cache miss.

**Disambiguation `/sprint <N>`:** if `.claude/sprints/sprint-<N>.md` exists, `<N>` is a sprint number → auto-chain. Otherwise treat as an issue number.

## Sprint numbering

```bash
ls .claude/sprints/sprint-*.md 2>/dev/null | sort -t- -k2 -n | tail -1
```

Start at sprint 1. The sprint number threads through plan → run → review → retro.

## Phase graph

Per-phase logic lives in `.mcx.yaml` + `.claude/phases/*.ts`, not in prose.

```
impl → review → done
         ↓
       repair → review (loop, max 2 rounds)
         ↓
    needs-attention
```

Inspect phases: `mcx phase show <name>`. Preview: `mcx phase run <name> --work-item "#N"`.

## Rules (all phases)

- **Never implement directly.** Delegate to spawned sessions.
- **Never implement more than 2 issues in parallel** — `SlideshowView.swift` is a hot file; concurrent edits cause conflicts.
- **Serialize issues that both touch SlideshowView.swift** using `addBlockedBy` edges at plan time.
- **File every problem as an issue.** Unfiled problems are invisible.
- **Use `mcx pr merge` not `gh pr merge --auto`** — handles re-arm after force-push.
- **Verify the merge actually fired** before marking done: poll `gh pr view <N> --json state,mergedAt` until `state == MERGED`.
- **Author trust filter:** only process issues filed by `josephclloyd`.
- **Cost threshold:** if a session exceeds $15, interrupt and file an issue about the work rather than continuing.

## Key references

- `references/plan.md` — survey backlog, batch, write sprint file
- `references/run.md` — pre-flight + orchestrator event loop
- `references/review.md` — release notes, changelog, tagging
- `references/retro.md` — diary, memory audit, skill updates
- `references/mcx-claude.md` — session management commands
- `references/investigations.md` — nerd-snipe gate for unclear bugs
- `references/compaction-survival.md` — recovery after context compaction
- `references/introspection.md` — code-first audits on sprints ending in 7
