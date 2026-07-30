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
      printf 'Usage: grok-video.sh generate <model> <prompt> <duration> <aspect_ratio> <resolution> [image_source]\n' >&2
      exit 1
    fi
    model="$2"
    prompt="$3"
    duration="$4"
    aspect_ratio="$5"
    resolution="$6"
    image_source="${7:-}"

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/o1key-video.XXXXXX")"
    trap 'rm -rf "$work_dir"' EXIT
    image_value_file="$work_dir/image-value.txt"
    body_file="$work_dir/request.json"

    if [[ -n "$image_source" && -f "$image_source" ]]; then
      case "${image_source##*.}" in
        jpg|JPG|jpeg|JPEG) mime_type="image/jpeg" ;;
        png|PNG) mime_type="image/png" ;;
        webp|WEBP) mime_type="image/webp" ;;
        gif|GIF) mime_type="image/gif" ;;
        *) printf 'ERROR: Unsupported local image type. Use JPEG, PNG, WebP, or GIF.\n' >&2; exit 1 ;;
      esac
      printf 'data:%s;base64,' "$mime_type" > "$image_value_file"
      base64 < "$image_source" | tr -d '\r\n' >> "$image_value_file"
    else
      printf '%s' "$image_source" > "$image_value_file"
    fi

    if command -v osascript >/dev/null 2>&1; then
      osascript -l JavaScript -e 'ObjC.import("Foundation");function run(a){const image=$.NSString.stringWithContentsOfFileEncodingError(a[5],$.NSUTF8StringEncoding,null).js;const o={model:a[0],prompt:a[1],duration:Number(a[2]),aspect_ratio:a[3],resolution:a[4]};if(image)o.image={url:image};return JSON.stringify(o)}' -- "$model" "$prompt" "$duration" "$aspect_ratio" "$resolution" "$image_value_file" > "$body_file"
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c 'import json,sys;o={"model":sys.argv[1],"prompt":sys.argv[2],"duration":int(sys.argv[3]),"aspect_ratio":sys.argv[4],"resolution":sys.argv[5]};image=open(sys.argv[6],encoding="utf-8").read();o.update({"image":{"url":image}} if image else {});print(json.dumps(o))' "$model" "$prompt" "$duration" "$aspect_ratio" "$resolution" "$image_value_file" > "$body_file"
    elif command -v node >/dev/null 2>&1; then
      node -e 'const fs=require("fs"),a=process.argv.slice(1),image=fs.readFileSync(a[5],"utf8"),o={model:a[0],prompt:a[1],duration:Number(a[2]),aspect_ratio:a[3],resolution:a[4]};if(image)o.image={url:image};process.stdout.write(JSON.stringify(o))' "$model" "$prompt" "$duration" "$aspect_ratio" "$resolution" "$image_value_file" > "$body_file"
    else
      printf 'ERROR: macOS osascript, python3, or node is required to encode JSON safely.\n' >&2
      exit 1
    fi

    curl --fail-with-body --silent --show-error \
      -X POST \
      -H "Authorization: Bearer $api_key" \
      -H 'Content-Type: application/json' \
      --data-binary "@$body_file" \
      "$base_url/grok/v1/videos/generations"
    ;;
  *)
    printf 'Usage: grok-video.sh <generate|status> ...\n' >&2
    exit 1
    ;;
esac
printf '\n'
