#!/usr/bin/env bash
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key_file="$skill_dir/.o1key-api-key"

printf 'Enter O1Key API key: ' >&2
if [[ -t 0 ]]; then
  IFS= read -r -s api_key
  printf '\n' >&2
else
  IFS= read -r api_key
fi

if [[ -z "$api_key" ]]; then
  printf 'ERROR: API key cannot be empty.\n' >&2
  exit 1
fi

(umask 077 && printf '%s' "$api_key" > "$key_file")
printf 'O1Key API key configured successfully.\n'
