#!/usr/bin/env bash
set -euo pipefail

if ! command -v op >/dev/null 2>&1; then
  echo "op (1Password CLI) not found on PATH" >&2
  echo "Install: https://developer.1password.com/docs/cli/get-started/" >&2
  exit 1
fi

if ! CONTEXT7_API_KEY="$(op read 'op://Personal/context7/credential' 2>/dev/null)"; then
  echo "op could not read op://Personal/context7/credential" >&2
  echo "Sign in (op signin) or check the item exists in the Personal vault." >&2
  exit 1
fi
export CONTEXT7_API_KEY

exec npx -y @upstash/context7-mcp@latest "$@"
