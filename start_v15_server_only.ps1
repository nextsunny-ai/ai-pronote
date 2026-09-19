$ErrorActionPreference = "Stop"

$ExpectedVersion = "v1.5.0-beta13.20260920.2"
$HostAddress = "127.0.0.1"
$Port = 8795
$BaseUrl = "http://${HostAddress}:${Port}"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalDataRoot = [Environment]::GetFolderPath('LocalApplicationData')
if ([string]::IsNullOrWhiteSpace($LocalDataRoot)) {
    throw "Windows 사용자 데이터 폴더를 찾을 수 없습니다."
}
$DataDir = Join-Path $LocalDataRoot "AI_PRONOTE\v1.5\data"
$mutex = New-Object System.Threading.Mutex($false, "Local\AI_PRONOTE_v15_Launcher")
$hasMutex = $false

function Get-Health {
    try {
        return Invoke-RestMethod -Uri "$BaseUrl/api/health" -TimeoutSec 2
    } catch {
        return $null
    }
}

try {
    try { $hasMutex = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $hasMutex = $true }
    if (-not $hasMutex) { exit 0 }
    $health = Get-Health
    if ($health) {
        if ($health.version -eq $ExpectedVersion) { exit 0 }
        exit 2
    }

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$env:PRONOTE_HOST = $HostAddress
$env:PRONOTE_PORT = [string]$Port
$env:PRONOTE_DATA_DIR = $DataDir
# Representative internal Windows build: expose read-only experimental CLI status.
# Public/default runs omit this flag and keep the experimental panel hidden.
$env:PRONOTE_EXPERIMENTAL_CLI = "true"

$python = Join-Path $ProjectDir ".venv\Scripts\pythonw.exe"
if (-not (Test-Path -LiteralPath $python)) { exit 4 }
Start-Process -FilePath $python -ArgumentList '"main.py"' -WorkingDirectory $ProjectDir -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds(45)
do {
    Start-Sleep -Milliseconds 350
    $health = Get-Health
    if ($health) { break }
} while ((Get-Date) -lt $deadline)

if (-not $health) { exit 3 }
if ($health.version -ne $ExpectedVersion) { exit 2 }
exit 0
} finally {
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
