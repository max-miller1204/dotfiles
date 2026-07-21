// Pi provides the Node.js runtime, while this source tree intentionally has no
// local npm dependency tree from which TypeScript could resolve Node's types.
// @ts-expect-error Runtime-provided Node.js built-in.
import { existsSync } from "node:fs";
// @ts-expect-error Runtime-provided Node.js built-in.
import { basename } from "node:path";

declare const process: {
	env: Record<string, string | undefined>;
	argv: string[];
	execPath: string;
};
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
	bashGuardReason,
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

type GuardRuntime = {
	treehouse?: TreehouseContext;
	mode: GuardMode;
	model: string;
	confidenceThreshold: number;
	timeout: number;
	cache: Map<string, Judgment | undefined>;
};

type AutoJudgeRequest = {
	pi: ExtensionAPI;
	command: string;
	reason: string;
	treehouse: TreehouseContext;
	model: string;
	timeout: number;
	ctx: ExtensionContext;
};

type BashGuardRequest = {
	event: ToolCallEvent;
	ctx: ExtensionContext;
	treehouse: TreehouseContext;
	pi: ExtensionAPI;
	runtime: GuardRuntime;
};

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

async function runAutoJudge({
	pi,
	command,
	reason,
	treehouse,
	model,
	timeout,
	ctx,
}: AutoJudgeRequest): Promise<Judgment | undefined> {
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
	try {
		const result = await pi.exec(invocation.command, invocation.args, {
			signal: ctx.signal,
			timeout,
		});
		if (result.code !== 0 || result.killed) return undefined;
		return parseJudgeResponse(result.stdout);
	} catch {
		return undefined;
	}
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

async function guardBashTool({
	event,
	ctx,
	treehouse,
	pi,
	runtime,
}: BashGuardRequest): Promise<BlockResult | undefined> {
	const command = event.input.command;
	if (typeof command !== "string") {
		return block(
			"Treehouse worktree guard rejected a Bash call without a command",
		);
	}

	const protectedPath = treehouse.protectedPaths.find((path) =>
		command.includes(path),
	);
	if (protectedPath) {
		const reason = `command references protected path ${protectedPath}`;
		ctx.ui.notify(`Blocked: ${reason}`, "warning");
		return block(`Treehouse worktree guard blocked command: ${reason}`);
	}

	const reviewReason = bashGuardReason(command, treehouse);
	if (!reviewReason) return undefined;
	if (runtime.mode === "prompt") {
		return confirmCommand(command, reviewReason, ctx);
	}

	let judgment = runtime.cache.get(command);
	if (!runtime.cache.has(command)) {
		ctx.ui.setStatus("worktree-guard", "Guard judging...");
		try {
			judgment = await runAutoJudge({
				pi,
				command,
				reason: reviewReason,
				treehouse,
				model: runtime.model,
				timeout: runtime.timeout,
				ctx,
			});
			runtime.cache.set(command, judgment);
		} finally {
			refreshGuardStatus(runtime, ctx);
		}
	}

	const decision = autoDecision(judgment, runtime.confidenceThreshold);
	if (decision === "allow") return undefined;
	if (decision === "deny") {
		const reason = judgment?.reason ?? reviewReason;
		ctx.ui.notify(`Auto-blocked: ${reason}`, "warning");
		return block(`Treehouse auto guard blocked command: ${reason}`);
	}

	const reason = judgment
		? `Auto judge requested confirmation (${judgment.reason})`
		: `Auto judge was unavailable; ${reviewReason}`;
	return confirmCommand(command, reason, ctx);
}

function createGuardRuntime(): GuardRuntime {
	return {
		mode:
			process.env.PI_WORKTREE_GUARD_MODE?.toLowerCase() === "prompt"
				? "prompt"
				: "auto",
		model: process.env.PI_WORKTREE_GUARD_MODEL || DEFAULT_GUARD_MODEL,
		confidenceThreshold: numericEnvironment(
			"PI_WORKTREE_GUARD_CONFIDENCE",
			DEFAULT_CONFIDENCE_THRESHOLD,
			0.5,
			1,
		),
		timeout: numericEnvironment(
			"PI_WORKTREE_GUARD_TIMEOUT_MS",
			DEFAULT_JUDGE_TIMEOUT_MS,
			1000,
			60_000,
		),
		cache: new Map<string, Judgment | undefined>(),
	};
}

function refreshGuardStatus(
	runtime: GuardRuntime,
	ctx: ExtensionContext,
): void {
	if (!runtime.treehouse) return;
	ctx.ui.setStatus(
		"worktree-guard",
		ctx.ui.theme.fg(
			"accent",
			`Guarded:${runtime.mode} ${runtime.treehouse.workspace}`,
		),
	);
}

function startGuardSession(runtime: GuardRuntime, ctx: ExtensionContext): void {
	runtime.treehouse = detectTreehouseContext(ctx.cwd);
	runtime.cache.clear();
	if (!runtime.treehouse) {
		ctx.ui.setStatus("worktree-guard", undefined);
		return;
	}
	refreshGuardStatus(runtime, ctx);
}

function stopGuardSession(runtime: GuardRuntime, ctx: ExtensionContext): void {
	ctx.ui.setStatus("worktree-guard", undefined);
	runtime.treehouse = undefined;
	runtime.cache.clear();
}

function guardToolCall(
	pi: ExtensionAPI,
	runtime: GuardRuntime,
	event: ToolCallEvent,
	ctx: ExtensionContext,
): BlockResult | Promise<BlockResult | undefined> | undefined {
	if (!runtime.treehouse) return undefined;

	const toolName = shortToolName(event.toolName);
	if (toolName === "write" || toolName === "edit") {
		return guardPathTool(event, ctx, runtime.treehouse);
	}
	if (toolName !== "bash") return undefined;
	return guardBashTool({
		event,
		ctx,
		treehouse: runtime.treehouse,
		pi,
		runtime,
	});
}

function guardArgumentCompletions(prefix: string) {
	return ["auto", "prompt", "status"].flatMap((value) =>
		value.startsWith(prefix) ? [{ value, label: value }] : [],
	);
}

function handleGuardCommand(
	runtime: GuardRuntime,
	args: string,
	ctx: ExtensionCommandContext,
): void {
	const requested = args.trim().toLowerCase();
	if (requested === "auto" || requested === "prompt") {
		runtime.mode = requested;
		runtime.cache.clear();
		refreshGuardStatus(runtime, ctx);
		ctx.ui.notify(`Treehouse worktree guard mode: ${runtime.mode}`, "info");
		return;
	}
	if (requested && requested !== "status") {
		ctx.ui.notify("Usage: /worktree-guard [auto|prompt|status]", "warning");
		return;
	}
	if (!runtime.treehouse) {
		ctx.ui.notify("Worktree guard is inactive outside Treehouse", "info");
		return;
	}

	ctx.ui.notify(
		[
			`Worktree guard active (${runtime.treehouse.detectedBy})`,
			`Mode: ${runtime.mode}`,
			`Auto model: ${runtime.model}`,
			`Auto confidence: ${runtime.confidenceThreshold}`,
			`Writable workspace: ${runtime.treehouse.workspace}`,
			`Writable temporary directory: ${runtime.treehouse.temporaryDirectory}`,
			`Protected paths: ${runtime.treehouse.protectedPaths.join(", ") || "(none discovered)"}`,
		].join("\n"),
		"info",
	);
}

export default function worktreeGuard(pi: ExtensionAPI): void {
	const runtime = createGuardRuntime();

	pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
		startGuardSession(runtime, ctx);
	});
	pi.on("session_shutdown", (_event: unknown, ctx: ExtensionContext) => {
		stopGuardSession(runtime, ctx);
	});
	pi.on("tool_call", (event: ToolCallEvent, ctx: ExtensionContext) =>
		guardToolCall(pi, runtime, event, ctx),
	);
	pi.registerCommand("worktree-guard", {
		description: "Show status or switch Treehouse guard mode: auto | prompt",
		getArgumentCompletions: guardArgumentCompletions,
		handler: (args: string, ctx: ExtensionCommandContext) => {
			handleGuardCommand(runtime, args, ctx);
		},
	});
}
