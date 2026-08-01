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

file_path="${1:-}"
if [[ -z "$file_path" || $# -ne 1 || ! -f "$file_path" ]]; then
  printf 'Usage: upload-media.sh <local_media_file>\n' >&2
  exit 1
fi

filename="$(basename "$file_path")"
extension="${filename##*.}"
extension="$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"
case "$extension" in
  jpg|jpeg) content_type="image/jpeg" ;;
  png) content_type="image/png" ;;
  gif) content_type="image/gif" ;;
  webp) content_type="image/webp" ;;
  mp4) content_type="video/mp4" ;;
  mov) content_type="video/quicktime" ;;
  webm) content_type="video/webm" ;;
  mp3) content_type="audio/mpeg" ;;
  wav) content_type="audio/wav" ;;
  m4a) content_type="audio/mp4" ;;
  aac) content_type="audio/aac" ;;
  *) printf 'ERROR: Unsupported media extension: %s\n' "$extension" >&2; exit 1 ;;
esac

file_size="$(wc -c < "$file_path" | tr -d '[:space:]')"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/o1key-upload.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
request_file="$work_dir/presign-request.json"
response_file="$work_dir/presign-response.json"
headers_file="$work_dir/headers.tsv"
metadata_file="$work_dir/metadata.txt"

if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.dump({"filename":sys.argv[1],"content_type":sys.argv[2],"size":int(sys.argv[3])},sys.stdout,ensure_ascii=False)' "$filename" "$content_type" "$file_size" > "$request_file"
elif command -v node >/dev/null 2>&1; then
  node -e 'process.stdout.write(JSON.stringify({filename:process.argv[1],content_type:process.argv[2],size:Number(process.argv[3])}))' "$filename" "$content_type" "$file_size" > "$request_file"
else
  printf 'ERROR: python3 or node is required to encode JSON safely.\n' >&2
  exit 1
fi

curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Authorization: Bearer $api_key" \
  -H 'Content-Type: application/json' \
  --data-binary "@$request_file" \
  "$base_url/v1/storage/oss/presign" > "$response_file"

if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
u=d.get("upload_url"); p=d.get("public_url"); m=d.get("method") or "PUT"; h=d.get("headers") or {}
if not isinstance(u,str) or not u.startswith("https://") or not isinstance(p,str) or not p.startswith("https://"): raise SystemExit("ERROR: Invalid OSS presign response")
open(sys.argv[2],"w",encoding="utf-8").write(m+"\n"+u+"\n"+p+"\n")
with open(sys.argv[3],"w",encoding="utf-8") as f:
  for k,v in h.items():
    if "\n" in str(k) or "\n" in str(v) or "\t" in str(k) or "\t" in str(v): raise SystemExit("ERROR: Invalid signed header")
    f.write(f"{k}\t{v}\n")' "$response_file" "$metadata_file" "$headers_file"
else
  node -e 'const fs=require("fs"),d=JSON.parse(fs.readFileSync(process.argv[1],"utf8")),u=d.upload_url,p=d.public_url,m=d.method||"PUT",h=d.headers||{};if(typeof u!=="string"||!u.startsWith("https://")||typeof p!=="string"||!p.startsWith("https://"))throw Error("Invalid OSS presign response");fs.writeFileSync(process.argv[2],[m,u,p,""].join("\n"));fs.writeFileSync(process.argv[3],Object.entries(h).map(([k,v])=>{if(/[\n\t]/.test(k)||/[\n\t]/.test(String(v)))throw Error("Invalid signed header");return `${k}\t${v}\n`}).join(""))' "$response_file" "$metadata_file" "$headers_file"
fi

method="$(sed -n '1p' "$metadata_file")"
upload_url="$(sed -n '2p' "$metadata_file")"
public_url="$(sed -n '3p' "$metadata_file")"
curl_args=(--fail-with-body --silent --show-error -X "$method")
while IFS=$'\t' read -r header_name header_value; do
  [[ -n "$header_name" ]] && curl_args+=(-H "$header_name: $header_value")
done < "$headers_file"
curl "${curl_args[@]}" --data-binary "@$file_path" "$upload_url" >/dev/null

if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; print(json.dumps({"public_url":sys.argv[1]},ensure_ascii=False))' "$public_url"
else
  node -e 'console.log(JSON.stringify({public_url:process.argv[1]}))' "$public_url"
fi
