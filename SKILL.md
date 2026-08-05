---
name: o1key-generate-media
description: Generate images and videos through the O1Key API, including Nano Banana, GPT Image, Grok, Seedance 2.0, Kling 3.0 Omni, and Kling 3.0 Motion Control with asynchronous task polling. Use when a user asks Codex or ChatGPT to create or edit an image, create or animate a video, use reference images/videos/audio, control a character from a motion video, or configure an O1Key API key for media generation. Designed for Windows and macOS clients.
---

# O1Key Media Generator

Use only these O1Key API base URLs: primary `https://api.o1key.cn`; fallback `https://cf-api.o1key.com`. Never send the API key anywhere else.

## Select the platform script

- On macOS, run `scripts/configure.sh`, `scripts/upload-media.sh`, `scripts/image-generation.sh`, `scripts/grok-video.sh`, `scripts/seedance-video.sh`, and `scripts/kling-video.sh` with `bash`.
- On Windows, run the corresponding `.ps1` scripts with PowerShell.
- On other POSIX systems, use the macOS shell scripts when `python3` or `node` is available.

Resolve all script paths relative to this `SKILL.md` directory. Do not assume the current working directory is the skill directory.

## Endpoint routing and recovery

Scripts use the primary endpoint by default. Set `O1KEY_API_ROUTE=fallback` only to retry on the CF fallback endpoint; do not substitute arbitrary base URLs.

- On Windows, set `$env:O1KEY_API_ROUTE = 'fallback'` before rerunning the same script. On macOS/Linux, prefix the command with `O1KEY_API_ROUTE=fallback`.
- Retry a submission exactly once on the fallback endpoint only when the primary endpoint fails before returning a public task ID because of a connection/TLS/timeout error, HTTP `403` with Cloudflare error `1010`, or HTTP `5xx`.
- Do not retry or switch endpoints for HTTP `400`, `401`, `402`, or `429`; correct the request, credentials, balance, or rate limit first. A `401 Invalid token` means this skill needs an explicitly configured valid O1Key key; never silently copy a key from another skill.
- After a task ID is returned, never resubmit the generation. Poll that task ID on the same endpoint; switch endpoints only for the GET status call if the current endpoint has a route failure.
- If the user supplies a local VPN/proxy port, set `HTTP_PROXY` and `HTTPS_PROXY` for that command only (for example, `http://127.0.0.1:9567`) and verify the port is listening before treating a connection failure as an API issue.

## Report generation results

After polling reaches a terminal state, always include a `本次消耗费用` line in the final user-facing summary.

- Use the terminal status response's `cost` value when present. Treat it as the platform's settled charge; do not use an intermediate queued, submitted, or processing value.
- Preserve the value exactly as returned and do not infer a currency symbol that the response does not provide.
- If a successful terminal response does not contain `cost`, write `本次消耗费用：接口未返回` instead of estimating from model pricing.
- If generation fails, report the terminal `cost` when present. Only describe the task as free or refunded when the terminal response explicitly returns zero.
- Never expose upstream/provider billing details, internal quota values, or private task IDs while explaining the charge.

Use this compact completion format:

```text
生成状态：成功
模型：<model>
任务 ID：<public_task_id>
本次消耗费用：<terminal cost, or 接口未返回>
视频地址：<video_url>
```

## Configure authentication

Before the first API call, check whether `.o1key-api-key` exists in this skill directory or `O1KEY_API_KEY` is set. Do not read or display the stored key.

Treat a user who sends an API key in the conversation and explicitly asks to configure this skill as authorizing these limited actions:

- Store that key only in this skill's `.o1key-api-key` file.
- Use it only for requests to `https://api.o1key.cn` or `https://cf-api.o1key.com`.
- Replace an existing local O1Key key when the user clearly asks to update it.

Do not refuse configuration merely because an API key is sensitive. Handle it as a secret: do not repeat it, quote it, validate it by printing it, place it in a command argument, or commit it to Git.

If neither exists:

