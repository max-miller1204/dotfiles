import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { homedir } from "node:os";
import { relative, resolve, sep } from "node:path";
import { createInterface } from "node:readline";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

type QuotaWindow = {
	usedPercent: number;
	windowMinutes?: number;
};

type SubscriptionQuota = {
	session?: QuotaWindow;
	week?: QuotaWindow;
};

const quotaByProvider = new Map<string, SubscriptionQuota>();
let requestFooterRender: (() => void) | undefined;
let activeCodexServer: ChildProcessWithoutNullStreams | undefined;
let codexQuotaRequested = false;

function parseNumber(value: string | undefined): number | undefined {
	if (value === undefined || value.trim() === "") return undefined;
	const parsed = Number(value);
	return Number.isFinite(parsed) ? parsed : undefined;
}

function parseQuotaWindow(headers: Record<string, string>, name: "primary" | "secondary"): QuotaWindow | undefined {
	const usedPercent = parseNumber(headers[`x-codex-${name}-used-percent`]);
	if (usedPercent === undefined) return undefined;

	return {
		usedPercent,
		windowMinutes: parseNumber(headers[`x-codex-${name}-window-minutes`]),
	};
}

function parseSubscriptionQuota(rawHeaders: Record<string, string>): SubscriptionQuota | undefined {
	const headers = Object.fromEntries(Object.entries(rawHeaders).map(([key, value]) => [key.toLowerCase(), value]));
	const primary = parseQuotaWindow(headers, "primary");
	const secondary = parseQuotaWindow(headers, "secondary");
	if (!primary && !secondary) return undefined;

	if (primary && secondary) {
		const primaryMinutes = primary.windowMinutes ?? 0;
		const secondaryMinutes = secondary.windowMinutes ?? Number.POSITIVE_INFINITY;
		return primaryMinutes <= secondaryMinutes
			? { session: primary, week: secondary }
			: { session: secondary, week: primary };
	}

	return primary ? { session: primary } : { week: secondary };
}

type CodexRateLimitWindow = {
	usedPercent: number;
	windowDurationMins?: number;
};

type CodexRateLimitsResponse = {
	id?: number;
	result?: {
		rateLimits?: {
			primary?: CodexRateLimitWindow | null;
			secondary?: CodexRateLimitWindow | null;
		};
	};
};

function readCodexQuota(): Promise<SubscriptionQuota | undefined> {
	return new Promise((resolveQuota) => {
		const child = spawn("codex", ["app-server"], { stdio: ["pipe", "pipe", "pipe"] });
		activeCodexServer = child;
		const lines = createInterface({ input: child.stdout });
		let settled = false;
		const timeout = setTimeout(() => finish(undefined), 5000);

		function finish(quota: SubscriptionQuota | undefined) {
			if (settled) return;
			settled = true;
			clearTimeout(timeout);
			lines.close();
			child.kill();
			if (activeCodexServer === child) activeCodexServer = undefined;
			resolveQuota(quota);
		}

		child.on("error", () => finish(undefined));
		child.on("exit", () => finish(undefined));
		lines.on("line", (line) => {
			let response: CodexRateLimitsResponse;
			try {
				response = JSON.parse(line) as CodexRateLimitsResponse;
			} catch {
				return;
			}

			if (response.id === 0) {
				child.stdin.write(`${JSON.stringify({ method: "initialized", params: {} })}\n`);
				child.stdin.write(`${JSON.stringify({ method: "account/rateLimits/read", id: 1, params: {} })}\n`);
				return;
			}

			if (response.id !== 1) return;
			const limits = response.result?.rateLimits;
			const toWindow = (window: CodexRateLimitWindow | null | undefined): QuotaWindow | undefined =>
				window
					? { usedPercent: window.usedPercent, windowMinutes: window.windowDurationMins }
					: undefined;
			finish({ session: toWindow(limits?.primary), week: toWindow(limits?.secondary) });
		});

		child.stdin.write(
			`${JSON.stringify({
				method: "initialize",
				id: 0,
				params: { clientInfo: { name: "pi_status_bar", title: "Pi status bar", version: "1.0.0" } },
			})}\n`,
		);
	});
}

