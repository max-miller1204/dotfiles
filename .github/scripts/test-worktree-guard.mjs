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

const fixture = mkdtempSync(join(tmpdir(), "worktree-guard-"));

try {
	const mainSource = join(fixture, "main");
	const commonGit = join(mainSource, ".git");
	const adminDir = join(commonGit, "worktrees", "one");
	const pool = join(fixture, "custom-treehouse-root", "repo-abcd12");
	const workspace = join(pool, "1", "repo");
	const sibling = join(pool, "2", "repo");
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
	assert.equal(context.temporaryDirectory, canonicalizePath(tmpdir()));
	assert.equal(context.detectedBy, "state");
	assert.deepEqual(
		new Set(context.protectedPaths),
		new Set([canonicalizePath(sibling), canonicalizePath(mainSource)]),
	);

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
	assert.equal(bashGuardReason("rm -f stale.txt", context), undefined);

	const judgePrompt = JSON.parse(
		buildJudgePrompt("git commit -m test", "git mutation", context),
	);
	assert.equal(judgePrompt.command, "git commit -m test");
	assert.equal(judgePrompt.workspace, canonicalizePath(workspace));
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
	assert.equal(autoDecision({ ...allowJudgment, confidence: 0.8 }), "ask");
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
	rmSync(fixture, { recursive: true, force: true });
}
