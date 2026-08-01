# Grok video API

## Endpoints

- Submit: `POST https://api.o1key.cn/grok/v1/videos/generations`
- Poll: `GET https://api.o1key.cn/grok/v1/videos/{request_id}`

Use `O1KEY_API_ROUTE=fallback` only to retry a route failure before a request ID is returned; it uses `https://cf-api.o1key.com`.
- Authentication: `Authorization: Bearer <O1Key API key>`

## Models

| Model | Mode | Resolutions | Duration |
| --- | --- | --- | --- |
| `grok-imagine-video` | Text-to-video or image-to-video | `480p`, `720p` | 1–15 seconds |
| `grok-imagine-video-1.5` | Image-to-video only | `480p`, `720p`, `1080p` | 1–15 seconds |

The 1.5 model requires `image.url`; it does not support text-to-video. Despite the field name, `image.url` accepts:

- A public HTTPS URL
- A Base64 data URI such as `data:image/jpeg;base64,...`
- A local file path when using the bundled scripts; the script converts it to a data URI

## Submit body

```json
{
  "model": "grok-imagine-video",
  "prompt": "A cinematic sunrise over the ocean",
  "duration": 5,
  "aspect_ratio": "16:9",
  "resolution": "720p"
}
```

For image-to-video, add:

```json
{
  "image": {
    "url": "https://example.com/input.jpg"
  }
}
```

Base64 example:

```json
{
  "image": {
    "url": "data:image/jpeg;base64,/9j/4AAQSk..."
  }
}
```

Common aspect ratios include `16:9`, `9:16`, `1:1`, `4:3`, and `3:4`.

## Responses

Submission:

```json
{
  "request_id": "task_public_id"
}
```

Pending:

```json
{
  "model": "grok-imagine-video",
  "status": "pending"
}
```

Completed:

```json
{
  "model": "grok-imagine-video",
  "progress": 100,
  "status": "done",
  "video": {
    "duration": 5,
    "url": "https://vidgen.x.ai/example.mp4"
  }
}
```

Treat `failed` and `expired` as terminal states.
