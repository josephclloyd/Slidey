/**
 * Phase: repair — fix review findings in the existing impl worktree.
 *
 * Spawns in the existing worktree (not a new one) so the impl session's
 * uncommitted context is preserved. Max 2 repair rounds; on round 3 → needs-attention.
 *
 * After repair, transitions back to review for a second pass.
 */
import { defineAlias, z } from "mcp-cli";

defineAlias({
  name: "phase-repair",
  description: "Sprint phase: fix review findings for a Slidey PR.",
  input: z.object({}),
  output: z.object({
    action: z.enum(["spawn", "in-flight", "goto"]),
    command: z.array(z.string()).optional(),
    allowTools: z.array(z.string()).optional(),
    prompt: z.string().optional(),
    target: z.enum(["needs-attention"]).optional(),
    reason: z.string().optional(),
    sessionId: z.string().optional(),
  }),
  fn: async (_input, ctx) => {
    const work = ctx.workItem;
    if (!work) throw new Error("phase-repair requires a work item");

    const existing = await ctx.state.get<string>("repair_session_id");
    if (existing) {
      return { action: "in-flight" as const, command: [], allowTools: [], prompt: "", sessionId: existing };
    }

    const repairRound = ((await ctx.state.get<number>("repair_round")) ?? 0) + 1;
    if (repairRound > 2) {
      return {
        action: "goto" as const,
        target: "needs-attention" as const,
        reason: `Exceeded max repair rounds (${repairRound - 1})`,
      };
    }
    await ctx.state.set("repair_round", repairRound);

    const worktreePath = await ctx.state.get<string>("worktree_path");
    const prNumber = work.prNumber;
    if (!prNumber) {
      return { action: "goto" as const, target: "needs-attention" as const, reason: "No PR number — cannot repair" };
    }

    // Use worktree if available; fall back to main checkout.
    const cwd = worktreePath ?? "/Users/joe/Projects/xCode/slidey";

    const allowTools = ["Read", "Glob", "Grep", "Write", "Edit", "Bash"];
    const prompt = [
      `Repair PR #${prNumber} for Slidey issue #${work.issueNumber} based on review findings.`,
      ``,
      `1. Read all review comments:`,
      `   gh pr view ${prNumber} --comments`,
      `   gh api repos/josephclloyd/Slidey/pulls/${prNumber}/comments`,
      `   gh api repos/josephclloyd/Slidey/pulls/${prNumber}/reviews`,
      ``,
      `2. Address every finding. For each fix, note the finding you're addressing.`,
      ``,
      `3. Verify the build still passes:`,
      `   xcodebuild -scheme Slidey -project Slidey.xcodeproj build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`,
      ``,
      `4. Commit and push:`,
      `   git add -A`,
      `   git commit -m "Address review findings for #${work.issueNumber}"`,
      `   git push`,
      ``,
      `5. Reply to each review comment on the PR citing the fix commit.`,
      ``,
      `Do not close the PR or merge — the orchestrator handles that.`,
    ].join("\n");

    const command = [
      "mcx", "claude", "spawn",
      "--model", "opus",
      "--cwd", cwd,
      "-t", prompt,
      "--allow", ...allowTools,
    ];

    await ctx.state.set("repair_session_id", `pending:${Date.now()}`);
    // Clear review session ID so next review gets a fresh session.
    await ctx.state.delete("review_session_id");

    return {
      action: "spawn" as const,
      command,
      allowTools,
      prompt,
    };
  },
});