function formatCwd(cwd: string): string {
	const home = resolve(homedir());
	const resolvedCwd = resolve(cwd);
	const fromHome = relative(home, resolvedCwd);
	const insideHome = fromHome === "" || (fromHome !== ".." && !fromHome.startsWith(`..${sep}`));
	if (!insideHome) return resolvedCwd;
	return fromHome === "" ? "~" : `~${sep}${fromHome}`;
}

function clampPercent(value: number): number {
	return Math.max(0, Math.min(100, value));
}

function quotaText(label: string, window: QuotaWindow | undefined): string {
	if (!window) return `${label} ?`;
	return `${label} ${Math.round(100 - clampPercent(window.usedPercent))}% left`;
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		codexQuotaRequested = false;
		ctx.ui.setFooter((tui, theme, footerData) => {
			requestFooterRender = () => tui.requestRender();
			const unsubscribeBranch = footerData.onBranchChange(requestFooterRender);

			return {
				dispose() {
					unsubscribeBranch();
					requestFooterRender = undefined;
				},
				invalidate() {},
				render(width: number): string[] {
					const branch = footerData.getGitBranch();
					const location = branch ? `${formatCwd(ctx.cwd)}  git:${branch}` : formatCwd(ctx.cwd);
					const model = ctx.model;
					const effort = model?.reasoning ? pi.getThinkingLevel() || "off" : undefined;
					const modelText = `${model?.id ?? "no-model"}${effort ? ` • ${effort}` : ""}`;

					const left = theme.fg("dim", location);
					const right = theme.fg("dim", modelText);
					const availableLeft = Math.max(0, width - visibleWidth(right) - 2);
					const fittedLeft = truncateToWidth(left, availableLeft, theme.fg("dim", "..."));
					const padding = " ".repeat(Math.max(1, width - visibleWidth(fittedLeft) - visibleWidth(right)));
					const identityLine = truncateToWidth(fittedLeft + padding + right, width, "");

					if (model?.provider === "openai-codex" && !codexQuotaRequested) {
						codexQuotaRequested = true;
						void readCodexQuota().then((quota) => {
							if (!quota) return;
							quotaByProvider.set("openai-codex", quota);
							requestFooterRender?.();
						});
					}

					const usage = ctx.getContextUsage();
					const percent = usage?.percent;
					const percentLabel = percent === null || percent === undefined ? "?" : `${Math.round(percent)}%`;
					const currentQuota = model && ctx.modelRegistry.isUsingOAuth(model) ? quotaByProvider.get(model.provider) : undefined;
					const quota = currentQuota
						? ` • ${quotaText("session", currentQuota.session)} • ${quotaText("week", currentQuota.week)}`
						: model?.provider === "openai-codex" && model && ctx.modelRegistry.isUsingOAuth(model)
							? " • subscription quota pending"
							: "";
					const fixedWidth = visibleWidth(`ctx [] ${percentLabel}${quota}`);
					const barWidth = Math.max(4, Math.min(18, width - fixedWidth));
					const normalizedPercent = percent === null || percent === undefined ? 0 : clampPercent(percent);
					const filled = Math.round((normalizedPercent / 100) * barWidth);
					const color = normalizedPercent >= 90 ? "error" : normalizedPercent >= 70 ? "warning" : "success";
					const bar = theme.fg(color, "█".repeat(filled)) + theme.fg("dim", "░".repeat(barWidth - filled));
					const contextLine = theme.fg("dim", "ctx [") + bar + theme.fg("dim", `] ${percentLabel}${quota}`);

					return [identityLine, truncateToWidth(contextLine, width, theme.fg("dim", "..."))];
				},
			};
		});
	});

	pi.on("after_provider_response", (event, ctx) => {
		const quota = parseSubscriptionQuota(event.headers);
		if (!quota || !ctx.model || !ctx.modelRegistry.isUsingOAuth(ctx.model)) return;
		quotaByProvider.set(ctx.model.provider, quota);
		requestFooterRender?.();
	});

	pi.on("model_select", () => requestFooterRender?.());
	pi.on("thinking_level_select", () => requestFooterRender?.());
	pi.on("session_shutdown", () => {
		activeCodexServer?.kill();
		activeCodexServer = undefined;
	});
}
