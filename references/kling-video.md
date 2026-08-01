# Kling 3.0 official video APIs

Use only the O1Key endpoints below. Both accept Kling's official `contents`, `settings`, and `options` request structure.

## Operations

| Operation | Model | Submit | Poll |
| --- | --- | --- | --- |
| `omni` | `kling-3.0-omni` | `POST /kling/omni-video/kling-3.0-omni` | `GET /kling/omni-video/kling-3.0-omni/{task_id}` |
| `motion` | `kling-3.0` | `POST /kling/motion-control/kling-3.0` | `GET /kling/motion-control/kling-3.0/{task_id}` |

Authentication is `Authorization: Bearer <O1Key API key>`. The scripts use `https://api.o1key.cn` by default. Set `O1KEY_API_ROUTE=fallback` only to retry a route failure before a task ID is returned; it uses `https://cf-api.o1key.com`.

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

### Content types…7241 tokens truncated…027 "$request_file"
    else
      printf 'ERROR: python3 or node is required to validate JSON safely.\n' >&2
      exit 1
    fi

    curl --fail-with-body --silent --show-error \
      -X POST \
      -H "Authorization: Bearer $api_key" \
      -H 'Content-Type: application/json' \
      --data-binary "@$request_file" \
      "$base_url/async/v1/generateImage"
    ;;
  *) printf 'Usage: image-generation.sh <generate|status> <request_json_file|public_task_id>\n' >&2; exit 1 ;;
esac
printf '\n'
