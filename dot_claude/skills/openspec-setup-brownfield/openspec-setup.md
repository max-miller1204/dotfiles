# OpenSpec setup playbook (brownfield variant)

Bundled with the `openspec-setup-brownfield` skill. Run this **after** the SKILL.md discovery step has surveyed the codebase. The greenfield variant of this playbook lives in the `grill-me-greenfield` skill bundle.

You're an agent helping the user adopt **OpenSpec** in a project that already has code. Read this whole file, then execute the phases below. Adapt judgment to what you find — don't blindly follow steps when the project's reality contradicts them.

OpenSpec (`@fission-ai/openspec` on npm) is a spec-driven development system: per-change folders with `proposal.md`, `design.md`, `tasks.md`, and **delta specs** that merge into a living `openspec/specs/` source-of-truth on archive. It's brownfield-first — designed to layer onto mature codebases without retro-speccing the past.

The goal of this playbook is to leave the project in a state where:
1. OpenSpec is initialized with the **custom** profile (all 11 commands available).
2. `openspec/config.yaml` has real, project-specific context + rules drawn from the SKILL.md discovery survey, so every artifact gets stack-aware AI generation.
3. CI validates specs on every PR (almost always present on brownfield — wire it).
4. Fish/zsh/bash shell completions are installed for the user's shell.

---

## Phase 0 — Sanity checks before doing anything

