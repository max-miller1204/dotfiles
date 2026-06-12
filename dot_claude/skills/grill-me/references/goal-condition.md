# Phase 4 reference: `/goal` condition formulation

Translate SPEC.md's MVP slice + smoke test + constraints into a multi-clause `/goal` condition. The evaluator checks it after every turn and stops the autonomous run when it holds.

When emitting the condition, substitute `<cwd>` with the actual absolute path of the project root, and fill every other `<…>` placeholder with concrete content from SPEC.md — `/goal`'s evaluator doesn't expand placeholders.

## Base clauses — always include

```
The project at <cwd> satisfies all of:
1. <smoke-test command from SPEC.md> exits 0 against a fresh checkout (or <observable outcome holds>).
2. The stack matches SPEC.md constraints: <constraint list>.
```

## Conditional MVP-slice clause

Add clause 3 *only when* the smoke test doesn't already exercise the full MVP slice — e.g., the user picked `curl /health` returns 200 but the slice is broader (sign up → create item → see it on the dashboard):

```
3. The MVP slice works end-to-end: <flow from SPEC.md, in one sentence>.
```

If the smoke test already drives the whole slice (Playwright script doing the exact flow, golden-fixture diff over the transformation, protocol driver calling the tool and asserting), drop clause 3. A redundant clause widens the autonomous run for zero verification gain.

## Dependency-append rule

Paired with Phase 1's pinning trio (static fixtures / in-process harness / live network). If clause 1's command depends on artifacts `/goal` won't build from source, make the dependency explicit so the autonomous run doesn't produce code that passes locally but fails on a fresh clone or in CI. One append per artifact, not per set:

- **Static fixtures** → append "with `<fixture path>` committed to the repo".
- **In-process harness code** → append "with `<harness module>` present".
- **Live network deps** → append "reachable upstream `<url>` (no auth required)".

## Splitting clause 1

If the smoke test has multiple independent assertions (static site + API, native app + sync server, two services that handshake), split clause 1 into `1a`, `1b`, … — one sub-clause per assertion, each independently checkable. Avoid `&&`-chaining commands into a single clause; the evaluator should be able to tell you which half failed.

## Optional add-ons — include when they pull weight

- **Fresh-clone check** (default-on for any stack with a build or install step beyond `git clone`): `<build-or-install>` succeeds and `<run-or-invoke>` produces the documented output. For stacks where build and install are one step (`cargo build --release`, `go build`, `swift build`), use one command for both slots — don't manufacture a separate install step. For products with no shell-invokable run command (browser extensions loaded unpacked, daemons blocking on stdin for protocol messages, libraries imported by other code), drop the run slot and note "(run-check folded into clause 1)".
- **README** (default-on): `README.md` at the project root documents install, run, and smoke-test steps. Skip only if SPEC.md explicitly says "no docs" or it's an explicit solo throwaway.
- **Commit**: `git log` shows at least one commit beyond the planning-artifact commit. Add when the user wants the autonomous run to commit progress, not just leave a dirty tree.
- **Constraint-driven** (from SPEC.md's `Constraints` section): e.g., "deploys to Cloudflare Workers", "passes lint and typecheck", "Lighthouse score ≥ 90".

Resist adding clauses that aren't either base or directly traceable to SPEC.md — every extra clause widens the autonomous run and risks the evaluator never converging.

When `## Constraints` is long, keep tightly-related items packed (a stack tuple like "TypeScript on Node 20+ with `@anthropic-ai/sdk`" is one logical thing) but peel out orthogonal items as their own constraint-driven add-ons (a deploy target, a perf budget, a runtime version that gates correctness).

## Worked example

For a fictional `urlshort` project at `/projects/urlshort`:

```
The project at /projects/urlshort satisfies all of:
1. `curl -fs http://localhost:8080/health` exits 0 against a fresh checkout.
2. The stack matches SPEC.md constraints: Go 1.22, no external DB (in-memory store), single-binary deploy.
3. The MVP slice works end-to-end: POSTing a long URL to `/shorten` returns a 7-char slug, and GET `/<slug>` 302-redirects to the original URL.
```

Clause 3 is included because the `/health` smoke test doesn't exercise the shorten/redirect flow. If the smoke test had been a script performing POST + redirect itself, drop clause 3. Every `<…>` placeholder is gone — replaced with concrete content from the project's SPEC.md. Do the same when emitting your condition.
