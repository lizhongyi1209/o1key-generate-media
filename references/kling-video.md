# Kling 3.0 official video APIs

Use only the O1Key endpoints below. Both accept Kling's official `contents`, `settings`, and `options` request structure.

## Operations

| Operation | Model | Submit | Poll |
| --- | --- | --- | --- |
| `omni` | `kling-3.0-omni` | `POST /kling/omni-video/kling-3.0-omni` | `GET /kling/omni-video/kling-3.0-omni/{task_id}` |
| `motion` | `kling-3.0` | `POST /kling/motion-control/kling-3.0` | `GET /kling/motion-control/kling-3.0/{task_id}` |

Authentication is `Authorization: Bearer <O1Key API key>`. The scripts use the fixed base URL `https://cf-api.o1key.com`.

## Omni 3.0

### Request

```json
{
  "contents": [
    {"type": "prompt", "text": "A cinematic product video"},
    {"type": "refer_image", "url": "https://example.com/product.png", "id": "image_1"}
  ],
  "settings": {
    "multi_shot": false,
    "audio": "off",
    "resolution": "1080p",
    "aspect_ratio": "1:1",
    "duration": 5
  },
  "options": {
    "watermark_info": {"enabled": false}
  }
}
```

### Content types

| Type | Required fields | Meaning |
| --- | --- | --- |
| `prompt` | `text` | Generation instructions |
| `first_frame` | `url`, optional unique `id` | First frame image |
| `last_frame` | `url`, optional unique `id` | Last frame; requires a first frame |
| `refer_image` | `url`, optional unique `id` | General visual reference |
| `feature_video` | `url`, optional unique `id` | Feature/motion reference video |
| `base_video` | `url`, optional unique `id` | Video-to-video base input |
| `element` | `element_id`, unique `id` | Existing Kling Element |

Every supplied `id` must be unique. All media URLs must use public HTTPS.

### Settings

| Field | Type | Accepted values |
| --- | --- | --- |
| `multi_shot` | boolean | `true`, `false` |
| `audio` | string | `native`, `original`, `off` |
| `resolution` | string | `720p`, `1080p`, `4k` |
| `aspect_ratio` | string | `16:9`, `9:16`, `1:1` |
| `duration` | integer | 3–15 seconds |

If there is no first frame, feature video, or base video, `settings.aspect_ratio` is required.

Special combinations:

- `last_frame` requires `first_frame`.
- `feature_video` requires `multi_shot: true` and cannot use `audio: native`.
- `base_video` cannot use multi-shot, native audio, first frame, or last frame.

### Options

| Field | Type | Guidance |
| --- | --- | --- |
| `callback_url` | string | Omit unless explicitly requested and approved |
| `external_task_id` | string | Optional caller-defined identifier |
| `watermark_info.enabled` | boolean | Enable or disable watermark |

## Motion Control 3.0

### Request

```json
{
  "contents": [
    {"type": "image", "url": "https://example.com/character.png"},
    {"type": "video", "url": "https://example.com/motion.mp4"},
    {"type": "prompt", "text": "The character follows the reference motion"}
  ],
  "settings": {
    "character_orientation": "video",
    "audio": "off",
    "resolution": "1080p"
  },
  "options": {
    "watermark_info": {"enabled": false}
  }
}
```

Content rules:

- Supply exactly one `video` with a public HTTPS `url`.
- Supply exactly one `image` with a public HTTPS `url`, or exactly one `element` with `element_id` and unique `id`.
- An optional `prompt` must contain 1–2500 characters.
- Do not provide both an image and an Element.
- Element input requires `character_orientation: video`.

Settings:

| Field | Required | Accepted values |
| --- | --- | --- |
| `character_orientation` | yes | `image`, `video` |
| `audio` | no | `original`, `off` |
| `resolution` | no | `720p`, `1080p` |

Options are the same as Omni.

## Responses

Submission returns an OpenAI-style queued object containing the public `id` and `task_id`.

Polling returns:

```json
{
  "task_id": "task_public_id",
  "status": "SUCCESS",
  "video_url": "https://example.com/result.mp4",
  "duration": 5.041,
  "model": "kling-3.0-omni",
  "cost": "3.825",
  "request_id": "provider_request_id"
}
```

Treat `SUCCESS` and `FAILURE` as terminal states. Other status values are non-terminal.