1. Ask the user to provide their O1Key API key.
2. Start the platform configure script interactively.
3. Send the key only to the script's stdin when prompted. Never place it in command arguments, source files, logs, or the response.
4. Trust the fixed success message; do not reopen the key file.

The configure scripts store the key locally in the ignored `.o1key-api-key` file and restrict permissions where the operating system supports it.

If the client cannot send secret text to an interactive process or its security policy prohibits the agent from writing credentials, do not bypass that restriction. Ask the user to run the platform configure script themselves and paste the key into its hidden prompt. Continue the requested generation after the script reports success.

When configuration succeeds, say only that the O1Key API key was configured. Never include any portion of the key in the confirmation.

## Upload local reference media

Read [references/media-upload.md](references/media-upload.md) whenever a video request contains a local image, video, or audio file and the target API requires a public HTTPS URL.

```text
upload-media.sh <local_media_file>
upload-media.ps1 -FilePath <local_media_file>
```

Upload the local file through `POST /v1/storage/oss/presign`, then use the returned `public_url` in the video request. Always use the returned upload method and every returned signed header. Do not expose or retain the presigned `upload_url`, send the O1Key API key to OSS, or construct an OSS URL manually. Stop before video submission if the upload fails.

Suggested user request:

```text
Configure this API key for $o1key-generate-media and use it only with https://api.o1key.cn or https://cf-api.o1key.com: <API_KEY>
```

## Generate or edit an image

Read [references/image-generation.md](references/image-generation.md) for the supported Nano Banana and GPT Image models, provider-specific parameters, limits, and examples.

```text
image-generation.sh generate <request_json_file>
image-generation.sh status <public_task_id>
```

```text
image-generation.ps1 generate -RequestFile <request_json_file>
image-generation.ps1 status -TaskId <public_task_id>
```

Workflow:

1. Use a Nano Banana model for Gemini-native generation and editing. Use `size`, `aspect_ratio`, and Gemini-only controls; never send GPT Image-only fields.
2. Use `gpt-image-2-c` for GPT Image generation, multi-image output, reference editing, or mask editing. Use `n`, pixel `size`, `quality`, and `output_format`; never send Gemini-only fields.
3. Put every reference image in `images`, including a single image. Accept an HTTP(S) URL, Base64 data URI, or raw Base64 string. Never use the removed `image` field.
4. Build a temporary UTF-8 JSON request file, submit it, and capture the public `task_id`.
5. Poll `status` every 5 seconds until `SUCCESS` or `FAILURE`; stop after 10 minutes unless the user asks to continue.
6. On success, return every `data.images[].url` or decoded `local_path`, model, public task ID, and the required fee line. Remove the temporary request file.
7. On failure, report the returned error and terminal fee fallback without exposing authentication or internal configuration.

Never invent image URLs or task IDs. Never call Gemini or OpenAI directly.

## Generate a Grok video

Read [references/grok-video.md](references/grok-video.md) for models, parameters, and request constraints.

Use one of these operations:

```text
grok-video.sh <generate|edit|extend> <request_json_file>
grok-video.sh status <public_task_id>
```

```text
grok-video.ps1 <generate|edit|extend> -RequestFile <request_json_file>
grok-video.ps1 status -TaskId <public_task_id>
```

Workflow:

1. Use `generate` with `grok-imagine-video` for text-to-video, image-to-video, or reference image/audio generation. Use a 1.5 model only for image-to-video.
2. Use `edit` to modify an MP4 and `extend` to continue an MP4. Both require `grok-imagine-video`, a prompt, and one `video` locator.
3. Build a temporary UTF-8 JSON request file using the exact mode-specific schema and limits in the reference. Use URL, Base64 data URI, or public `file_id` media locators. The legacy basic generation syntax remains supported for compatibility.
4. Do not configure `output.upload_url`, `storage_options`, or a callback-like external destination unless the user explicitly requests it and approves the destination.
5. Submit once and capture the returned public `request_id`. Never switch routes and resubmit after receiving an ID.
6. Poll `status` every 5 seconds until `done`, `failed`, or `expired`. Stop after 10 minutes unless the user asks to continue.
7. On success, return the terminal response's `video.url` unchanged, duration, model, public task ID, and required fee line. The URL may be O1Key R2-accelerated. Remove the temporary request file.
8. On failure, report the API error without exposing authentication, upstream cost, moderation metadata, or internal configuration.

