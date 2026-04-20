#!/usr/bin/env bash
set -euo pipefail

# Plain-file secret, managed outside chezmoi — drop the raw key in yourself.
secret_file="${HOME}/.config/secrets/context7_api_key"
if [[ ! -r "$secret_file" ]]; then
  echo "Missing context7 key at $secret_file" >&2
  echo "Create it with: mkdir -p ~/.config/secrets && chmod 700 ~/.config/secrets" >&2
  echo "Then: echo -n '<key>' > $secret_file && chmod 600 $secret_file" >&2
  exit 1
fi

export CONTEXT7_API_KEY="$(tr -d '\n' < "$secret_file")"
exec npx -y @upstash/context7-mcp "$@"
