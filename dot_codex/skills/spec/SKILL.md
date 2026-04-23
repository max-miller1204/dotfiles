---
name: spec
description: "Write detailed implementation specs through a focused interview. Use when the user wants to spec, plan, or design a feature, project, or task, or when they provide a brief or file and want a concrete SPEC.md with scope, design, verification, and optional execution waves."
---

# Spec

Write a spec through a focused interview. Read any user-mentioned file or brief first, then ask only the questions needed to lock the design.

## Workflow

1. Gather the real constraints.
   - Ask about implementation approach, UX, risks, tradeoffs, and explicit in-scope vs out-of-scope boundaries.
   - Ask non-obvious questions that might change the architecture, not just surface details.
   - If the repo already exists, anchor questions in concrete files, modules, and integration points.

2. Probe for execution shape before drafting.
   - Ask whether the work is:
     - atomic with no parallelism
     - one wave: serial scaffold, then parallel leaf chunks
     - multiple dependency-ordered waves
   - In default mode, ask this as a concise plain-text question with explicit options instead of relying on special UI tools.

3. If the answer includes waves, drill until `swarm` can execute without re-asking.
   - For each wave, capture:
     - scaffold work that must land first
     - locked interface contracts established by the scaffold
     - chunk list with branch name, ownership, and done-when criteria
     - any intra-wave sequencing constraints

4. Write the spec.
   - Default output path: `./SPEC.md`
   - If the user names another output path, use it.

## Required structure

- `Context` - why this exists and the problem it solves
- `Scope` - in-scope and out-of-scope, explicit
- `Design` - the settled approach, not a brainstorm dump
- `Verification` - how to prove the work functions end to end
- `Waves` - include only when the user confirmed wave-based execution

For each wave, include:
- scaffold
- locked interface contracts
- chunks with branch name, scope, and done-when
- sequencing notes when relevant

## Quality rules

- Prefer one sharp question at a time over a long questionnaire.
- Challenge weak assumptions directly when they affect architecture, scope, or verification.
- If the user does not want a long interview, state the assumptions clearly in the spec instead of pretending they were settled.
- Make the spec concrete enough that a later `swarm` run can use it as an execution plan rather than a vague design note.
- If there are no waves, the spec itself is the deliverable.
- If there are waves, tell the user the next step is `swarm`.
