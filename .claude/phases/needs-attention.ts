/**
 * Phase: needs-attention — terminal. Records why an issue stalled and surfaces it.
 *
 * The orchestrator is responsible for notifying Joe. This handler records
 * the reason in state and updates the work item phase.
 */
import { defineAlias, z } from "mcp-cli";

defineAlias({
  name: "phase-needs-attention",
  description: "Sprint phase: terminal. Record escalation and surface to Joe.",
  input: z.object({
    reason: z.string().default("No reason provided"),
  }),
  output: z.object({
    issueNumber: z.number(),
    prNumber: z.number().optional(),
    reason: z.string(),
    branch: z.string().optional(),
  }),
  fn: async (input, ctx) => {
    const work = ctx.workItem;
    if (!work) throw new Error("phase-needs-attention requires a work item");

    try {
      await ctx.mcp._work_items.work_items_update({ id: work.id, phase: "needs-attention" });
    } catch {}

    // Post a comment on the issue so Joe can see it without checking the daemon
    try {
      const body = [
        `🔴 **Needs attention** — sprint orchestrator could not complete this issue.`,
        ``,
        `**Reason:** ${input.reason}`,
        ``,
        work.prNumber
          ? `PR #${work.prNumber} has the work in progress. Review and reassign or close.`
          : `No PR was opened. The issue needs to be re-planned.`,
      ].join("\n");
      await ctx.gh.issue(work.issueNumber).comment(body);
    } catch {}

    return {
      issueNumber: work.issueNumber,
      prNumber: work.prNumber ?? undefined,
      reason: input.reason,
      branch: work.branch ?? undefined,
    };
  },
});
