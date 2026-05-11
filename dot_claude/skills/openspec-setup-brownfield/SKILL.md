---
name: openspec-setup-brownfield
description: Survey an existing codebase for domain shape, stack, conventions, and CI, then run a bundled brownfield-tightened playbook to initialize OpenSpec with a project-aware config.yaml. Use when adding OpenSpec to a project that already has code, or when the user mentions "brownfield".
---

Brownfield projects already have a stack, conventions, and in-flight work — `openspec/config.yaml` is most useful when it reflects all of that on day one. This skill surveys the codebase first, presents the findings to the user, then runs a bundled brownfield-tightened OpenSpec setup playbook with the survey as input.

## 1. Discovery — codebase survey

Before running the playbook, do a quick survey and hold the findings in context as a scratch note (no file written). Probe for:

- **Domain shape**: source layout (`ls src/` or equivalent). Identify natural domain boundaries that will become subdirectories under `openspec/specs/`.
- **Stack & versions**: language, runtime version, package manager, framework. From `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `flake.nix`, `Dockerfile`, `mise.toml`, `.tool-versions`.
- **Env wrappers**: does every command run inside `nix develop`, `docker compose run`, etc.? Matters for CI and for AI-suggested commands.
- **Test / lint / typecheck commands**: scan `package.json` scripts, `pyproject.toml`, `Makefile`, CI workflow files. Note exact commands.
- **CI platform**: `.github/workflows/`, `.gitlab-ci.yml`, `.circleci/`, `Jenkinsfile`, etc. Note the platform.
- **Existing agent docs**: `CLAUDE.md`, `AGENTS.md`, `README.md` — hoist any "use X, prefer Y" rules so they propagate into OpenSpec's config.
- **Branch + commit conventions**: `git log --oneline -20` plus any documented convention.
- **In-flight work**: open branches, TODO files, recent PRs — useful for picking the first OpenSpec change once setup is done.

After surveying, briefly present the findings to the user and ask: "Anything to add about conventions, compute scale, deployment, or team practices before I write `config.yaml`?" This catches things that aren't visible from code alone.

## 2. Run the bundled playbook

Now follow the bundled playbook: [openspec-setup.md](openspec-setup.md).

Use the discovery findings as the primary input for the `context:` block in Phase 3 — the playbook expects you to have the survey already and won't re-probe.

The skill ends after the playbook completes. The user picks a small in-flight opportunity (NOT a sweeping refactor) for their first OpenSpec change. Strongly suggest `/opsx:onboard` for first-time use on this codebase — it walks the full lifecycle on a real small opportunity.
