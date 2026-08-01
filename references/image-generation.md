# Unified image generation

Use the asynchronous O1Key image API for Nano Banana and GPT Image. Never call a provider directly.

## Endpoints

```text
POST /async/v1/generateImage
GET  /async/v1/tasks/{public_task_id}
```

Both requests use `Authorization: Bearer <O1Key API key>`. Submit JSON with `Content-Type: application/json`.

Use `https://api.o1key.cn` by default. If the primary endpoint fails before returning a task ID with a connection error, timeout, HTTP `403` / Cloudflare `1010`, or HTTP `5xx`, rerun once with `O1KEY_API_ROUTE=fallback` to use `https://cf-api.o1key.com`. Do not switch endpoints for `400`, `401`, `402`, or `429`.

## Supported models

### Nano Banana

- `nano-banana-pro`
- `nano-banana-pro-2k`
- `nano-banana-pro-4k`
- `nano-banana-2-0.5k`
- `nano-banana-2-1k`
- `nano-banana-2-2k`
- `nano-banana-2-4k`

Use `size`, `aspect_ratio`, and Gemini-specific options. Do not send `n`, `quality`, `output_format`, or `mask`.

```json
{
  "model": "nano-banana-pro-2k",
  "prompt": "Create a cinematic product photograph",
  "size": "2K",
  "aspect_ratio": "16:9",
  "response_modalities": ["IMAGE"],
  "images": ["https://example.com/reference.png"]
}
```

Nano Banana fields:

| Field | Values and behavior |
|---|---|
| `size` | `1K`, `2K`, or `4K`; use `0.5K` only with `nano-banana-2-0.5k`. Prefer the size encoded in the model ID. |
| `aspect_ratio` | A supported ratio such as `1:1`, `16:9`, or `9:16`. |
| `images` | Optional reference-image array. Use an array even for one image. |
| `response_modalities` | Prefer `["IMAGE"]`; omitted defaults upstream to text and image. |
| `media_resolution` | Optional Gemini media-resolution enum. |
| `google_search` | Optional boolean; only `true` enables grounding. |
| `thinking_level` | Optional non-empty Gemini thinking level. |
| `include_thoughts` | Optional boolean. |

`nano-banana-pro` has no encoded output size. Omit `size` for the upstream default or set a supported size explicitly.

### GPT Image

Use `gpt-image-2-c`. It maps to the upstream `gpt-image-2` model while preserving the public model ID.

```json
{
  "model": "gpt-image-2-c",
  "prompt": "Create a studio product photograph",
  "n": 1,
  "size": "1024x1024",
  "quality": "high",
  "output_format": "png",
  "images": ["https://example.com/reference.png"]
}
```

GPT Image fields:

| Field | Values and behavior |
|---|---|
| `n` | Optional image count. Keep within the API image-count limit. |
| `size` | Pixel dimensions such as `1024x1024`, or `auto`. Use lowercase `x`, never `×`. |
| `quality` | `low`, `medium`, `high`, or `auto`. |
| `output_format` | `png`, `jpeg`, or `webp`. |
| `images` | Optional reference-image array. Its presence selects image editing. |
| `mask` | Optional edit mask containing exactly one of `image_url` or `file_id`. |

Do not send Nano Banana-only fields to GPT Image. Prefer `size` over `aspect_ratio`.

## Reference images

The `images` array accepts public HTTP(S) URLs, Base64 data URIs, or raw Base64 strings. URL images are limited to 50 MB each; decoded Base64 images are limited to 20 MB. Nano Banana's final inline request body is also limited to approximately 20 MB.

The singular top-level `image` field is removed. Always use `images`, including for one image.

## Responses

Submission:

```json
{
  "task_id": "task_public_id",
  "status": "SUBMITTED"
}
```

Successful polling response:

```json
{
  "task_id": "task_public_id",
  "status": "SUCCESS",
  "progress": "100%",
  "data": {
    "model": "gpt-image-2-c",
    "created": 1785560000,
    "images": [
      {
        "url": "https://example.com/output.png",
        "mime_type": "image/png"
      }
    ]
  }
}
```

When the API returns `b64_json`, the platform status script decodes it into `O1KEY_OUTPUT_DIR` or the current directory's `output` folder and replaces the large Base64 value with `local_path`. Return that local file to the user. When the API returns `url`, preserve and return the URL.

Treat `SUCCESS` and `FAILURE` as terminal. The task response currently has no `cost`; follow the main skill's required fee-line fallback instead of estimating.
