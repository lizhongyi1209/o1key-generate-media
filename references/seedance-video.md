# Seedance 2.0 video API

## Endpoints

- Submit: `POST https://api.o1key.cn/v1/video/generations`
- Poll: `GET https://api.o1key.cn/v1/video/generations/{task_id}`

Use `O1KEY_API_ROUTE=fallback` only to retry a route failure before a task ID is returned; it uses `https://cf-api.o1key.com`.
- Authentication: `Authorization: Bearer <O1Key API key>`

## Models

| Model | Guidance |
| --- | --- |
| `seedance-2.0` | Standard model for final-quality generation |
| `seedance-2.0-fast` | Faster model for drafts and iteration |
| `seedance-2.0-mini` | Lower-cost model for simple or exploratory generation |

## Parameters

| Field | Type | Required | Accepted values and meaning |
| --- | --- | --- | --- |
| `model` | string | yes | One of the three models above |
| `prompt` | string | yes | Generation instructions and references such as image/video/audio roles |
| `images` | array | no | Public HTTPS image references, as URL strings or `{url, role}` objects |
| `image_urls` | array | no | Alias of `images`; bundled scripts emit `images` |
| `videos` | string[] | no | Public HTTPS reference video URLs |
| `audios` | string[] | no | Public HTTPS reference audio URLs |
| `duration` | integer | yes in scripts | 4–15 seconds |
| `resolution` | string | yes in scripts | `480p`, `720p`, `1080p`, or `4k` |
| `ratio` | string | yes in scripts | `adaptive`, `16:9`, `4:3`, `1:1`, `3:4`, `9:16`, `21:9`, or `9:21` |
| `camera_fixed` | boolean | no | Keep the camera fixed when `true` |
| `generate_audio` | boolean | no | Generate synchronized audio when `true` |
| `web_search` | boolean | no | Enable supported web-search augmentation |
| `seed` | integer | no | `-1` for random or a non-negative seed |

Image roles include `first_frame`, `last_frame`, and `reference_image`. Use `-` in the Bash script to omit a role.

All reference media must be publicly reachable over HTTPS. Do not pass local paths, `file:` URLs, or Base64 data URIs. For local media, use the bundled `upload-media` script to upload through `POST /v1/storage/oss/presign`, then pass its returned `public_url`.

Recommended multimodal limits:

- Up to 9 images
- Up to 3 videos with no more than 15 seconds combined duration
- Up to 3 audios with no more than 15 seconds combined duration
- Up to 12 total reference materials

## Bash examples

Text-to-video:

```text
seedance-video.sh generate seedance-2.0 "A cinematic sunrise over the ocean" 5 16:9 720p --generate-audio true
```

Image-to-video:

```text
seedance-video.sh generate seedance-2.0 "The subject slowly turns toward the camera" 5 9:16 720p --image https://example.com/first.jpg first_frame --generate-audio true
```

Multimodal reference generation:

```text
seedance-video.sh generate seedance-2.0 "Use the character, camera motion, and audio rhythm from the references" 8 16:9 720p --image https://example.com/character.jpg reference_image --video https://example.com/motion.mp4 --audio https://example.com/rhythm.mp3 --generate-audio true
```

## PowerShell examples

```text
seedance-video.ps1 generate -Model seedance-2.0 -Prompt "A cinematic sunrise over the ocean" -Duration 5 -Ratio 16:9 -Resolution 720p -GenerateAudio $true
```

```text
seedance-video.ps1 generate -Model seedance-2.0 -Prompt "Animate the subject" -Duration 5 -Ratio 9:16 -Resolution 720p -Image https://example.com/first.jpg -ImageRole first_frame -GenerateAudio $true
```

## Responses

Submission returns a public task ID:

```json
{
  "id": "task_public_id",
  "task_id": "task_public_id",
  "object": "video",
  "model": "seedance-2.0",
  "status": "queued",
  "progress": 0
}
```

Completed task:

```json
{
  "status": "success",
  "task_id": "task_public_id",
  "model": "seedance-2.0",
  "progress": 100,
  "video_url": "https://example.com/output.mp4"
}
```

Treat `success` and `failed` as terminal states; `processing` is non-terminal.
