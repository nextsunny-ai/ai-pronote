$ErrorActionPreference = "Stop"

$ExpectedVersion = "v1.5.0-beta11.20260919"
$HostAddress = "127.0.0.1"
$Port = 8795
$BaseUrl = "http://${HostAddress}:${Port}"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $ProjectDir "data_v15"
$mutex = New-Object System.Threading.Mutex($false, "Local\AI_PRONOTE_v15_Launcher")
$hasMutex = $false
$splash = $null

function Get-Health {
    try {
        return Invoke-RestMethod -Uri "$BaseUrl/api/health" -TimeoutSec 2
    } catch {
        return $null
    }
}

function Show-AppWindow {
    $matching = Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains("--app=$BaseUrl") } |
        Select-Object -First 1
    if ($matching) {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.AppActivate([int]$matching.ProcessId)
        return
    }

    $chromeCandidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    $chrome = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($chrome) {
        Start-Process -FilePath $chrome -ArgumentList "--app=$BaseUrl"
    } else {
        Start-Process $BaseUrl
    }
}

function Show-VersionConflict([string]$runningVersion) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "AI PRONOTE version conflict: port $Port is serving '$runningVersion', expected '$ExpectedVersion'. No process was stopped.",
        "AI PRONOTE - version conflict",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

try {
    try {
        $hasMutex = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $hasMutex = $true
    }
    if (-not $hasMutex) { exit 0 }

    $health = Get-Health
    if ($health) {
        if ($health.version -ne $ExpectedVersion) {
            Show-VersionConflict ([string]$health.version)
            exit 2
        }
        Show-AppWindow
        exit 0
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $splash = New-Object System.Windows.Forms.Form
    $splash.Text = "AI PRONOTE"
    $splash.Size = New-Object System.Drawing.Size(360, 145)
    $splash.StartPosition = "CenterScreen"
    $splash.FormBorderStyle = "FixedDialog"
    $splash.ControlBox = $false
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "AI PRONOTE 준비 중..."
    $label.AutoSize = $true
    $label.Font = New-Object System.Drawing.Font("Malgun Gothic", 14)
    $label.Location = New-Object System.Drawing.Point(55, 38)
    $splash.Controls.Add($label)
    $splash.Show()
    [System.Windows.Forms.Application]::DoEvents()

    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    $env:PRONOTE_HOST = $HostAddress
    $env:PRONOTE_PORT = [string]$Port
    $env:PRONOTE_DATA_DIR = $DataDir
    $python = Join-Path $ProjectDir '.venv\Scripts\pythonw.exe'
    if (-not (Test-Path -LiteralPath $python)) {
        throw "처음 설치가 필요합니다. 1_FIRST_SETUP.cmd를 먼저 실행하세요."
    }
    # Internal representative test launcher only. Public/default server process keeps this flag off.
    $env:PRONOTE_EXPERIMENTAL_CLI = "true"
    Start-Process -FilePath $python -ArgumentList '"main.py"' -WorkingDirectory $ProjectDir -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Milliseconds 350
        [System.Windows.Forms.Application]::DoEvents()
        $health = Get-Health
        if ($health) { break }
    } while ((Get-Date) -lt $deadline)

    if (-not $health) { throw "서버가 45초 안에 준비되지 않았습니다." }
    if ($health.version -ne $ExpectedVersion) {
        Show-VersionConflict ([string]$health.version)
        exit 2
    }
    $splash.Close()
    $splash = $null
    Show-AppWindow
} catch {
    if ($splash) { $splash.Close() }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "AI PRONOTE 시작 실패") | Out-Null
    exit 1
} finally {
    if ($splash) { $splash.Close() }
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
