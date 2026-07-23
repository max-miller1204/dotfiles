#!/usr/bin/env node

import assert from "node:assert/strict";
import {
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	autoDecision,
	buildJudgePrompt,
	DEFAULT_GUARD_MODEL,
	parseJudgeResponse,
} from "../../dot_pi/agent/extensions/worktree-guard/auto-judge.mjs";
import {
	assessBashCommand,
	bashGuardReason,
	canonicalizePath,
	detectTreehouseContext,
	isWritablePath,
	resolveToolPath,
} from "../../dot_pi/agent/extensions/worktree-guard/policy.mjs";

let settings;
try {
	settings = JSON.parse(
		readFileSync(
			new URL("../../dot_pi/agent/settings.json", import.meta.url),
			"utf8",
		),
	);
} catch (error) {
	throw new Error("could not parse dot_pi/agent/settings.json", {
		cause: error,
	});
}
assert.ok(
	settings.enabledModels.includes(DEFAULT_GUARD_MODEL),
	`auto-judge model must remain enabled: ${DEFAULT_GUARD_MODEL}`,
);

const guardIndex = readFileSync(
	new URL(
		"../../dot_pi/agent/extensions/worktree-guard/index.ts",
		import.meta.url,
	),
	"utf8",
);
assert.match(
	guardIndex,
	/\bbashGuardReason\b/,
	"extension must use the reload-compatible policy API",
);
assert.doesNotMatch(
	guardIndex,
	/\bassessBashCommand\b/,
	"extension must not depend on policy exports added after initial load",
);

// macOS resolves the per-user temporary directory through the /var symlink, so
// keep a raw and a canonical spelling of the same fixture. Assertions that
// compare against canonical paths must hold for commands written either way.
const rawFixture = mkdtempSync(join(tmpdir(), "worktree-guard-"));
const fixture = canonicalizePath(rawFixture);

