# Install-method helpers that the package loop in
# run_once_before_10-install-packages.sh.tmpl dispatches to, one per method named
# in .chezmoidata/packages.yaml. Each helper reproduces exactly the idempotency
# guard that method used before the manifest refactor, so re-runs stay safe
# no-ops. Included after lib-log.sh (provides `log` + set -euo pipefail),
# lib-resolve.sh (provides PATH helpers), and lib-apt.sh (provides
# `install_aptrepo`), so those helpers are already defined here. Depending on the
# target OS some of these are defined-but-unused (e.g. install_apt on macOS,
# install_cask on Linux); that is expected and stays shellcheck-clean at
# --severity=warning. The `script` method has no helper: its vendor installers
# carry shell quoting that cannot round-trip through a positional argument, so the
# loop emits them verbatim inline (guard + command) instead.

# brew formula: core CLI tools. Strict - a failed core formula aborts the run,
# matching the un-guarded `brew install a b c` batch before the refactor (brew is
# itself idempotent, so no command -v guard). brev opts into `|| true` at the call
# site via its `tolerant` flag, mirroring the old optional-formula behavior.
install_brew() {
    log "Installing $1 via Homebrew"
    brew install "$1"
}

# brew cask: GUI apps. Tolerant (`|| true`) so an unavailable cask does not abort
# the run, matching every `brew install --cask x || true` before the refactor.
install_cask() {
    log "Installing $1 via Homebrew cask"
    brew install --cask "$1" || true
}

# apt package. With a PPA, guard the whole add-repo + update + install on the
# command (matching the ghostty block); without one, install unconditionally
# (apt is idempotent), matching the un-guarded base `apt-get install -y ...` batch.
install_apt() {
    local bin="$1" pkg="$2" ppa="${3:-}"
    if [[ -n "$ppa" ]]; then
        command -v "$bin" >/dev/null 2>&1 && return 0
        log "Installing $pkg from $ppa"
        sudo add-apt-repository -y "$ppa"
        sudo apt-get update -y
        sudo apt-get install -y "$pkg"
    else
        log "Installing $pkg via apt"
        sudo apt-get install -y "$pkg"
    fi
}

# flatpak app from flathub. Ensures flatpak itself (guarded on the flatpak
# command) and the flathub remote (--if-not-exists) before guarding the app on
# `flatpak info <id>`, exactly as the pre-refactor flatpak block did. remote-add
# is idempotent, so ensuring it per app is harmless.
install_flatpak() {
    local appid="$1"
    if ! command -v flatpak >/dev/null 2>&1; then
        log "Installing flatpak"
        sudo apt-get install -y flatpak
    fi
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    if ! flatpak info "$appid" >/dev/null 2>&1; then
        log "Installing $appid via flatpak"
        sudo flatpak install -y flathub "$appid"
    fi
}

# .deb fetched from a URL and installed via apt (which resolves its deps). Guarded
# at the call site (like install_aptrepo), so obsidian's URL - a GitHub-API lookup
# - is resolved into a variable only inside the caller's `command -v` guard and
# never on an already-installed re-run; matches the discord/obsidian download blocks.
install_deburl() {
    local bin="$1" url="$2"
    log "Installing $bin from a downloaded .deb"
    local deb
    deb="$(mktemp --suffix=.deb)"
    curl -fsSL -o "$deb" "$url"
    sudo apt-get install -y "$deb"
    rm -f "$deb"
}

# debsig verification policy + keyring, independent of the apt keyring/list. Only
# 1Password ships one; run before install_aptrepo, matching the pre-refactor
# 1Password block. The policy/keyring filenames are 1Password's own.
install_debsig() {
    local policy_id="$1" pol_url="$2" key_url="$3"
    sudo mkdir -p "/etc/debsig/policies/$policy_id/"
    curl -fsSL "$pol_url" | sudo tee "/etc/debsig/policies/$policy_id/1password.pol" >/dev/null
    sudo mkdir -p "/usr/share/debsig/keyrings/$policy_id"
    curl -fsSL "$key_url" | sudo gpg --dearmor --output "/usr/share/debsig/keyrings/$policy_id/debsig.gpg"
}
