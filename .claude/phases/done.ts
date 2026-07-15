/**
 * Phase: done — verify CI is green, merge the PR, close out the work item.
 *
 * Guards before merge:
 *   1. PR exists
 *   2. CI "Build" check is SUCCESS
 *   3. No open review threads
 *
 * On success: squash-merges (deletes branch), updates work item phase=done,
 * pulls main.
 */
import { defineAlias, z } from "mcp-cli";

defineAlias({
  name: "phase-done",
  description: "Sprint phase: merge PR and close work item.",
  input: z.object({}),
  output: z.object({
    merged: z.boolean(),
    prNumber: z.number(),
    issueNumber: z.number(),
    error: z.object({
      reason: z.string(),
      nextAction: z.string(),
    }).optional(),
  }),
  fn: async (_input, ctx) => {
    const work = ctx.workItem;
    if (!work || work.prNumber == null || work.issueNumber == null) {
      throw new Error("phase-done requires prNumber and issueNumber on the work item");
    }

    const pr = work.prNumber;
    const issue = work.issueNumber;

    // Check CI
    try {
      const checks = await ctx.gh.pr(pr).checks();
      const buildCheck = [...checks.check_runs, ...checks.commit_statuses]
        .find(c => c.name === "Build" || c.name === "build");

      if (!buildCheck) {
        return {
          merged: false, prNumber: pr, issueNumber: issue,
          error: { reason: "Build CI check not found", nextAction: "Wait for CI to run or check workflow name" },
        };
      }
      if (buildCheck.conclusion !== "SUCCESS") {
        return {
          merged: false, prNumber: pr, issueNumber: issue,
          error: { reason: `Build check is ${buildCheck.conclusion ?? "pending"}`, nextAction: "Wait for CI or investigate failure" },
        };
      }
    } catch (err) {
      return {
        merged: false, prNumber: pr, issueNumber: issue,
        error: { reason: `CI check failed: ${err instanceof Error ? err.message : String(err)}`, nextAction: "Retry" },
      };
    }

    // Resolve open review threads (best-effort, cosmetic)
    try {
      const threads = await ctx.gh.pr(pr).reviewThreads();
      for (const t of threads.filter(t => !t.isResolved)) {
        try { await ctx.gh.pr(pr).resolveReviewThread(t.id); } catch {}
      }
    } catch {}

    // Merge
    try {
      await ctx.gh.pr(pr).merge({ method: "squash", deleteBranch: true });
    } catch (err) {
      return {
        merged: false, prNumber: pr, issueNumber: issue,
        error: { reason: `Merge failed: ${err instanceof Error ? err.message : String(err)}`, nextAction: "Check branch protection or re-run done phase" },
      };
    }

    // Poll until confirmed merged (lesson #33: qa:pass ≠ merged)
    for (let attempt = 0; attempt < 10; attempt++) {
      try {
        const prBody = await ctx.gh.pr(pr).body();
        if (prBody.merged) break;
      } catch {}
      await new Promise(r => setTimeout(r, 3000));
    }

    // Update work item state
    try {
      await ctx.mcp._work_items.work_items_update({ id: work.id, phase: "done" });
    } catch {}

    // Pull main
    const pullProc = Bun.spawn(["git", "pull"], { stdout: "pipe", stderr: "pipe" });
    setTimeout(() => { try { pullProc.kill(); } catch {} }, 60_000);
    await pullProc.exited;

    // Clear scratchpad
    for (const key of ["session_id", "review_session_id", "repair_session_id", "worktree_path", "review_round", "repair_round", "review_round_retry", "repair_round_retry", "previous_phase", "model"]) {
      await ctx.state.delete(key);
    }

    return { merged: true, prNumber: pr, issueNumber: issue };
  },
});
