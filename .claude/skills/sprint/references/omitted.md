# Omitted Components

Rationale for things explicitly excluded from the sprint skill.

## Triage phase

**Omitted.** mcp-cli uses triage to classify complexity and route to review vs. QA based
on diff size, coverage changes, and test gaps. Slidey has no test suite and no coverage
ratchet, so there's nothing to measure. All issues go directly to review.

**Re-evaluate if:** the project acquires XCTest UI tests, a coverage threshold, or
issues start varying significantly in complexity.

## QA phase

**Omitted.** mcp-cli's QA phase exists to verify test coverage and run the `am-i-done`
gate before merge. Slidey's only automated gate is `xcodebuild build` (CI). The `done`
phase checks CI directly; there's no separate QA session needed.

**Re-evaluate if:** Slidey adds a test target or a more complex validation gate.

## Multi-provider routing (Copilot, Gemini, Grok)

**Omitted.** Only Claude Code is used for Slidey sessions. The ACP routing complexity
in mcp-cli's phase scripts adds no value here.

**Re-evaluate if:** Joe wants to experiment with other providers for review sessions.

## Screenshots requirement

**Omitted.** mcp-cli checks for screenshot attachments as a PR quality gate. Slidey is
a UI app where screenshots would be valuable, but capturing them automatically from a
headless worker session is not straightforward (requires launching the app, interacting
with it). This is a manual step for Joe during review.

**Re-evaluate if:** Xcode UI testing is added, enabling screenshot capture via XCTest.

## Release gate (block tag on red main-CI)

**Partially implemented.** The review.md checks `gh run list --branch main --limit 3`
before tagging, but does not enforce it as a hard block. For a personal app with one
developer, a yellow advisory is sufficient.

**Re-evaluate if:** Slidey ships to users who could be harmed by a broken build.
