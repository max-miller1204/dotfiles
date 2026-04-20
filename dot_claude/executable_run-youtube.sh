#!/usr/bin/env bash
set -euo pipefail

secret_file="${HOME}/.config/secrets/youtube_api_key"
if [[ ! -r "$secret_file" ]]; then
  echo "Missing YouTube API key at $secret_file" >&2
  echo "Create it with: mkdir -p ~/.config/secrets && chmod 700 ~/.config/secrets" >&2
  echo "Then: echo -n '<key>' > $secret_file && chmod 600 $secret_file" >&2
  exit 1
fi

export YOUTUBE_API_KEY="$(tr -d '\n' < "$secret_file")"
# Requires Nix installed (both Ubuntu and Mac). Uses the user's own flake input.
exec nix run github:max-miller1204/youtube-mcp-server-nix -- "$@"
