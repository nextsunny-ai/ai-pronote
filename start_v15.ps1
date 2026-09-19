$ErrorActionPreference = "Stop"

$ExpectedVersion = "v1.5.0-beta13.20260920"
$HostAddress = "127.0.0.1"
$Port = 8795
$BaseUrl = "http://${HostAddress}:${Port}"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalDataRoot = [Environment]::GetFolderPath('LocalApplicationData')
if ([string]::IsNullOrWhiteSpace($LocalDataRoot)) {
    throw "Windows 사용자 데이터 폴더를 찾을 수 없습니다."
}
# Keep recordings, transcripts, and reports outside the versioned application
# folder so a side-by-side update cannot hide or orphan existing work.
$DataDir = Join-Path $LocalDataRoot "AI_PRONOTE\v1.5\data"
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

function Get-ActiveJobCount {
    try {
        $payload = Invoke-RestMethod -Uri "$BaseUrl/api/jobs" -TimeoutSec 3
        $items = if ($payload -is [array]) { $payload } elseif ($payload.jobs) { $payload.jobs } else { @() }
        return @($items | Where-Object {
            $_.status -in @('queued', 'processing', 'running', 'transcribing', 'summarizing') -or
            $_.summary_status -in @('pending', 'running')
        }).Count
    } catch {
        return -1
    }
}

function Confirm-And-StopPreviousVersion([string]$runningVersion) {
    Add-Type -AssemblyName System.Windows.Forms
    $activeJobs = Get-ActiveJobCount
    if ($activeJobs -ne 0) {
        $detail = if ($activeJobs -gt 0) { "진행 중인 작업 ${activeJobs}건이 있습니다." } else { "이전 버전의 작업 상태를 확인하지 못했습니다." }
        [System.Windows.Forms.MessageBox]::Show(
            "$detail`n이전 AI PRONOTE에서 작업이 끝난 뒤 다시 실행하세요.",
            "AI PRONOTE - 업데이트 대기",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "이전 버전($runningVersion)이 실행 중입니다.`n`n진행 중인 녹음이 없는지 확인했습니다. 이전 서버를 종료하고 새 버전을 시작할까요?`n회의·노트·녹음 원본은 삭제되지 않습니다.",
        "AI PRONOTE 업데이트",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $listener) { return $true }
    $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
    if (-not $processInfo -or $processInfo.Name -notmatch '^pythonw?\.exe$' -or $processInfo.CommandLine -notmatch '(^|[\\/\s])main\.py([\s\"]|$)') {
        [System.Windows.Forms.MessageBox]::Show(
            "포트 $Port 사용 프로그램을 AI PRONOTE로 확인하지 못해 종료하지 않았습니다.",
            "AI PRONOTE - 안전 확인 실패",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }
    Stop-Process -Id $listener.OwningProcess -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        if (-not (Get-Health)) { return $true }
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Release-LauncherMutex {
    if ($script:hasMutex) {
        try { $script:mutex.ReleaseMutex() } catch {}
        $script:hasMutex = $false
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
            if (-not (Confirm-And-StopPreviousVersion ([string]$health.version))) { exit 2 }
            $health = $null
        } else {
            Show-AppWindow
            exit 0
        }
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
    $VenvRoot = if (-not [string]::IsNullOrWhiteSpace($env:PRONOTE_SHARED_VENV)) {
        $env:PRONOTE_SHARED_VENV
    } else {
        Join-Path $ProjectDir '.venv'
    }
    $python = Join-Path $VenvRoot 'Scripts\pythonw.exe'
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
        Release-LauncherMutex
        Show-VersionConflict ([string]$health.version)
        exit 2
    }
    $splash.Close()
    $splash = $null
    Show-AppWindow
} catch {
    if ($splash) { $splash.Close() }
    Release-LauncherMutex
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "AI PRONOTE 시작 실패") | Out-Null
    exit 1
} finally {
    if ($splash) { $splash.Close() }
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
