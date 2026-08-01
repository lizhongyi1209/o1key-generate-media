#!/usr/bin/env bash
set -euo pipefail

primary_base_url="https://api.o1key.cn"
fallback_base_url="https://cf-api.o1key.com"
route="${O1KEY_API_ROUTE:-primary}"
case "$route" in
  primary) base_url="$primary_base_url" ;;
  fallback) base_url="$fallback_base_url" ;;
  *) printf 'ERROR: O1KEY_API_ROUTE must be primary or fallback.\n' >&2; exit 1 ;;
esac
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

kind="${1:-}"
operation="${2:-}"
case "$kind" in
  omni) endpoint="/kling/omni-video/kling-3.0-omni" ;;
  motion) endpoint="/kling/motion-control/kling-3.0" ;;
  *) printf 'Usage: kling-video.sh <omni|motion> <generate|status> <request_json_file|public_task_id>\n' >&2; exit 1 ;;
esac

case "$operation" in
  status)
    task_id="${3:-}"
    if [[ -z "$task_id" || $# -ne 3 ]]; then
      printf 'Usage: kling-video.sh %s status <public_task_id>\n' "$kind" >&2
      exit 1
    fi
    curl --fail-with-body --silent --show-error \
      -H "Authorization: Bearer $api_key" \
      "$base_url$endpoint/$task_id"
    ;;
  generate)
    request_file="${3:-}"
    if [[ -z "$request_file" || $# -ne 3 || ! -f "$request_file" ]]; then
      printf 'Usage: kling-video.sh %s generate <request_json_file>\n' "$kind" >&2
      exit 1
    fi

    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import json,sys
body=json.load(open(sys.argv[1],encoding="utf-8"))
if not isinstance(body,dict) or not isinstance(body.get("contents"),list) or not body["contents"]: raise SystemExit("ERROR: contents must be a non-empty array")
if "model" in body or "model_name" in body: raise SystemExit("ERROR: model is fixed by the endpoint and must be omitted")
for item in body["contents"]:
    if not isinstance(item,dict) or not isinstance(item.get("type"),str): raise SystemExit("ERROR: every content item requires type")
    url=item.get("url")
    if url is not None and (not isinstance(url,str) or not url.startswith("https://")): raise SystemExit("ERROR: media URLs must use public HTTPS")' "$request_file"
    elif command -v node >/dev/null 2>&1; then
      node -e 'const fs=require("fs"),b=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));if(!b||typeof b!=="object"||!Array.isArray(b.contents)||!b.contents.length)throw Error("contents must be a non-empty array");if("model" in b||"model_name" in b)throw Error("model is fixed by the endpoint and must be omitted");for(const x of b.contents){if(!x||typeof x!=="object"||typeof x.type!=="string")throw Error("every content item requires type");if(x.url!==undefined&&(typeof x.url!=="string"||!x.url.startsWith("https://")))throw Error("media URLs must use public HTTPS")}' "$request_file"
    else
      printf 'ERROR: python3 or node is required to validate JSON safely.\n' >&2
      exit 1
    fi

    curl --fail-with-body --silent --show-error \
      -X POST \
      -H "Authorization: Bearer $api_key" \
      -H 'Content-Type: application/json' \
      --data-binary "@$request_file" \
      "$base_url$endpoint"
    ;;
  *) printf 'Usage: kling-video.sh <omni|motion> <generate|status> <request_json_file|public_task_id>\n' >&2; exit 1 ;;
esac
printf '\n'
