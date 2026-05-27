# Introspection

Periodic code-first audit cadence: **sprints whose number ends in 7** (7, 17, 27, …).

Slidey is a small codebase (4 files, ~2,200 LOC) so introspection is quick. The main
risk is `SlideshowView.swift` growing into an unmanageable god-class as features accumulate.

## How to run

Spawn one Explore agent with a **trust-nothing** posture — do not trust CLAUDE.md,
README, issue bodies, or PR descriptions. Read only the actual source files.

```bash
mcx claude spawn \
  --model sonnet \
  --cwd /Users/joe/Projects/xCode/slidey \
  -t "Introspection audit of Slidey. Trust only the source files — not README, CLAUDE.md, issues, or PRs. Look for: (1) SlideshowView.swift line count and complexity growth — is it approaching 2000 lines? (2) Duplicated logic that could be extracted to ImageLoader or a helper (3) Notification name strings hardcoded in multiple places (4) Force-unwraps or error-swallowing (5) App Sandbox entitlement scope creep (6) Any TODOs or fixmes in the code (7) Dead code or commented-out blocks (8) Anything that would surprise a new reader. Produce 5-10 file:line-citable findings as a GitHub issue titled 'Sprint N introspection findings'." \
  --allow Read Grep Glob Bash
```

## What to look for in Slidey specifically

- **SlideshowView.swift line count** — it was 1,558 lines at sprint 1. If it approaches
  2,000, propose an extraction sprint (e.g., separate `ZoomController`, `SlideshowController`).
- **Notification name proliferation** — currently 15+ hardcoded string literals like
  `NSNotification.Name("EnhanceImage")`. If > 20, propose a `Notifications.swift` enum.
- **Session-state key sprawl** — per-image state (rotation, enhancement, upscale, smooth)
  is a `[URL: ...]` dictionary in `SlideshowView`. If it grows > 5 keys, propose a
  `ImageSessionState` struct.
- **Entitlement drift** — check `.entitlements` against what the app actually uses.

## Output

The introspection produces a GitHub issue with findings. Those findings become Bucket-1
anchor candidates (tech debt, refactors) in the next sprint's plan.
