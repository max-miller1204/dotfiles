import { existsSync } from "node:fs";
import { basename } from "node:path";
// Pi supplies this package at runtime; the dotfiles repository has no local npm tree.
import type {
	ExtensionAPI,
	ExtensionCommandContext,
	ExtensionContext,
	// @ts-expect-error The module is resolved by Pi's extension loader.
} from "@earendil-works/pi-coding-agent";
import {
	autoDecision,
	buildJudgePrompt,
	DEFAULT_CONFIDENCE_THRESHOLD,
	DEFAULT_GUARD_MODEL,
	DEFAULT_JUDGE_TIMEOUT_MS,
	JUDGE_SYSTEM_PROMPT,
	parseJudgeResponse,
} from "./auto-judge.mjs";
import {
	assessBashCommand,
	detectTreehouseContext,
	isWritablePath,
	resolveToolPath,
} from "./policy.mjs";

type TreehouseContext = NonNullable<ReturnType<typeof detectTreehouseContext>>;
type GuardMode = "auto" | "prompt";

type ToolCallEvent = {
	toolName: string;
	input: Record<string, unknown>;
};

type BlockResult = { block: true; reason: string };
type Judgment = NonNullable<ReturnType<typeof parseJudgeResponse>>;

function shortToolName(toolName: string): string {
	return toolName.split(".").at(-1) ?? toolName;
}

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

function numericEnvironment(
	name: string,
	fallback: number,
	minimum: number,
	maximum: number,
): number {
	const parsed = Number(process.env[name]);
	return Number.isFinite(parsed) && parsed >= minimum && parsed <= maximum
		? parsed
		: fallback;
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
	if (currentScript && !isBunVirtualScript && existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}

	const executable = basename(process.execPath).toLowerCase();
	if (!/^(node|bun)(\.exe)?$/.test(executable)) {
		return { command: process.execPath, args };
	}
	return { command: "pi", args };
}

async function runAutoJudge(
	pi: ExtensionAPI,
	command: string,
	reason: string,
	treehouse: TreehouseContext,
	model: string,
	timeout: number,
	ctx: ExtensionContext,
): Promise<Judgment | undefined> {
	const args = [
		"--mode",
		"text",
		"--print",
		"--no-session",
		"--no-tools",
		"--no-extensions",
		"--no-skills",
		"--no-prompt-templates",
		"--no-context-files",
		"--no-themes",
		"--model",
		model,
		"--thinking",
		"off",
		"--system-prompt",
		JUDGE_SYSTEM_PROMPT,
		buildJudgePrompt(command, reason, treehouse),
	];
	const invocation = getPiInvocation(args);
	const result = await pi.exec(invocation.command, invocation.args, {
		signal: ctx.signal,
		timeout,
	});
	if (result.code !== 0 || result.killed) return undefined;
	return parseJudgeResponse(result.stdout);
}

async function confirmCommand(
	command: string,
	reason: string,
	ctx: ExtensionContext,
): Promise<BlockResult | undefined> {
	if (!ctx.hasUI) {
		return block(`Treehouse worktree guard blocked command: ${reason}`);
	}
	const approved = await ctx.ui.confirm(
		"Treehouse worktree guard",
		`${reason}.\n\nAllow this command?\n\n${command}`,
	);
	return approved
		? undefined
		: block(`Command rejected by Treehouse worktree guard: ${reason}`);
}

async function guardBashTool(
	event: ToolCallEvent,
	ctx: ExtensionContext,
	treehouse: TreehouseContext,
	pi: ExtensionAPI,
	mode: GuardMode,
	model: string,
	confidenceThreshold: number,
	timeout: number,
	cache: Map<string, Judgment | undefined>,
	refreshStatus: () => void,
): Promise<BlockResult | undefined> {
	const command = event.input.command;
	if (typeof command !== "string") {
		return block(
			"Treehouse worktree guard rejected a Bash call without a command",
		);
	}

	const assessment = assessBashCommand(command, treehouse);
	if (assessment.action === "allow") return undefined;
	if (assessment.action === "block") {
		ctx.ui.notify(`Blocked: ${assessment.reason}`, "warning");
		return block(`Treehouse worktree guard blocked command: ${assessment.reason}`);
	}
	const reviewReason = assessment.reason ?? "command requires safety review";
	if (mode === "prompt") {
		return confirmCommand(command, reviewReason, ctx);
	}

	let judgment = cache.get(command);
	if (!cache.has(command)) {
		ctx.ui.setStatus("worktree-guard", "Guard judging...");
		try {
			judgment = await runAutoJudge(
				pi,
				command,
				reviewReason,
				treehouse,
				model,
				timeout,
				ctx,
			);
			cache.set(command, judgment);
		} finally {
			refreshStatus();
		}
	}

	const decision = autoDecision(judgment, confidenceThreshold);
	if (decision === "allow") return undefined;
	if (decision === "deny") {
		const reason = judgment?.reason ?? assessment.reason;
		ctx.ui.notify(`Auto-blocked: ${reason}`, "warning");
		return block(`Treehouse auto guard blocked command: ${reason}`);
	}

	const reason = judgment
		? `Auto judge requested confirmation (${judgment.reason})`
		: `Auto judge was unavailable; ${reviewReason}`;
	return confirmCommand(command, reason, ctx);
}

