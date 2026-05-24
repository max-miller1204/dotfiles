---
name: scaffold-mvp
description: Use when the user wants a *running* MVP scaffold for a greenfield project — not just specs. Interviews them (or picks up from an existing `SPEC.md` if one is present), carves an MVP slice with a measurable smoke test, then hands off to `/goal` so Claude Code autonomously scaffolds the working app. Triggers on "MVP-first", "scaffold an MVP", "scaffold the MVP now", "build me an MVP", "greenfield, code first", "I want to /goal a new project", or any greenfield kickoff where the user wants code running fast. Do not trigger on bare "MVP" without greenfield/scaffold context.
---

Discover the product, define the smallest observable flow that means "alive," then hand off to `/goal` for autonomous scaffolding. Run from the directory the project should live in.

## 0. Detect prior state

Check cwd for existing artifacts before interviewing.

- **`SPEC.md` has `## MVP slice` and `## Smoke test` sections** → skip to Phase 3.
- **`SPEC.md` present but missing MVP-slice or smoke-test** → ask only the two interview branches below, append the sections, then go to Phase 3.
- **Nothing present** → run all phases.

If you skip Phases 1–2, read the existing `SPEC.md` end-to-end before Phase 3 — the `/goal` condition pulls from it.

## 1. Interview

Walk the product decision tree — problem → users → goals → non-goals → core capabilities → **MVP slice** → **smoke test** → constraints. One question at a time. Lead with your recommended answer. If the user defers, accept your recommendation and move on. Partial acceptance counts — don't re-ask the unchanged parts. If a question can be answered by exploring cwd, explore instead of asking.

Stop when every SPEC.md section has at least one user-confirmed sentence (empty-by-confirmation counts) AND your last two questions haven't surfaced new branches. The goal is enough shared understanding to write a checkable `/goal` condition, not a complete design doc.

The tree is product-shaped, not code-shaped — architecture decisions belong in later iterations, not the MVP-defining interview.

**MVP slice.** Push for a single observable end-to-end flow, not a list of capabilities. "What's the one thing that proves this product exists, observed from the consumer's side?" The consumer can be a human (signup + create item), an LLM client (MCP tool result), a peer program (CLI invoked by a script), a browser (extension producing its observable side effect), a scheduler (cron writing to the right place), or a downstream caller (library returning its documented behavior). "User-facing" is shorthand for *observable*. If the user lists three flows, ask which one comes first and park the rest in the roadmap.

**Smoke test.** This is what makes the `/goal` condition verifiable. Ask: "What command or observable action, with what outcome, proves the MVP slice works?" Push back on tests that aren't mechanically checkable. Offer a concrete alternative:

- **Exit-code check**: `<command>` exits 0. Fits most CLIs.
- **Grep-on-output**: `<command> | grep -q '<pattern>'` exits 0. Fits text-emitting tools.
- **HTTP probe**: `curl -fs <url>` succeeds. Fits HTTP servers.
- **Test-runner invocation**: `npm run test:smoke`, `cargo test --test smoke`, `pytest tests/smoke.py`. For browser-shaped products this means a headless test (Playwright, Puppeteer) asserting the observable side effect.
- **Protocol round-trip driver**: a script that spawns the server, sends a message (MCP, LSP, DAP, gRPC, stdio JSON-RPC), asserts the response, kills the server, exits 0. Fits daemons.
- **Golden-fixture diff**: `<command> input.csv | diff - expected.csv` exits 0. Fits deterministic transformations.

Anything mechanically checkable via exit code is fair game.

If the smoke test depends on anything `/goal` won't build from source, pin it explicitly. Phase 3 turns these pins into clause-1 appends — see [goal-condition.md](goal-condition.md).

- **Static fixtures** (sample PDF, expected CSV, reference table): "are these part of the scaffold, or do you have them already?" List all of them.
- **In-process harness code** (a `TcpListener::bind("127.0.0.1:0")` in a Rust test, mock SMTP in a pytest fixture, stub MCP server inside a Node test): "is the harness part of the test scaffold?" Usually yes — name the test module that owns it.
- **Live network dependencies** (Open-Meteo, Open-Library, etc.): "no auth? Free tier? Rate limit OK for one CI run?" Pin the endpoint and confirm keyless, OR pin the mocking strategy. Flaky upstreams break `/goal`'s convergence.

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

Buckets are starting points the user picks from after the MVP is live. Not phased milestones, not tasks.

## 3. Formulate the `/goal` condition

Translate SPEC.md's MVP slice + smoke test + constraints into a multi-clause `/goal` condition. The evaluator checks it after every turn and stops the autonomous run when it holds.

See [goal-condition.md](goal-condition.md) for clause shapes, the dependency-append rules (paired with Phase 1's pinning trio), and a worked example.

Show the formulated condition to the user verbatim. Offer one round of edits, then proceed.

## 4. Hand off to `/goal`

Print the exact invocation the user should type:

```
/goal <condition from Phase 3>
```

`/goal` takes over autonomous execution — it picks the stack within SPEC.md's constraints, writes code, installs deps, runs tests, commits, looping until the condition holds. The user can leave it running; `/goal` clears itself when satisfied.

## What this skill does NOT do

- Does not write application code, install deps, or pick a stack. `/goal` does that.
- Does not invoke `/goal` itself — slash commands are user-typed. The skill ends with a ready-to-paste invocation.
