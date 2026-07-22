import { existsSync, lstatSync, readFileSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import {
	basename,
	dirname,
	isAbsolute,
	join,
	relative,
	resolve,
	sep,
} from "node:path";

const TREEHOUSE_STATE_FILE = "treehouse-state.json";

const SUSPICIOUS_BASH_PATTERNS = [
	{
		pattern: /\bchezmoi\b/i,
		reason: "chezmoi can resolve or mutate the live source directory",
	},
	{
		pattern: /\bgit\s+-C\b/i,
		reason: "git -C can target a repository outside this worktree",
	},
	{
		pattern:
			/\bgit\s+(?:add|commit|switch|checkout|reset|clean|worktree|branch|merge|rebase|cherry-pick|stash|tag|push)\b/i,
		reason:
			"this Git operation can mutate shared worktree metadata or repository state",
	},
	{
		pattern: /\bsudo\b/i,
		reason: "sudo escapes the worktree's user-level write policy",
	},
	{
		pattern: /\brm\s+(?:-[^\s]+\s+)*(?:-[^\s]*r[^\s]*|--recursive)\b/i,
		reason: "recursive removal can affect paths outside this worktree",
	},
	{
		pattern: /(?:^|[\s"'=])\.\.(?:\/|$)/,
		reason: "parent-directory traversal can escape this worktree",
	},
];

export function canonicalizePath(path) {
	const absolute = resolve(path);
	let existing = absolute;

	while (!existsSync(existing)) {
		const parent = dirname(existing);
		if (parent === existing) {
			return absolute;
		}
		existing = parent;
	}

	const suffix = relative(existing, absolute);
	return resolve(realpathSync(existing), suffix);
}

export function isPathInside(root, target) {
	const relativePath = relative(root, target);
	return (
		relativePath === "" ||
		(!relativePath.startsWith(`..${sep}`) &&
			relativePath !== ".." &&
			!isAbsolute(relativePath))
	);
}

export function isWritablePath(context, target) {
	if (
		context.protectedPaths.some((protectedPath) =>
			isPathInside(protectedPath, target),
		)
	) {
		return false;
	}

	return (
		isPathInside(context.workspace, target) ||
		isPathInside(context.temporaryDirectory, target)
	);
}

export function resolveToolPath(workspace, inputPath, home = process.env.HOME) {
	const stripped = inputPath.startsWith("@") ? inputPath.slice(1) : inputPath;
	const expanded =
		stripped.startsWith("~/") && home
			? resolve(home, stripped.slice(2))
			: resolve(workspace, stripped);
	return canonicalizePath(expanded);
}

function readTreehouseState(statePath) {
	try {
		const state = JSON.parse(readFileSync(statePath, "utf8"));
		if (!Array.isArray(state.worktrees)) return undefined;
		return state.worktrees.filter(
			(entry) => entry && typeof entry.path === "string",
		);
	} catch {
		return undefined;
	}
}

function findTreehouseEntries(cwd) {
	let current = canonicalizePath(cwd);

	while (true) {
		const statePath = join(current, TREEHOUSE_STATE_FILE);
		if (existsSync(statePath)) {
			const entries = readTreehouseState(statePath);
			if (entries) return entries;
		}

		const parent = dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

function linkedMainSource(workspace) {
	const dotGit = join(workspace, ".git");
	if (!existsSync(dotGit) || !lstatSync(dotGit).isFile()) return undefined;

	try {
		const match = readFileSync(dotGit, "utf8")
			.trim()
			.match(/^gitdir:\s*(.+)$/);
		if (!match) return undefined;
		const adminDir = canonicalizePath(resolve(workspace, match[1]));
		const commonDirFile = join(adminDir, "commondir");
		if (!existsSync(commonDirFile)) return undefined;
		const commonDir = canonicalizePath(
			resolve(adminDir, readFileSync(commonDirFile, "utf8").trim()),
		);
		// A normal checkout keeps its common dir at <live source>/.git, so the
		// live source tree is one level up. A bare repository IS its common dir;
		// taking its parent would hard-block an arbitrarily broad directory.
		return basename(commonDir) === ".git" ? dirname(commonDir) : commonDir;
	} catch {
		return undefined;
	}
}

export function detectTreehouseContext(
	cwd,
	treehouseDir = process.env.TREEHOUSE_DIR,
	temporaryDirectory = tmpdir(),
) {
	const canonicalCwd = canonicalizePath(cwd);
	const entries = findTreehouseEntries(canonicalCwd) ?? [];
	const stateEntry = entries.find((entry) => {
		const entryPath = canonicalizePath(entry.path);
		return isPathInside(entryPath, canonicalCwd);
	});

	let workspace;
	let detectedBy;
	if (stateEntry) {
		workspace = canonicalizePath(stateEntry.path);
		detectedBy = "state";
	} else if (treehouseDir && existsSync(treehouseDir)) {
		const environmentPath = canonicalizePath(treehouseDir);
		if (isPathInside(environmentPath, canonicalCwd)) {
			workspace = environmentPath;
			detectedBy = "environment";
		}
	}

	if (!workspace) return undefined;

	const protectedPaths = entries
		.map((entry) => canonicalizePath(entry.path))
		.filter((entryPath) => entryPath !== workspace);
	const mainSource = linkedMainSource(workspace);
	if (mainSource && !isPathInside(workspace, mainSource)) {
		protectedPaths.push(mainSource);
	}

	return {
		workspace,
		temporaryDirectory: canonicalizePath(temporaryDirectory),
		protectedPaths: [...new Set(protectedPaths)],
		detectedBy,
	};
}

export function assessBashCommand(command, context) {
	for (const protectedPath of context.protectedPaths) {
		if (command.includes(protectedPath)) {
			return {
				action: "block",
				reason: `command references protected path ${protectedPath}`,
			};
		}
	}

	for (const { pattern, reason } of SUSPICIOUS_BASH_PATTERNS) {
		if (pattern.test(command)) return { action: "review", reason };
	}

	return { action: "allow" };
}

export function bashGuardReason(command, context) {
	const assessment = assessBashCommand(command, context);
	return assessment.action === "allow" ? undefined : assessment.reason;
}
