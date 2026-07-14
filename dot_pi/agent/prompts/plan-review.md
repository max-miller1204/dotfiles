---
description: Run a bounded cross-model review loop on an implementation plan before coding
argument-hint: "[plan-source] [reviewer-model] [max-rounds]"
---
Run a plan-review loop with these resolved inputs:

- Plan source: `${1:-current plan}`
- Reviewer model: `${2:-opencode-go/glm-5.2}`
- Maximum review rounds: `${3:-5}`

This command reviews a completed implementation plan before any code is written.
The parent Pi session is the orchestrator, final decision-maker, and only plan writer.
Do not implement the plan during this workflow.

## Resolve the plan

If the plan source is `current plan`, use the latest concrete implementation plan in this session.
If no unambiguous completed plan exists, ask the human to provide one and stop until they do.
If the source is a file path, read that file and treat it as the canonical plan.
Otherwise, treat the source argument as the plan description or reference and resolve it before review.
Multiword source descriptions must be quoted when invoking this command.
If any supplied source cannot be resolved unambiguously, ask the human and stop rather than guessing.

Validate that the maximum round count is a positive integer.
Confirm that the reviewer model differs from the parent session's current model.
If either check fails, ask the human for a valid replacement rather than guessing.

## Start the reviewer

Launch one `reviewer` subagent with the resolved reviewer model and set `async: true`, `context: "fresh"`, and `artifacts: false` explicitly.
The reviewer is advisory and review-only: instruct it to inspect the plan, repository, relevant instructions, and referenced files directly, but not to modify project or source files or run subagents.
Include the full current plan in its task, or give it the exact canonical plan path when the plan is file-backed.
Ask for concise, evidence-backed findings with plan-section and repository file references where applicable.
Require the last non-blank line of every response to be exactly one of:

```text
VERDICT: APPROVED
VERDICT: REVISE
```

Approval means the plan is specific, internally consistent, feasible in the repository, properly scoped, and has adequate validation, risk handling, and rollback handling where rollback applies.
Revision means there are material issues worth fixing before implementation.
Save the returned run ID and wait on that explicit ID for the reviewer to finish.
If model resolution, launch, or waiting fails, stop and report `STATUS: REVIEW FAILED`.

## Review rounds

Count the initial review as round 1.
For every response, inspect the last non-blank line literally.
A missing, malformed, or contradictory verdict is a review failure: stop, report `STATUS: REVIEW FAILED`, and do not infer approval.

On `VERDICT: REVISE`:

1. If the current round equals the maximum review rounds, stop immediately and report `STATUS: REJECTED` as described below. Do not revise the plan, resume the reviewer, or start another round.
2. Separate blockers, fixes worth incorporating, optional suggestions, and feedback to reject or defer with reasons.
3. Do not blindly accept reviewer feedback.
4. If a proposed revision requires an unapproved product, scope, or architecture decision, pause and ask the human before changing the plan.
5. Revise only the canonical plan as the parent session's sole plan writer.
6. Call `subagent` with `action: "resume"`, the explicit saved reviewer run ID, and a message containing the revised full plan or exact canonical path, a summary of accepted and rejected feedback, and the same exact verdict requirement.
7. Save the newly returned revived run ID, replacing the previous saved ID, increment the round, and wait on that new explicit ID.

If resuming or waiting fails, stop and report `STATUS: REVIEW FAILED`.
Never use a global or implicit "last session" selector.
Never launch multiple plan reviewers concurrently for this loop.
Never start a round greater than the configured maximum.

## Resolution

Stop immediately on `VERDICT: APPROVED`.
Present:

- `STATUS: APPROVED`
- the final plan or canonical plan path;
- the number of review rounds;
- a concise summary of improvements made through review;
- any optional or deferred feedback.

Then ask the human whether to implement the plan.
Do not begin implementation without that approval.

If the maximum round count is reached without approval, stop and present:

- `STATUS: REJECTED`
- the latest plan or canonical plan path;
- the number of review rounds;
- every unresolved material disagreement;
- the reviewer's position and the parent's position on each disagreement.

Never claim convergence when the reviewer did not approve the plan.
