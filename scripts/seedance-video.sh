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
  if [[ ! "$task_id" =~ ^task_[A-Za-z0-9_-]+$ || $# -ne 2 ]]; then
    printf 'Usage: seedance-video.sh status <public_task_id>\n' >&2
    exit 1
  fi
  curl --fail-with-body --silent --show-error \
    -H "Authorization: Bearer $api_key" \
    "$base_url/v1/video/generations/$task_id"
  printf '\n'
  exit 0
fi

if [[ "$operation" == "asset" ]]; then
  asset_operation="${2:-}"
  case "$asset_operation" in
    create)
      asset_url="${3:-}"
      asset_name="${4:-}"
      asset_type="${5:-}"
      if [[ $# -ne 5 ]]; then
        printf 'Usage: seedance-video.sh asset create <public_https_url> <name> <Image|Video|Audio>\n' >&2
        exit 1
      fi
      [[ "$asset_url" == https://* ]] || { printf 'ERROR: Asset source must use a public HTTPS URL.\n' >&2; exit 1; }
      [[ -n "$asset_name" ]] || { printf 'ERROR: Asset name cannot be empty.\n' >&2; exit 1; }
      case "$asset_type" in Image|Video|Audio) ;; *) printf 'ERROR: Asset type must be Image, Video, or Audio.\n' >&2; exit 1 ;; esac

      work_dir="$(mktemp -d "${TMPDIR:-/tmp}/o1key-seedance-asset.XXXXXX")"
      trap 'rm -rf "$work_dir"' EXIT
      body_file="$work_dir/request.json"
      if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys; json.dump({"URL":sys.argv[1],"Name":sys.argv[2],"AssetType":sys.argv[3]},sys.stdout,ensure_ascii=False)' "$asset_url" "$asset_name" "$asset_type" > "$body_file"
      elif command -v node >/dev/null 2>&1; then
        node -e 'process.stdout.write(JSON.stringify({URL:process.argv[1],Name:process.argv[2],AssetType:process.argv[3]}))' "$asset_url" "$asset_name" "$asset_type" > "$body_file"
      else
        printf 'ERROR: python3 or node is required to encode JSON safely.\n' >&2
        exit 1
      fi
      curl --fail-with-body --silent --show-error \
        -X POST \
        -H "Authorization: Bearer $api_key" \
        -H 'Content-Type: application/json' \
        --data-binary "@$body_file" \
        "$base_url/v1/sd/assets"
      printf '\n'
      ;;
    status)
      asset_id="${3:-}"
      if [[ ! "$asset_id" =~ ^asset-[A-Za-z0-9._-]+$ || $# -ne 3 ]]; then
        printf 'Usage: seedance-video.sh asset status <asset_id>\n' >&2
        exit 1
      fi
      curl --fail-with-body --silent --show-error \
        -H "Authorization: Bearer $api_key" \
        "$base_url/v1/sd/assets/$asset_id"
      printf '\n'
      ;;
    *)
      printf 'Usage: seedance-video.sh asset <create|status> ...\n' >&2
      exit 1
      ;;
  esac
  exit 0
fi

if [[ "$operation" != "generate" || $# -lt 6 ]]; then
  printf 'Usage: seedance-video.sh generate <hc_model> <prompt> <duration> <ratio> <resolution> [--image <https_or_asset_url> <role|->] [--video <https_or_asset_url> <role|->] [--audio <https_or_asset_url> <role|->] [--generate-audio <true|false>] [--watermark <true|false>] [--return-last-frame <true|false>]\n' >&2
  exit 1
fi

model="$2"
prompt="$3"
duration="$4"
ratio="$5"
resolution="$6"
shift 6

case "$model" in
  dreamina-seedance-2-0-hc) ;;
  dreamina-seedance-2-0-fast-hc|dreamina-seedance-2-0-mini-hc)
    case "$resolution" in 480p|720p) ;; *) printf 'ERROR: Fast HC and Mini HC support only 480p or 720p.\n' >&2; exit 1 ;; esac
    ;;
  *) printf 'ERROR: Unsupported HC model.\n' >&2; exit 1 ;;
esac
[[ "$duration" =~ ^[0-9]+$ ]] && (( duration >= 4 && duration <= 15 )) || { printf 'ERROR: Duration must be an integer from 4 to 15.\n' >&2; exit 1; }
case "$ratio" in adaptive|16:9|4:3|1:1|3:4|9:16|21:9|9:21) ;; *) printf 'ERROR: Unsupported ratio.\n' >&2; exit 1 ;; esac
case "$resolution" in 480p|720p|1080p|4k) ;; *) printf 'ERROR: Unsupported resolution.\n' >&2; exit 1 ;; esac
[[ -n "$prompt" ]] || { printf 'ERROR: Prompt cannot be empty.\n' >&2; exit 1; }

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/o1key-seedance.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
images_file="$work_dir/images.tsv"
videos_file="$work_dir/videos.tsv"
audios_file="$work_dir/audios.tsv"
body_file="$work_dir/request.json"
: > "$images_file"
: > "$videos_file"
: > "$audios_file"
generate_audio=""
watermark=""
return_last_frame=""

