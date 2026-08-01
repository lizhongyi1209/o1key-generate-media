[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$FilePath
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

if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw 'FilePath must point to an existing media file.' }
$file = Get-Item -LiteralPath $FilePath
$contentType = switch ($file.Extension.ToLowerInvariant()) {
    '.jpg'  { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.png'  { 'image/png' }
    '.gif'  { 'image/gif' }
    '.webp' { 'image/webp' }
    '.mp4'  { 'video/mp4' }
    '.mov'  { 'video/quicktime' }
    '.webm' { 'video/webm' }
    '.mp3'  { 'audio/mpeg' }
    '.wav'  { 'audio/wav' }
    '.m4a'  { 'audio/mp4' }
    '.aac'  { 'audio/aac' }
    default { throw "Unsupported media extension: $($file.Extension)" }
}

$authHeaders = @{ Authorization = "Bearer $apiKey" }
$presignBody = [ordered]@{
    filename = $file.Name
    content_type = $contentType
    size = $file.Length
} | ConvertTo-Json -Compress
$presign = Invoke-RestMethod -Method Post -Uri "$baseUrl/v1/storage/oss/presign" -Headers $authHeaders -ContentType 'application/json' -Body $presignBody
if ([string]::IsNullOrWhiteSpace($presign.upload_url) -or -not ([string]$presign.upload_url).StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Invalid OSS presign response: upload_url is missing.'
}
if ([string]::IsNullOrWhiteSpace($presign.public_url) -or -not ([string]$presign.public_url).StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Invalid OSS presign response: public_url is missing.'
}

$uploadHeaders = @{}
$uploadContentType = $null
if ($null -ne $presign.headers) {
    foreach ($property in $presign.headers.PSObject.Properties) {
        if ($property.Name -ieq 'Content-Type') {
            $uploadContentType = [string]$property.Value
        } elseif ($property.Name -ine 'Content-Length') {
            $uploadHeaders[$property.Name] = [string]$property.Value
        }
    }
}
$method = if ([string]::IsNullOrWhiteSpace($presign.method)) { 'PUT' } else { [string]$presign.method }
$uploadParameters = @{
    Method = $method
    Uri = $presign.upload_url
    Headers = $uploadHeaders
    InFile = $file.FullName
    UseBasicParsing = $true
}
if (-not [string]::IsNullOrWhiteSpace($uploadContentType)) { $uploadParameters.ContentType = $uploadContentType }
Invoke-WebRequest @uploadParameters | Out-Null

[ordered]@{ public_url = [string]$presign.public_url } | ConvertTo-Json -Compress
