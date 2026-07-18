# HTML artifact patterns

Choose a pattern based on the user's task, not on which components are easiest to generate.
Combine patterns only when the result remains easy to scan and navigate.

## Exploration and comparison

Use this pattern when the user is choosing among approaches, designs, architectures, or parameter sets.

Useful elements:

- A shared framing of the problem and constraints.
- Distinct alternatives shown in a common coordinate system.
- The same examples or data applied to every alternative.
- Explicit tradeoffs, failure modes, and assumptions.
- A comparison matrix for attributes that are genuinely comparable.
- Stable option identifiers and an exportable preference or decision.

Avoid presenting minor cosmetic variations as meaningfully different approaches.
Do not declare a winner unless the evidence supports one or the user asks for a recommendation.

## Code review

Use this pattern when findings depend on changed code, control flow, or interactions between files.

Useful elements:

- Change summary and risk orientation.
- Findings grouped by severity and confidence.
- Exact diff hunks or source excerpts with inline annotations.
- File paths, line ranges, and links between overview and evidence.
- A compact module or data-flow diagram when it explains cross-file behavior.
- Suggested fixes and verification steps.

Preserve diff semantics and whitespace.
Do not use color as the only indicator of additions, deletions, or severity.
Keep unremarkable files collapsed or summarized so important findings dominate.

## Technical explainer

Use this pattern when the user needs to understand a subsystem, algorithm, incident mechanism, or unfamiliar concept.

Useful elements:

- A one-screen mental model.
- A sequence, data-flow, or state diagram.
- Three to five exact source excerpts chosen for explanatory value.
- A guided walkthrough from input to outcome.
- Failure cases, invariants, and operational gotchas.
- A glossary or expandable detail for unfamiliar terminology.

Prefer one strong diagram over several decorative diagrams.
Make diagram labels readable without zooming.
Keep source excerpts short enough that annotations remain visible.

## Implementation plan

Use this pattern when a plan needs richer review than a linear checklist permits.

Useful elements:

- Goal, constraints, scope, and non-goals.
- Current and proposed architecture.
- Data flow and interface boundaries.
- Ordered implementation slices with dependencies.
- Representative schemas, APIs, or code snippets.
- Risks paired with mitigations and verification.
- Explicit decisions and open questions with owners or deadlines where known.

Do not invent dates, staffing, or effort estimates.
A visual timeline should express dependency and sequence rather than fake calendar precision.

## Status or incident report

Use this pattern when evidence, chronology, and audience scanning matter.

Useful elements:

- Executive summary and current state.
- Metrics with units, comparison windows, and provenance.
- Timeline with clear event types and uncertainty.
- Impact, contributing factors, response, and follow-up work.
- Ownership and status for next actions.
- Print-friendly presentation.

Do not use visual certainty to hide uncertain or incomplete evidence.
Distinguish correlation, hypothesis, and confirmed cause.

## Prototype and parameter tuner

Use this pattern when motion, styling, geometry, or algorithm parameters must be experienced.

Useful elements:

- The real interactive subject, not a static imitation.
- Controls with sensible ranges, units, defaults, and reset behavior.
- Immediate preview with reduced-motion handling.
- Presets that represent meaningfully different regions of the design space.
- Exact export of selected values.

Avoid adding controls that have no observable effect.
Keep the control surface small enough that the user can understand cause and effect.

## Structured editor

Use this pattern when text instructions are an inefficient way to reorder, classify, annotate, or configure data.

Useful elements:

- A visible state model that matches the task.
- Validation and dependency warnings close to affected controls.
- Keyboard-accessible alternatives to drag and drop.
- Reset, undo, and unsaved-change indication where appropriate.
- Stable item identifiers.
- Deterministic export as JSON, Markdown, prompt text, or a minimal diff.

Do not make the browser page the only copy of valuable user work.
Use local persistence only when it materially protects work, and make reset behavior explicit.

## Diagram selection

Use a flowchart for ordered decisions or processing steps.
Use a sequence diagram for interactions across actors over time.
Use a state diagram for valid states and transitions.
Use a dependency graph for structural relationships.
Use a timeline for events anchored in time.
Use a table when precise comparison matters more than topology.

Prefer inline SVG for diagrams that need exact layout and crisp scaling.
Provide text equivalents or adjacent explanations for essential relationships.
Avoid crossing connectors, tiny labels, and arrows whose direction is ambiguous.

## Interaction and export selection

Use copy as prompt when the user's output is qualitative guidance to the agent.
Use Markdown when the output should remain easy for humans to read and edit.
Use JSON when structure, stable identifiers, and programmatic reuse matter.
Use a minimal diff when editing an existing configuration.
Use file download when clipboard limits or data size make copying unreliable.

The export should include enough context to be understood in a fresh agent session.
It should not include decorative layout state unless that state is itself the user's decision.
