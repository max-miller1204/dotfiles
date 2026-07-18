/**
 * Handoff extension - transfer context to a new focused session
 *
 * Instead of compacting (which is lossy), handoff extracts what matters
 * for your next task and creates a new session with a generated prompt.
 *
 * Usage:
 *   /handoff now implement this for teams as well
 *   /handoff execute phase one of the plan
 *   /handoff check other places that need this fix
 *
 * The generated prompt appears as a draft in the editor for review/editing.
 */

import { writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { extname, resolve } from "node:path";
import type { AgentMessage } from "@earendil-works/pi-agent-core";
import { complete, type Message } from "@earendil-works/pi-ai/compat";
import type {
	ExtensionAPI,
	ExtensionCommandContext,
	SessionEntry,
} from "@earendil-works/pi-coding-agent";
import {
	BorderedLoader,
	convertToLlm,
	copyToClipboard,
	serializeConversation,
} from "@earendil-works/pi-coding-agent";

const SYSTEM_PROMPT = `You are a context transfer assistant. Given a conversation history and the user's goal for a new thread, generate a focused prompt that:

1. Summarizes relevant context from the conversation (decisions made, approaches taken, key findings)
2. Lists any relevant files that were discussed or modified
3. Clearly states the next task based on the user's goal
4. Is self-contained - the new thread should be able to proceed without the old conversation

Format your response as a prompt the user can send to start the new thread. Be concise but include all necessary context. Do not include any preamble like "Here's the prompt" - just output the prompt itself.

Example output format:
## Context
We've been working on X. Key decisions:
- Decision 1
- Decision 2

Files involved:
- path/to/file1.ts
- path/to/file2.ts

## Task
[Clear description of what to do next based on user's goal]`;

function entryToMessage(entry: SessionEntry): AgentMessage | undefined {
	if (entry.type === "message") {
		return entry.message;
	}
	if (entry.type === "compaction") {
		return {
			role: "compactionSummary",
			summary: entry.summary,
			tokensBefore: entry.tokensBefore,
			timestamp: new Date(entry.timestamp).getTime(),
		};
	}
	return undefined;
}

function resolveMarkdownPath(input: string, cwd: string): string {
	const requestedPath = input.trim() || "handoff.md";
	const expandedPath = requestedPath.startsWith("~/")
		? resolve(homedir(), requestedPath.slice(2))
		: resolve(cwd, requestedPath);
	return extname(expandedPath).toLowerCase() === ".md"
		? expandedPath
		: `${expandedPath}.md`;
}

async function savePromptAsMarkdown(
	ctx: ExtensionCommandContext,
	prompt: string,
): Promise<void> {
	const requestedPath = await ctx.ui.input("Save handoff prompt", "handoff.md");
	if (requestedPath === undefined) {
		ctx.ui.notify("Cancelled", "info");
		return;
	}

	const markdownPath = resolveMarkdownPath(requestedPath, ctx.cwd);
	try {
		await writeFile(markdownPath, prompt, { encoding: "utf8", flag: "wx" });
	} catch (error: unknown) {
		if ((error as { code?: string }).code !== "EEXIST") {
			const message = error instanceof Error ? error.message : String(error);
			ctx.ui.notify(`Could not save handoff prompt: ${message}`, "error");
			return;
		}

		const overwrite = await ctx.ui.confirm(
			"Overwrite Markdown file?",
			`${markdownPath} already exists.`,
		);
		if (!overwrite) {
			ctx.ui.notify("Cancelled", "info");
			return;
		}

		try {
			await writeFile(markdownPath, prompt, "utf8");
		} catch (overwriteError: unknown) {
			const message =
				overwriteError instanceof Error
					? overwriteError.message
					: String(overwriteError);
			ctx.ui.notify(`Could not save handoff prompt: ${message}`, "error");
			return;
		}
	}

	ctx.ui.notify(`Handoff prompt saved to ${markdownPath}`, "info");
}

async function shouldStartNewSession(
	ctx: ExtensionCommandContext,
	prompt: string,
): Promise<boolean> {
	const action = await ctx.ui.select("Use handoff prompt", [
		"Start a new session",
		"Copy entire prompt to clipboard",
		"Save prompt as Markdown",
	]);

	if (action === undefined) {
		ctx.ui.notify("Cancelled", "info");
		return false;
	}

	if (action === "Copy entire prompt to clipboard") {
		try {
			await copyToClipboard(prompt);
			ctx.ui.notify("Handoff prompt copied to clipboard.", "info");
		} catch (error: unknown) {
			const message = error instanceof Error ? error.message : String(error);
			ctx.ui.notify(`Could not copy handoff prompt: ${message}`, "error");
		}
		return false;
	}

	if (action === "Save prompt as Markdown") {
		await savePromptAsMarkdown(ctx, prompt);
		return false;
	}

	return true;
}

function getHandoffMessages(branch: SessionEntry[]): AgentMessage[] {
	let compactionIndex = -1;
	for (let i = branch.length - 1; i >= 0; i--) {
		if (branch[i].type === "compaction") {
			compactionIndex = i;
			break;
		}
	}
	if (compactionIndex < 0) {
		return branch
			.map(entryToMessage)
			.filter((message) => message !== undefined);
	}

	const compaction = branch[compactionIndex];
	const firstKeptIndex =
		compaction.type === "compaction"
			? branch.findIndex((entry) => entry.id === compaction.firstKeptEntryId)
			: -1;
	const compactedBranch = [
		compaction,
		...(firstKeptIndex >= 0
			? branch.slice(firstKeptIndex, compactionIndex)
			: []),
		...branch.slice(compactionIndex + 1),
	];
	return compactedBranch
		.map(entryToMessage)
		.filter((message) => message !== undefined);
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("handoff", {
		description: "Transfer context to a new focused session",
		handler: async (args, ctx) => {
			if (ctx.mode !== "tui") {
				ctx.ui.notify("handoff requires interactive mode", "error");
				return;
			}

			const model = ctx.model;
			if (!model) {
				ctx.ui.notify("No model selected", "error");
				return;
			}

			const goal = args.trim();
			if (!goal) {
				ctx.ui.notify("Usage: /handoff <goal for new thread>", "error");
				return;
			}

			// Gather conversation context from current branch. If the branch was compacted,
			// include the compaction summary plus entries from firstKeptEntryId onward.
			const messages = getHandoffMessages(ctx.sessionManager.getBranch());

			if (messages.length === 0) {
				ctx.ui.notify("No conversation to hand off", "error");
				return;
			}

			// Convert to LLM format and serialize
			const llmMessages = convertToLlm(messages);
			const conversationText = serializeConversation(llmMessages);
			const currentSessionFile = ctx.sessionManager.getSessionFile();

			// Generate the handoff prompt with loader UI
			let generationError: string | undefined;
			const result = await ctx.ui.custom<string | null>(
				(tui, theme, _kb, done) => {
					const loader = new BorderedLoader(
						tui,
						theme,
						"Generating handoff prompt...",
					);
					let completed = false;
					const finish = (value: string | null) => {
						if (completed) return;
						completed = true;
						done(value);
					};
					loader.onAbort = () => finish(null);

					const doGenerate = async () => {
						const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
						if (!auth.ok || !auth.apiKey) {
							throw new Error(
								auth.ok ? `No API key for ${model.provider}` : auth.error,
							);
						}

						const userMessage: Message = {
							role: "user",
							content: [
								{
									type: "text",
									text: `## Conversation History\n\n${conversationText}\n\n## User's Goal for New Thread\n\n${goal}`,
								},
							],
							timestamp: Date.now(),
						};

						const response = await complete(
							model,
							{ systemPrompt: SYSTEM_PROMPT, messages: [userMessage] },
							{
								apiKey: auth.apiKey,
								headers: auth.headers,
								env: auth.env,
								signal: loader.signal,
							},
						);

						if (response.stopReason === "aborted") return null;

						return response.content
							.flatMap((content) =>
								content.type === "text" ? [content.text] : [],
							)
							.join("\n");
					};

					void doGenerate()
						.then(finish)
						.catch((error: unknown) => {
							generationError =
								error instanceof Error ? error.message : String(error);
							finish(null);
						});

					return loader;
				},
			);

			if (result === null) {
				if (generationError)
					ctx.ui.notify(
						`Handoff generation failed: ${generationError}`,
						"error",
					);
				else ctx.ui.notify("Cancelled", "info");
				return;
			}

			// Let user edit the generated prompt
			const editedPrompt = await ctx.ui.editor("Edit handoff prompt", result);

			if (editedPrompt === undefined) {
				ctx.ui.notify("Cancelled", "info");
				return;
			}

			if (!(await shouldStartNewSession(ctx, editedPrompt))) return;

			// Create new session with parent tracking. Use the replacement-session
			// context for post-switch UI work; the original ctx is stale after a
			// successful session replacement.
			const newSessionResult = await ctx.newSession({
				parentSession: currentSessionFile,
				withSession: (replacementCtx) => {
					replacementCtx.ui.setEditorText(editedPrompt);
					replacementCtx.ui.notify("Handoff ready. Submit when ready.", "info");
					return Promise.resolve();
				},
			});

			if (newSessionResult.cancelled) {
				ctx.ui.notify("New session cancelled", "info");
			}
		},
	});
}
