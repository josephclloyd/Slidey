/**
 * Phase: impl — spawn an implementation session for a tracked Slidey issue.
 *
 * Idempotent: if session_id is already set, returns "in-flight".
 * Writes a pending sentinel to session_id before returning "spawn" so
 * re-entry returns "in-flight" instead of double-spawning.
 * Orchestrator replaces the sentinel with the real session ID after spawn.
 */
import { defineAlias, z } from "mcp-cli";

defineAlias({
  name: "phase-impl",
  description: "Sprint phase: spawn implementation session for a tracked Slidey issue.",
  input: z.object({
    model: z.enum(["opus", "sonnet"]).default("opus"),
  }),
  output: z.object({
    action: z.enum(["spawn", "in-flight"]),
    command: z.array(z.string()),
    allowTools: z.array(z.string()),
    prompt: z.string(),
    model: z.enum(["opus", "sonnet"]),
    sessionId: z.string().optional(),
  }),
  fn: async (input, ctx) => {
    const work = ctx.workItem;
    if (!work || work.issueNumber == null) {
      throw new Error("phase-impl requires a tracked work item with an issueNumber");
    }

    const existing = await ctx.state.get<string>("session_id");
    if (existing) {
      return {
        action: "in-flight" as const,
        command: [],
        allowTools: [],
        prompt: "",
        model: ((await ctx.state.get<string>("model")) as "opus" | "sonnet") ?? "opus",
        sessionId: existing,
      };
    }

    const model = input.model;
    const allowTools = ["Read", "Glob", "Grep", "Write", "Edit", "Bash"];
    const prompt = `/implement ${work.issueNumber}`;

    const command = [
      "mcx", "claude", "spawn",
      "--worktree",
      "--model", model,
      "--cwd", "/Users/joe/Projects/xCode/slidey",
      "-t", prompt,
      "--allow", ...allowTools,
    ];

    await ctx.state.set("model", model);
    // Pending sentinel: prevents re-spawn on re-entry before the real ID is written.
    await ctx.state.set("session_id", `pending:${Date.now()}`);

    return {
      action: "spawn" as const,
      command,
      allowTools,
      prompt,
      model,
    };
  },
});
