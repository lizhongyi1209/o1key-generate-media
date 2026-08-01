[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('generate', 'edit', 'extend', 'status')]
    [string]$Operation,
    [string]$RequestFile,
    [string]$TaskId,
    # Backward-compatible basic generation parameters.
    [string]$Model,
    [string]$Prompt,
    [Nullable[int]]$Duration,
    [string]$AspectRatio,
    [string]$Resolution,
    [Alias('ImageUrl')]
    [string]$Image
)

$ErrorActionPreference = 'Stop'
$primaryBaseUrl = 'https://api.o1key.cn'
$fallbackBaseUrl = 'https://cf-api.o1key.com'
$route = if ([string]::IsNullOrWhiteSpace($env:O1KEY_API_ROUTE)) { 'primary' } else { $env:O1KEY_API_ROUTE.Trim().ToLowerInvariant() }
if ($route -notin @('primary', 'fallback')) { throw 'O1KEY_API_ROUTE must be primary or fallback.' }
$baseUrl = if ($route -eq 'fallback') { $fallbackBaseUrl } else { $primaryBaseUrl }
$skillDir = Split-Path -Parent $PSScriptRoot
$keyFile = Join-Path $skillDir '.o1key-api-key'
$apiKey = $env:O1KEY_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey) -and (Test-Path $keyFile)) {
    $apiKey = [IO.File]::ReadAllText($keyFile).Trim()
}
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'O1Key API key is not configured. Run scripts/configure.ps1 first.' }
$headers = @{ Authorization = "Bearer $apiKey" }

if ($Operation -eq 'status') {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw 'TaskId is required for status.' }
    $result = Invoke-RestMethod -Method Get -Uri "$baseUrl/grok/v1/videos/$([Uri]::EscapeDataString($TaskId))" -Headers $headers
    $result | ConvertTo-Json -Depth 20
    exit
}

function Has-Field([object]$Object, [string]$Name) {
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Test-MediaInput([string]$Name, [object]$Value, [bool]$AllowImageUrl = $false) {
    if ($null -eq $Value) { throw "$Name is required." }
    $fields = @('url', 'file_id')
    if ($AllowImageUrl) { $fields += 'image_url' }
    $present = @($fields | Where-Object { (Has-Field $Value $_) -and -not [string]::IsNullOrWhiteSpace([string]$Value.$_) })
    if ($present.Count -ne 1) { throw "$Name requires exactly one media locator." }
}

$body = $null
if (-not [string]::IsNullOrWhiteSpace($RequestFile)) {
    if (-not (Test-Path -LiteralPath $RequestFile -PathType Leaf)) { throw 'RequestFile must point to an existing JSON file.' }
    $body = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $RequestFile).Path) | ConvertFrom-Json
} elseif ($Operation -eq 'generate') {
    if ([string]::IsNullOrWhiteSpace($Model) -or [string]::IsNullOrWhiteSpace($Prompt) -or $null -eq $Duration -or [string]::IsNullOrWhiteSpace($AspectRatio) -or [string]::IsNullOrWhiteSpace($Resolution)) {
        throw 'Use -RequestFile for the complete API, or provide Model, Prompt, Duration, AspectRatio, and Resolution for legacy generation.'
    }
    $body = [ordered]@{ model = $Model; prompt = $Prompt; duration = $Duration.Value; aspect_ratio = $AspectRatio; resolution = $Resolution }
    if (-not [string]::IsNullOrWhiteSpace($Image)) {
        $imageValue = $Image
        if (Test-Path -LiteralPath $Image -PathType Leaf) {
            $extension = [IO.Path]::GetExtension($Image).ToLowerInvariant()
            $mimeType = switch ($extension) {
                '.jpg' { 'image/jpeg' }; '.jpeg' { 'image/jpeg' }; '.png' { 'image/png' }; '.webp' { 'image/webp' }; '.gif' { 'image/gif' }
                default { throw 'Unsupported local image type. Use JPEG, PNG, WebP, or GIF.' }
            }
            $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Image)))
            $imageValue = "data:$mimeType;base64,$encoded"
        }
        $body.image = @{ url = $imageValue }
    }
} else {
    throw "RequestFile is required for $Operation."
}

$models = @('grok-imagine-video', 'grok-imagine-video-1.5', 'grok-imagine-video-1.5-preview', 'grok-imagine-video-1.5-2026-05-30')
if ($body.model -notin $models) { throw 'Unsupported Grok video model.' }
$is15 = $body.model -ne 'grok-imagine-video'
if ((Has-Field $body 'duration') -and (Has-Field $body 'seconds')) { throw 'Send duration or seconds, not both.' }
$durationValue = $null
if (Has-Field $body 'duration') { $durationValue = [int]$body.duration }
elseif (Has-Field $body 'seconds') { $durationValue = [int]$body.seconds }
if ((Has-Field $body 'aspect_ratio') -and $body.aspect_ratio -notin @('1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3')) { throw 'Invalid aspect_ratio.' }
if ((Has-Field $body 'resolution') -and $body.resolution -notin @('480p', '720p', '1080p')) { throw 'Invalid resolution.' }

