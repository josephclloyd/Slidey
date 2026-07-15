/**
 * Phase: review — spawn a sonnet session to review the PR.
 *
 * Waits for a PR to exist on the work item's branch before spawning.
 * Max 2 review rounds; on round 3 → needs-attention.
 *
 * Review session posts findings as PR comments and returns a verdict:
 *   clean → goto done
 *   has-issues → goto repair
 *   unresolvable → goto needs-attention
 *
 * Quota-failed retry: if the orchestrator detects a spawned session died instantly
 * (0 tokens/cost, no verdict — a genuine quota failure, not a real review), it should set
 * the "review_round_retry" state key to true (in addition to deleting "review_session_id")
 * before re-running this phase. That signals the next spawn attempt is a retry of the
 * SAME round, not a new one, so the round counter isn't double-charged for infrastructure
 * failures. Hit twice in Sprint 27 before this existed; see run.md's Quota-hit recovery
 * section for the exact orchestrator-side steps.
 */
import { defineAlias, z } from "mcp-cli";

defineAlias({
  name: "phase-review",
  description: "Sprint phase: spawn review session for a Slidey PR.",
  input: z.object({
    timeoutMs: z.number().default(300_000),
  }),
  output: z.object({
    action: z.enum(["spawn", "in-flight", "wait", "goto"]),
    command: z.array(z.string()).optional(),
    allowTools: z.array(z.string()).optional(),
    prompt: z.string().optional(),
    target: z.enum(["repair", "done", "needs-attention"]).optional(),
    reason: z.string().optional(),
    sessionId: z.string().optional(),
    prNumber: z.number().optional(),
  }),
  fn: async (input, ctx) => {
    const work = ctx.workItem;
    if (!work) throw new Error("phase-review requires a work item");

    const existing = await ctx.state.get<string>("review_session_id");
    if (existing) {
      return {
        action: "in-flight" as const,
        command: [],
        allowTools: [],
        prompt: "",
        sessionId: existing,
      };
    }

    const isRetry = (await ctx.state.get<boolean>("review_round_retry")) ?? false;
    const priorRound = (await ctx.state.get<number>("review_round")) ?? 0;
    const reviewRound = isRetry ? priorRound : priorRound + 1;
    if (isRetry) await ctx.state.delete("review_round_retry");
    if (reviewRound > 2) {
      return {
        action: "goto" as const,
        target: "needs-attention" as const,
        reason: `Exceeded max review rounds (${reviewRound - 1})`,
      };
    }

    // Wait for PR to exist
    if (work.prNumber == null) {
      try {
        const event = await ctx.waitForEvent(
          { type: "pr.opened", branch: work.branch ?? undefined },
          { timeoutMs: input.timeoutMs },
        );
        if (!event) {
          return { action: "wait" as const, reason: "Waiting for PR to be opened" };
        }
      } catch {
        return { action: "wait" as const, reason: "Waiting for PR to be opened" };
      }
    }

    const prNumber = work.prNumber;
    if (prNumber == null) {
      return { action: "wait" as const, reason: "PR number not yet set on work item" };
    }

    await ctx.state.set("review_round", reviewRound);

    const allowTools = ["Read", "Glob", "Grep", "Bash"];
    const prompt = [
      `Review PR #${prNumber} for Slidey issue #${work.issueNumber}.`,
      ``,
      `Steps:`,
      `1. Read the PR: gh pr view ${prNumber} --json title,body,files,additions,deletions`,
      `2. Read the diff: gh pr diff ${prNumber}`,
      `3. Read related source files for context`,
      `4. Check all four comment surfaces for any existing feedback:`,
      `   gh pr view ${prNumber} --comments`,
      `   gh api repos/josephclloyd/Slidey/pulls/${prNumber}/comments`,
      `   gh api repos/josephclloyd/Slidey/pulls/${prNumber}/reviews`,
      ``,
      `Review criteria for a macOS SwiftUI app:`,
      `- Does the feature work as described in the issue?`,
      `- Are App Sandbox entitlements respected (no broad filesystem access)?`,
      `- Are new menu commands wired via NotificationCenter (not direct state mutation)?`,
      `- Is per-image session state keyed by URL, not index?`,
      `- No force-unwraps or silent error swallowing?`,
      `- Is the manual test checklist in the PR body specific enough for Joe to follow?`,
      `- Does the PR include tests for new logic? ImageLoader and SlideshowController changes are unit-testable and must have tests. If no tests are present and the logic is testable, flag as has-issues. If the logic is genuinely untestable (pure SwiftUI wiring), the PR description must say so explicitly.`,
      ``,
      `If the PR looks good: post a brief "LGTM" comment on the PR first, then as your`,
      `very last message output exactly one line and nothing else: VERDICT: clean`,
      `If there are issues: post a review comment on the PR describing each issue clearly`,
      `first, then as your very last message output exactly one line and nothing else:`,
      `VERDICT: has-issues`,
      `If there is a fundamental problem that can't be repaired without rethinking the approach:`,
      `Post a comment explaining why first, then as your very last message output exactly`,
      `one line and nothing else: VERDICT: unresolvable`,
      ``,
      `Your final message must be ONLY that one-line verdict token — no summary, no`,
      `recap of findings, nothing else on that line or after it.`,
    ].join("\n");

    const command = [
      "mcx", "claude", "spawn",
      "--model", "sonnet",
      "--cwd", "/Users/joe/Projects/xCode/slidey",
      "-t", prompt,
      "--allow", ...allowTools,
    ];

    await ctx.state.set("review_session_id", `pending:${Date.now()}`);

    return {
      action: "spawn" as const,
      command,
      allowTools,
      prompt,
      prNumber,
    };
  },
});
