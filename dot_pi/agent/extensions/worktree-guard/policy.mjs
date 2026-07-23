import {
	existsSync,
	lstatSync,
	readFileSync,
	readlinkSync,
	realpathSync,
} from "node:fs";
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
import { fileURLToPath } from "node:url";

const TREEHOUSE_STATE_FILE = "treehouse-state.json";
const MAX_SYMLINK_DEPTH = 32;
const FILE_URL_PATTERN = /^file:\/\//;
// Split on shell word boundaries, so `--source=/x` yields its operand.
const COMMAND_TOKEN_PATTERN = /[^\s"'`;|&<>()=,]+/g;

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
			/\bgit\s+(?:add|commit|switch|checkout|restore|reset|clean|worktree|branch|merge|rebase|cherry-pick|revert|stash|tag|push|pull|config)\b/i,
		reason:
			"this Git operation can mutate shared worktree metadata or repository state",
	},
	{
		pattern: /\bsudo\b/i,
		reason: "sudo escapes the worktree's user-level write policy",
	},
	{
		pattern:
			/\brm\s+(?:[^\s;&|<>()]+\s+)*(?:-[^\s]*r[^\s]*|--recursive)(?:\s|$)/i,
		reason: "recursive removal can affect paths outside this worktree",
	},
	{
		pattern: /(?:^|[\s"'=(])\.\.(?=$|[\s/;&|)"'`])/,
		reason: "parent-directory traversal can escape this worktree",
	},
];

function pathEntryExists(path) {
	try {
		lstatSync(path);
		return true;
	} catch {
		return false;
	}
}

export function canonicalizePath(path, depth = 0) {
	const absolute = resolve(path);
	let existing = absolute;

	// lstat rather than exists: a dangling symlink is a real directory entry
	// whose own target still decides where a write lands.
	while (!pathEntryExists(existing)) {
		const parent = dirname(existing);
		if (parent === existing) {
			return absolute;
		}
		existing = parent;
	}

	const suffix = relative(existing, absolute);
	try {
		return resolve(realpathSync(existing), suffix);
	} catch {
		if (depth >= MAX_SYMLINK_DEPTH) return absolute;
		try {
			const target = resolve(dirname(existing), readlinkSync(existing));
			return resolve(canonicalizePath(target, depth + 1), suffix);
		} catch {
			return absolute;
		}
	}
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

// Mirrors pi's own tool path normalization: strip an `@` mention prefix, honor
// a file:// URL, then expand `~/`. A branch missing here checks a different
// path than the one pi writes.
function expandToolPath(workspace, inputPath, home) {
	if (FILE_URL_PATTERN.test(inputPath)) {
		try {
			return fileURLToPath(inputPath);
		} catch {
			return resolve(workspace, inputPath);
		}
	}
	if (inputPath.startsWith("~/") && home) {
		return resolve(home, inputPath.slice(2));
	}
	return resolve(workspace, inputPath);
}

export function resolveToolPath(workspace, inputPath, home = process.env.HOME) {
	const stripped = inputPath.startsWith("@") ? inputPath.slice(1) : inputPath;
	return canonicalizePath(expandToolPath(workspace, stripped, home));
}

// Canonicalize every path-shaped operand so a non-canonical spelling of a
// protected path - `../2/repo`, or /var vs /private/var on macOS - cannot slip
// past a raw substring comparison.
export function protectedPathReference(command, context) {
	for (const token of command.match(COMMAND_TOKEN_PATTERN) ?? []) {
		if (!token.includes("/")) continue;
		const target = resolveToolPath(context.workspace, token);
		const referenced = context.protectedPaths.find((protectedPath) =>
			isPathInside(protectedPath, target),
		);
		if (referenced) return referenced;
	}
	return context.protectedPaths.find((protectedPath) =>
		command.includes(protectedPath),
	);
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

	const candidates = entries
		.map((entry) => canonicalizePath(entry.path))
		.filter((entryPath) => entryPath !== workspace);
	const mainSource = linkedMainSource(workspace);
	if (mainSource) candidates.push(mainSource);

	// A candidate that contains the workspace would block every write and every
	// command in the assigned worktree, and one inside it would carve a hole out
	// of the writable tree. Treehouse supports a repository-relative root, which
	// puts the linked live source directly above the worktree.
	const protectedPaths = candidates.filter(
		(candidate) =>
			!isPathInside(workspace, candidate) &&
			!isPathInside(candidate, workspace),
	);

	return {
		workspace,
		cwd: canonicalCwd,
		temporaryDirectory: canonicalizePath(temporaryDirectory),
		protectedPaths: [...new Set(protectedPaths)],
		detectedBy,
	};
}

export function assessBashCommand(command, context) {
	const protectedPath = protectedPathReference(command, context);
	if (protectedPath) {
		// index.ts recovers this hard-block class from the reason's leading
		// "command references protected path " prefix instead of a second scan;
		// keep this wording stable or update its copy in index.ts in lockstep.
		return {
			action: "block",
			reason: `command references protected path ${protectedPath}`,
		};
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
