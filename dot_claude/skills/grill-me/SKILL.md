---
name: grill-me
description: Use when the user wants to kick off a *greenfield* project and is willing to be interviewed first — the interactive front half of an MVP build. Grills them one question at a time to pin down problem → users → goals → non-goals → core capabilities → **MVP slice** → **smoke test** → constraints, then writes `SPEC.md` + `ROADMAP.md` and hands off to the `/grill-me-build` workflow, which scaffolds the running MVP and files the remaining backlog autonomously. Triggers on "grill me", "interview me for an MVP", "MVP-first", "scaffold an MVP", "build me an MVP", "greenfield, code first", or any greenfield kickoff where the user wants to nail the spec before code. Do not trigger on bare "MVP" without greenfield/kickoff context, and do not run the build itself — that's the workflow's job.
---

Discover the product and define the smallest observable flow that means "alive." This skill owns the **interactive** half: the interview and the spec it produces. The autonomous half — scaffolding the running app and filing the backlog — lives in the `/grill-me-build` workflow, which this skill hands off to. Run from the directory the project should live in.

## 0. Detect prior state

Check cwd for existing artifacts before interviewing.

- **`SPEC.md` has `## MVP slice` and `## Smoke test` sections** → skip to Phase 3 (hand off).
- **`SPEC.md` present but missing MVP-slice or smoke-test** → ask only the two interview branches below, append the sections, then hand off.
- **Nothing present** → run all phases.

If you skip Phases 1–2, read the existing `SPEC.md` end-to-end before handing off — the workflow's build condition pulls from it.

## 1. Interview

Walk the product decision tree — problem → users → goals → non-goals → core capabilities → **MVP slice** → **smoke test** → constraints. One question at a time. Lead with your recommended answer. If the user defers, accept your recommendation and move on. Partial acceptance counts — don't re-ask the unchanged parts. If a question can be answered by exploring cwd, explore instead of asking.

Stop when every SPEC.md section has at least one user-confirmed sentence (empty-by-confirmation counts) AND your last two questions haven't surfaced new branches. The goal is enough shared understanding to write a checkable build condition, not a complete design doc.

The tree is product-shaped, not code-shaped — architecture decisions belong in later iterations, not the MVP-defining interview.

**MVP slice.** Push for a single observable end-to-end flow, not a list of capabilities. "What's the one thing that proves this product exists, observed from the consumer's side?" The consumer can be a human (signup + create item), an LLM client (MCP tool result), a peer program (CLI invoked by a script), a browser (extension producing its observable side effect), a scheduler (cron writing to the right place), or a downstream caller (library returning its documented behavior). "User-facing" is shorthand for *observable*. If the user lists three flows, ask which one comes first and park the rest in the roadmap.

**Smoke test.** This is what makes the build condition verifiable. Ask: "What command or observable action, with what outcome, proves the MVP slice works?" Push back on tests that aren't mechanically checkable. Offer a concrete alternative:

- **Exit-code check**: `<command>` exits 0. Fits most CLIs.
- **Grep-on-output**: `<command> | grep -q '<pattern>'` exits 0. Fits text-emitting tools.
- **HTTP probe**: `curl -fs <url>` succeeds. Fits HTTP servers.
- **Test-runner invocation**: `npm run test:smoke`, `cargo test --test smoke`, `pytest tests/smoke.py`. For browser-shaped products this means a headless test (Playwright, Puppeteer) asserting the observable side effect.
- **Protocol round-trip driver**: a script that spawns the server, sends a message (MCP, LSP, DAP, gRPC, stdio JSON-RPC), asserts the response, kills the server, exits 0. Fits daemons.
- **Golden-fixture diff**: `<command> input.csv | diff - expected.csv` exits 0. Fits deterministic transformations.

Anything mechanically checkable via exit code is fair game.

If the smoke test depends on anything the build won't produce from source, pin it explicitly so the autonomous build doesn't ship code that passes locally but fails on a fresh clone:

- **Static fixtures** (sample PDF, expected CSV, reference table): "are these part of the scaffold, or do you have them already?" List all of them.
- **In-process harness code** (a `TcpListener::bind("127.0.0.1:0")` in a Rust test, mock SMTP in a pytest fixture, stub MCP server inside a Node test): "is the harness part of the test scaffold?" Usually yes — name the test module that owns it.
- **Live network dependencies** (Open-Meteo, Open-Library, etc.): "no auth? Free tier? Rate limit OK for one CI run?" Pin the endpoint and confirm keyless, OR pin the mocking strategy. Flaky upstreams break the build's convergence.

## 2. Synthesis

Write two files at the project root.

### SPEC.md

```
# <Project Name>

## Problem
<What's broken or missing.>

## Users
<Who it's for. Primary use cases.>

## Goals
<Observable outcomes that mean success.>

## Non-goals
<Explicitly out of scope. Anti-scope is high-leverage for greenfield.>

## Core capabilities
<The WHAT, user-facing language. No implementation.>

## MVP slice
<The single observable flow that defines "done" for the first scaffold pass. One paragraph.>

## Smoke test
<The verifiable check. One command or one user action with an observable outcome.>

## Constraints
<Stack, deadlines, compute, compliance — anything that bounds the solution space.>

## Open questions
<Anything the interview surfaced but couldn't resolve.>
```

### ROADMAP.md

```
# Roadmap

## North star
<One or two sentences of vision.>

## Work areas
- <Bucket 1 — one line.>
- ...

## Notes
<Ordering constraints, if any.>

---
Living document.
```

Buckets are starting points the user picks from after the MVP is live. Not phased milestones, not tasks. The `/grill-me-build` workflow turns the *remaining* work (everything past the MVP slice) into a GitHub backlog, so a well-shaped ROADMAP feeds directly into good issues.

## 3. Hand off to the build workflow

The interview is done and `SPEC.md` + `ROADMAP.md` are written. The rest — scaffolding the running MVP and filing the backlog — is autonomous and non-interactive, so it runs as a workflow rather than as more conversation.

Show the user the MVP slice and smoke test verbatim, offer one round of edits to `SPEC.md`, then tell them to run:

```
/grill-me-build
```

What that workflow does, in two phases (no further questions — it does not stop for input):

1. **Scaffold MVP** — derives a multi-clause build condition from `SPEC.md` (smoke test + constraints + MVP slice), then writes code, installs deps, and runs the smoke test in a loop until it passes.
2. **Backlog** — now that code exists, runs a gap analysis against the real codebase + `SPEC.md`/`ROADMAP.md`, then files a deduplicated, dependency-linked GitHub issue backlog via `gh`. **It files without a confirmation gate** — so make sure the repo and the spec are where you want them before launching. Needs a github.com remote and authenticated `gh`; without them it still produces the local `ISSUES_PLAN.json` preview and stops short of filing.

## What this skill does NOT do

- Does not write application code, install deps, or pick a stack. The workflow's scaffold phase does that.
- Does not file GitHub issues. The workflow's backlog phase does that.
- Does not run the workflow itself — workflows are user-launched. The skill ends with the ready-to-run `/grill-me-build` command.
