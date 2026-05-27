# Sprint Retro

Write the diary, audit memory, propose skill improvements, merge the sprint PR, tag the release.

## 1. Write the diary entry

Create `.claude/diary/yyyyMMdd.N.md` (N = sprint number):

```markdown
# Sprint N — [date]

## What was done
[bullet list of shipped issues]

## What worked
[approaches that produced clean results]

## What didn't
[failures, surprises, manual interventions needed]

## Patterns established
[anything worth baking into the sprint skill or CLAUDE.md]

## Stats
- Issues shipped: N / planned
- PRs merged: N
- Sessions spawned: N
- Total cost: ~$X
- Wall time: Xh Xm
- CI pass rate: N/N builds green
```

## 2. Sweep uncommitted memory updates

Memory files get written in whichever checkout the orchestrator ran in (typically main,
not the sprint worktree). Don't let them leak unpushed:

```bash
git -C /Users/joe/Projects/xCode/slidey status -- .claude/memory/
```

If any memory files are modified or new, copy them into the sprint worktree and stage them:

```bash
cp /Users/joe/Projects/xCode/slidey/.claude/memory/* \
   /Users/joe/Projects/xCode/slidey/.claude/worktrees/sprint-N/.claude/memory/
```

## 3. Audit memory for staleness

```bash
mcx memory audit --json
```

For each candidate marked stale: verify whether it's still accurate by checking the
current source. If stale, delete it. If still accurate, update the description.

## 4. Promote repeated memories into skill text

If any memory was applied in 2+ sprints in a row, copy its rule + **Why:** + **How to apply:**
into the most relevant `references/*.md` file. Skill-text rules apply without memory
being loaded; they're more reliable.

## 5. Propose skill improvements

Every retro should propose at least one concrete change to the sprint skill files:
- A rule that would have prevented a problem
- A command that was wrong or missing
- A phase that needs adjustment based on what actually happened

Write the proposals. Joe decides which to apply. Apply approved ones now.

## 6. Commit diary + memory to sprint branch

```bash
cd .claude/worktrees/sprint-N
git add .claude/diary/ .claude/memory/ .claude/skills/sprint/
git commit -m "Sprint N: retro + diary"
git push
```

## 7. Merge the sprint PR

Convert draft → ready and arm auto-merge:

```bash
gh pr ready <sprint-pr-number>
mcx pr merge <sprint-pr-number> --squash --delete-branch
```

Poll until confirmed merged:

```bash
gh pr view <sprint-pr-number> --json state,mergedAt \
  -q '"state=\(.state) mergedAt=\(.mergedAt)"'
# Wait for: state=MERGED mergedAt=<iso-timestamp>
```

## 8. Tag the release

After the sprint PR merges, tag at the merged sha:

```bash
git fetch origin main
git tag v1.1.0 origin/main
git push origin v1.1.0
```

## 9. Clean up

```bash
# Remove sprint sentinel
rm -f .claude/sprints/.active

# Remove sprint worktree (already merged)
git worktree remove .claude/worktrees/sprint-N

# Confirm
git worktree list
mcx claude ls   # expect no sprint sessions
```
