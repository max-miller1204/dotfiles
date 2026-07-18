---
name: html-artifacts
description: Create, revise, and validate purpose-built HTML artifacts for visual exploration, comparison, code review, technical explanation, planning, reports, diagrams, prototypes, and one-off editing or decision interfaces. Use when the user explicitly asks for an HTML artifact or when spatial, visual, comparative, or interactive presentation would materially improve understanding or review. Do not use for routine answers, short linear documents, production web features, or HTML application code unless the user asks for an artifact.
---

# HTML Artifacts

Build the smallest purpose-built interface that helps the user understand something, review it, or make a decision.
Do not merely wrap ordinary prose in styled HTML.

## Core principle

Treat an artifact as a temporary or durable working surface between the user and the agent.
Its information architecture, visual design, and interactions must serve the specific task.
Content accuracy and decision usefulness matter more than visual novelty.

Read [references/patterns.md](references/patterns.md) when choosing the artifact structure or interaction model.
Use [references/quality-checklist.md](references/quality-checklist.md) before presenting the finished artifact.

## When HTML is appropriate

Prefer an HTML artifact when at least one of these conditions applies:

- The user needs to compare alternatives side by side.
- The information is spatial, visual, temporal, or relational.
- Code, diffs, findings, or source annotations need richer presentation.
- A long plan, report, or explainer needs navigation and progressive disclosure.
- Motion or interaction must be experienced instead of described.
- The user needs a purpose-built editor for structured data or hard-to-describe choices.
- The result will be shared with people who are unlikely to read a long Markdown document.

Prefer a normal response or Markdown when the material is short, linear, and non-interactive.
Do not create an artifact merely because HTML can represent the content.

## Artifact modes

Choose a primary mode before designing the page.
Modes can be combined when the combination has a clear purpose.

1. **Explore** presents distinct alternatives, tradeoffs, and a way to identify or export a preference.
2. **Explain** combines a guided narrative with diagrams, exact source excerpts, examples, and progressive disclosure.
3. **Review** emphasizes evidence, annotated diffs, severity, risk, and actionable findings.
4. **Plan or report** emphasizes status, sequence, dependencies, evidence, decisions, and open questions.
5. **Edit or decide** exposes a task-specific state model through controls and exports the resulting state in a stable form.

## Workflow

### 1. Establish purpose and lifetime

Determine what the user should understand, review, compare, tune, or export after using the artifact.
Ask a question only when an essential objective or input is missing.

Classify the artifact as scratch or durable.

- Scratch artifacts include explorations, tuning tools, and throwaway editors.
- Durable artifacts include approved plans, explainers, incident reports, and shareable review summaries.

Use a user-specified output path when provided.
For a durable artifact, follow an existing project convention or use `artifacts/<descriptive-slug>.html` when no convention exists.
For a scratch artifact, use an operating-system temporary directory and report the exact path.
Never change ignore files merely to accommodate an artifact unless the user requests it.

Default to one self-contained HTML file.
Use a small linked set of files only when separate views materially improve navigation or handoff.

### 2. Gather authoritative context

Read the relevant repository files, diffs, history, documents, web sources, and connected data before composing the artifact.
Use the available code-navigation and browser tools rather than guessing.

For technical artifacts:

- Quote code exactly and escape it correctly.
- Label excerpts with file paths and line ranges when available.
- Distinguish observed behavior from inference and recommendation.
- Include the source revision or commit when stale references would be risky.

For research and reports:

- Make evidence and provenance visible near the claims they support.
- Separate facts, estimates, assumptions, and unresolved questions.
- Do not fabricate metrics, screenshots, users, implementation details, or source content for visual completeness.

### 3. Design the reading and decision path

Decide the page structure before writing detailed markup.
Lead with the information needed to orient the user, then reveal supporting detail.

A useful structure often includes:

