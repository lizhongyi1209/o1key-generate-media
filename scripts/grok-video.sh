#!/usr/bin/env bash
set -euo pipefail

base_url="https://cf-api.o1key.com"
skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key_file="$skill_dir/.o1key-api-key"
api_key="${O1KEY_API_KEY:-}"
if [[ -z "$api_key" && -f "$key_file" ]]; then
  api_key="$(<"$key_file")"
fi
if [[ -z "$api_key" ]]; then
  printf 'ERROR: O1Key API key is not configured. Run scripts/configure.sh first.\n' >&2
  exit 1
fi

operation="${1:-}"
case "$operation" in
  status)
    task_id="${2:-}"
    if [[ -z "$task_id" ]]; then
      printf 'Usage: grok-video.sh status <public_task_id>\n' >&2
      exit 1
    fi
    curl --fail-with-body --silent --show-error \
      -H "Authorization: Bearer $api_key" \
      "$base_url/grok/v1/videos/$task_id"
    ;;
  generate)
    if [[ $# -lt 6 || $# -gt 7 ]]; then
      printf 'Usage: grok-video.sh generate <model> <prompt> <duration> <aspect_ratio> <resolution> [image_url]\n' >&2
      exit 1
    fi
    model="$2"
    prompt="$3"
    duration="$4"
    aspect_ratio="$5"
    resolution="$6"
    image_url="${7:-}"

    if command -v osascript >/dev/null 2>&1; then
      body="$(osascript -l JavaScript -e 'function run(a){const o={model:a[0],prompt:a[1],duration:Number(a[2]),aspect_ratio:a[3],resolution:a[4]};if(a[5])o.image={url:a[5]};return JSON.stringify(o)}' -- "$model" "$prompt" "$duration" "$aspect_ratio" "$resolution" "$image_url")"
    elif command -v python3 >/dev/null 2>&1; then
      body="$(python3 -c 'import json,sys;o={"model":sys.argv[1],"prompt":sys.argv[2],"duration":int(sys.argv[3]),"aspect_ratio":sys.argv[4],"resolution":sys.argv[5]};o.update({"image":{"url":sys.argv[6]}} if sys.argv[6] else {});print(json.dumps(o))' "$model" "$prompt" "$duration" "$aspect_ratio" "$resolution" "$image_url")"
    elif command -v node >/dev/null 2>&1; then
      body="$(node -e 'const a=process.argv.slice(1),o={model:a[0],prompt:a[1],duration:Number(a[2]),aspect_ratio:a[3],resolution:a[4]};if(a[5])o.image={url:a[5]};process.stdout.write(JSON.stringify(o))' "$model" "$prompt" "$duration" "$aspect_ratio" "$resolution" "$image_url")"
    else
      printf 'ERROR: macOS osascript, python3, or node is required to encode JSON safely.\n' >&2
      exit 1
    fi

    curl --fail-with-body --silent --show-error \
      -X POST \
      -H "Authorization: Bearer $api_key" \
      -H 'Content-Type: application/json' \
      --data "$body" \
      "$base_url/grok/v1/videos/generations"
    ;;
  *)
    printf 'Usage: grok-video.sh <generate|status> ...\n' >&2
    exit 1
    ;;
esac
printf '\n'
