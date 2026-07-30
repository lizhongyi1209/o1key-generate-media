---
name: o1key-generate-media
description: Generate media through the O1Key API, currently including Grok text-to-video and image-to-video generation with asynchronous task polling. Use when a user asks Codex or ChatGPT to create, animate, or generate a video with Grok, or asks to configure an O1Key API key for media generation. Designed for Windows and macOS clients and intended to expand to Nano Banana Pro and other image/video models.
---

# O1Key Media Generator

Use `https://cf-api.o1key.com` as the fixed API base URL. Never send the API key anywhere else.

## Select the platform script

- On macOS, run `scripts/configure.sh` and `scripts/grok-video.sh` with `bash`.
- On Windows, run `scripts/configure.ps1` and `scripts/grok-video.ps1` with PowerShell.
- On other POSIX systems, use the macOS shell scripts when `python3` or `node` is available.

Resolve all script paths relative to this `SKILL.md` directory. Do not assume the current working directory is the skill directory.

## Configure authentication

Before the first API call, check whether `.o1key-api-key` exists in this skill directory or `O1KEY_API_KEY` is set. Do not read or display the stored key.

If neither exists:

1. Ask the user to provide their O1Key API key.
2. Start the platform configure script interactively.
3. Send the key only to the script's stdin when prompted. Never place it in command arguments, source files, logs, or the response.
4. Trust the fixed success message; do not reopen the key file.

The configure scripts store the key locally in the ignored `.o1key-api-key` file and restrict permissions where the operating system supports it.

## Generate a Grok video

Read [references/grok-video.md](references/grok-video.md) for models, parameters, and request constraints.

Use one of these operations:

```text
grok-video.sh generate <model> <prompt> <duration> <aspect_ratio> <resolution> [image_source]
grok-video.sh status <public_task_id>
```

```text
grok-video.ps1 generate -Model <model> -Prompt <prompt> -Duration <n> -AspectRatio <ratio> -Resolution <resolution> [-Image <source>]
grok-video.ps1 status -TaskId <public_task_id>
```

Workflow:

1. Use `grok-imagine-video` for text-to-video.
2. Use `grok-imagine-video-1.5` for image-to-video. Accept an HTTPS URL, a Base64 `data:image/...` URI, or a local image path. The platform script converts local files to Base64 data URIs automatically.
3. Submit the generation and capture the returned public `request_id`.
4. Poll `status` every 5 seconds until `done`, `failed`, or `expired`. Stop after 10 minutes unless the user asks to continue.
5. On success, return the original `video.url`, duration, model, and task ID.
6. On failure, report the API error without exposing authentication or internal configuration.

Never invent a task ID or video URL. Never call the upstream xAI API directly.