if (Has-Field $body 'output') {
    if ($null -eq $body.output -or [string]::IsNullOrWhiteSpace([string]$body.output.upload_url)) { throw 'output.upload_url is required.' }
}
if (Has-Field $body 'storage_options') {
    $storage = $body.storage_options
    if ($null -eq $storage -or [string]::IsNullOrWhiteSpace([string]$storage.filename)) { throw 'storage_options.filename is required.' }
    if (Has-Field $storage 'expires_after') {
        $expiry = [int]$storage.expires_after
        if ($expiry -lt 3600 -or $expiry -gt 2592000) { throw 'storage_options.expires_after must be between 3600 and 2592000.' }
    }
    if (Has-Field $storage 'public_url') {
        $public = $storage.public_url
        if ($public -isnot [bool] -and $public -isnot [PSCustomObject]) { throw 'storage_options.public_url must be a boolean or object.' }
        if ($public -is [PSCustomObject] -and (Has-Field $public 'expires_after')) {
            $publicExpiry = [int]$public.expires_after
            if ($publicExpiry -lt 3600 -or $publicExpiry -gt 2592000) { throw 'Invalid public URL expiration.' }
            if ((Has-Field $storage 'expires_after') -and $publicExpiry -gt [int]$storage.expires_after) { throw 'Public URL expiration cannot exceed file expiration.' }
        }
    }
}

$references = if (Has-Field $body 'reference_images') { @($body.reference_images) } else { @() }
$audios = if (Has-Field $body 'reference_audios') { @($body.reference_audios) } else { @() }
$hasImage = Has-Field $body 'image'
$hasVideo = Has-Field $body 'video'
$hasPrompt = (Has-Field $body 'prompt') -and -not [string]::IsNullOrWhiteSpace([string]$body.prompt)

if ($Operation -eq 'generate') {
    if ($hasVideo) { throw 'video is only valid for edit or extend.' }
    if ($null -ne $durationValue -and ($durationValue -lt 1 -or $durationValue -gt 15)) { throw 'Generation duration must be 1-15.' }
    if ($hasImage -and ($references.Count -gt 0 -or $audios.Count -gt 0)) { throw 'image and reference inputs are mutually exclusive.' }
    if ($hasImage) {
        Test-MediaInput 'image' $body.image $true
    } elseif ($references.Count -gt 0 -or $audios.Count -gt 0) {
        if ($is15) { throw 'Grok 1.5 does not support reference-to-video.' }
        if (-not $hasPrompt) { throw 'Prompt is required for reference-to-video.' }
        if ($references.Count -gt 7 -or $audios.Count -gt 3) { throw 'Reference limits are 7 images and 3 audios.' }
        if ($null -ne $durationValue -and $durationValue -gt 10) { throw 'Reference duration must be 1-10.' }
        for ($i = 0; $i -lt $references.Count; $i++) { Test-MediaInput "reference_images[$i]" $references[$i] $true }
        for ($i = 0; $i -lt $audios.Count; $i++) {
            if ($null -eq $audios[$i] -or [string]::IsNullOrWhiteSpace([string]$audios[$i].url)) { throw "reference_audios[$i].url is required." }
        }
    } else {
        if ($is15) { throw 'Grok 1.5 supports image-to-video only.' }
        if (-not $hasPrompt) { throw 'Prompt is required for text-to-video.' }
    }
    if ((Has-Field $body 'resolution') -and $body.resolution -eq '1080p' -and -not ($is15 -and $hasImage)) { throw '1080p requires Grok 1.5 image-to-video.' }
} elseif ($Operation -eq 'edit') {
    if ($is15) { throw 'Edit requires grok-imagine-video.' }
    if (-not $hasPrompt) { throw 'Prompt is required for edit.' }
    Test-MediaInput 'video' $body.video
    foreach ($field in @('duration', 'seconds', 'aspect_ratio', 'resolution', 'image', 'reference_images', 'reference_audios')) {
        if (Has-Field $body $field) { throw "Edit does not support $field." }
    }
} else {
    if ($is15) { throw 'Extend requires grok-imagine-video.' }
    if (-not $hasPrompt) { throw 'Prompt is required for extend.' }
    Test-MediaInput 'video' $body.video
    if ($null -ne $durationValue -and ($durationValue -lt 2 -or $durationValue -gt 10)) { throw 'Extension duration must be 2-10.' }
    foreach ($field in @('aspect_ratio', 'resolution', 'image', 'reference_images', 'reference_audios')) {
        if (Has-Field $body $field) { throw "Extend does not support $field." }
    }
}

$endpoint = switch ($Operation) {
    'generate' { '/grok/v1/videos/generations' }
    'edit' { '/grok/v1/videos/edits' }
    'extend' { '/grok/v1/videos/extensions' }
}
$jsonBody = $body | ConvertTo-Json -Depth 20 -Compress
$result = Invoke-RestMethod -Method Post -Uri "$baseUrl$endpoint" -Headers $headers -ContentType 'application/json' -Body $jsonBody
$result | ConvertTo-Json -Depth 20
