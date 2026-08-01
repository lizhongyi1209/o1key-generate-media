[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('generate', 'status')]
    [string]$Operation,
    [ValidateSet('seedance-2.0', 'seedance-2.0-fast', 'seedance-2.0-mini')]
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
    [string[]]$Audio,
    [Nullable[bool]]$CameraFixed,
    [Nullable[bool]]$GenerateAudio,
    [Nullable[bool]]$WebSearch,
    [Nullable[long]]$Seed,
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
    $result = Invoke-RestMethod -Method Get -Uri "$baseUrl/v1/video/generations/$([Uri]::EscapeDataString($TaskId))" -Headers $headers
    $result | ConvertTo-Json -Depth 10
    exit
}

if ([string]::IsNullOrWhiteSpace($Model) -or [string]::IsNullOrWhiteSpace($Prompt) -or -not $PSBoundParameters.ContainsKey('Duration') -or [string]::IsNullOrWhiteSpace($Ratio) -or [string]::IsNullOrWhiteSpace($Resolution)) {
    throw 'Model, Prompt, Duration, Ratio, and Resolution are required for generate.'
}
if ($Seed.HasValue -and $Seed.Value -lt -1) { throw 'Seed must be -1 or a non-negative integer.' }
foreach ($url in @($Image) + @($Video) + @($Audio)) {
    if (-not [string]::IsNullOrWhiteSpace($url) -and -not $url.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Reference media must use a public HTTPS URL.'
    }
}
if ($ImageRole -and $ImageRole.Count -ne $Image.Count) { throw 'ImageRole count must match Image count.' }

$body = [ordered]@{ model = $Model; prompt = $Prompt; duration = $Duration; ratio = $Ratio; resolution = $Resolution }
if ($Image) {
    $body.images = for ($i = 0; $i -lt $Image.Count; $i++) {
        $role = if ($ImageRole) { $ImageRole[$i] } else { '-' }
        if ($role -eq '-') { $Image[$i] } else { [ordered]@{ url = $Image[$i]; role = $role } }
    }
}
if ($Video) { $body.videos = @($Video) }
if ($Audio) { $body.audios = @($Audio) }
if ($CameraFixed.HasValue) { $body.camera_fixed = $CameraFixed.Value }
if ($GenerateAudio.HasValue) { $body.generate_audio = $GenerateAudio.Value }
if ($WebSearch.HasValue) { $body.web_search = $WebSearch.Value }
if ($Seed.HasValue) { $body.seed = $Seed.Value }

$result = Invoke-RestMethod -Method Post -Uri "$baseUrl/v1/video/generations" -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 8 -Compress)
$result | ConvertTo-Json -Depth 10
