---
name: o1key-generate-media
description: Generate media through the O1Key API, including Grok and Seedance 2.0 text-to-video, image-to-video, and multimodal reference video generation with asynchronous task polling. Use when a user asks Codex or ChatGPT to create, animate, or generate a video with Grok or Seedance, use reference images/videos/audio, or configure an O1Key API key for media generation. Designed for Windows and macOS clients and intended to expand to Nano Banana Pro and other image/video models.
---

# O1Key Media Generator

Use `https://cf-api.o1key.com` as the fixed API base URL. Never send the API key anywhere else.

## Select the platform script

- On macOS, run `scripts/configure.sh`, `scripts/grok-video.sh`, and `scripts/seedance-video.sh` with `bash`.
- On Windows, run the corresponding `.ps1` scripts with PowerShell.
- On other POSIX systems, use the macOS shell scripts when `python3` or `node` is available.

Resolve all script paths relative to this `SKILL.md` directory. Do not assume the current working directory is the skill directory.

## Configure authentication

Before the first API call, check whether `.o1key-api-key` exists in this skill directory or `O1KEY_API_KEY` is set. Do not read or display the stored key.

Treat a user who sends an API key in the conversation and explicitly asks to configure this skill as authorizing these limited actions:

- Store that key only in this skill's `.o1key-api-key` file.
- Use it only for requests to `https://cf-api.o1key.com`.
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

Suggested user request:

```text
Configure this API key for $o1key-generate-media and use it only with https://cf-api.o1key.com: <API_KEY>
```

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

## Generate a Seedance 2.0 video

Read [references/seedance-video.md](references/seedance-video.md) for models, parameters, media limits, and examples.

Use one of these operations:

```text
seedance-video.sh generate <model> <prompt> <duration> <ratio> <resolution> [options]
seedance-video.sh status <public_task_id>
```

```text
seedance-video.ps1 generate -Model <model> -Prompt <prompt> -Duration <n> -Ratio <ratio> -Resolution <resolution> [options]
seedance-video.ps1 status -TaskId <public_task_id>
```

Workflow:

1. Select `seedance-2.0`, `seedance-2.0-fast`, or `seedance-2.0-mini` according to the user's quality and speed preference.
2. Accept text-only generation or public HTTPS image, video, and audio references. Seedance media inputs must be public URLs; do not send local paths or Base64 data URIs.
3. Submit the generation and capture the returned public `task_id`.
4. Poll `status` every 5 seconds until `success` or `failed`. Stop after 15 minutes unless the user asks to continue.
5. On success, return `video_url`, model, and task ID.
6. On failure, report the API error without exposing authentication or internal configuration.

Never invent media URLs or task IDs. Never call a Seedance upstream provider directly.
