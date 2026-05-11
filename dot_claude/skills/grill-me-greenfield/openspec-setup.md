# OpenSpec setup playbook (greenfield variant)

Bundled with the `grill-me-greenfield` skill. Run after the synthesis step has written `SPEC.md` and `ROADMAP.md` at the project root. The canonical brownfield-friendly playbook lives at `~/openspec-setup.md` — this is a slimmer variant tailored to fresh projects.

You're an agent helping the user adopt **OpenSpec** in a fresh project. Read this whole file, then execute the phases below. Adapt judgment to what you find — don't blindly follow steps when the project's reality contradicts them.

OpenSpec (`@fission-ai/openspec` on npm) is a spec-driven development system: per-change folders with `proposal.md`, `design.md`, `tasks.md`, and **delta specs** that merge into a living `openspec/specs/` source-of-truth on archive.

The goal of this playbook is to leave the project in a state where:
1. OpenSpec is initialized with the **custom** profile (all 11 commands available).
2. `openspec/config.yaml` has real, project-specific context + rules — drawing primarily from the `SPEC.md` you just wrote, plus whatever scaffold exists.
3. Fish/zsh/bash shell completions are installed for the user's shell.
4. The OpenSpec init + config is committed (and `SPEC.md`/`ROADMAP.md` are committed too if they aren't already).

CI validation is optional on a greenfield repo — only wire it if CI already exists.

---

## Phase 0 — Sanity checks before doing anything

Confirm:
- Working directory is the project root.
- Inside a git repo (`git rev-parse --git-dir`). If not, `git init` first.
- `openspec --version` exists. If not, install globally:
  ```bash
  npm install -g @fission-ai/openspec@latest
  ```
  Requires Node 20.19+. If `npm` is missing, ask the user how they prefer to install Node (mise, nvm, brew, etc.) — don't assume.

---

## Phase 1 — Initialize OpenSpec with the custom profile

The `custom` profile gives all 11 slash commands (propose, explore, new, continue, ff, apply, verify, sync, archive, bulk-archive, onboard) instead of the 4-command `core` default. Better for a project that wants the full surface area.

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

If `--profile custom` fails (the CLI's preset shortcut for switching profiles only accepts `core`), force it via the global config file:
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

## Phase 2 — Write a SPEC-aware `openspec/config.yaml`

This is the single highest-leverage step. The `context` and `rules` here are injected into **every** AI prompt for artifact generation — so good context here saves you re-explaining the stack on every `/opsx:propose`.

### Inputs

You have two strong inputs already on disk:
1. **`SPEC.md` at the project root** — product context: problem, users, goals, non-goals, core capabilities, constraints. Use this for the *first half* of `context:` (what the project does, who it's for, what success means).
2. **The scaffold** — whatever language/framework files exist (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `flake.nix`, `Dockerfile`, `mise.toml`, etc.). Use these for the *second half* of `context:` (stack, package manager, env wrappers, test/lint commands).

If the scaffold is minimal or absent, write the stack section based on what the user committed to during the interview, and mark unconfirmed slots clearly so they're easy to fill in later.

### What to probe for in the scaffold

- **Language + version**: from package metadata files. Note runtime version constraints.
- **Package manager / dep manager**: `uv`, `poetry`, `pip`, `pnpm`, `npm`, `yarn`, `bun`, `cargo`, `go mod`. Note lock-file flavor.
- **Env / system deps**: `flake.nix`, `Dockerfile`, `.tool-versions`, `mise.toml`. Note if commands run inside a wrapper (`nix develop`, `docker compose run`, etc.) — this matters for CI and for AI-suggested commands.
- **Test / lint / type-check tooling**: scan `pyproject.toml`, `package.json` scripts, `.github/workflows/`. Note exact commands.
- **Source layout**: `ls src/` or equivalent. On a fresh greenfield project this may be empty — list the planned domains from SPEC.md "Core capabilities" instead.
- **Existing CLAUDE.md / AGENTS.md / README.md conventions**: any explicit "use X, prefer Y" rules. Hoist them into the OpenSpec context so they propagate.
- **Branch naming + commit style**: `git log --oneline -20` + look for any documented convention.

### Template to start from

```yaml
schema: spec-driven

context: |
  Project: <one-line description from SPEC.md problem/goals.>

  Users and goals: <distill SPEC.md "Users" and "Goals" sections — who it's for
  and what success looks like in observable terms.>

  Runtime: <language + version>. Dependencies managed by <tool> (<exact command>).
  <Env wrapper notes — e.g. "Every command runs inside `nix develop` because
  system deps come from nixpkgs.">. <Compute scale notes — e.g. "Local compute is
  weak; heavy ML training runs on Brev.">

  Stack: <key libraries that should appear in every artifact — frameworks,
  data layers, test runners.>

  Source layout (`<src dir>/`): <list domain-shaped subdirs and their purpose
  in one phrase each. On a fresh greenfield project this may be empty — list
  the planned domains from SPEC.md "Core capabilities" instead.>. Public
  entrypoints: <CLI names, server bootstraps, etc.>.

  Tests in `<test dir>/` use <runner>; lint is <linter>; types are <type-checker>.
  Fixture / snapshot data lives in <path>.

  Conventions:
  - Run commands as `<wrapper> …` (locally and in CI) — NEVER skip the wrapper.
  - Branch naming: <pattern>. Commit style: <conventional / custom / freeform>.
  - Code style: <case conventions, comment policy, etc.>.

  Non-goals: <pull from SPEC.md — explicitly call out what's out of scope so
  proposals don't drift.>

rules:
  proposal:
    - State which existing modules this change touches and why. Early changes
      are greenfield additions; flag clearly when something is the first module
      in a domain vs. modifying an existing one.
    - Call out compute requirements explicitly. <If applicable: which tasks
      must run on cloud vs. local.>
    - Link back to the relevant work area in `ROADMAP.md` so it's clear which
      bucket this change is draining.

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
      On the first few changes there's no prior pattern to follow — that's fine,
      establish one explicitly and note it.
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

## Phase 3 — Wire CI validation (only if CI already exists)

A greenfield repo usually has no CI yet. **Don't create one** as part of this skill — that's a bigger decision than this playbook should make. Surface it to the user as an option and move on.

If the project does have CI (`.github/workflows/`, `.gitlab-ci.yml`, etc.), offer to add the OpenSpec validation step.

For GitHub Actions, add this job to the existing workflow file:

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

OpenSpec is a Node CLI. Don't try to install it inside an existing Python/Rust/Go env — add a separate, lightweight CI job that uses `npx`.

For non-GitHub CI (GitLab, CircleCI, Buildkite, etc.), translate the same shape (Node 20, `npx --yes …openspec…`, exit-on-failure) to that platform's syntax.

---

## Phase 4 — Install shell completions

```bash
openspec completion install        # auto-detects user's shell
```

Supported: `bash`, `zsh`, `fish`, `powershell`. If auto-detection picks the wrong shell, pass it explicitly:
```bash
openspec completion install fish
```

Fish loads from `~/.config/fish/completions/openspec.fish` — no shell restart needed.

---

## Phase 5 — Commit (and separately push)

Two separate commits keep history clean:

1. **Product docs** (if `SPEC.md`/`ROADMAP.md` aren't already in their own commit):
   ```
   docs: initial product spec and roadmap
   ```

2. **OpenSpec infrastructure** — `openspec/config.yaml` plus the OpenSpec init artifacts. Skip `.claude/` if it's gitignored (very common — OpenSpec writes there but the user typically ignores it).
   ```
   chore: initialize OpenSpec (custom profile + tailored config.yaml)
   ```

**Do not push directly to `main`** without explicit user confirmation. Many projects (and Claude Code permission rules) gate this. Tell the user the commits are local; let them push or open a PR themselves.

---

## Phase 6 — Tell the user how to use it

End with a short crib-sheet so they know what to run next:

```
OpenSpec is ready. Pick a work area from ROADMAP.md, then:
  /opsx:propose <kebab-name-or-description>   # one-shot: scaffold + all artifacts
  /opsx:apply                                  # implement the tasks
  /opsx:verify                                 # check work matches artifacts
  /opsx:archive                                # merge deltas into openspec/specs/

Browsing:
  openspec list                                # active changes
  openspec view                                # interactive TUI
  openspec show <name>                         # view a change or spec

If you've never used OpenSpec, run /opsx:onboard once — it walks you through
the full lifecycle on a real (small) opportunity in this codebase.
```

---

## Notes, gotchas, and judgment calls

- **`openspec/` is normally tracked.** Specs are version-controlled with code — that's the whole point. Don't add `openspec/` to `.gitignore`. (`.claude/` often is gitignored, which is fine — those files are agent-tool specific.)
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
- **Each project is different.** This playbook is the *shape* of the work, not a literal script. Read SPEC.md and the scaffold before writing the config; that's where the value is.
