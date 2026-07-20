// Pi supplies this package at runtime; the dotfiles repository has no local npm tree.
import type {
	ExtensionAPI,
	ExtensionCommandContext,
	ExtensionContext,
	// @ts-expect-error The module is resolved by Pi's extension loader.
} from "@earendil-works/pi-coding-agent";
import {
	bashGuardReason,
	detectTreehouseContext,
	isWritablePath,
	resolveToolPath,
} from "./policy.mjs";

type TreehouseContext = NonNullable<ReturnType<typeof detectTreehouseContext>>;

type ToolCallEvent = {
	toolName: string;
	input: Record<string, unknown>;
};

function shortToolName(toolName: string): string {
	return toolName.split(".").at(-1) ?? toolName;
}

type BlockResult = { block: true; reason: string };

function block(reason: string): BlockResult {
	return { block: true, reason };
}

function guardPathTool(
	event: ToolCallEvent,
	ctx: ExtensionContext,
	treehouse: TreehouseContext,
): BlockResult | undefined {
	const inputPath = event.input.path;
	if (typeof inputPath !== "string" || inputPath.length === 0) {
		return block("Treehouse worktree guard rejected a write without a path");
	}

	const target = resolveToolPath(treehouse.workspace, inputPath);
	if (isWritablePath(treehouse, target)) return undefined;
	ctx.ui.notify(
		`Blocked write outside Treehouse worktree: ${target}`,
		"warning",
	);
	return block(
		`Writes are restricted to ${treehouse.workspace} and ${treehouse.temporaryDirectory}`,
	);
}

async function guardBashTool(
	event: ToolCallEvent,
	ctx: ExtensionContext,
	treehouse: TreehouseContext,
): Promise<BlockResult | undefined> {
	const command = event.input.command;
	if (typeof command !== "string") {
		return block(
			"Treehouse worktree guard rejected a Bash call without a command",
		);
	}

	const reason = bashGuardReason(command, treehouse);
	if (!reason) return undefined;
	if (!ctx.hasUI) {
		return block(`Treehouse worktree guard blocked command: ${reason}`);
	}

	const approved = await ctx.ui.confirm(
		"Treehouse worktree guard",
		`${reason}.\n\nAllow this command?\n\n${command}`,
	);
	if (approved) return undefined;
	return block(`Command rejected by Treehouse worktree guard: ${reason}`);
}

export default function worktreeGuard(pi: ExtensionAPI): void {
	let treehouse: TreehouseContext | undefined;

	pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
		treehouse = detectTreehouseContext(ctx.cwd);
		if (!treehouse) {
			ctx.ui.setStatus("worktree-guard", undefined);
			return;
		}

		ctx.ui.setStatus(
			"worktree-guard",
			ctx.ui.theme.fg("accent", `Guarded: ${treehouse.workspace}`),
		);
	});

	pi.on("session_shutdown", (_event: unknown, ctx: ExtensionContext) => {
		ctx.ui.setStatus("worktree-guard", undefined);
		treehouse = undefined;
	});

	pi.on("tool_call", (event: ToolCallEvent, ctx: ExtensionContext) => {
		if (!treehouse) return undefined;

		const toolName = shortToolName(event.toolName);
		if (toolName === "write" || toolName === "edit") {
			return guardPathTool(event, ctx, treehouse);
		}
		if (toolName === "bash") return guardBashTool(event, ctx, treehouse);
		return undefined;
	});

	pi.registerCommand("worktree-guard", {
		description: "Show Treehouse worktree guard status",
		handler: (_args: string, ctx: ExtensionCommandContext) => {
			if (!treehouse) {
				ctx.ui.notify("Worktree guard is inactive outside Treehouse", "info");
				return;
			}

			ctx.ui.notify(
				[
					`Worktree guard active (${treehouse.detectedBy})`,
					`Writable workspace: ${treehouse.workspace}`,
					`Writable temporary directory: ${treehouse.temporaryDirectory}`,
					`Protected paths: ${treehouse.protectedPaths.join(", ") || "(none discovered)"}`,
				].join("\n"),
				"info",
			);
		},
	});
}
