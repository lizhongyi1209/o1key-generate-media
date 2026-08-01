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

operation="${1:-}"
if [[ "$operation" == "status" ]]; then
  task_id="${2:-}"
  if [[ -z "$task_id" || $# -ne 2 ]]; then
    printf 'Usage: seedance-video.sh status <public_task_id>\n' >&2
    exit 1
  fi
  curl --fail-with-body --silent --show-error \
    -H "Authorization: Bearer $api_key" \
    "$base_url/v1/video/generations/$task_id"
  printf '\n'
  exit 0
fi

if [[ "$operation" != "generate" || $# -lt 6 ]]; then
  printf 'Usage: seedance-video.sh generate <model> <prompt> <duration> <ratio> <resolution> [--image <https_url> <role|->] [--video <https_url>] [--audio <https_url>] [--camera-fixed <true|false>] [--generate-audio <true|false>] [--web-search <true|false>] [--seed <-1|integer>]\n' >&2
  exit 1
fi

model="$2"
prompt="$3"
duration="$4"
ratio="$5"
resolution="$6"
shift 6

case "$model" in
  seedance-2.0|seedance-2.0-fast|seedance-2.0-mini) ;;
  *) printf 'ERROR: Unsupported model.\n' >&2; exit 1 ;;
esac
[[ "$duration" =~ ^[0-9]+$ ]] && (( duration >= 4 && duration <= 15 )) || { printf 'ERROR: Duration must be an integer from 4 to 15.\n' >&2; exit 1; }
case "$ratio" in adaptive|16:9|4:3|1:1|3:4|9:16|21:9|9:21) ;; *) printf 'ERROR: Unsupported ratio.\n' >&2; exit 1 ;; esac
case "$resolution" in 480p|720p|1080p|4k) ;; *) printf 'ERROR: Unsupported resolution.\n' >&2; exit 1 ;; esac
[[ -n "$prompt" ]] || { printf 'ERROR: Prompt cannot be empty.\n' >&2; exit 1; }

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/o1key-seedance.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
images_file="$work_dir/images.tsv"
videos_file="$work_dir/videos.txt"
audios_file="$work_dir/audios.txt"
body_file="$work_dir/request.json"
: > "$images_file"
: > "$videos_file"
: > "$audios_file"
camera_fixed=""
generate_audio=""
web_search=""
seed=""

validate_url() {
  [[ "$1" == https://* ]] || { printf 'ERROR: Reference media must use a public HTTPS URL.\n' >&2; exit 1; }
}
validate_bool() {
  [[ "$2" == "true" || "$2" == "false" ]] || { printf 'ERROR: %s must be true or false.\n' "$1" >&2; exit 1; }
}

while (( $# > 0 )); do
  case "$1" in
    --image)
      (( $# >= 3 )) || { printf 'ERROR: --image requires URL and role (use - for no role).\n' >&2; exit 1; }
      validate_url "$2"
      case "$3" in -|first_frame|last_frame|reference_image) ;; *) printf 'ERROR: Unsupported image role.\n' >&2; exit 1 ;; esac
      printf '%s\t%s\n' "$2" "$3" >> "$images_file"
      shift 3
      ;;
    --video|--audio)
      (( $# >= 2 )) || { printf 'ERROR: %s requires a URL.\n' "$1" >&2; exit 1; }
      validate_url "$2"
      if [[ "$1" == "--video" ]]; then printf '%s\n' "$2" >> "$videos_file"; else printf '%s\n' "$2" >> "$audios_file"; fi
      shift 2
      ;;
    --camera-fixed|--generate-audio|--web-search)
      (( $# >= 2 )) || { printf 'ERROR: %s requires true or false.\n' "$1" >&2; exit 1; }
      validate_bool "$1" "$2"
      case "$1" in --camera-fixed) camera_fixed="$2" ;; --generate-audio) generate_audio="$2" ;; --web-search) web_search="$2" ;; esac
      shift 2
      ;;
    --seed)
      (( $# >= 2 )) || { printf 'ERROR: --seed requires an integer.\n' >&2; exit 1; }
      [[ "$2" =~ ^-?[0-9]+$ ]] && (( $2 >= -1 )) || { printf 'ERROR: Seed must be -1 or a non-negative integer.\n' >&2; exit 1; }
      seed="$2"
      shift 2
      ;;
    *) printf 'ERROR: Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys
model,prompt,duration,ratio,resolution,images_path,videos_path,audios_path,camera,audio,web,seed=sys.argv[1:]
body={"model":model,"prompt":prompt,"duration":int(duration),"ratio":ratio,"resolution":resolution}
images=[]
for line in open(images_path,encoding="utf-8"):
    url,role=line.rstrip("\n").split("\t",1); images.append(url if role=="-" else {"url":url,"role":role})
videos=[x.strip() for x in open(videos_path,encoding="utf-8") if x.strip()]
audios=[x.strip() for x in open(audios_path,encoding="utf-8") if x.strip()]
if images: body["images"]=images
if videos: body["videos"]=videos
if audios: body["audios"]=audios
for key,value in (("camera_fixed",camera),("generate_audio",audio),("web_search",web)):
    if value: body[key]=value=="true"
if seed: body["seed"]=int(seed)
print(json.dumps(body,ensure_ascii=False))' "$model" "$prompt" "$duration" "$ratio" "$resolution" "$images_file" "$videos_file" "$audios_file" "$camera_fixed" "$generate_audio" "$web_search" "$seed" > "$body_file"
elif command -v node >/dev/null 2>&1; then
  node -e 'const fs=require("fs"),a=process.argv.slice(1),[model,prompt,duration,ratio,resolution,ip,vp,ap,camera,audio,web,seed]=a,b={model,prompt,duration:Number(duration),ratio,resolution},lines=p=>fs.readFileSync(p,"utf8").split(/\r?\n/).filter(Boolean);const images=lines(ip).map(x=>{const [url,role]=x.split("\t");return role==="-"?url:{url,role}}),videos=lines(vp),audios=lines(ap);if(images.length)b.images=images;if(videos.length)b.videos=videos;if(audios.length)b.audios=audios;for(const [k,v] of [["camera_fixed",camera],["generate_audio",audio],["web_search",web]])if(v)b[k]=v==="true";if(seed)b.seed=Number(seed);process.stdout.write(JSON.stringify(b))' "$model" "$prompt" "$duration" "$ratio" "$resolution" "$images_file" "$videos_file" "$audios_file" "$camera_fixed" "$generate_audio" "$web_search" "$seed" > "$body_file"
else
  printf 'ERROR: python3 or node is required to encode JSON safely.\n' >&2
  exit 1
fi

curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Authorization: Bearer $api_key" \
  -H 'Content-Type: application/json' \
  --data-binary "@$body_file" \
  "$base_url/v1/video/generations"
printf '\n'
