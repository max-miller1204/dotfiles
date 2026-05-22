#!/usr/bin/env bash
set -euo pipefail

secret_file="${HOME}/.config/secrets/context7_api_key"
if [[ ! -r "$secret_file" ]]; then
  echo "Missing context7 key at $secret_file" >&2
  echo "Ensure the chezmoi age identity is at ~/.config/chezmoi/age-key.txt," >&2
  echo "then run: chezmoi apply" >&2
  exit 1
fi

CONTEXT7_API_KEY="$(tr -d '\n' < "$secret_file")"
export CONTEXT7_API_KEY
exec npx -y @upstash/context7-mcp@latest "$@"
