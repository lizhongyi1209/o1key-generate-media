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
    printf 'Usage: grok-video.sh status <public_task_id>\n' >&2
    exit 1
  fi
  curl --fail-with-body --silent --show-error \
    -H "Authorization: Bearer $api_key" \
    "$base_url/grok/v1/videos/$task_id"
  printf '\n'
  exit
fi

case "$operation" in
  generate) endpoint="/grok/v1/videos/generations" ;;
  edit) endpoint="/grok/v1/videos/edits" ;;
  extend) endpoint="/grok/v1/videos/extensions" ;;
  *) printf 'Usage: grok-video.sh <generate|edit|extend> <request_json_file> OR grok-video.sh status <public_task_id>\n' >&2; exit 1 ;;
esac

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/o1key-grok-video.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
request_file="${2:-}"

# Backward-compatible basic generation command.
if [[ "$operation" == "generate" && $# -ge 6 && $# -le 7 ]]; then
  request_file="$work_dir/legacy-request.json"
  image_value_file="$work_dir/image-value.txt"
  image_source="${7:-}"
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
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
image=open(sys.argv[6],encoding="utf-8").read()
body={"model":sys.argv[1],"prompt":sys.argv[2],"duration":int(sys.argv[3]),"aspect_ratio":sys.argv[4],"resolution":sys.argv[5]}
if image: body["image"]={"url":image}
print(json.dumps(body))' "$2" "$3" "$4" "$5" "$6" "$image_value_file" > "$request_file"
  elif command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs"),a=process.argv.slice(1),image=fs.readFileSync(a[5],"utf8"),body={model:a[0],prompt:a[1],duration:Number(a[2]),aspect_ratio:a[3],resolution:a[4]};if(image)body.image={url:image};process.stdout.write(JSON.stringify(body))' "$2" "$3" "$4" "$5" "$6" "$image_value_file" > "$request_file"
  else
    printf 'ERROR: python3 or node is required to encode JSON safely.\n' >&2
    exit 1
  fi
elif [[ $# -ne 2 || ! -f "$request_file" ]]; then
  printf 'Usage: grok-video.sh %s <request_json_file>\n' "$operation" >&2
  exit 1
fi

body_file="$work_dir/validated-request.json"
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys
op,src,dst=sys.argv[1:]
with open(src,encoding="utf-8") as f: b=json.load(f)
if not isinstance(b,dict): raise SystemExit("ERROR: request must be a JSON object")
models={"grok-imagine-video","grok-imagine-video-1.5","grok-imagine-video-1.5-preview","grok-imagine-video-1.5-2026-05-30"}
model=b.get("model")
if model not in models: raise SystemExit("ERROR: unsupported Grok video model")
is15=model!="grok-imagine-video"
if "duration" in b and "seconds" in b: raise SystemExit("ERROR: send duration or seconds, not both")
duration=b.get("duration",b.get("seconds"))
if duration is not None:
    if isinstance(duration,bool) or not isinstance(duration,(int,str)) or not str(duration).isdigit(): raise SystemExit("ERROR: duration must be an integer or integer string")
    duration=int(duration)
ratios={"1:1","16:9","9:16","4:3","3:4","3:2","2:3"}
if "aspect_ratio" in b and b["aspect_ratio"] not in ratios: raise SystemExit("ERROR: invalid aspect_ratio")
if "resolution" in b and b["resolution"] not in {"480p","720p","1080p"}: raise SystemExit("ERROR: invalid resolution")
def media(name,value,image=False):
    if not isinstance(value,dict): raise SystemExit(f"ERROR: {name} must be an object")
    keys=[k for k in (("url","image_url","file_id") if image else ("url","file_id")) if isinstance(value.get(k),str) and value[k].strip()]
    if len(keys)!=1: raise SystemExit(f"ERROR: {name} requires exactly one media locator")
def common_options():
    output=b.get("output")
    if output is not None and (not isinstance(output,dict) or not isinstance(output.get("upload_url"),str) or not output["upload_url"].strip()): raise SystemExit("ERROR: output.upload_url is required")
    storage=b.get("storage_options")
    if storage is not None:
        if not isinstance(storage,dict) or not isinstance(storage.get("filename"),str) or not storage["filename"].strip(): raise SystemExit("ERROR: storage_options.filename is required")
        expiry=storage.get("expires_after")
        if expiry is not None and (isinstance(expiry,bool) or not isinstance(expiry,int) or not 3600<=expiry<=2592000): raise SystemExit("ERROR: invalid storage_options.expires_after")
        public=storage.get("public_url")
        if public is not None and not isinstance(public,(bool,dict)): raise SystemExit("ERROR: storage_options.public_url must be boolean or object")
        if isinstance(public,dict):
            pe=public.get("expires_after")
            if pe is not None and (isinstance(pe,bool) or not isinstance(pe,int) or not 3600<=pe<=2592000): raise SystemExit("ERROR: invalid public URL expiration")
            if pe is not None and expiry is not None and pe>expiry: raise SystemExit("ERROR: public URL expiration cannot exceed file expiration")
common_options()
refs=b.get("reference_images",[]); audios=b.get("reference_audios",[]); image=b.get("image"); video=b.get("video")
if refs is None: refs=[]
if audios is None: audios=[]
if not isinstance(refs,list) or not isinstance(audios,list): raise SystemExit("ERROR: reference inputs must be arrays")
if op=="generate":
    if video is not None: raise SystemExit("ERROR: video is only valid for edit or extend")
    if duration is not None and not 1<=duration<=15: raise SystemExit("ERROR: generation duration must be 1–15")
    if image is not None and (refs or audios): raise SystemExit("ERROR: image and reference inputs are mutually exclusive")
    if image is not None:
        media("image",image,True)
    elif refs or audios:
        if is15: raise SystemExit("ERROR: Grok 1.5 does not support reference-to-video")
        if not isinstance(b.get("prompt"),str) or not b["prompt"].strip(): raise SystemExit("ERROR: prompt is required for reference-to-video")
        if len(refs)>7 or len(audios)>3: raise SystemExit("ERROR: reference limits are 7 images and 3 audios")
        if duration is not None and duration>10: raise SystemExit("ERROR: reference duration must be 1–10")
        for i,x in enumerate(refs): media(f"reference_images[{i}]",x,True)
        for i,x in enumerate(audios):
            if not isinstance(x,dict) or not isinstance(x.get("url"),str) or not x["url"].strip(): raise SystemExit(f"ERROR: reference_audios[{i}].url is required")
    else:
        if is15: raise SystemExit("ERROR: Grok 1.5 supports image-to-video only")
        if not isinstance(b.get("prompt"),str) or not b["prompt"].strip(): raise SystemExit("ERROR: prompt is required for text-to-video")
    if b.get("resolution")=="1080p" and not (is15 and image is not None): raise SystemExit("ERROR: 1080p requires Grok 1.5 image-to-video")
elif op=="edit":
    if is15: raise SystemExit("ERROR: edit requires grok-imagine-video")
    if not isinstance(b.get("prompt"),str) or not b["prompt"].strip(): raise SystemExit("ERROR: prompt is required for edit")
    media("video",video)
    forbidden=[x for x in ("duration","seconds","aspect_ratio","resolution","image","reference_images","reference_audios") if x in b]
    if forbidden: raise SystemExit("ERROR: edit does not support: "+", ".join(forbidden))
else:
    if is15: raise SystemExit("ERROR: extend requires grok-imagine-video")
    if not isinstance(b.get("prompt"),str) or not b["prompt"].strip(): raise SystemExit("ERROR: prompt is required for extend")
    media("video",video)
    if duration is not None and not 2<=duration<=10: raise SystemExit("ERROR: extension duration must be 2–10")
    forbidden=[x for x in ("aspect_ratio","resolution","image","reference_images","reference_audios") if x in b]
    if forbidden: raise SystemExit("ERROR: extend does not support: "+", ".join(forbidden))
with open(dst,"w",encoding="utf-8") as f: json.dump(b,f,ensure_ascii=False,separators=(",",":"))' "$operation" "$request_file" "$body_file"
elif command -v node >/dev/null 2>&1; then
  node -e 'const fs=require("fs"),[op,src,dst]=process.argv.slice(1),b=JSON.parse(fs.readFileSync(src,"utf8")),models=new Set(["grok-imagine-video","grok-imagine-video-1.5","grok-imagine-video-1.5-preview","grok-imagine-video-1.5-2026-05-30"]);const fail=m=>{throw Error(m)},model=b.model,is15=model!=="grok-imagine-video";if(!b||typeof b!=="object"||Array.isArray(b))fail("request must be a JSON object");if(!models.has(model))fail("unsupported Grok video model");if("duration" in b&&"seconds" in b)fail("send duration or seconds, not both");let d=b.duration??b.seconds;if(d!==undefined&&(!/^\d+$/.test(String(d))))fail("duration must be an integer");if(d!==undefined)d=Number(d);if("aspect_ratio" in b&&!new Set(["1:1","16:9","9:16","4:3","3:4","3:2","2:3"]).has(b.aspect_ratio))fail("invalid aspect_ratio");if("resolution" in b&&!new Set(["480p","720p","1080p"]).has(b.resolution))fail("invalid resolution");const media=(n,v,img=false)=>{if(!v||typeof v!=="object"||Array.isArray(v))fail(n+" must be an object");const ks=(img?["url","image_url","file_id"]:["url","file_id"]).filter(k=>typeof v[k]==="string"&&v[k].trim());if(ks.length!==1)fail(n+" requires exactly one media locator")};if(b.output&&(!b.output.upload_url||typeof b.output.upload_url!=="string"))fail("output.upload_url is required");if(b.storage_options){const s=b.storage_options;if(!s.filename||typeof s.filename!=="string")fail("storage_options.filename is required");if("public_url" in s&&typeof s.public_url!=="boolean"&&(typeof s.public_url!=="object"||s.public_url===null||Array.isArray(s.public_url)))fail("storage_options.public_url must be boolean or object");for(const e of [s.expires_after,s.public_url&&typeof s.public_url==="object"?s.public_url.expires_after:undefined])if(e!==undefined&&(!Number.isInteger(e)||e<3600||e>2592000))fail("invalid storage expiration");if(s.public_url&&typeof s.public_url==="object"&&s.expires_after&&s.public_url.expires_after>s.expires_after)fail("public URL expiration cannot exceed file expiration")}const refs=b.reference_images||[],aud=b.reference_audios||[],image=b.image,video=b.video,prompt=typeof b.prompt==="string"&&b.prompt.trim();if(!Array.isArray(refs)||!Array.isArray(aud))fail("reference inputs must be arrays");if(op==="generate"){if(video)fail("video is only valid for edit or extend");if(d!==undefined&&(d<1||d>15))fail("generation duration must be 1–15");if(image&&(refs.length||aud.length))fail("image and reference inputs are mutually exclusive");if(image)media("image",image,true);else if(refs.length||aud.length){if(is15)fail("Grok 1.5 does not support reference-to-video");if(!prompt)fail("prompt is required for references");if(refs.length>7||aud.length>3)fail("reference limits are 7 images and 3 audios");if(d!==undefined&&d>10)fail("reference duration must be 1–10");refs.forEach((x,i)=>media(`reference_images[${i}]`,x,true));aud.forEach((x,i)=>{if(!x||typeof x.url!=="string"||!x.url.trim())fail(`reference_audios[${i}].url is required`)})}else{if(is15)fail("Grok 1.5 supports image-to-video only");if(!prompt)fail("prompt is required for text-to-video")}if(b.resolution==="1080p"&&!(is15&&image))fail("1080p requires Grok 1.5 image-to-video")}else{if(is15)fail(op+" requires grok-imagine-video");if(!prompt)fail("prompt is required for "+op);media("video",video);const fields=op==="edit"?["duration","seconds","aspect_ratio","resolution","image","reference_images","reference_audios"]:["aspect_ratio","resolution","image","reference_images","reference_audios"],bad=fields.filter(x=>x in b);if(bad.length)fail(op+" does not support: "+bad.join(", "));if(op==="extend"&&d!==undefined&&(d<2||d>10))fail("extension duration must be 2–10")}fs.writeFileSync(dst,JSON.stringify(b))' "$operation" "$request_file" "$body_file"
else
  printf 'ERROR: python3 or node is required to validate JSON safely.\n' >&2
  exit 1
fi

curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Authorization: Bearer $api_key" \
  -H 'Content-Type: application/json' \
  --data-binary "@$body_file" \
  "$base_url$endpoint"
printf '\n'
