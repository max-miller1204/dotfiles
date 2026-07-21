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

# Resolve symlink chains without GNU readlink -f, which is unavailable on macOS.
# Prints the canonical target path. Fails without output when the chain ends in
# a directory that no longer exists, so callers can diagnose dangling links.
# Fails with a stderr diagnostic after 40 hops, mirroring the kernel's ELOOP
# limit, so a cyclic link cannot hang callers.
resolve_link() {
	local path="$1" link directory hops=0
	while [[ -L "$path" ]]; do
		if ((++hops > 40)); then
			printf 'Symlink chain exceeded 40 hops (cycle?): %s\n' "$1" >&2
			return 1
		fi
		link="$(readlink "$path")"
		if [[ "$link" == /* ]]; then
			path="$link"
		else
			path="$(dirname "$path")/$link"
		fi
	done
	directory="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || return 1
	printf '%s/%s\n' "$directory" "$(basename "$path")"
}

# Prepend directories to PATH so Home Manager and user-local commands resolve
# in a non-interactive `chezmoi apply`. Arguments are kept
# in order, so the first argument has the highest priority on PATH.
prepend_path() {
	local prefix="" dir
	for dir in "$@"; do
		prefix="${prefix:+$prefix:}$dir"
	done
	export PATH="${prefix:+$prefix:}$PATH"
}
