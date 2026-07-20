# Install a package from a third-party apt repository: drop its signing key into a
# keyring, register the repo under sources.list.d, then update and install. GitHub
# CLI (gh) and 1Password use this keyring+list+update+install dance now; only the
# label, keyring path, key URL, repo line, list path, and
# package name differ. gh's published keyring is already binary, but `gpg --dearmor`
# is a byte-for-byte pass-through on binary OpenPGP input, so the same call works.
# Usage: install_aptrepo LABEL KEYRING KEY_URL REPO_LINE LIST_PATH PACKAGE
install_aptrepo() {
    local label="$1" keyring="$2" key_url="$3" repo_line="$4" list_path="$5" package="$6"
    log "Installing $label"
    sudo mkdir -p -m 755 "$(dirname "$keyring")"
    curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring"
    printf '%s\n' "$repo_line" | sudo tee "$list_path" >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y "$package"
}