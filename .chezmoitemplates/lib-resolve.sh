# Resolve mise without relying on PATH activation: the mise bootstrap installs it
# under ~/.local/bin, which is not on PATH in a non-interactive `chezmoi apply`.
# Prints the resolved mise path on stdout, or nothing if mise is not installed.
resolve_mise() {
	if command -v mise >/dev/null 2>&1; then
		command -v mise
	elif [[ -x "$HOME/.local/bin/mise" ]]; then
		printf '%s\n' "$HOME/.local/bin/mise"
	fi
}

# Resolve Nix without relying on shell startup files. The Determinate installer
# exposes the daemon profile under /nix even before a newly installed shell has
# reloaded its environment.
resolve_nix() {
	if command -v nix >/dev/null 2>&1; then
		command -v nix
	elif [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
		printf '%s\n' /nix/var/nix/profiles/default/bin/nix
	fi
}

# Resolve a rustup-managed binary (rustup itself, or a component shim such as
# rust-analyzer) without relying on PATH activation: the mise rust bootstrap
# installs them under ~/.cargo/bin, which is not on PATH in a non-interactive
# apply. Prints the resolved path on stdout, or nothing if it is not installed.
resolve_rustup() {
	local bin="$1"
	if command -v "$bin" >/dev/null 2>&1; then
		command -v "$bin"
	elif [[ -x "$HOME/.cargo/bin/$bin" ]]; then
		printf '%s\n' "$HOME/.cargo/bin/$bin"
	fi
}

# Prepend directories to PATH so Home Manager, mise shims, and ~/.local/bin
# resolve in a non-interactive `chezmoi apply`. Arguments are kept
# in order, so the first argument has the highest priority on PATH.
prepend_path() {
	local prefix="" dir
	for dir in "$@"; do
		prefix="${prefix:+$prefix:}$dir"
	done
	export PATH="${prefix:+$prefix:}$PATH"
}
