[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('generate', 'status')]
    [string]$Operation,
    [string]$RequestFile,
    [string]$TaskId
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
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'O1Key API key is not configured. Run scripts/configure.ps1 first.'
}

$headers = @{ Authorization = "Bearer $apiKey" }
if ($Operation -eq 'status') {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw 'TaskId is required for status.' }
    $result = Invoke-RestMethod -Method Get -Uri "$baseUrl/async/v1/tasks/$([Uri]::EscapeDataString($TaskId))" -Headers $headers
    $outputDir = if ([string]::IsNullOrWhiteSpace($env:O1KEY_OUTPUT_DIR)) { Join-Path (Get-Location) 'output' } else { $env:O1KEY_OUTPUT_DIR }
    $index = 0
    foreach ($image in @($result.data.images)) {
        $index++
        if ([string]::IsNullOrWhiteSpace($image.b64_json)) { continue }
        $bytes = [Convert]::FromBase64String($image.b64_json)
        $extension = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) { 'jpg' } elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { 'png' } else { 'bin' }
        [IO.Directory]::CreateDirectory($outputDir) | Out-Null
        $outputPath = [IO.Path]::GetFullPath((Join-Path $outputDir "$TaskId-$index.$extension"))
        [IO.File]::WriteAllBytes($outputPath, $bytes)
        $image.PSObject.Properties.Remove('b64_json')
        $image | Add-Member -NotePropertyName local_path -NotePropertyValue $outputPath
    }
    $result | ConvertTo-Json -Depth 10
    exit
}

if ([string]::IsNullOrWhiteSpace($RequestFile) -or -not (Test-Path -LiteralPath $RequestFile -PathType Leaf)) {
    throw 'RequestFile must point to an existing JSON file.'
}
$body = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $RequestFile).Path) | ConvertFrom-Json
$models = @('nano-banana-pro', 'nano-banana-pro-2k', 'nano-banana-pro-4k', 'nano-banana-2-0.5k', 'nano-banana-2-1k', 'nano-banana-2-2k', 'nano-banana-2-4k', 'gpt-image-2-c')
if ($body.model -notin $models) { throw 'Unsupported image model.' }
if ([string]::IsNullOrWhiteSpace($body.prompt)) { throw 'Prompt is required.' }
if ($null -ne $body.PSObject.Properties['image']) { throw 'image is removed; use the images array.' }
if ($null -ne $body.PSObject.Properties['images']) {
    foreach ($image in @($body.images)) {
        if ($image -isnot [string] -or [string]::IsNullOrWhiteSpace($image)) { throw 'images must contain non-empty strings.' }
    }
}
if ([string]$body.model -like 'nano-banana*') {
    foreach ($field in @('n', 'quality', 'output_format', 'mask')) {
        if ($null -ne $body.PSObject.Properties[$field]) { throw "Nano Banana does not use $field." }
    }
    if ($null -ne $body.PSObject.Properties['size'] -and ([string]$body.size).ToUpperInvariant() -notin @('0.5K', '1K', '2K', '4K')) {
        throw 'Nano Banana size must be 0.5K, 1K, 2K, or 4K.'
    }
} else {
    foreach ($field in @('response_modalities', 'media_resolution', 'google_search', 'thinking_level', 'include_thoughts', 'aspect_ratio')) {
        if ($null -ne $body.PSObject.Properties[$field]) { throw "GPT Image does not use $field." }
    }
    if ($null -ne $body.PSObject.Properties['n'] -and ([int]$body.n -lt 1)) { throw 'n must be a positive integer.' }
    if ($null -ne $body.PSObject.Properties['quality'] -and $body.quality -notin @('low', 'medium', 'high', 'auto')) { throw 'Invalid GPT Image quality.' }
    if ($null -ne $body.PSObject.Properties['output_format'] -and $body.output_format -notin @('png', 'jpeg', 'webp')) { throw 'Invalid GPT Image output_format.' }
}

$jsonBody = $body | ConvertTo-Json -Depth 10 -Compress
$result = Invoke-RestMethod -Method Post -Uri "$baseUrl/async/v1/generateImage" -Headers $headers -ContentType 'application/json' -Body $jsonBody
$result | ConvertTo-Json -Depth 10