Never invent a task ID or video URL. Never call the upstream xAI API directly.

## Generate a Seedance 2.0 video

Read [references/seedance-video.md](references/seedance-video.md) for HC models, asset registration, parameters, media limits, and multimodal examples.

Use one of these operations:

```text
seedance-video.sh asset <create|status> ...
seedance-video.sh generate <hc_model> <prompt> <duration> <ratio> <resolution> [options]
seedance-video.sh status <public_task_id>
```

```text
seedance-video.ps1 asset -AssetOperation <create|status> [options]
seedance-video.ps1 generate -Model <hc_model> -Prompt <prompt> -Duration <n> -Ratio <ratio> -Resolution <resolution> [options]
seedance-video.ps1 status -TaskId <public_task_id>
```

Workflow:

1. Select `dreamina-seedance-2-0-hc`, `dreamina-seedance-2-0-fast-hc`, or `dreamina-seedance-2-0-mini-hc` according to the user's quality, speed, and cost preference. Use only `480p` or `720p` with Fast HC and Mini HC.
2. For text-only generation, skip asset registration. For each image, video, or audio reference, obtain a public HTTPS source URL. When the user supplies a local file, run `upload-media` first and use its returned OSS `public_url`.
3. Register every reference through `POST /v1/sd/assets` with the exact `URL`, `Name`, and `AssetType` fields. Poll `GET /v1/sd/assets/{asset_id}` every 2–5 seconds until `data.Status` is `Active`, then use `asset://<data.Id>`. Do not submit a `Processing` or `Failed` asset.
4. Build the video request as `content[]`: one `text` item plus typed `image_url`, `video_url`, and `audio_url` items with roles such as `reference_image`, `reference_video`, or `reference_audio`.
5. Submit once to `POST /v1/video/generations` and capture the returned public `task_id`. Never call the internal `/v1/video/generate` endpoint.
6. Poll `status` every 5 seconds until `completed` or `failed`. Stop after 15 minutes unless the user asks to continue.
7. On success, return `metadata.url` or `metadata.outputs[0]`, model, task ID, and the required fee line described above.
8. On failure, report the API error without exposing authentication or internal configuration.

Never send local paths or Base64 data URIs to Seedance, invent media URLs or task IDs, use legacy non-HC model names for identity references, or call a Seedance upstream provider directly.

## Generate a Kling 3.0 video

Read [references/kling-video.md](references/kling-video.md) before creating the request JSON. Use only the official 3.0 operations documented there; do not substitute the legacy `/kling/v1/videos/...` APIs.

```text
kling-video.sh <omni|motion> generate <request_json_file>
kling-video.sh <omni|motion> status <public_task_id>
```

```text
kling-video.ps1 <omni|motion> generate -RequestFile <request_json_file>
kling-video.ps1 <omni|motion> status -TaskId <public_task_id>
```

Workflow:

1. Use `omni` for text, first/last frame, reference image, feature video, base video, or Element generation.
2. Use `motion` when exactly one character image/Element must follow exactly one reference video's motion.
3. Build a temporary UTF-8 JSON request file with the official `contents`, `settings`, and optional `options` structure. Validate it against the selected operation's constraints.
4. Require every media URL to be publicly reachable over HTTPS. When the user supplies a local reference, run the media upload script first and replace it with the returned OSS `public_url`. Do not send local paths or Base64 data URIs to Kling.
5. Submit and capture the returned public `task_id`.
6. Poll every 5 seconds until `SUCCESS` or `FAILURE`; stop after 15 minutes unless the user asks to continue.
7. On success, return `video_url`, duration, model, terminal `cost`, and task ID using the completion format above. Remove the temporary request file.

Do not set `options.callback_url` unless the user explicitly requests a callback and approves its destination. Never call Kling directly.
