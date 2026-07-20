verify_home_manager_lsp_command() {
	local command_name="$1"
	local command_path="$HOME_MANAGER_BIN/$command_name"
	local path_command target

	if [[ ! -x "$command_path" ]]; then
		printf 'Missing Home Manager LSP command: %s\n' "$command_path" >&2
		return 1
	fi

	target="$(readlink "$command_path" 2>/dev/null || true)"
	case "$target" in
	/nix/store/*) ;;
	*)
		printf 'Home Manager LSP command does not resolve into /nix/store: %s -> %s\n' \
			"$command_path" "${target:-<not-a-symlink>}" >&2
		return 1
		;;
	esac

	path_command="$(command -v "$command_name" 2>/dev/null || true)"
	if [[ "$path_command" != "$command_path" ]]; then
		printf 'Home Manager LSP command loses PATH precedence: %s -> %s\n' \
			"$command_name" "${path_command:-<missing>}" >&2
		return 1
	fi
}

probe_home_manager_lsp_command() {
	local command_name="$1"
	shift

	verify_home_manager_lsp_command "$command_name" || return 1
	if ! "$HOME_MANAGER_BIN/$command_name" "$@" >/dev/null 2>&1; then
		printf 'Home Manager LSP probe failed: %s' "$command_name" >&2
		printf ' %q' "$@" >&2
		printf '\n' >&2
		return 1
	fi
}

lsp_initialize_response_has() {
	local member="$1"
	local output="$2"
	grep -Eq \
		"\"id\"[[:space:]]*:[[:space:]]*1.*\"$member\"|\"$member\".*\"id\"[[:space:]]*:[[:space:]]*1" \
		"$output"
}

probe_lsp_initialize() {
	local server="$1"
	local label="$2"
	local without_node_path="$3"
	local input output payload pid="" probe_dir result=1

	if ! probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-lsp.XXXXXX")"; then
		printf '%s\n' "Unable to create a temporary directory for $label" >&2
		return 1
	fi
	input="$probe_dir/input"
	output="$probe_dir/output"
	if ! mkfifo "$input"; then
		printf '%s\n' "Unable to create the LSP probe FIFO for $label" >&2
		rm -rf "$probe_dir"
		return 1
	fi

	# Keep both FIFO ends open while the server handles initialize. The
	# TypeScript probe explicitly removes NODE_PATH to prove its Nix closure
	# replaces the former mise global-prefix workaround.
	if ! exec 3<>"$input"; then
		printf '%s\n' "Unable to open the LSP probe FIFO for $label" >&2
		rm -rf "$probe_dir"
		return 1
	fi
	if [[ "$without_node_path" == true ]]; then
		env -u NODE_PATH "$server" --stdio <"$input" >"$output" \
			2>"$probe_dir/error" &
	else
		"$server" --stdio <"$input" >"$output" 2>"$probe_dir/error" &
	fi
	pid=$!
	payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
	if ! printf 'Content-Length: %d\r\n\r\n%s' \
		"${#payload}" "$payload" >&3; then
		printf '%s\n' "Unable to write the LSP initialize request for $label" >&2
	else
		for _ in {1..50}; do
			if lsp_initialize_response_has result "$output"; then
				result=0
				break
			fi
			if lsp_initialize_response_has error "$output"; then
				break
			fi
			if ! kill -0 "$pid" 2>/dev/null; then
				break
			fi
			sleep 0.1
		done
	fi

	if [[ -n "$pid" ]]; then
		kill "$pid" >/dev/null 2>&1 || true
		wait "$pid" 2>/dev/null || true
	fi
	exec 3>&-

	if [[ "$result" -ne 0 ]]; then
		printf '%s failed the LSP initialize probe.\n' "$label" >&2
		if [[ -s "$output" ]]; then
			cat "$output" >&2
		fi
		if [[ -s "$probe_dir/error" ]]; then
			cat "$probe_dir/error" >&2
		fi
	fi
	rm -rf "$probe_dir"
	return "$result"
}

verify_home_manager_lsp_servers() {
	local HOME_MANAGER_BIN="$1"
	local fail=0 initialize_probe label probe_arg probe_bin spec
	local verify_bin without_node_path
	shift

	prepend_path "$HOME_MANAGER_BIN"
	hash -r
	log "Verifying Home Manager language servers"
	for spec in "$@"; do
		IFS='|' read -r verify_bin probe_bin probe_arg initialize_probe \
			without_node_path label <<<"$spec"
		if ! verify_home_manager_lsp_command "$verify_bin"; then
			fail=1
		fi
		if ! probe_home_manager_lsp_command "$probe_bin" "$probe_arg"; then
			fail=1
		fi
		if [[ "$initialize_probe" == true ]] &&
			! probe_lsp_initialize "$HOME_MANAGER_BIN/$verify_bin" \
				"$label" "$without_node_path"; then
			fail=1
		fi
	done

	if [[ "$fail" -ne 0 ]]; then
		echo "One or more Home Manager LSP servers failed verification" >&2
		return 1
	fi
	log "All Home Manager LSP servers passed startup and version probes"
}
