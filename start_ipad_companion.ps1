param(
    [Parameter(Mandatory=$true)][string]$Certificate,
    [Parameter(Mandatory=$true)][string]$PrivateKey,
    [int]$Port = 8796,
    [int]$SessionMinutes = 240
)
$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mutex = New-Object System.Threading.Mutex($false, "Local\AI_PRONOTE_iPad_Companion_$Port")
$hasMutex = $false
$artifactDir = Join-Path $env:TEMP ("AI_PRONOTE_iPad_" + $PID)
try {
    try { $hasMutex = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $hasMutex = $true }
    if (-not $hasMutex) { throw "AI PRONOTE iPad companion is already running on port $Port." }
if (-not (Test-Path -LiteralPath $Certificate -PathType Leaf)) { throw "HTTPS certificate not found: $Certificate" }
if (-not (Test-Path -LiteralPath $PrivateKey -PathType Leaf)) { throw "HTTPS private key not found: $PrivateKey" }

$address = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
    Sort-Object InterfaceMetric |
    Select-Object -First 1 -ExpandProperty IPAddress
if (-not $address) { throw "No LAN IPv4 address found" }

$tokenBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($tokenBytes)
$token = [Convert]::ToBase64String($tokenBytes).Replace('+','-').Replace('/','_').TrimEnd('=')
$connectUrl = "https://${address}:${Port}/companion/connect"

$env:PRONOTE_IPAD_MODE = "true"
$env:PRONOTE_HOST = "0.0.0.0"
$env:PRONOTE_PORT = [string]$Port
$env:PRONOTE_LAN_HOSTS = $address
$env:PRONOTE_LAN_TOKEN = $token
$env:PRONOTE_LAN_SESSION_SECONDS = [string]([Math]::Max(5, [Math]::Min($SessionMinutes, 1440)) * 60)
$env:PRONOTE_HTTPS_CERT = (Resolve-Path -LiteralPath $Certificate).Path
$env:PRONOTE_HTTPS_KEY = (Resolve-Path -LiteralPath $PrivateKey).Path
$env:PRONOTE_DATA_DIR = Join-Path $ProjectDir "data_v15"

New-Item -ItemType Directory -Path $artifactDir | Out-Null
$qrPath = Join-Path $artifactDir "ipad_companion_qr.png"
Write-Host "iPad connection URL (contains no secret): $connectUrl"
Write-Host "One-time connection code (do not share): $token"
Write-Host "No API key is sent to or stored on the iPad. Keep this window open; Ctrl+C stops LAN access."
python (Join-Path $ProjectDir "tools\make_companion_qr.py") $connectUrl $qrPath
Write-Host "QR image: $qrPath"
try {
    python (Join-Path $ProjectDir "main.py")
} finally {
    Remove-Item -LiteralPath $qrPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $artifactDir -Force -ErrorAction SilentlyContinue
    Remove-Item Env:PRONOTE_LAN_TOKEN -ErrorAction SilentlyContinue
}
} finally {
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
