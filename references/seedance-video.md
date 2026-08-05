# Seedance 2.0 HC video API

Use the HC models for Seedance 2.0 text-to-video, identity-preserving human references, and multimodal image/video/audio generation. Register reference media as HC assets before generation; do not use the legacy non-HC model names or grouped `/v1/assets` workflow.

## Endpoints

- Create asset: `POST https://api.o1key.cn/v1/sd/assets`
- Poll asset: `GET https://api.o1key.cn/v1/sd/assets/{asset_id}`
- Submit video: `POST https://api.o1key.cn/v1/video/generations`
- Poll video: `GET https://api.o1key.cn/v1/video/generations/{task_id}`
- Authentication: `Authorization: Bearer <O1Key API key>`

Use `O1KEY_API_ROUTE=fallback` only for the route-recovery cases in `SKILL.md`; it switches all four operations to `https://cf-api.o1key.com`. Never call the internal upstream `/v1/video/generate` or `/v1/video/tasks/...` endpoints.

## HC models

| Model | Guidance | Resolutions |
| --- | --- | --- |
| `dreamina-seedance-2-0-hc` | Base HC for highest-quality identity-preserving output | `480p`, `720p`, `1080p`, `4k` |
| `dreamina-seedance-2-0-fast-hc` | Faster HC drafts and iteration | `480p`, `720p` |
| `dreamina-seedance-2-0-mini-hc` | Lower-cost HC exploration | `480p`, `720p` |

Use an HC model whenever a request contains a human reference or an `asset://` locator. Do not substitute `seedance-2.0`, `seedance-2.0-fast`, `seedance-2.0-mini`, or a non-HC `dreamina-*` model.

## Register multimodal assets

For every reference image, video, or audio:

1. Obtain a public HTTPS source URL. If the user provides a local file, run the bundled `upload-media` script first and use its `public_url`.
2. Create the HC asset with the exact case-sensitive fields `URL`, `Name`, and `AssetType`.
3. Read the asset ID from `data.Id`.
4. Poll the asset endpoint every 2–5 seconds until `data.Status` is `Active`. Treat `Failed` as terminal and report its error. Do not generate while the asset is `Processing`.
5. Replace the public URL with `asset://<data.Id>` in the video request. An active asset can be reused in later requests made by the same O1Key account.

Bash:

```text
seedance-video.sh asset create https://example.com/person.jpg avatar_front Image
seedance-video.sh asset status asset-20260805-example

seedance-video.sh asset create https://example.com/motion.mp4 motion_reference Video
seedance-video.sh asset status asset-20260805-motion

seedance-video.sh asset create https://example.com/voice.mp3 voice_reference Audio
seedance-video.sh asset status asset-20260805-voice
```

PowerShell:

```text
seedance-video.ps1 asset -AssetOperation create -AssetUrl https://example.com/person.jpg -AssetName avatar_front -AssetType Image
seedance-video.ps1 asset -AssetOperation status -AssetId asset-20260805-example
```

Raw asset request:

```json
{
  "URL": "https://example.com/person.jpg",
  "Name": "avatar_front",
  "AssetType": "Image"
}
```

Typical responses:

```json
{
  "success": true,
  "data": {
    "Id": "asset-20260805-example",
    "base_resp": { "status_code": 0, "status_msg": "success" }
  }
}
```

```json
{
  "success": true,
  "data": {
    "Id": "asset-20260805-example",
    "Status": "Active",
    "AssetType": "Image",
    "Name": "avatar_front"
  }
}
```

The source URL must remain directly downloadable while the asset is processing. A webpage URL, expired signed URL, anti-hotlink response, or URL requiring cookies can fail with `DownloadFailed`.

## Generate with `content[]`

The scripts send the HC-native multimodal structure. The first item is text; each reference is a typed media item containing either an active `asset://` locator or, only when explicitly appropriate, a public HTTPS URL.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `model` | string | yes | One HC model from the table above |
| `content` | array | yes | Text plus zero or more image/video/audio references |
| `duration` | integer | yes in scripts | 4–15 seconds |
| `resolution` | string | yes in scripts | Model-supported resolution |
| `ratio` | string | yes in scripts | `adaptive`, `16:9`, `4:3`, `1:1`, `3:4`, `9:16`, `21:9`, or `9:21` |
| `generate_audio` | boolean | no | Generate synchronized audio |
| `watermark` | boolean | no | Add a watermark |
| `return_last_frame` | boolean | no | Include the generated last-frame URL in the completed task metadata |

