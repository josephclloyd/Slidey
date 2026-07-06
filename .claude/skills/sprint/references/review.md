# Sprint Review

Gather what shipped, write release notes, determine version bump, stage the release commit.

Slidey does not ship versioned artifacts to an app store or package registry — it's a
personal macOS app built and run locally. The "release" here means: tag a version in git
so there's a named anchor for the work, and update the README changelog.

## 1. Check main is green

```bash
gh run list --branch main --limit 3
```

If the **latest** run on `main` is red, do not tag. Surface to Joe and stop.

If an **older** run failed but a later run on top of the same history passed (the failing
test is unrelated to that PR's diff), don't stop to investigate live — that's very likely
CI flakiness, not a regression. Confirm by checking that the next push's run passed the
same test suite cleanly, file an issue for the flaky test (per the "file every problem"
rule), and proceed using the latest run's result. Only investigate live if the failure
recurs on a subsequent run too.

## 2. Gather what shipped

```bash
git fetch origin main
git log $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~50")..origin/main \
  --oneline --no-merges
```

Also pull the sprint plan file for context on what was intended vs. what landed.

## 3. Determine version bump

Slidey uses `MARKETING_VERSION` in `Slidey.xcodeproj/project.pbxproj`. Current convention:

| Change type | Bump |
|-------------|------|
| New user-visible feature | minor (1.x.0) |
| Bug fix or polish | patch (1.0.x) |
| Breaking change to file formats / config | major (x.0.0) |

Read the shipped commits. Most sprints will be minor (new features from the TODO list).

## 4. Write release notes

Format for the sprint plan file's Results section:

```markdown
## Results

Released: v1.1.0 — [date]

### Shipped
- #14 Prevent display sleep while fullscreen (IOKit power assertion)
- #15 Move to Trash + Reveal in Finder
- #16 Auto-open most recent directory at launch

### Needs attention
(issues that didn't land and why)

### Stats
- PRs merged: 3
- Total cost: ~$X
- CI wall time per PR: ~76s
```

## 5. Update MARKETING_VERSION

**First, merge main into the sprint worktree** — feature PRs land on main after the sprint
worktree was branched; the version bump must be applied to the up-to-date `project.pbxproj`:

```bash
cd .claude/worktrees/sprint-N
git merge origin/main --no-edit
```

Then bump all MARKETING_VERSION occurrences (use a version-agnostic pattern so it works
regardless of the current value — the test target may be at a different version than the
app target):

```bash
NEW=1.2   # set to the new version
sed -i '' "s/MARKETING_VERSION = [0-9][0-9.]*;/MARKETING_VERSION = $NEW;/g" \
  Slidey.xcodeproj/project.pbxproj
```

Verify: `grep MARKETING_VERSION Slidey.xcodeproj/project.pbxproj`

## 6. Commit to sprint branch

```bash
cd .claude/worktrees/sprint-N
git add .claude/sprints/sprint-N.md Slidey.xcodeproj/project.pbxproj
git commit -m "Sprint N: results + bump to v1.1.0"
git push
```

The tag happens in retro.md after the sprint PR merges, at the merged sha.
