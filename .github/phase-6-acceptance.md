<!-- markdownlint-disable MD013 -->

# Phase 6 acceptance ledger

Phase 6 expands platform evidence and imposes a soak gate before the final manual mise cleanup.
Phase 5 ownership remains active throughout this phase.
CI success cannot close the real WSL2, physical Apple Silicon GUI, primary-machine soak, no-GC, or manual cleanup gates.
Do not run Nix garbage collection, expire generations, wipe profile history, or delete rollback data during the soak.
Do not automate mise archival or deletion in chezmoi, Home Manager, Fish, or CI.

## Candidate

- Source SHA: `pending`
- Soak start UTC: `pending`
- Soak completion UTC: `pending`
- Reviewer: `pending`
- Overall status: `blocked`

The overall status remains blocked until every required row has immutable evidence and reviewer approval.
Workflow evidence must name the exact source SHA and include artifact checksums.
Machine evidence must redact usernames, account identifiers, serial numbers, and secret-bearing output where appropriate.

## Primary machine inventory

The required soak set is fixed before the first checkpoint so a machine cannot be omitted after a failure.
Stable labels are intentionally redacted and must not be replaced with hostnames.

| Stable label | Platform class | Required for soak | Operator | Status |
| --- | --- | --- | --- | --- |
| `primary-linux-desktop` | Native Ubuntu desktop | yes | pending | pending |
| `primary-macos-aarch64` | Physical Apple Silicon macOS | yes | pending | pending |
| `acceptance-wsl2` | Fresh Ubuntu 24.04 WSL2 | platform gate only | pending | pending |

## Gate ledger

| Gate | Machine or workflow | Required evidence | Evidence URL or artifact | Reviewer | Status |
| --- | --- | --- | --- | --- | --- |
| Native Ubuntu desktop fresh apply | `e2e-native-ubuntu`, `linux-desktop` | First apply starts without user Home Manager profiles and records the selected configuration | pending | pending | pending |
| Native Ubuntu desktop second apply | `e2e-native-ubuntu`, `linux-desktop` | Second apply succeeds, preserves both profile targets, and does not rerun unchanged runtime hooks | pending | pending | pending |
| Headless Linux fresh apply | `e2e-native-ubuntu`, `linux-headless` | First apply selects `ci@linux-headless` and logs GUI omission | pending | pending | pending |
| Headless Linux second apply | `e2e-native-ubuntu`, `linux-headless` | Second apply succeeds, preserves both profile targets, and Ghostty config remains absent | pending | pending | pending |
| Interactive Linux profile prompt | `prompt-selection` | Default selects desktop and `y` selects headless at the candidate SHA | pending | pending | pending |
| Real WSL2 fresh and second apply | Fresh Ubuntu 24.04 WSL2 distribution | Both applies succeed on a Microsoft WSL2 kernel and select `max@wsl` even when headless is true | pending | pending | pending |
| WSL2 integrations | Same WSL2 distribution | GUI omission, `op.exe`, systemd PID 1, Nix daemon store, plain direnv, and nix-direnv flake checks pass | pending | pending | pending |
| Native Apple Silicon activation | Hosted or physical arm64 macOS | Two native activations select `ci@macos-aarch64` or `max@macos-aarch64` and preserve both profile targets | pending | pending | pending |
| Physical Apple Silicon GUI acceptance | Primary Apple Silicon Mac | Required GUI applications launch and chezmoi-managed GUI behavior is visible | pending | pending | pending |
| Linux primary cycle 1 | `primary-linux-desktop` | Update or apply succeeds with selected configuration, profile links, ownership paths, and drift recorded | pending | pending | pending |
| Linux primary cycle 2 | `primary-linux-desktop` | A later update or apply succeeds with the same evidence fields | pending | pending | pending |
| Linux no-GC attestation | `primary-linux-desktop` | Operator confirms no store GC, generation expiry, history wipe, or manual store cleanup occurred | pending | pending | pending |
| macOS primary cycle 1 | `primary-macos-aarch64` | Update or apply succeeds with selected configuration, profile links, ownership paths, and drift recorded | pending | pending | pending |
| macOS primary cycle 2 | `primary-macos-aarch64` | A later update or apply succeeds with the same evidence fields | pending | pending | pending |
| macOS no-GC attestation | `primary-macos-aarch64` | Operator confirms no store GC, generation expiry, history wipe, or manual store cleanup occurred | pending | pending | pending |
| Manual mise cleanup | Every previously mise-managed primary machine | Cleanup occurs only after every prior gate passes and archives are recorded | pending | pending | blocked |
| Post-cleanup apply | Every cleaned primary machine | Fresh Fish cannot resolve mise, chezmoi apply succeeds, and no mise path is recreated | pending | pending | blocked |

