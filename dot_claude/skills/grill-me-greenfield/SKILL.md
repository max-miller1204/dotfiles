---
name: grill-me-greenfield
description: Interview the user about a greenfield project until shared understanding emerges, synthesize SPEC.md and ROADMAP.md at the project root, then run a bundled greenfield-trimmed OpenSpec setup playbook to fully initialize the project. Use when starting a new project, mentioning "greenfield", or kicking off OpenSpec on a fresh repo.
---

Greenfield projects start vague, which makes the first OpenSpec change vague, which infects every change downstream. This skill fixes the cold start: discover the product first, then set up OpenSpec with that context already in hand.

## 1. Interview

Interview the user relentlessly about every aspect of this greenfield project until you reach shared understanding. Walk down the **product** decision tree — problem → users → goals → non-goals → core capabilities → MVP slice → constraints — resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask questions one at a time.

If a question can be answered by exploring the scaffold (existing files, `package.json`, etc.), explore instead of asking.

The decision tree here is product-shaped, not code-shaped — there's no codebase yet to discuss architecture against. Architecture decisions belong in OpenSpec changes later.

## 2. Synthesis

Once the interview converges (no new branches surface from your questions), write two files at the project root.

### SPEC.md

```
# <Project Name>

## Problem
<What's broken or missing in the world.>

## Users
<Who it's for. Primary use cases.>

## Goals
<Observable outcomes that mean success.>

## Non-goals
<Explicitly out of scope. Anti-scope is high-leverage for greenfield — write it down.>

## Core capabilities
<The WHAT, in user-facing language. No implementation.>

## Constraints
<Tech stack constraints, deadlines, compute, compliance — anything that bounds the solution space.>

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
- <Bucket 2 — one line.>
- ...

## Notes
<Ordering dependencies or "do X before Y" constraints, if any.>

---
Living document. Discrete changes are derived from these buckets, not generated automatically.
```

Keep ROADMAP.md loose. Buckets are not phased milestones and not tasks — they're starting points the user picks from when running `/opsx:propose` later.

## 3. Set up OpenSpec

Now follow the bundled playbook: [openspec-setup.md](openspec-setup.md).

When you reach the `openspec/config.yaml` phase, use the `SPEC.md` you just wrote as the primary input for the `context:` block. That's the whole point of doing synthesis first — the config gets stack- and product-aware on the first try.

The skill ends after the playbook completes. The user picks a work area from `ROADMAP.md` and runs `/opsx:propose` themselves to author the first change.

Out of scope for this skill: writing anything inside `openspec/changes/` or `openspec/specs/`.
