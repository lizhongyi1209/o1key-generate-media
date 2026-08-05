# Upload local reference media to O1Key OSS

Video APIs that require public HTTPS references cannot consume local paths. Upload each local image, video, or audio file through O1Key's authenticated OSS presign endpoint before building the generation request.

## Commands

macOS/Linux:

```text
upload-media.sh <local_media_file>
```

Windows:

```text
upload-media.ps1 -FilePath <local_media_file>
```

The scripts:

1. Call `POST https://api.o1key.cn/v1/storage/oss/presign` with the configured O1Key API key, filename, MIME type, and exact byte size.
2. Upload the file directly to the returned Aliyun OSS `upload_url` using the returned method and every signed header.
3. Print only JSON containing the resulting public HTTPS URL:

```json
{"public_url":"https://oss.o1key.cn/uploads/oss/example.mp4"}
```

For Seedance HC, use that `public_url` as the `URL` input to `seedance-video asset create`, wait for the resulting HC asset to become `Active`, and put its `asset://<Id>` locator in the video request. For Kling, use the `public_url` directly in the documented reference field. Never put the O1Key API key in the OSS upload request, log the presigned URL, or construct the public URL manually.

The endpoint accepts images, videos, and audio. Videos are limited to 100 MB. If upload or public retrieval fails, stop before submitting generation; do not replace the media URL with a local path or Base64 value for an API that requires public HTTPS.