## Automated candidate run

Dispatch the Ubuntu workflow against an immutable candidate commit:

```sh
gh workflow run e2e-native-ubuntu.yml \
  --ref feat/home-manager-phase-6-platform-soak \
  -f expected_head="$(git rev-parse HEAD)"
```

Acceptance requires both matrix jobs and the dependent interactive prompt job to pass.
Download `e2e-native-ubuntu-linux-desktop`, `e2e-native-ubuntu-linux-headless`, and `e2e-linux-profile-prompt` and record their URLs and checksums above.
The normal CI workflow supplies native arm64 and x86_64 macOS activation evidence but does not install or launch GUI applications.

## Real WSL2 gate

Use a fresh Ubuntu 24.04 WSL2 distribution with systemd enabled and Windows 1Password CLI integration configured.
Answer yes to the headless prompt so the run also proves that WSL selection takes precedence.
Capture the first `chezmoi init --apply` log, then run the second apply with explicit status and profile evidence.
Record `uname -r`, the exact `max@wsl` selection, systemd PID 1, and a successful Nix daemon-store ping.
Run `op.exe --version` and `op.exe whoami`, but redact account details from retained evidence.
Use the clean candidate checkout that chezmoi installed as its source directory:

```sh
source_dir=$(chezmoi source-path)
expected_sha='<copy the independently reviewed Candidate source SHA here>'
actual_sha=$(git -C "$source_dir" rev-parse HEAD)
test "$actual_sha" = "$expected_sha"
test -z "$(git -C "$source_dir" status --porcelain)"
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
profile="$state_home/nix/profiles/home-manager"
package_profile="$state_home/nix/profiles/profile"
profile_before=$(readlink -f "$profile")
package_before=$(readlink -f "$package_profile")
set +e
chezmoi apply --force --no-tty 2>&1 | tee second-apply.log
second_status=${PIPESTATUS[0]}
set -e
profile_after=$(readlink -f "$profile")
package_after=$(readlink -f "$package_profile")
EXPECTED_SOURCE_SHA="$expected_sha" \
APPLY_LOG="$PWD/apply.log" \
SECOND_APPLY_LOG="$PWD/second-apply.log" \
SECOND_APPLY_STATUS="$second_status" \
PROFILE_BEFORE_SECOND="$profile_before" \
PROFILE_AFTER_SECOND="$profile_after" \
PACKAGE_BEFORE_SECOND="$package_before" \
PACKAGE_AFTER_SECOND="$package_after" \
  bash "$source_dir/.github/e2e/verify.sh" verify hardware max@wsl
```

The report must end with `FAIL=0` and must include plain direnv, nix-direnv, project-runtime precedence, GUI omission, and Ghostty-config absence checks.

## Physical Apple Silicon gate

Record the source SHA, macOS version, hardware model with serial number redacted, and `uname -m` equal to `arm64`.
Run `chezmoi apply` and confirm that the recorded configuration is `max@macos-aarch64`.
Record Home Manager and package profile targets before and after a second apply.
Confirm `op whoami` succeeds without retaining account details.
Launch and inspect Ghostty, 1Password, Raycast, AeroSpace, Karabiner-Elements, and every other required GUI application from the package manifest.
Confirm that managed Ghostty, Raycast, AeroSpace, and Karabiner behavior is visible.
A hosted macOS result cannot substitute for this GUI gate.

## Primary-machine soak

For every designated primary machine, record the starting Home Manager and package profile histories.
Complete two successful update or apply cycles at separate soak checkpoints.
For each cycle, record UTC time, source SHA, selected configuration, command, exit status, both profile links, command ownership paths, and unexpected chezmoi drift.
Keep every Home Manager generation, Nix profile history entry, runtime rollback archive, and retained mise directory throughout the soak.
Record a reviewer-approved no-GC attestation after the second cycle.

## Post-soak manual cleanup

The operator may begin this section only after every preceding gate is passed and reviewed.
Record the cleanup timestamp and the archive destination before changing anything.
Manually archive `~/.config/mise`, `~/.local/share/mise`, `~/.cache/mise`, and `~/.local/state/mise` where present.
Manually archive or remove `~/.local/bin/mise` where present.
On macOS, manually uninstall the Homebrew mise formula.
Launch a completely fresh Fish login shell and confirm that `mise` does not resolve.
Run the ownership checks and a normal `chezmoi apply`.
Confirm that chezmoi neither recreates nor deletes any mise path.
Keep the automated retained-mise fixture test permanently because it proves that future applies remain non-destructive.
