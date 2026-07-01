# Install a package from a third-party apt repository: drop its signing key into a
# keyring, register the repo under sources.list.d, then update and install. eza,
# gum, and 1Password all share this keyring+list+update+install dance; only the
# label, keyring path, key URL, repo line, list path, and package name differ.
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