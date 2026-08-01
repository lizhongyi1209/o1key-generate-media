# Grok video API

## Contents

- [Endpoints and operations](#endpoints-and-operations)
- [Models](#models)
- [Shared parameters](#shared-parameters)
- [Generate video](#generate-video)
- [Reference-to-video](#reference-to-video)
- [Edit video](#edit-video)
- [Extend video](#extend-video)
- [Output persistence](#output-persistence)
- [Responses](#responses)

## Endpoints and operations

| Script operation | HTTP endpoint | Purpose |
|---|---|---|
| `generate` | `POST /grok/v1/videos/generations` | Text, image, image-reference, or audio-reference generation |
| `edit` | `POST /grok/v1/videos/edits` | Edit an existing video |
| `extend` | `POST /grok/v1/videos/extensions` | Continue an existing video |
| `status` | `GET /grok/v1/videos/{request_id}` | Poll any submitted task |

The primary base URL is `https://api.o1key.cn`; the fallback is `https://cf-api.o1key.com`. Use `O1KEY_API_ROUTE=fallback` only as described in the main skill. Authenticate with `Authorization: Bearer <O1Key API key>`.

## Models

| Model | Supported modes | Resolutions | Generated duration |
|---|---|---|---|
| `grok-imagine-video` | Text, image, references, edit, extend | `480p`, `720p` | 1–15 seconds |
| `grok-imagine-video-1.5` | Image-to-video only | `480p`, `720p`, `1080p` | 1–15 seconds |

The aliases `grok-imagine-video-1.5-preview` and `grok-imagine-video-1.5-2026-05-30` follow the same image-to-video-only rules as `grok-imagine-video-1.5`.

## Shared parameters

| Field | Type | Rules |
|---|---|---|
| `model` | string | Required. Use a supported model above. |
| `prompt` | string | Required except for image-to-video. |
| `duration` | integer or integer string | Generation: 1–15. References: 1–10. Extension: 2–10. |
| `seconds` | integer or integer string | Compatibility alias for `duration`; never send both. |
| `aspect_ratio` | string | `1:1`, `16:9`, `9:16`, `4:3`, `3:4`, `3:2`, or `2:3`. |
| `resolution` | string | `480p`, `720p`, or eligible `1080p`. |
| `user` | string | Optional end-user identifier. |
| `storage_options` | object | Optional O1Key/xAI file persistence settings. |
| `output` | object | Optional upload destination. |

When normal generation omits `duration`, O1Key currently estimates and charges the default as 8 seconds. Extension defaults to 6 added seconds.

Media inputs use exactly one locator:

```json
{"url":"https://example.com/media.mp4"}
{"url":"data:video/mp4;base64,..."}
{"file_id":"file_public_id"}
```

For image inputs, `image_url` is accepted as an alias for `url`. The bundled legacy image-to-video command also accepts a local JPEG, PNG, WebP, or GIF path and converts it to a Base64 data URI.

## Generate video

Text-to-video uses `grok-imagine-video` and requires `prompt`:

```json
{
  "model": "grok-imagine-video",
  "prompt": "A cinematic sunrise over the ocean",
  "duration": 8,
  "aspect_ratio": "16:9",
  "resolution": "720p"
}
```

Image-to-video uses one `image`. The prompt is optional. Only a 1.5 image-to-video request may use `1080p`:

```json
{
  "model": "grok-imagine-video-1.5",
  "prompt": "The camera slowly pushes toward the subject",
  "image": {"url": "https://example.com/input.jpg"},
  "duration": 12,
  "resolution": "1080p"
}
```

Do not combine `image` with `reference_images` or `reference_audios`.

## Reference-to-video

Reference generation requires `grok-imagine-video`, a non-empty prompt, and at least one reference image or audio. It supports at most 7 images, 3 audio inputs, and 10 seconds.

```json
{
  "model": "grok-imagine-video",
  "prompt": "Show the person from <IMAGE_1> wearing the jacket from <IMAGE_2>, speaking with the supplied voice",
  "reference_images": [
    {"url": "https://example.com/person.jpg"},
    {"file_id": "file_jacket"}
  ],
  "reference_audios": [
    {"url": "https://example.com/voice.wav"}
  ],
  "duration": 10,
  "aspect_ratio": "16:9",
  "resolution": "720p"
}
```

`grok-imagine-video-1.5` does not support reference-to-video.

## Edit video

Editing requires `grok-imagine-video`, `prompt`, and one `video`. The input video may be a URL, Base64 data URI, or `file_id`; it must be a supported MP4 no longer than 8.7 seconds.

```json
{
  "model": "grok-imagine-video",
  "prompt": "Add gentle snowfall while preserving the scene",
  "video": {"url": "https://example.com/input.mp4"}
}
```

Do not send `duration`, `seconds`, `aspect_ratio`, `resolution`, `image`, `reference_images`, or `reference_audios`. Output keeps the input duration and aspect ratio, with resolution capped at 720p.

## Extend video

Extension requires `grok-imagine-video`, `prompt`, and one `video`. The MP4 input duration must be 2–15 seconds. `duration` controls only the added segment and accepts 2–10 seconds; the default is 6.

```json
{
  "model": "grok-imagine-video",
  "prompt": "The camera rises above the mountains and reveals the valley",
  "video": {"file_id": "file_source_video"},
  "duration": 6
}
```

Do not send `aspect_ratio`, `resolution`, `image`, `reference_images`, or `reference_audios`. Output inherits the input format, capped at 720p.

## Output persistence

Ask before configuring an external upload destination. `output` requires `upload_url`:

```json
{"output":{"upload_url":"https://example.com/signed-upload-url"}}
```

`storage_options.filename` is required when the object is present. Expirations accept 3600–2592000 seconds. A public URL expiration cannot exceed the file expiration.

```json
{
  "storage_options": {
    "filename": "result.mp4",
    "expires_after": 86400,
    "public_url": {"expires_after": 43200}
  }
}
```

`public_url` may also be `true` or `false`. Omit both persistence objects to use O1Key's normal returned `video.url`, which may already be an R2-accelerated URL.

## Responses

Submission returns only the public task ID:

```json
{"request_id":"task_public_id"}
```

Poll until `done`, `failed`, or `expired`:

```json
{
  "model": "grok-imagine-video",
  "progress": 100,
  "status": "done",
  "video": {
    "duration": 8,
    "url": "https://example.com/output.mp4"
  }
}
```

Return the terminal response's `video.url` unchanged. Never expose or reconstruct an upstream task ID, upstream cost, or moderation metadata. The current Grok response does not include platform `cost`; follow the main skill's fee fallback rather than estimating.
