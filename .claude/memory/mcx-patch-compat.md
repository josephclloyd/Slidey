---
name: mcx-patch-compat
description: mcx spawn fails when claude not on PATH — use claudeBinary config; patch-update fails on Claude 2.1.152+. Config verified still required as of Sprint 40 (2026-07-30) — pre-flight confirmed claudeBinary=/Users/joe/.mcp-cli/claude-patched/2.1.128.patched, all sessions spawned successfully.
metadata: 
  node_type: memory
  type: project
  originSessionId: 88687a1d-e566-430a-9927-9e60402a92fc
---

## Preferred fix: set claudeBinary in config (Sprint 3, 2026-05-28)

The most reliable approach — no PATH gymnastics needed:

```bash
/Users/joe/.mcp-cli/bin/mcx config set claude-binary /Users/joe/.mcp-cli/claude-patched/2.1.128.patched
```

This writes `claudeBinary` to `~/.mcp-cli/config.json`. The daemon reads it at startup — restart daemon after setting:

```bash
pid=$(pgrep -f mcpd | head -1) && kill $pid && sleep 3
/Users/joe/.mcp-cli/bin/mcpd --background
sleep 10  # wait for all servers to connect
```

The patched binary lives at `/Users/joe/.mcp-cli/claude-patched/2.1.128.patched` and is already built — no re-patching needed unless a new claude version ships.

## patch-update failure context

`mcx claude patch-update` fails on Claude ≥ 2.1.152 with:
> patch-update failed: strategy host-check-ipv6-loopback-v1 validation failed: expected 4 replacement occurrences, found 3

The 2.1.128 source directory (`~/.local/share/claude/versions/2.1.128`) no longer exists — minimum available is 2.1.133, which also fails. The patched binary is preserved at `~/.mcp-cli/claude-patched/2.1.128.patched` and should be reused rather than re-patching.

**Fallback when `mcx restart _claude` fails** ("server was disconnected and cannot be auto-reconnected" — observed Sprints 1, 2, 3):
```bash
pid=$(pgrep -f mcpd | head -1)
kill $pid
sleep 3
/Users/joe/.mcp-cli/bin/mcpd --background
sleep 10
```

**Status:** Filed against mcx 1.12.1. Watch for fix in future mcx release. [[mcx-version-constraint]]

## Session auth failure (Sprint 16, 2026-06-28)

Even with `claudeBinary` set to the patched binary, spawned sessions returned "Not logged in · Please run /login" and could not authenticate. Sprint 16 was implemented directly in the main conversation as a workaround. If mcx session spawning continues to fail, implement directly rather than blocking the sprint.