export default function worktreeGuard(pi: ExtensionAPI): void {
	let treehouse: TreehouseContext | undefined;
	let mode: GuardMode =
		process.env.PI_WORKTREE_GUARD_MODE?.toLowerCase() === "prompt"
			? "prompt"
			: "auto";
	const model = process.env.PI_WORKTREE_GUARD_MODEL || DEFAULT_GUARD_MODEL;
	const confidenceThreshold = numericEnvironment(
		"PI_WORKTREE_GUARD_CONFIDENCE",
		DEFAULT_CONFIDENCE_THRESHOLD,
		0.5,
		1,
	);
	const timeout = numericEnvironment(
		"PI_WORKTREE_GUARD_TIMEOUT_MS",
		DEFAULT_JUDGE_TIMEOUT_MS,
		1000,
		60_000,
	);
	const cache = new Map<string, Judgment | undefined>();

	const refreshStatus = (ctx?: ExtensionContext) => {
		if (!ctx || !treehouse) return;
		ctx.ui.setStatus(
			"worktree-guard",
			ctx.ui.theme.fg(
				"accent",
				`Guarded:${mode} ${treehouse.workspace}`,
			),
		);
	};

	pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
		treehouse = detectTreehouseContext(ctx.cwd);
		cache.clear();
		if (!treehouse) {
			ctx.ui.setStatus("worktree-guard", undefined);
			return;
		}
		refreshStatus(ctx);
	});

	pi.on("session_shutdown", (_event: unknown, ctx: ExtensionContext) => {
		ctx.ui.setStatus("worktree-guard", undefined);
		treehouse = undefined;
		cache.clear();
	});

	pi.on("tool_call", (event: ToolCallEvent, ctx: ExtensionContext) => {
		if (!treehouse) return undefined;

		const toolName = shortToolName(event.toolName);
		if (toolName === "write" || toolName === "edit") {
			return guardPathTool(event, ctx, treehouse);
		}
		if (toolName === "bash") {
			return guardBashTool(
				event,
				ctx,
				treehouse,
				pi,
				mode,
				model,
				confidenceThreshold,
				timeout,
				cache,
				() => refreshStatus(ctx),
			);
		}
		return undefined;
	});

	pi.registerCommand("worktree-guard", {
		description: "Show status or switch Treehouse guard mode: auto | prompt",
		getArgumentCompletions: (prefix: string) =>
			["auto", "prompt", "status"]
				.filter((value) => value.startsWith(prefix))
				.map((value) => ({ value, label: value })),
		handler: (args: string, ctx: ExtensionCommandContext) => {
			const requested = args.trim().toLowerCase();
			if (requested === "auto" || requested === "prompt") {
				mode = requested;
				cache.clear();
				refreshStatus(ctx);
				ctx.ui.notify(`Treehouse worktree guard mode: ${mode}`, "info");
				return;
			}
			if (requested && requested !== "status") {
				ctx.ui.notify("Usage: /worktree-guard [auto|prompt|status]", "warning");
				return;
			}
			if (!treehouse) {
				ctx.ui.notify("Worktree guard is inactive outside Treehouse", "info");
				return;
			}

			ctx.ui.notify(
				[
					`Worktree guard active (${treehouse.detectedBy})`,
					`Mode: ${mode}`,
					`Auto model: ${model}`,
					`Auto confidence: ${confidenceThreshold}`,
					`Writable workspace: ${treehouse.workspace}`,
					`Writable temporary directory: ${treehouse.temporaryDirectory}`,
					`Protected paths: ${treehouse.protectedPaths.join(", ") || "(none discovered)"}`,
				].join("\n"),
				"info",
			);
		},
	});
}
