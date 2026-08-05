[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('generate', 'status', 'asset')]
    [string]$Operation,
    [ValidateSet('create', 'status')]
    [string]$AssetOperation,
    [ValidateSet('dreamina-seedance-2-0-hc', 'dreamina-seedance-2-0-fast-hc', 'dreamina-seedance-2-0-mini-hc')]
    [string]$Model,
    [string]$Prompt,
    [ValidateRange(4, 15)]
    [int]$Duration,
    [ValidateSet('adaptive', '16:9', '4:3', '1:1', '3:4', '9:16', '21:9', '9:21')]
    [string]$Ratio,
    [ValidateSet('480p', '720p', '1080p', '4k')]
    [string]$Resolution,
    [string[]]$Image,
    [ValidateSet('-', 'first_frame', 'last_frame', 'reference_image')]
    [string[]]$ImageRole,
    [string[]]$Video,
    [ValidateSet('-', 'reference_video')]
    [string[]]$VideoRole,
    [string[]]$Audio,
    [ValidateSet('-', 'reference_audio')]
    [string[]]$AudioRole,
    [Nullable[bool]]$GenerateAudio,
    [Nullable[bool]]$Watermark,
    [Nullable[bool]]$ReturnLastFrame,
    [string]$TaskId,
    [string]$AssetId,
    [string]$AssetUrl,
    [string]$AssetName,
    [ValidateSet('Image', 'Video', 'Audio')]
    [string]$AssetType
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
    if ([string]::IsNullOrWhiteSpace($TaskId) -or $TaskId -notmatch '^task_[A-Za-z0-9_-]+$') {
        throw 'A valid public TaskId is required for status.'
    }
    $result = Invoke-RestMethod -Method Get -Uri "$baseUrl/v1/video/generations/$([Uri]::EscapeDataString($TaskId))" -Headers $headers
    $result | ConvertTo-Json -Depth 10
    exit
}

if ($Operation -eq 'asset') {
    if ($AssetOperation -eq 'create') {
        if ([string]::IsNullOrWhiteSpace($AssetUrl) -or -not $AssetUrl.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'AssetUrl must be a public HTTPS URL.'
        }
        if ([string]::IsNullOrWhiteSpace($AssetName)) { throw 'AssetName is required.' }
        if ([string]::IsNullOrWhiteSpace($AssetType)) { throw 'AssetType is required.' }
        $body = [ordered]@{ URL = $AssetUrl; Name = $AssetName; AssetType = $AssetType }
        $result = Invoke-RestMethod -Method Post -Uri "$baseUrl/v1/sd/assets" -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Compress)
        $result | ConvertTo-Json -Depth 10
        exit
    }
    if ($AssetOperation -eq 'status') {
        if ([string]::IsNullOrWhiteSpace($AssetId) -or $AssetId -notmatch '^asset-[A-Za-z0-9._-]+$') {
            throw 'A valid AssetId is required for asset status.'
        }
        $result = Invoke-RestMethod -Method Get -Uri "$baseUrl/v1/sd/assets/$([Uri]::EscapeDataString($AssetId))" -Headers $headers
        $result | ConvertTo-Json -Depth 10
        exit
    }
    throw 'AssetOperation must be create or status.'
}

if ([string]::IsNullOrWhiteSpace($Model) -or [string]::IsNullOrWhiteSpace($Prompt) -or -not $PSBoundParameters.ContainsKey('Duration') -or [string]::IsNullOrWhiteSpace($Ratio) -or [string]::IsNullOrWhiteSpace($Resolution)) {
    throw 'Model, Prompt, Duration, Ratio, and Resolution are required for generate.'
}
if ($Model -in @('dreamina-seedance-2-0-fast-hc', 'dreamina-seedance-2-0-mini-hc') -and $Resolution -notin @('480p', '720p')) {
    throw 'Fast HC and Mini HC support only 480p or 720p.'
}

function Test-MediaLocator([string]$Value) {
    return $Value.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase) -or $Value.StartsWith('asset://asset-', [StringComparison]::OrdinalIgnoreCase)
}

foreach ($url in @($Image) + @($Video) + @($Audio)) {
    if (-not [string]::IsNullOrWhiteSpace($url) -and -not (Test-MediaLocator $url)) {
        throw 'Reference media must use a public HTTPS URL or asset://asset-id.'
    }
}
if ($ImageRole -and $ImageRole.Count -ne @($Image).Count) { throw 'ImageRole count must match Image count.' }
if ($VideoRole -and $VideoRole.Count -ne @($Video).Count) { throw 'VideoRole count must match Video count.' }
if ($AudioRole -and $AudioRole.Count -ne @($Audio).Count) { throw 'AudioRole count must match Audio count.' }

$content = [System.Collections.Generic.List[object]]::new()
$content.Add([ordered]@{ type = 'text'; text = $Prompt })
for ($i = 0; $i -lt @($Image).Count; $i++) {
    $role = if ($ImageRole) { $ImageRole[$i] } else { 'reference_image' }
    $item = [ordered]@{ type = 'image_url'; image_url = [ordered]@{ url = $Image[$i] } }
    if ($role -ne '-') { $item['role'] = $role }
    $content.Add($item)
}
for ($i = 0; $i -lt @($Video).Count; $i++) {
    $role = if ($VideoRole) { $VideoRole[$i] } else { 'reference_video' }
    $item = [ordered]@{ type = 'video_url'; video_url = [ordered]@{ url = $Video[$i] } }
    if ($role -ne '-') { $item['role'] = $role }
    $content.Add($item)
}
for ($i = 0; $i -lt @($Audio).Count; $i++) {
    $role = if ($AudioRole) { $AudioRole[$i] } else { 'reference_audio' }
    $item = [ordered]@{ type = 'audio_url'; audio_url = [ordered]@{ url = $Audio[$i] } }
    if ($role -ne '-') { $item['role'] = $role }
    $content.Add($item)
}

$body = [ordered]@{
    model = $Model
    content = $content
    duration = $Duration
    ratio = $Ratio
    resolution = $Resolution
}
if ($GenerateAudio.HasValue) { $body.generate_audio = $GenerateAudio.Value }
if ($Watermark.HasValue) { $body.watermark = $Watermark.Value }
if ($ReturnLastFrame.HasValue) { $body.return_last_frame = $ReturnLastFrame.Value }

$result = Invoke-RestMethod -Method Post -Uri "$baseUrl/v1/video/generations" -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 8 -Compress)
$result | ConvertTo-Json -Depth 10