Confirm:
- Working directory is the project root (look for `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.).
- Inside a git repo (`git rev-parse --git-dir`).
- Working tree is clean enough that you can attribute new commits cleanly. If there's substantial in-progress work, ask the user before continuing.
- `openspec --version` exists. If not, install globally:
  ```bash
  npm install -g @fission-ai/openspec@latest
  ```
  Requires Node 20.19+. If `npm` is missing, ask the user how they prefer to install Node (mise, nvm, brew, etc.) — don't assume.

---

## Phase 1 — Check for prior OpenSpec install

Check for `openspec/` directory and `openspec/config.yaml`. If present, the project is already initialized — skip Phase 2 and go directly to Phase 3 (tailoring config). Confirm with the user before overwriting their config.

---

## Phase 2 — Initialize OpenSpec with the custom profile

The `custom` profile gives all 11 slash commands (propose, explore, new, continue, ff, apply, verify, sync, archive, bulk-archive, onboard) instead of the 4-command `core` default. Better for a mature project that wants the full surface area.

```bash
openspec init --tools claude --profile custom
```

If the project uses other AI tools (Cursor, Codex, GitHub Copilot, etc.), pass them as a comma-separated list:
```bash
openspec init --tools claude,cursor,codex
```

Supported tool IDs: `amazon-q, antigravity, auggie, claude, cline, codex, codebuddy, continue, costrict, crush, cursor, factory, gemini, github-copilot, iflow, kilocode, kimi, kiro, opencode, pi, qoder, qwen, roocode, trae, windsurf`.

**Verify** afterward:
```bash
openspec config get profile        # should print: custom
ls .claude/commands/opsx/          # should show 11 .md files
```

If `--profile custom` fails (the CLI's preset shortcut for switching profiles only accepts `core`), you can force it via the global config file:
```bash
openspec config path               # prints location, usually ~/.config/openspec/config.json
# Edit that file: set "profile": "custom" and add the full workflows array
openspec update                    # regenerates project skill/command files
```

The full `workflows` array for the custom profile:
```json
["propose", "explore", "new", "continue", "apply", "ff", "sync", "archive", "bulk-archive", "verify", "onboard"]
```

---

## Phase 3 — Write a project-tailored `openspec/config.yaml`

This is the single highest-leverage step. The `context` and `rules` here are injected into **every** AI prompt for artifact generation — so good context here saves you re-explaining the stack on every `/opsx:propose`.

### Inputs — reuse the discovery survey

The SKILL.md discovery step has already surveyed this codebase: domain shape, stack, env wrappers, test/lint/typecheck commands, CI platform, agent docs (`CLAUDE.md`/`AGENTS.md`/`README.md`), branch + commit conventions, in-flight work. You also asked the user for any context not visible from code (team practices, compute scale, deployment quirks).

**Reuse those findings.** Don't re-probe — that's the point of doing discovery upfront. If a slot is genuinely missing from the survey, surface it to the user rather than re-running the scan.

### Template to start from

```yaml
schema: spec-driven

context: |
  Project: <one-line description of what the project does>

  Runtime: <language + version>. Dependencies managed by <tool> (<exact command>).
  <Env wrapper notes — e.g. "Every command runs inside `nix develop` because
  system deps come from nixpkgs.">. <Compute scale notes — e.g. "Local compute is
  weak; heavy ML training runs on Brev.">

  Stack: <key libraries that should appear in every artifact — frameworks,
  data layers, test runners>.

  Source layout (`<src dir>/`): <list domain-shaped subdirs and their purpose
  in one phrase each>. Public entrypoints: <CLI names, server bootstraps, etc.>.

  Tests in `<test dir>/` use <runner>; lint is <linter>; types are <type-checker>.
  Fixture / snapshot data lives in <path>.

  Conventions:
  - Run commands as `<wrapper> …` (locally and in CI) — NEVER skip the wrapper.
  - Branch naming: <pattern>. Commit style: <conventional / custom / freeform>.
  - Code style: <case conventions, comment policy, etc.>.
  - <Any project-specific "edit X before inventing Y" rule>.

rules:
  proposal:
    - State which existing modules this change touches and why. <Project> is a
      brownfield codebase — almost every change is a modification, not a
      greenfield addition.
    - Call out compute requirements explicitly. <If applicable: which tasks
      must run on cloud vs. local.>
    - <Other proposal-level rules specific to the project — e.g. "flag any new
      external API calls upfront", "identify which existing tests will need
      updating".>

  specs:
    - Specs are behavior contracts. Do not name internal classes, functions, or
      file paths in requirements/scenarios — those belong in `design.md`.
    - Use Given/When/Then scenarios. <Any project-specific scenario style guide
      — e.g. "for pipeline stages, frame scenarios around input/output types
      not implementation steps".>
    - Organize specs by domain mirroring the source tree where it makes sense.
    - Use SHALL/MUST for hard contracts; SHOULD for performance/quality targets.

  design:
    - Reference existing patterns in `<src dir>/` before inventing new structure.
    - Declare data shapes precisely. <Project-specific guidance — for ML: dtypes,
      column schemas. For web apps: request/response schemas.>
    - <Any design-doc rules — e.g. "if adding a pipeline stage, document the
      interface contract", "include a sequence diagram for any new external API
      interaction".>
    - Note any new system / native deps that need to land in `<env-config>`.

  tasks:
    - Group tasks by file or module. One logical unit per task.
    - <Compute marking — e.g. "[Brev] for cloud-only tasks", "[GPU] for tasks
      requiring CUDA".>
    - Include a verification task per logical unit (test, smoke check, etc.).
    - Keep scope tight. Refactor next to a feature is a signal to split.
```

### Validate before committing

```bash
openspec validate --all --strict
```

Should exit 0 on a freshly initialized project (nothing to validate yet).

**Also validate the YAML directly** — the OpenSpec CLI silently swallows YAML parse errors in `config.yaml` (see Notes). Run:
```bash
node -e "require('@fission-ai/openspec/node_modules/yaml').parse(require('fs').readFileSync('openspec/config.yaml','utf8'))"
# silent exit = OK; any throw = real bug
```

---

## Phase 4 — Wire CI validation

Brownfield projects almost always have CI. The discovery step identified the platform — wire OpenSpec validation into it. Skip this phase only if the project genuinely has no CI at all (rare).

OpenSpec is a Node CLI. Don't try to install it inside an existing Python/Rust/Go env — add a separate, lightweight CI job that uses `npx`:

```yaml
  validate-specs:
    name: OpenSpec validate
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Validate OpenSpec changes and specs
        run: npx --yes @fission-ai/openspec@latest validate --all --strict
```

Drop this job into the existing CI workflow file. On a freshly initialized project, the job passes trivially because there's nothing to validate. As changes get authored, it starts catching malformed delta specs.

If the project uses a non-GitHub CI (GitLab, CircleCI, Buildkite, etc.), translate the same shape (Node 20, `npx --yes …openspec…`, exit-on-failure) to that platform's syntax.

If the project genuinely has no CI at all, **don't create one** as part of this skill — that's a bigger decision than this playbook should make. Surface it to the user as an option.

---

## Phase 5 — Install shell completions

```bash
openspec completion install        # auto-detects user's shell
```

Supported: `bash`, `zsh`, `fish`, `powershell`. If auto-detection picks the wrong shell, pass it explicitly:
```bash
openspec completion install fish
```

Fish loads from `~/.config/fish/completions/openspec.fish` — no shell restart needed.

---

## Phase 6 — Commit and (separately) push

Commit `openspec/config.yaml` + the `validate-specs` CI job. Skip `.claude/` if it's gitignored (very common — OpenSpec writes there but the user typically ignores it).
```
chore: initialize OpenSpec (custom profile + CI validation)
```

If Phase 1 detected an existing `openspec/` setup, skip the init commit and just commit the config update.

**Do not push directly to `main`** without explicit user confirmation. Many projects (and Claude Code permission rules) gate this. Tell the user the commits are local; let them push or open a PR themselves.

---

## Phase 7 — Tell the user how to use it

End with a short crib-sheet so they know what to run next:

```
OpenSpec is ready. The first change should be small — pick something in-flight,
a small known issue, or a low-risk refactor. NOT a sweeping rewrite.

Strongly recommended for first-time use on this codebase:
  /opsx:onboard                                # walks the full lifecycle on a real (small) opportunity

After onboarding (or for follow-up changes):
  /opsx:propose <kebab-name-or-description>   # one-shot: scaffold + all artifacts
  /opsx:apply                                  # implement the tasks
  /opsx:verify                                 # check work matches artifacts
  /opsx:archive                                # merge deltas into openspec/specs/

Browsing:
  openspec list                                # active changes
  openspec view                                # interactive TUI
  openspec show <name>                         # view a change or spec
```

---

## Notes, gotchas, and judgment calls

- **`openspec/` is normally tracked.** Specs are version-controlled with code — that's the whole point. Don't add `openspec/` to `.gitignore`. (`.claude/` often is gitignored, which is fine — those files are agent-tool specific.)
- **Don't retro-spec finished work.** Only use `/opsx:propose` for changes going forward. Backfilling specs for shipped code is almost always wasted effort. If the user asks, push back: `openspec/specs/` accretes naturally as new changes archive. This is also why the first change should be something in-flight or upcoming, not a survey of existing behavior.
- **The custom profile's `/opsx:propose` and `/opsx:new + /opsx:ff` are equivalent.** Don't run both in sequence — pick one entry style.
- **Multi-language projects**: OpenSpec supports non-English artifacts. Add to context: `Language: <language code>. All artifacts must be written in <language>.`
- **Custom schemas** (`openspec schema fork spec-driven my-workflow`) let teams replace the default `proposal → specs → design → tasks` flow. Don't introduce a custom schema during initial setup unless the user asks — defaults are good defaults.
- **Watch for permission blocks.** Claude Code may block direct pushes to `main` or `git rm` of tracked files. If a tool call fails with a permission denial, surface it to the user — don't try to work around it.
- **YAML gotcha — implicit-key context inside `rules:` bullets.** A plain-scalar bullet that wraps across multiple lines must not contain `: ` (colon followed by space) ANYWHERE, and must not start with a YAML reserved indicator (`` ` ``, `&`, `*`, `!`, `|`, `>`, `'`, `"`, `%`, `@`). Both are aspects of the same underlying rule: when the parser is mid-bullet and sees something that could start an implicit key, it tries to resolve a `key: value` pair, then chokes on the multi-line continuation.

  Three confirmed-failing patterns:
  1. **`: ` mid-bullet, bullet wraps.** A colon-space inside a plain bullet is fine on a single line, but as soon as the bullet wraps to a continuation, the parser reads `before-colon` as an implicit map key and throws `Implicit keys need to be on a single line` or `Implicit map keys need to be followed by map values`.
     ```yaml
     - Declare data shapes precisely: exact Rust type signatures for     # ← fails
       anything that crosses a public boundary.
     ```
     The colon doesn't have to be at the line end — `: ` on line 2 of a 3-line bullet fails just as hard. Single-line bullets with `: ` are fine.
  2. **Backtick (or other reserved indicator) at bullet start.** The first character of the bullet's value cannot be a reserved indicator.
     ```yaml
     - `colony-core` is pure-logic.    # ← fails
     ```
  3. **Backtick at the start of a continuation line whose prior line ends with `:`.** A trailing colon opens an implicit-key context; the continuation then starts a fresh value position where the reserved-indicator rule fires.
     ```yaml
     - Organize specs by domain mirroring the source tree where it makes sense:
       `detection/`, `tracking/`, `ocr/`, `pipeline/`.    # ← fails
     ```
     Continuation lines that start with a backtick are **fine** when the prior line ends with normal text (`.`, `,`, a word) — the parser treats them as one continuous plain scalar.

  Block scalars (`context: |`, `>-`) are exempt — colons, backticks, and other reserved indicators all parse fine inside a literal or folded block.

  Three fixes (in order of preference):
  1. **Replace the colon with non-colon prose punctuation** — em-dash (`—`), period, or restructure the sentence. Usually cleanest and most readable.
  2. **Wrap the bullet in double quotes**: `- "Declare data shapes precisely: exact Rust type signatures for anything..."`. Quoted scalars don't have the implicit-key or reserved-indicator rules.
  3. **Use a folded `>-` block scalar** if the bullet is long.

  **Failure mode (openspec 1.3.x).** This is worse than "broken rules silently dropped". The two layers behave differently:
  - **YAML-level parse error** (the colon-space and reserved-indicator bugs above): `readProjectConfig()` in `OpenSpec/src/core/project-config.ts` wraps `parseYaml(content)` in a try/catch, emits a `console.warn`, and returns `null`. The **entire** config — all `context`, all `rules` — disappears. AI artifact generation falls back to OpenSpec defaults with none of your project context plumbed in.
  - **Schema-level field error** (a rule that isn't a string, a `rules` value that isn't an object): the YAML parses fine, then per-field Zod `safeParse` rejects only the malformed entry and emits a `console.warn`. Just that one artifact's rules drop; everything else survives. This is the only case where "broken section silently dropped" is accurate.

  Why no visible warning: most CLI commands (`openspec list`, `openspec validate`, `openspec show`) don't read `config.yaml` at all — they just walk `openspec/changes/` and `openspec/specs/` on the filesystem. Only artifact-generating commands (`/opsx:propose`, `/opsx:new` + friends) call `readProjectConfig()`. And when they do, the `console.warn` goes to stderr, where Claude Code's slash-command wrappers, AI agent invocations, and hook contexts typically buffer or drop it.

  **Validation: do NOT trust `openspec` CLI output.** Parse the file directly with the same `yaml` package OpenSpec ships:
  ```bash
  node -e "require('@fission-ai/openspec/node_modules/yaml').parse(require('fs').readFileSync('openspec/config.yaml','utf8'))"
  # silent exit = OK; any throw = real bug
  ```
  Run this every time you finish editing `config.yaml`. (The exact path is whatever `npm root -g`/`@fission-ai/openspec/node_modules/yaml` resolves to on the system; on a global install with mise/nvm-style Node it's under `<node-modules-root>/@fission-ai/openspec/node_modules/yaml`.)
- **Each project is different.** This playbook is the *shape* of the work, not a literal script. Reuse the SKILL.md discovery findings before writing the config; that's where the value is.