- A concise title and purpose.
- A summary or orientation layer.
- The primary visual, comparison, timeline, review, or editor.
- Evidence and implementation detail.
- Risks, caveats, decisions, or open questions.
- A clear next action or export when the artifact is interactive.

Choose visual primitives because they clarify the material.
Do not turn every fact into a card, every number into a dashboard metric, or every relationship into a diagram.
Avoid generic gradient-heavy landing-page styling and decorative interface chrome.
Use project design tokens when the artifact is evaluating a real product surface.
Otherwise choose a restrained, content-led visual system with deliberate typography, spacing, and hierarchy.

### 4. Build a portable standalone document

Unless the brief requires otherwise:

- Inline the CSS, JavaScript, SVG, and small data payloads.
- Use system fonts.
- Avoid frameworks, package installation, build steps, CDNs, analytics, and remote assets.
- Do not make background network requests.
- Use semantic HTML before custom JavaScript widgets.
- Keep the document responsive and usable at narrow and wide viewport sizes.
- Add print styles for plans, reports, reviews, and explainers that may be shared or archived.
- Respect reduced-motion preferences when motion is present.
- Preserve visible focus states and sufficient contrast.

Reports and explainers should remain useful when JavaScript is unavailable whenever practical.
Interactive editors may require JavaScript, but their purpose and initial state must still be clear.

Treat embedded or user-derived content as untrusted data.
Prefer `textContent` and explicit DOM construction over interpolating untrusted strings into `innerHTML`.
Never embed secrets, credentials, private environment values, or unnecessary sensitive data.

### 5. Close the interaction loop

If the artifact lets the user change state or make choices, provide an explicit export.
Export the decision or data, not a dump of the page markup.

Choose the format that best feeds the next workflow:

- Prompt text for qualitative feedback or a selected direction.
- Markdown for ordered lists, reviews, and human-readable handoff.
- JSON for structured state and datasets.
- A minimal diff for configuration changes.
- A downloadable file when clipboard access is insufficient.

The export must be deterministic, complete, and understandable without the artifact.
Use stable identifiers for items and options so exported feedback can be mapped back to sources.
Provide clear copied, saved, validation-error, and reset states.
Include a clipboard fallback when practical.

Do not let a standalone artifact directly mutate repository files or external systems.
Export proposed changes for the user and agent to review and apply through the normal workflow.

### 6. Validate in a real browser

Render the artifact in an available browser automation or preview tool before presenting it.
Do not rely only on reading the source.

At minimum:

- Inspect a desktop viewport around 1440 pixels wide.
- Inspect a narrow mobile viewport around 390 pixels wide.
- Check for clipping, overflow, unreadable density, weak hierarchy, awkward whitespace, and broken sticky elements.
- Review screenshots with the same care as a production interface.
- Check the browser console for errors.
- Exercise every important control and navigation path.
- Verify that export output is accurate and complete.
- Test keyboard navigation for interactive controls.
- Spot-check displayed facts, code, paths, and numbers against their sources.

Fix visible defects and unrelated breakage encountered in the artifact rather than presenting them as caveats.
If browser tooling is unavailable, say so and perform the strongest static review possible.
Do not install a heavyweight browser stack solely for a small artifact unless the user approves it.

### 7. Present the result

Return the exact artifact path and state whether it is scratch or durable.
Briefly explain what the artifact is for, how to open it, and how to export any decisions.
Mention validation performed and any remaining limitations.
Do not paste the full HTML into the chat unless the user asks.

## Revision rules

When revising an existing artifact, inspect it in the browser before changing it.
Preserve useful interactions, stable identifiers, and user-authored state unless the requested change requires otherwise.
Revalidate the affected viewports and interactions after every substantial revision.

## Boundaries

This skill produces review and communication artifacts, prototypes, and one-off interfaces.
It does not replace the project's production framework, testing strategy, or design system implementation.
When the user asks to implement a production web feature, follow the project's normal engineering workflow instead of treating it as a standalone artifact.
