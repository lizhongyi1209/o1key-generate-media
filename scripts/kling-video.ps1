[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('omni', 'motion')]
    [string]$Kind,
    [Parameter(Position = 1, Mandatory = $true)]
    [ValidateSet('generate', 'status')]
    [string]$Operation,
    [string]$RequestFile,
    [string]$TaskId
)

$ErrorActionPreference = 'Stop'
$baseUrl = 'https://cf-api.o1key.com'
$endpoint = if ($Kind -eq 'omni') { '/kling/omni-video/kling-3.0-omni' } else { '/kling/motion-control/kling-3.0' }
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
    $result = Invoke-RestMethod -Method Get -Uri "$baseUrl$endpoint/$([Uri]::EscapeDataString($TaskId))" -Headers $headers
    $result | ConvertTo-Json -Depth 10
    exit
}

if ([string]::IsNullOrWhiteSpace($RequestFile) -or -not (Test-Path -LiteralPath $RequestFile -PathType Leaf)) {
    throw 'RequestFile must point to an existing JSON file.'
}
$requestPath = (Resolve-Path -LiteralPath $RequestFile).Path
$body = [IO.File]::ReadAllText($requestPath) | ConvertFrom-Json
if ($null -eq $body.contents -or @($body.contents).Count -eq 0) { throw 'contents must be a non-empty array.' }
if ($null -ne $body.model -or $null -ne $body.model_name) { throw 'Model is fixed by the endpoint and must be omitted.' }
foreach ($item in @($body.contents)) {
    if ([string]::IsNullOrWhiteSpace($item.type)) { throw 'Every content item requires type.' }
    if ($null -ne $item.url -and -not ([string]$item.url).StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Media URLs must use public HTTPS.'
    }
}

$jsonBody = $body | ConvertTo-Json -Depth 10 -Compress
$result = Invoke-RestMethod -Method Post -Uri "$baseUrl$endpoint" -Headers $headers -ContentType 'application/json' -Body $jsonBody
$result | ConvertTo-Json -Depth 10
