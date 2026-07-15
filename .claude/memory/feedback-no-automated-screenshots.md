---
name: feedback-no-automated-screenshots
description: "Don't attempt automated screencapture/cliclick GUI verification for Slidey — window-position math is unreliable and has leaked personal data twice"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: c6440f1e-232f-4112-89e8-b23af36437cf
---

Do not use `screencapture` (full-screen or computed-region `-R`) to verify Slidey UI
changes, even after confirming Screen Recording permission is granted and computing the
Slidey window's bounds via AppleScript/System Events. Joe verifies UI fixes manually
instead.

**Why:** Attempted this during the object-removal brush/mask alignment bug fix
(2026-07-14, PR #260). `screencapture -x` full-screen and a follow-up `-R0,0,2240,1260`
region capture computed from `System Events`-reported Slidey window bounds — both leaked
Joe's Mail inbox, Finder sidebar, and System Settings windows (visible bank/crypto folder
names, personal correspondence) instead of showing only Slidey. Likely cause: multiple
displays/Spaces mean the on-screen position AppleScript reports for the frontmost-process
window doesn't reliably correspond to what a given screen region or the default display
actually shows. Two independent attempts both failed the same way — this isn't a one-off
fluke, it's a structural gap (no reliable way from this environment to confirm which
physical screen/Space a window is actually rendered on before capturing).

**How to apply:** If a UI change needs visual verification, describe what to check (as a
manual test checklist in the PR body, per this repo's existing convention) and ask Joe to
verify directly rather than attempting `cliclick`/`screencapture` automation. If Joe later
gives explicit per-display/Space targeting info (e.g., "Slidey always opens on my second
monitor, which is display 2"), automated capture could be reconsidered — but default to
manual verification otherwise. See also [[project-sprint17-patterns]] for other
SlideshowView-adjacent gotchas.
