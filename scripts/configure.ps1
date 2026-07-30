[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$skillDir = Split-Path -Parent $PSScriptRoot
$keyFile = Join-Path $skillDir '.o1key-api-key'
$secureKey = Read-Host 'Enter O1Key API key' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)

try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'API key cannot be empty.'
    }
    [IO.File]::WriteAllText($keyFile, $apiKey, [Text.UTF8Encoding]::new($false))
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
}

Write-Output 'O1Key API key configured successfully.'
