# Evidence: switch pi-subagents to the nicobailon fork

Every artifact here was produced by running the real consumers of the changed files, not by reading them.
The fork resolving the configuration is the installed `pi-subagents` v0.42.1 from `git+https://github.com/nicobailon/pi-subagents.git`, driven through its own `discoverAgents`, `resolveWatchdogConfigStrict`, `checkModelScope` and `getSupportedThinkingLevels`.
Thinking support is resolved against this machine's real pi models store, `~/.pi/agent/models-store.json`, which is the catalog the E2E hands the pin checker.
The settings and agent definitions are read from a throwaway agent dir seeded with the committed `dot_pi/agent/` files, so nothing under `$HOME` was mutated.

| File | What it shows |
| --- | --- |
| [`01-subagent-routing.txt`](01-subagent-routing.txt) | The routing the fork actually resolves: all eight builtins plus `shaper` on their capability tiers, zero Anthropic models, and `checkModelScope` rejecting Anthropic ids reached through a per-run override. Also shows the fork registering neither retired definition when `Explore.md` and `Plan.md` are put back. |
| [`02-watchdog-thinking.txt`](02-watchdog-thinking.txt) | The `max` versus `high` correctness fix, resolved twice by the fork's own strict watchdog loader: this branch reviews at thinking `max`, the pre-fix commit `1cc291e` reviews with thinking OFF. The same two configurations through `check-pi-model-pins.sh` with the real models store, which is the invocation the native E2E performs. |
| [`03-pi-startup-and-commands.txt`](03-pi-startup-and-commands.txt) | pi 0.84.0 starting on the committed settings and reporting the fork's slash commands (`/subagents`, `/subagents-watchdog`, `/subagents-fleet`, ...) to a client, with no extension errors. |
| [`04-chezmoi-retired-agents.txt`](04-chezmoi-retired-agents.txt) | `chezmoi apply` into a throwaway destination that starts out holding the retired definitions, run with and without `.chezmoiremove`, so the deletion is attributable to the new mechanism. |
| [`05-config-guards.txt`](05-config-guards.txt) | Both CI guards accepting the committed configuration, the pre-fork base commit failing all seven structural invariants, and the 49-case regression suite that proves the guards still reject what they exist to reject. |
