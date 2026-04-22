---
name: spec
description: "Use this skill when the user wants to spec out, plan, or design a feature, project, or task. Triggers on: 'spec', 'write a spec', 'plan this', 'design this', 'let me describe what I want', or when the user provides a file/description and wants a detailed specification written. Takes an optional $1 argument pointing to a file to read first, and an optional $2 for the output path (defaults to ./SPEC.md)."
---

You are writing a spec through interview. Read `$1` if given, then interview the user in detail using `AskUserQuestion` about anything relevant:

- Technical implementation
- UI & UX
- Concerns
- Tradeoffs
- Scope — what's explicitly in and out

Make the questions non-obvious. Challenge assumptions — ask questions that might change the whole approach, not just refine it.

## Probe wave structure

Before writing the spec, ask one extra question: does the work have a **serial-foundation-then-parallel-leaves** shape, or multiple dependency-ordered waves? Use `AskUserQuestion` with explicit options:

- No — single atomic piece of work, no parallelism needed
- Yes — one wave (scaffold + parallel leaves, then done)
- Yes — multiple waves with dependencies between them

If "yes" in either form, drill further:
- For each wave: what's the scaffold (serial pre-dispatch work)? What are the leaf chunks (branch name, scope, done-when smoke test)? Any intra-wave sequencing (e.g. chunk B must land after A)?
- The goal is enough detail that the companion `/swarm` skill can later execute each wave verbatim without re-asking.

## Write SPEC.md

At the end of the interview, write the spec to `$2` if given, otherwise `./SPEC.md`. Structure:

- **Context** — why this is being built, the problem it solves
- **Scope** — in-scope and out-of-scope, explicit
- **Design** — the approach settled on (not the alternatives considered)
- **Verification** — how to know it works end-to-end
- **Waves** (only if the user answered yes above) — for each wave:
  - Scaffold: files/modules to land serially before dispatch
  - Interface contracts locked in the scaffold commit (trait signatures, type definitions)
  - Chunks: table with branch name, scope, done-when
  - Intra-wave sequencing notes if any

If there are waves, tell the user the next step is `/swarm` to execute them one at a time. If there are no waves, the spec is the deliverable — they can implement it themselves or pass it to other tooling.