try {
	const mainSource = join(fixture, "main");
	const commonGit = join(mainSource, ".git");
	const adminDir = join(commonGit, "worktrees", "one");
	const pool = join(fixture, "custom-treehouse-root", "repo-abcd12");
	const workspace = join(pool, "1", "repo");
	const sibling = join(pool, "2", "repo");
	const rawSibling = join(
		rawFixture,
		"custom-treehouse-root",
		"repo-abcd12",
		"2",
		"repo",
	);
	const nested = join(workspace, "src", "nested");

	for (const path of [adminDir, workspace, sibling, nested]) {
		mkdirSync(path, { recursive: true });
	}
	writeFileSync(join(workspace, ".git"), `gitdir: ${adminDir}\n`);
	writeFileSync(join(adminDir, "commondir"), "../..\n");
	writeFileSync(
		join(pool, "treehouse-state.json"),
		JSON.stringify({
			worktrees: [
				{ name: "1", path: workspace },
				{ name: "2", path: sibling },
			],
		}),
	);

	const context = detectTreehouseContext(nested, undefined);
	assert.ok(
		context,
		"state-file detection should activate inside a managed worktree",
	);
	assert.equal(context.workspace, canonicalizePath(workspace));
	assert.equal(context.cwd, canonicalizePath(nested));
	assert.equal(context.temporaryDirectory, canonicalizePath(tmpdir()));
	assert.equal(context.detectedBy, "state");
	assert.deepEqual(
		new Set(context.protectedPaths),
		new Set([canonicalizePath(sibling), canonicalizePath(mainSource)]),
	);

	// A worktree linked to a bare repository has a common dir that IS the
	// repository (no ".git" basename); the guard must protect that directory
	// itself rather than hard-blocking its arbitrarily broad parent.
	const bareRepo = join(fixture, "bare-main.git");
	const bareAdminDir = join(bareRepo, "worktrees", "one");
	const barePool = join(fixture, "custom-treehouse-root", "bare-abcd34");
	const bareWorkspace = join(barePool, "1", "repo");
	const bareSibling = join(barePool, "2", "repo");
	for (const path of [bareAdminDir, bareWorkspace, bareSibling]) {
		mkdirSync(path, { recursive: true });
	}
	writeFileSync(join(bareWorkspace, ".git"), `gitdir: ${bareAdminDir}\n`);
	writeFileSync(join(bareAdminDir, "commondir"), "../..\n");
	writeFileSync(
		join(barePool, "treehouse-state.json"),
		JSON.stringify({
			worktrees: [
				{ name: "1", path: bareWorkspace },
				{ name: "2", path: bareSibling },
			],
		}),
	);
	const bareContext = detectTreehouseContext(bareWorkspace, undefined);
	assert.ok(bareContext, "bare-linked worktree should still activate");
	assert.deepEqual(
		new Set(bareContext.protectedPaths),
		new Set([canonicalizePath(bareSibling), canonicalizePath(bareRepo)]),
		"a bare repository common dir must be protected itself, not its parent",
	);

	// Treehouse supports a repository-relative root, which places the linked
	// live source ABOVE the worktree. Protecting an ancestor would block every
	// write and every command in the assigned worktree.
	const relativeMain = join(fixture, "relative-root");
	const relativeAdminDir = join(relativeMain, ".git", "worktrees", "one");
	const relativePool = join(relativeMain, ".treehouse", "repo-abcd56");
	const relativeWorkspace = join(relativePool, "1", "repo");
	const relativeSibling = join(relativePool, "2", "repo");
	for (const path of [relativeAdminDir, relativeWorkspace, relativeSibling]) {
		mkdirSync(path, { recursive: true });
	}
	writeFileSync(
		join(relativeWorkspace, ".git"),
		`gitdir: ${relativeAdminDir}\n`,
	);
	writeFileSync(join(relativeAdminDir, "commondir"), "../..\n");
	writeFileSync(
		join(relativePool, "treehouse-state.json"),
		JSON.stringify({
			worktrees: [
				{ name: "1", path: relativeWorkspace },
				{ name: "2", path: relativeSibling },
			],
		}),
	);
	const relativeContext = detectTreehouseContext(relativeWorkspace, undefined);
	assert.ok(relativeContext, "repository-relative worktree should activate");
	assert.deepEqual(
		new Set(relativeContext.protectedPaths),
		new Set([canonicalizePath(relativeSibling)]),
		"a live source that contains the workspace must not be protected",
	);
	assert.equal(
		isWritablePath(
			relativeContext,
			resolveToolPath(relativeWorkspace, "src/main.rs"),
		),
		true,
		"a repository-relative worktree must stay writable",
	);
	assert.deepEqual(assessBashCommand("npm test", relativeContext), {
		action: "allow",
	});

	const ordinaryRepo = join(fixture, "ordinary", "repo");
	mkdirSync(ordinaryRepo, { recursive: true });
	assert.equal(
		detectTreehouseContext(ordinaryRepo, undefined),
		undefined,
		"ordinary directories must leave the extension inactive",
	);

	const environmentTree = join(fixture, "environment-tree");
	const environmentCwd = join(environmentTree, "project", "src");
	mkdirSync(environmentCwd, { recursive: true });
	const environmentContext = detectTreehouseContext(
		environmentCwd,
		environmentTree,
	);
	assert.ok(
		environmentContext,
		"TREEHOUSE_DIR should activate without a state file",
	);
	assert.equal(environmentContext.workspace, canonicalizePath(environmentTree));
	assert.equal(environmentContext.detectedBy, "environment");

	const isolatedTemporaryDirectory = join(fixture, "agent-temporary-files");
	mkdirSync(isolatedTemporaryDirectory);
	const policyContext = {
		...context,
		temporaryDirectory: canonicalizePath(isolatedTemporaryDirectory),
	};

	const inTreeTarget = resolveToolPath(workspace, "new/deep/file.txt");
	assert.equal(isWritablePath(policyContext, inTreeTarget), true);
	assert.equal(
		isWritablePath(
			policyContext,
			resolveToolPath(
				workspace,
				join(isolatedTemporaryDirectory, "scratch.txt"),
			),
		),
		true,
		"the canonical OS temporary directory should be writable",
	);
	assert.equal(
		isWritablePath(policyContext, resolveToolPath(workspace, ordinaryRepo)),
		false,
		"arbitrary paths outside the worktree and temporary directory stay blocked",
	);

	// pi resolves a file:// URL through fileURLToPath before writing, so the
	// guard must resolve it the same way instead of joining it under the tree.
	assert.equal(
		resolveToolPath(workspace, `file://${sibling}/planted.txt`),
		join(canonicalizePath(sibling), "planted.txt"),
		"file:// paths must resolve exactly as pi resolves them",
	);
	assert.equal(
		isWritablePath(
			policyContext,
			resolveToolPath(workspace, `file://${sibling}/planted.txt`),
		),
		false,
		"a file:// URL must not bypass the write boundary",
	);
	assert.equal(
		isWritablePath(
			policyContext,
			resolveToolPath(workspace, `file://${workspace}/allowed.txt`),
		),
		true,
		"an in-tree file:// URL stays writable",
	);

	const workspaceEscapeLink = join(workspace, "escape");
	symlinkSync(sibling, workspaceEscapeLink, "dir");
	assert.equal(
		isWritablePath(
			policyContext,
			resolveToolPath(workspace, "escape/new-file.txt"),
		),
		false,
		"worktree symlinks must not escape into a protected path",
	);

	// A symlink whose target does not exist yet still decides where the write
	// lands, so canonicalization must follow it rather than stop at the link.
	const danglingEscapeLink = join(workspace, "pending");
	symlinkSync(join(sibling, "not-created-yet.txt"), danglingEscapeLink, "file");
	assert.equal(
		resolveToolPath(workspace, "pending"),
		join(canonicalizePath(sibling), "not-created-yet.txt"),
		"a dangling symlink must canonicalize to its target",
	);
	assert.equal(
		isWritablePath(policyContext, resolveToolPath(workspace, "pending")),
		false,
		"a dangling symlink must not escape into a protected path",
	);

	const temporaryEscapeLink = join(isolatedTemporaryDirectory, "escape");
	symlinkSync(sibling, temporaryEscapeLink, "dir");
	assert.equal(
		isWritablePath(
			policyContext,
			resolveToolPath(workspace, join(temporaryEscapeLink, "new-file.txt")),
		),
		false,
		"temporary-directory symlinks must not escape into a protected path",
	);
	assert.equal(
		isWritablePath(policyContext, resolveToolPath(workspace, "../outside.txt")),
		false,
	);

	assert.equal(bashGuardReason("git status --short", context), undefined);
	assert.equal(bashGuardReason("npm test", context), undefined);
	assert.deepEqual(assessBashCommand("npm test", context), {
		action: "allow",
	});
	assert.deepEqual(assessBashCommand("git commit -m test", context), {
		action: "review",
		reason:
			"this Git operation can mutate shared worktree metadata or repository state",
	});
	for (const command of [
		"git pull --rebase",
		"git revert HEAD",
		"git restore --staged .",
		"git config user.email x@example.com",
	]) {
		assert.match(
			bashGuardReason(command, context) ?? "",
			/Git operation/,
			`shared-metadata mutation must be reviewed: ${command}`,
		);
	}
	assert.match(
		bashGuardReason(`git -C ${mainSource} status`, context) ?? "",
		/protected path/,
	);
	assert.deepEqual(
		assessBashCommand(`printf data > ${sibling}/file`, context),
		{
			action: "block",
			reason: `command references protected path ${canonicalizePath(sibling)}`,
		},
	);
	// The same reference written through the platform's non-canonical spelling
	// (macOS /var vs /private/var) must be blocked identically.
	assert.deepEqual(
		assessBashCommand(`printf data > ${rawSibling}/file`, context),
		{
			action: "block",
			reason: `command references protected path ${canonicalizePath(sibling)}`,
		},
	);
	// Traversal spellings that never contain the canonical protected path.
	assert.deepEqual(
		assessBashCommand(`cat ${workspace}/../../2/repo/secret`, context),
		{
			action: "block",
			reason: `command references protected path ${canonicalizePath(sibling)}`,
		},
	);
	assert.deepEqual(assessBashCommand("cat ../../2/repo/secret", context), {
		action: "block",
		reason: `command references protected path ${canonicalizePath(sibling)}`,
	});
	assert.deepEqual(
		assessBashCommand(`chezmoi apply --source=${mainSource}`, context),
		{
			action: "block",
			reason: `command references protected path ${canonicalizePath(mainSource)}`,
		},
	);
	assert.match(bashGuardReason("chezmoi apply", context) ?? "", /chezmoi/);
	assert.match(
		bashGuardReason("git commit -m test", context) ?? "",
		/Git operation/,
	);
	assert.match(
		bashGuardReason("rm -rf ../other", context) ?? "",
		/recursive removal/,
	);
	assert.match(
		bashGuardReason("rm -f -r /tmp/scratch", context) ?? "",
		/recursive removal/,
	);
	assert.match(
		bashGuardReason("rm -v --recursive /tmp/scratch", context) ?? "",
		/recursive removal/,
	);
	assert.match(
		bashGuardReason("rm /tmp/scratch -rf", context) ?? "",
		/recursive removal/,
	);
	assert.equal(bashGuardReason("rm -f stale.txt", context), undefined);
	assert.equal(
		bashGuardReason("rm stale.txt && npm run build", context),
		undefined,
	);
	const traversals = ["cd ..; make install", "cd .. && npm publish", "cd .."];
	for (const command of traversals) {
		assert.match(
			bashGuardReason(command, context) ?? "",
			/traversal/,
			`parent-directory escape must be reviewed: ${command}`,
		);
	}

	const judgePrompt = JSON.parse(
		buildJudgePrompt("git commit -m test", "git mutation", context),
	);
	assert.equal(judgePrompt.command, "git commit -m test");
	assert.equal(judgePrompt.workspace, canonicalizePath(workspace));
	assert.equal(
		judgePrompt.cwd,
		canonicalizePath(nested),
		"the judge must see the real session cwd, not the workspace root",
	);
	assert.deepEqual(
		new Set(judgePrompt.protectedPaths),
		new Set([canonicalizePath(sibling), canonicalizePath(mainSource)]),
	);

	const allowJudgment = parseJudgeResponse(
		JSON.stringify({
			verdict: "allow",
			confidence: 0.99,
			reason: "targets only the assigned worktree",
			affectedPaths: [canonicalizePath(workspace)],
		}),
	);
	assert.ok(allowJudgment);
	assert.equal(autoDecision(allowJudgment), "allow");
	assert.equal(autoDecision(allowJudgment, undefined, context), "allow");
	assert.equal(autoDecision({ ...allowJudgment, confidence: 0.8 }), "ask");

	// A confident allow whose own affectedPaths name a protected path must not
	// run: that one field can be checked against the boundary mechanically.
	const selfContradictingJudgment = parseJudgeResponse(
		JSON.stringify({
			verdict: "allow",
			confidence: 0.99,
			reason: "claims to stay inside the worktree",
			affectedPaths: [join(sibling, "file.txt")],
		}),
	);
	assert.ok(selfContradictingJudgment);
	assert.equal(
		autoDecision(selfContradictingJudgment, undefined, context),
		"ask",
	);

	assert.equal(
		parseJudgeResponse('```json\n{"verdict":"allow"}\n```'),
		undefined,
	);
	assert.equal(
		parseJudgeResponse(
			JSON.stringify({
				verdict: "allow",
				confidence: 2,
				reason: "invalid confidence",
				affectedPaths: [],
			}),
		),
		undefined,
	);

	process.stdout.write(
		"Treehouse worktree guard policy and auto-judge tests passed\n",
	);
} finally {
	rmSync(rawFixture, { recursive: true, force: true });
}
