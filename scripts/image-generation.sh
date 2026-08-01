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
    if [[ -z "$task_id" || $# -ne 2 ]]; then
      printf 'Usage: image-generation.sh status <public_task_id>\n' >&2
      exit 1
    fi
    response_file="$(mktemp)"
    trap 'rm -f "$response_file"' EXIT
    curl --fail-with-body --silent --show-error \
      -H "Authorization: Bearer $api_key" \
      -o "$response_file" \
      "$base_url/async/v1/tasks/$task_id"
    output_dir="${O1KEY_OUTPUT_DIR:-$PWD/output}"
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import base64,json,os,sys
p,output_dir,task_id=sys.argv[1:]
with open(p,encoding="utf-8") as f: body=json.load(f)
images=((body.get("data") or {}).get("images") or []) if isinstance(body,dict) else []
for i,item in enumerate(images,1):
    if not isinstance(item,dict) or not item.get("b64_json"): continue
    raw=base64.b64decode(item.pop("b64_json"),validate=True)
    ext="jpg" if raw.startswith(b"\xff\xd8\xff") else "png" if raw.startswith(b"\x89PNG") else "webp" if raw[:4]==b"RIFF" and raw[8:12]==b"WEBP" else "bin"
    os.makedirs(output_dir,exist_ok=True)
    path=os.path.abspath(os.path.join(output_dir,f"{task_id}-{i}.{ext}"))
    with open(path,"wb") as f: f.write(raw)
    item["local_path"]=path
print(json.dumps(body,ensure_ascii=False,separators=(",",":")))' "$response_file" "$output_dir" "$task_id"
    elif command -v node >/dev/null 2>&1; then
      node -e 'const fs=require("fs"),path=require("path"),[p,out,id]=process.argv.slice(1),b=JSON.parse(fs.readFileSync(p,"utf8")),images=b?.data?.images||[];images.forEach((x,i)=>{if(!x||!x.b64_json)return;const raw=Buffer.from(x.b64_json,"base64");delete x.b64_json;let ext=raw.subarray(0,3).equals(Buffer.from([255,216,255]))?"jpg":raw.subarray(0,4).equals(Buffer.from([137,80,78,71]))?"png":raw.subarray(0,4).toString()==="RIFF"&&raw.subarray(8,12).toString()==="WEBP"?"webp":"bin";fs.mkdirSync(out,{recursive:true});const file=path.resolve(out,`${id}-${i+1}.${ext}`);fs.writeFileSync(file,raw);x.local_path=file});process.stdout.write(JSON.stringify(b))' "$response_file" "$output_dir" "$task_id"
    else
      printf 'ERROR: python3 or node is required to process image results safely.\n' >&2
      exit 1
    fi
    ;;
  generate)
    request_file="${2:-}"
    if [[ -z "$request_file" || $# -ne 2 || ! -f "$request_file" ]]; then
      printf 'Usage: image-generation.sh generate <request_json_file>\n' >&2
      exit 1
    fi

    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import json,sys
b=json.load(open(sys.argv[1],encoding="utf-8"))
models={"nano-banana-pro","nano-banana-pro-2k","nano-banana-pro-4k","nano-banana-2-0.5k","nano-banana-2-1k","nano-banana-2-2k","nano-banana-2-4k","gpt-image-2-c"}
if not isinstance(b,dict): raise SystemExit("ERROR: request must be a JSON object")
if b.get("model") not in models: raise SystemExit("ERROR: unsupported image model")
if not isinstance(b.get("prompt"),str) or not b["prompt"].strip(): raise SystemExit("ERROR: prompt is required")
if "image" in b: raise SystemExit("ERROR: image is removed; use the images array")
if "images" in b and (not isinstance(b["images"],list) or any(not isinstance(x,str) or not x.strip() for x in b["images"])): raise SystemExit("ERROR: images must be an array of non-empty strings")
if b["model"].startswith("nano-banana"):
    bad=[x for x in ("n","quality","output_format","mask") if x in b]
    if bad: raise SystemExit("ERROR: Nano Banana does not use: "+", ".join(bad))
    if "size" in b and str(b["size"]).upper() not in {"0.5K","1K","2K","4K"}: raise SystemExit("ERROR: Nano Banana size must be 0.5K, 1K, 2K, or 4K")
else:
    bad=[x for x in ("response_modalities","media_resolution","google_search","thinking_level","include_thoughts","aspect_ratio") if x in b]
    if bad: raise SystemExit("ERROR: GPT Image does not use: "+", ".join(bad))
    if "n" in b and (not isinstance(b["n"],int) or isinstance(b["n"],bool) or b["n"] < 1): raise SystemExit("ERROR: n must be a positive integer")
    if "quality" in b and b["quality"] not in {"low","medium","high","auto"}: raise SystemExit("ERROR: invalid GPT Image quality")
    if "output_format" in b and b["output_format"] not in {"png","jpeg","webp"}: raise SystemExit("ERROR: invalid GPT Image output_format")' "$request_file"
    elif command -v node >/dev/null 2>&1; then
      node -e 'const fs=require("fs"),b=JSON.parse(fs.readFileSync(process.argv[1],"utf8")),models=new Set(["nano-banana-pro","nano-banana-pro-2k","nano-banana-pro-4k","nano-banana-2-0.5k","nano-banana-2-1k","nano-banana-2-2k","nano-banana-2-4k","gpt-image-2-c"]);if(!b||typeof b!=="object"||Array.isArray(b))throw Error("request must be a JSON object");if(!models.has(b.model))throw Error("unsupported image model");if(typeof b.prompt!=="string"||!b.prompt.trim())throw Error("prompt is required");if("image" in b)throw Error("image is removed; use the images array");if("images" in b&&(!Array.isArray(b.images)||b.images.some(x=>typeof x!=="string"||!x.trim())))throw Error("images must be an array of non-empty strings");if(b.model.startsWith("nano-banana")){const bad=["n","quality","output_format","mask"].filter(x=>x in b);if(bad.length)throw Error("Nano Banana does not use: "+bad.join(", "));if("size" in b&&!new Set(["0.5K","1K","2K","4K"]).has(String(b.size).toUpperCase()))throw Error("invalid Nano Banana size")}else{const bad=["response_modalities","media_resolution","google_search","thinking_level","include_thoughts","aspect_ratio"].filter(x=>x in b);if(bad.length)throw Error("GPT Image does not use: "+bad.join(", "));if("n" in b&&(!Number.isInteger(b.n)||b.n<1))throw Error("n must be a positive integer");if("quality" in b&&!new Set(["low","medium","high","auto"]).has(b.quality))throw Error("invalid GPT Image quality");if("output_format" in b&&!new Set(["png","jpeg","webp"]).has(b.output_format))throw Error("invalid GPT Image output_format")}' "$request_file"
    else
      printf 'ERROR: python3 or node is required to validate JSON safely.\n' >&2
      exit 1
    fi

    curl --fail-with-body --silent --show-error \
      -X POST \
      -H "Authorization: Bearer $api_key" \
      -H 'Content-Type: application/json' \
      --data-binary "@$request_file" \
      "$base_url/async/v1/generateImage"
    ;;
  *) printf 'Usage: image-generation.sh <generate|status> <request_json_file|public_task_id>\n' >&2; exit 1 ;;
esac
printf '\n'
