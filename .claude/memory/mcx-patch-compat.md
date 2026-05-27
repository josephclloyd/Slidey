---
name: mcx-patch-compat
description: mcx patch-update fails on Claude 2.1.152+ — workaround using 2.1.128 symlink trick
metadata: 
  node_type: memory
  type: project
  originSessionId: 88687a1d-e566-430a-9927-9e60402a92fc
---

`mcx claude patch-update` fails on Claude ≥ 2.1.152 with:
> patch-update failed: strategy host-check-ipv6-loopback-v1 validation failed: expected 4 replacement occurrences, found 3

**Workaround (Sprint 1, 2026-05-27):**
1. Patch with the last known-good version: `mcx claude patch-update --source ~/.local/share/claude/versions/2.1.128`
2. Downgrade active symlink: `ln -sf ~/.local/share/claude/versions/2.1.128 ~/.local/bin/claude`
3. Restart _claude only: `mcx restart _claude && sleep 5`
4. Spawn sessions normally
5. After sessions finish: `ln -sf ~/.local/share/claude/versions/2.1.152 ~/.local/bin/claude`

**Why:** The daemon caches the resolved binary version at `_claude` connect time. Must restart `_claude` (not full daemon) after changing the symlink.

**Fallback when `mcx restart _claude` fails** ("server was disconnected and cannot be auto-reconnected" — observed Sprints 1 and 2):
```bash
pid=$(pgrep -f mcpd | head -1)
kill $pid
sleep 2
mcpd --background
sleep 5
```

**Status:** Filed against mcx 1.12.1. Watch for fix in future mcx release — `patch-update --force` with newer strategy. [[mcx-version-constraint]]
