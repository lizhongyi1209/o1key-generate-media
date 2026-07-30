[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('generate', 'status')]
    [string]$Operation,
    [string]$Model,
    [string]$Prompt,
    [int]$Duration,
    [string]$AspectRatio,
    [string]$Resolution,
    [Alias('ImageUrl')]
    [string]$Image,
    [string]$TaskId
)

$ErrorActionPreference = 'Stop'
$baseUrl = 'https://cf-api.o1key.com'
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
    if ([string]::IsNullOrWhiteSpace($TaskId)) {
        throw 'TaskId is required for status.'
    }
    $result = Invoke-RestMethod -Method Get -Uri "$baseUrl/grok/v1/videos/$([Uri]::EscapeDataString($TaskId))" -Headers $headers
} else {
    if ([string]::IsNullOrWhiteSpace($Model) -or [string]::IsNullOrWhiteSpace($Prompt) -or $Duration -le 0 -or [string]::IsNullOrWhiteSpace($AspectRatio) -or [string]::IsNullOrWhiteSpace($Resolution)) {
        throw 'Model, Prompt, Duration, AspectRatio, and Resolution are required for generate.'
    }
    $body = [ordered]@{
        model = $Model
        prompt = $Prompt
        duration = $Duration
        aspect_ratio = $AspectRatio
        resolution = $Resolution
    }
    if (-not [string]::IsNullOrWhiteSpace($Image)) {
        $imageValue = $Image
        if (Test-Path -LiteralPath $Image -PathType Leaf) {
            $extension = [IO.Path]::GetExtension($Image).ToLowerInvariant()
            $mimeType = switch ($extension) {
                '.jpg' { 'image/jpeg' }
                '.jpeg' { 'image/jpeg' }
                '.png' { 'image/png' }
                '.webp' { 'image/webp' }
                '.gif' { 'image/gif' }
                default { throw 'Unsupported local image type. Use JPEG, PNG, WebP, or GIF.' }
            }
            $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Image)))
            $imageValue = "data:$mimeType;base64,$encoded"
        }
        $body.image = @{ url = $imageValue }
    }
    $result = Invoke-RestMethod -Method Post -Uri "$baseUrl/grok/v1/videos/generations" -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 5 -Compress)
}

$result | ConvertTo-Json -Depth 10