validate_locator() {
  case "$1" in
    https://*|asset://asset-*) ;;
    *) printf 'ERROR: Reference media must use a public HTTPS URL or asset://asset-id.\n' >&2; exit 1 ;;
  esac
  [[ "$1" != *$'\t'* && "$1" != *$'\n'* && "$1" != *$'\r'* ]] || { printf 'ERROR: Reference media URL contains invalid whitespace.\n' >&2; exit 1; }
}

validate_bool() {
  [[ "$2" == "true" || "$2" == "false" ]] || { printf 'ERROR: %s must be true or false.\n' "$1" >&2; exit 1; }
}

while (( $# > 0 )); do
  case "$1" in
    --image)
      (( $# >= 3 )) || { printf 'ERROR: --image requires URL and role (use - for no role).\n' >&2; exit 1; }
      validate_locator "$2"
      case "$3" in -|first_frame|last_frame|reference_image) ;; *) printf 'ERROR: Unsupported image role.\n' >&2; exit 1 ;; esac
      printf '%s\t%s\n' "$2" "$3" >> "$images_file"
      shift 3
      ;;
    --video)
      (( $# >= 3 )) || { printf 'ERROR: --video requires URL and role (use - for no role).\n' >&2; exit 1; }
      validate_locator "$2"
      case "$3" in -|reference_video) ;; *) printf 'ERROR: Unsupported video role.\n' >&2; exit 1 ;; esac
      printf '%s\t%s\n' "$2" "$3" >> "$videos_file"
      shift 3
      ;;
    --audio)
      (( $# >= 3 )) || { printf 'ERROR: --audio requires URL and role (use - for no role).\n' >&2; exit 1; }
      validate_locator "$2"
      case "$3" in -|reference_audio) ;; *) printf 'ERROR: Unsupported audio role.\n' >&2; exit 1 ;; esac
      printf '%s\t%s\n' "$2" "$3" >> "$audios_file"
      shift 3
      ;;
    --generate-audio|--watermark|--return-last-frame)
      (( $# >= 2 )) || { printf 'ERROR: %s requires true or false.\n' "$1" >&2; exit 1; }
      validate_bool "$1" "$2"
      case "$1" in
        --generate-audio) generate_audio="$2" ;;
        --watermark) watermark="$2" ;;
        --return-last-frame) return_last_frame="$2" ;;
      esac
      shift 2
      ;;
    *) printf 'ERROR: Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys
model,prompt,duration,ratio,resolution,images_path,videos_path,audios_path,audio,watermark,last_frame=sys.argv[1:]
body={"model":model,"content":[{"type":"text","text":prompt}],"duration":int(duration),"ratio":ratio,"resolution":resolution}
def append_media(path,kind):
    for line in open(path,encoding="utf-8"):
        url,role=line.rstrip("\n").split("\t",1)
        item={"type":kind+"_url",kind+"_url":{"url":url}}
        if role!="-": item["role"]=role
        body["content"].append(item)
append_media(images_path,"image")
append_media(videos_path,"video")
append_media(audios_path,"audio")
for key,value in (("generate_audio",audio),("watermark",watermark),("return_last_frame",last_frame)):
    if value: body[key]=value=="true"
print(json.dumps(body,ensure_ascii=False))' "$model" "$prompt" "$duration" "$ratio" "$resolution" "$images_file" "$videos_file" "$audios_file" "$generate_audio" "$watermark" "$return_last_frame" > "$body_file"
elif command -v node >/dev/null 2>&1; then
  node -e 'const fs=require("fs"),a=process.argv.slice(1),[model,prompt,duration,ratio,resolution,ip,vp,ap,audio,watermark,lastFrame]=a,b={model,content:[{type:"text",text:prompt}],duration:Number(duration),ratio,resolution},lines=p=>fs.readFileSync(p,"utf8").split(/\r?\n/).filter(Boolean);for(const [path,kind] of [[ip,"image"],[vp,"video"],[ap,"audio"]])for(const row of lines(path)){const [url,role]=row.split("\t"),item={type:`${kind}_url`,[`${kind}_url`]:{url}};if(role!=="-")item.role=role;b.content.push(item)}for(const [k,v] of [["generate_audio",audio],["watermark",watermark],["return_last_frame",lastFrame]])if(v)b[k]=v==="true";process.stdout.write(JSON.stringify(b))' "$model" "$prompt" "$duration" "$ratio" "$resolution" "$images_file" "$videos_file" "$audios_file" "$generate_audio" "$watermark" "$return_last_frame" > "$body_file"
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