Supported content forms:

```json
{ "type": "text", "text": "generation prompt" }
{ "type": "image_url", "image_url": { "url": "asset://asset-id" }, "role": "reference_image" }
{ "type": "image_url", "image_url": { "url": "asset://asset-id" }, "role": "first_frame" }
{ "type": "image_url", "image_url": { "url": "asset://asset-id" }, "role": "last_frame" }
{ "type": "video_url", "video_url": { "url": "asset://asset-id" }, "role": "reference_video" }
{ "type": "audio_url", "audio_url": { "url": "asset://asset-id" }, "role": "reference_audio" }
```

Recommended limits:

- Up to 9 images
- Up to 3 videos with no more than 15 seconds combined duration
- Up to 3 audios with no more than 15 seconds combined duration
- Up to 12 total reference materials

## Multimodal examples

### Human image and reference audio

Register both sources and wait for `Active`, then run:

```text
seedance-video.sh generate dreamina-seedance-2-0-hc "The woman looks at the camera, speaks naturally with the reference voice, and keeps the same identity, face, clothing, and background" 5 9:16 720p --image asset://asset-person reference_image --audio asset://asset-voice reference_audio --generate-audio true --watermark false --return-last-frame true
```

PowerShell:

```text
seedance-video.ps1 generate -Model dreamina-seedance-2-0-hc -Prompt "The woman looks at the camera and speaks naturally with the reference voice" -Duration 5 -Ratio 9:16 -Resolution 720p -Image asset://asset-person -ImageRole reference_image -Audio asset://asset-voice -AudioRole reference_audio -GenerateAudio $true -Watermark $false -ReturnLastFrame $true
```

### Multiple images, motion video, and audio

```text
seedance-video.sh generate dreamina-seedance-2-0-hc "Preserve the subject identity and clothing from the portrait, follow the movement and camera rhythm from the video, and synchronize the action to the reference audio" 8 16:9 720p --image asset://asset-person reference_image --image asset://asset-scene first_frame --video asset://asset-motion reference_video --audio asset://asset-rhythm reference_audio --generate-audio true --watermark false
```

Equivalent request body:

```json
{
  "model": "dreamina-seedance-2-0-hc",
  "content": [
    {
      "type": "text",
      "text": "Preserve the subject identity and clothing from the portrait, follow the movement and camera rhythm from the video, and synchronize the action to the reference audio"
    },
    {
      "type": "image_url",
      "image_url": { "url": "asset://asset-person" },
      "role": "reference_image"
    },
    {
      "type": "image_url",
      "image_url": { "url": "asset://asset-scene" },
      "role": "first_frame"
    },
    {
      "type": "video_url",
      "video_url": { "url": "asset://asset-motion" },
      "role": "reference_video"
    },
    {
      "type": "audio_url",
      "audio_url": { "url": "asset://asset-rhythm" },
      "role": "reference_audio"
    }
  ],
  "duration": 8,
  "resolution": "720p",
  "ratio": "16:9",
  "generate_audio": true,
  "watermark": false,
  "return_last_frame": true
}
```

Text-only generation uses the same HC model and omits all media options:

```text
seedance-video.sh generate dreamina-seedance-2-0-mini-hc "A cinematic sunrise over the ocean" 5 16:9 720p --generate-audio true
```

## Video task responses

Submission returns a public task ID:

```json
{
  "id": "task_public_id",
  "task_id": "task_public_id",
  "object": "video",
  "model": "dreamina-seedance-2-0-hc",
  "status": "queued",
  "progress": 0
}
```

Poll only the public `task_...` ID returned by O1Key. Treat `queued` and `in_progress` as non-terminal, `completed` as success, and `failed` as failure. On completion, read `metadata.url` or `metadata.outputs[0]`; `metadata.last_frame_url` is present when requested and supported.

```json
{
  "id": "task_public_id",
  "task_id": "task_public_id",
  "model": "dreamina-seedance-2-0-hc",
  "status": "completed",
  "progress": 100,
  "metadata": {
    "url": "https://example.com/output.mp4",
    "outputs": ["https://example.com/output.mp4"],
    "last_frame_url": "https://example.com/last-frame.jpg"
  }
}
```
