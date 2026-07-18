# HTML artifact quality checklist

Use this checklist before presenting an artifact.
Apply the sections that match the artifact's purpose.

## Purpose and content

- [ ] The artifact helps the user understand, review, compare, tune, or decide something specific.
- [ ] The first viewport explains what the artifact is and how to use it.
- [ ] The information architecture is task-specific rather than a generic dashboard.
- [ ] Important claims, code excerpts, paths, numbers, and statuses match authoritative sources.
- [ ] Facts, assumptions, recommendations, and open questions are visually distinguishable.
- [ ] The page contains no fabricated data added merely to make the layout feel complete.
- [ ] The artifact avoids unnecessary sensitive information and contains no secrets.

## Visual design

- [ ] Typography, spacing, hierarchy, color, and density have been reviewed in a rendered browser.
- [ ] The primary reading or decision path is visually obvious.
- [ ] Visual elements encode meaningful information rather than decoration.
- [ ] Text remains readable without zooming.
- [ ] Code, tables, diagrams, and long labels do not clip or overflow.
- [ ] Color is not the sole carrier of meaning.
- [ ] Empty, loading, copied, selected, validation, and error states are polished where applicable.
- [ ] Print output is usable for durable reports, reviews, plans, and explainers.

## Responsive and accessible behavior

- [ ] The page works at desktop and narrow mobile widths.
- [ ] Semantic landmarks and headings form a coherent outline.
- [ ] Controls have accessible names and visible focus states.
- [ ] The complete interaction can be performed with a keyboard.
- [ ] Drag-and-drop interactions have an accessible alternative.
- [ ] Contrast is sufficient for text, controls, diagrams, and annotations.
- [ ] Motion respects reduced-motion preferences.
- [ ] Essential reports and explainers remain useful without JavaScript where practical.

## Interaction and export

- [ ] Every control has an observable and correct effect.
- [ ] Reset and undo behavior is clear and safe where applicable.
- [ ] User choices use stable identifiers.
- [ ] Export captures the complete meaningful state in the intended format.
- [ ] Exported output is understandable outside the artifact and in a fresh agent session.
- [ ] Copy and download actions provide visible success or failure feedback.
- [ ] Clipboard behavior has a practical fallback when needed.
- [ ] The artifact does not directly mutate repository files or external systems.

## Portability and security

- [ ] The artifact is self-contained unless external dependencies were explicitly required.
- [ ] It has no unnecessary framework, package, CDN, remote font, analytics, or background request.
- [ ] User-derived or embedded data is escaped and inserted safely.
- [ ] Browser code does not expose filesystem paths, credentials, environment values, or private context unnecessarily.
- [ ] The artifact opens from the documented location without a build step.

## Browser validation

- [ ] A desktop viewport around 1440 pixels wide was inspected.
- [ ] A mobile viewport around 390 pixels wide was inspected.
- [ ] Screenshots were reviewed for visual defects and awkward composition.
- [ ] The browser console has no relevant errors.
- [ ] Navigation, controls, links, and interactive states were exercised.
- [ ] Export output was generated and checked against the visible state.
- [ ] Displayed evidence was spot-checked against its source.
- [ ] Any remaining limitation is stated clearly in the final response.
