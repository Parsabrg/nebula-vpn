[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$destination = Join-Path $root 'assets\windows_runtime'
$xrayVersion = 'v26.9.30'
$xrayHash = 'B17A619343C11B89D8FAF36278298856749B15C52277D875D32051B33DCDA617'
$hysteriaHash = '807AE5332A8FEFEEFF804923E057B6942ACCEAA11706AC7FA3DB42F192C2FDE1'
# The DNS tunnel's engine (docs/runbooks/dns-tunnel.md): the same release Android ships.
$cottenVersion = 'v2026.11.03.161534-be99443'
$cottenHash = 'B62C43CA8E75890598F4FAEB4EBCFD3BB0D0709A98B25CD1F3E3A8440B342B43'

New-Item -ItemType Directory -Path $destination -Force | Out-Null

function Get-VerifiedAsset([string]$Url, [string]$Destination, [string]$ExpectedHash) {
    Invoke-WebRequest -Uri $Url -OutFile $Destination
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedHash) {
        throw "SHA-256 mismatch for $(Split-Path $Destination -Leaf): expected $ExpectedHash, got $actual"
    }
}

$temporary = Join-Path $env:TEMP 'nebula-xray-windows.zip'
$cottenZip = Join-Path $env:TEMP 'nebula-cottendns-windows.zip'
try {
    Get-VerifiedAsset "https://github.com/XTLS/Xray-core/releases/download/$xrayVersion/Xray-windows-64.zip" $temporary $xrayHash
    Expand-Archive -LiteralPath $temporary -DestinationPath $destination -Force
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'wintun.dll'))) {
        throw 'The official Xray Windows archive did not contain wintun.dll.'
    }
    Get-VerifiedAsset 'https://github.com/HyNetworks/hysteria/releases/download/app/v2.12.2/hysteria-windows-amd64.exe' (Join-Path $destination 'hysteria.exe') $hysteriaHash
    Get-VerifiedAsset "https://github.com/WhiteDNS/CottenDNS/releases/download/$cottenVersion/CottenDns_Client_Windows_AMD64.zip" $cottenZip $cottenHash
    $cottenFolder = Join-Path $env:TEMP 'nebula-cottendns-windows'
    Expand-Archive -LiteralPath $cottenZip -DestinationPath $cottenFolder -Force
    Copy-Item -LiteralPath (Join-Path $cottenFolder "CottenDns_Client_Windows_AMD64_$cottenVersion.exe") -Destination (Join-Path $destination 'cottendns_client.exe') -Force
    Remove-Item -LiteralPath $cottenFolder -Recurse -Force
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    if (Test-Path -LiteralPath $cottenZip) { Remove-Item -LiteralPath $cottenZip -Force }
}
