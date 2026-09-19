param(
    [switch]$SkipShortcut,
    [string]$ShortcutDirectory = [Environment]::GetFolderPath('Desktop'),
    [string]$Version = 'v1.5.0-beta13.20260920',
    [string]$InstallRoot = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Version -notmatch '^v?[0-9A-Za-z][0-9A-Za-z.-]{0,79}$') {
    throw '설치 버전 이름이 올바르지 않습니다.'
}
Write-Host 'AI PRONOTE v1.5 비공개 베타 설치 점검' -ForegroundColor Cyan
try { $python = Get-Command python.exe -ErrorAction Stop } catch {
    Write-Host 'Python이 없습니다. Python 3.12 64비트를 먼저 설치해 주세요.' -ForegroundColor Red
    Start-Process 'https://www.python.org/downloads/windows/'
    exit 2
}
$versionText = & $python.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')"
if ($LASTEXITCODE -ne 0) { throw 'Python 실행에 실패했습니다.' }
$parts = $versionText.Split('.')
if ([int]$parts[0] -ne 3 -or [int]$parts[1] -ne 12) {
    throw "Python 3.12 64비트가 필요합니다. 현재: $versionText"
}
$is64Bit = & $python.Source -c "import sys; print('true' if sys.maxsize > 2**32 else 'false')"
if ($is64Bit -ne 'true') { throw '64비트 Python이 필요합니다.' }
Write-Host "Python $versionText 확인"
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Windows 사용자 데이터 폴더를 찾을 수 없습니다.' }
    $InstallRoot = Join-Path $localData 'AI_PRONOTE\v1.5\install'
}
$installRoot = [IO.Path]::GetFullPath($InstallRoot)
$versionsRoot = Join-Path $installRoot 'versions'
$versionRoot = Join-Path $versionsRoot $Version
if (-not (Test-Path -LiteralPath $versionRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $versionsRoot -Force | Out-Null
    $temporaryVersion = Join-Path $versionsRoot ('.' + $Version + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryVersion | Out-Null
    try {
        Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -ne '.venv' } |
            Copy-Item -Destination $temporaryVersion -Recurse -Force
        if (-not (Test-Path -LiteralPath (Join-Path $temporaryVersion 'main.py') -PathType Leaf)) {
            throw '설치할 프로그램 파일을 복사하지 못했습니다.'
        }
        Move-Item -LiteralPath $temporaryVersion -Destination $versionRoot
    } finally {
        if (Test-Path -LiteralPath $temporaryVersion) {
            Remove-Item -LiteralPath $temporaryVersion -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
foreach ($requiredFile in @('main.py', 'start_v15.ps1', 'requirements-lock-windows.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $versionRoot $requiredFile) -PathType Leaf)) {
        throw "설치 버전 폴더가 완전하지 않습니다: $requiredFile"
    }
}
$runtimeRoot = Join-Path $installRoot "runtime\versions\$Version"
$venvPython = Join-Path $runtimeRoot 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot '.runtime-complete.json') -PathType Leaf)) {
    Write-Host 'AI PRONOTE 전용 실행환경을 만듭니다.'
    $oldPythonPath = $env:PYTHONPATH
    try {
        $env:PYTHONPATH = $Root
        & $python.Source -c "import sys; from pathlib import Path; from updater import prepare_version_runtime; prepare_version_runtime(Path(sys.argv[1]), sys.argv[2])" $installRoot $Version
        if ($LASTEXITCODE -ne 0) { throw '전용 실행환경 생성에 실패했습니다.' }
    } finally {
        $env:PYTHONPATH = $oldPythonPath
    }
}
$venvVersion = & $venvPython -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ($LASTEXITCODE -ne 0 -or $venvVersion -ne '3.12') {
    throw "설치된 실행환경이 지원 Python 환경이 아닙니다. 기존 파일은 보존되므로 고객지원에 문의하세요. 현재: $venvVersion"
}
$venvArchitecture = & $venvPython -c "import platform,sys; print(f'{platform.machine().lower()}|{64 if sys.maxsize > 2**32 else 32}')"
if ($LASTEXITCODE -ne 0 -or $venvArchitecture -notmatch '^(amd64|x86_64)\|64$') {
    throw "설치된 실행환경이 지원 Windows 64비트 환경이 아닙니다. 기존 파일은 보존되므로 고객지원에 문의하세요. 현재: $venvArchitecture"
}
& $venvPython -c "import fastapi, uvicorn, multipart, faster_whisper, requests; print('핵심 구성요소 확인 완료')"
if ($LASTEXITCODE -ne 0) { throw '설치 후 구성요소 확인에 실패했습니다.' }
Copy-Item -LiteralPath (Join-Path $Root 'stable_launcher.py') -Destination (Join-Path $installRoot 'stable_launcher.py') -Force
Copy-Item -LiteralPath (Join-Path $Root 'updater.py') -Destination (Join-Path $installRoot 'updater.py') -Force
Copy-Item -LiteralPath (Join-Path $Root 'launch_managed_windows.ps1') -Destination (Join-Path $installRoot 'launch_managed_windows.ps1') -Force
$statePath = Join-Path $installRoot 'active-version.json'
$previous = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try { $previous = (Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).active_version } catch {}
}
$state = [ordered]@{ schema_version = 1; active_version = $Version }
if ($previous -and $previous -ne $Version) { $state.rollback_version = [string]$previous }
$stateTemporary = $statePath + '.tmp'
$stateJson = $state | ConvertTo-Json
[IO.File]::WriteAllText($stateTemporary, $stateJson, (New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath $stateTemporary -Destination $statePath -Force
if (-not $SkipShortcut) {
    if (-not (Test-Path -LiteralPath $ShortcutDirectory -PathType Container)) {
        throw "단축아이콘 폴더를 찾을 수 없습니다: $ShortcutDirectory"
    }
    $shortcutPath = Join-Path $ShortcutDirectory 'AI PRONOTE.lnk'
    $shortcutShell = New-Object -ComObject WScript.Shell
    $shortcut = $shortcutShell.CreateShortcut($shortcutPath)
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) {
        throw "Windows PowerShell 실행 파일을 찾을 수 없습니다: $powershell"
    }
    $launcher = Join-Path $installRoot 'launch_managed_windows.ps1'
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '"'
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.IconLocation = (Join-Path $versionRoot 'icon_v15_pro_note.ico') + ',0'
    $shortcut.Description = 'AI PRONOTE — 노트와 녹음을 함께'
    $shortcut.Save()
    Write-Host ''
    Write-Host '설치가 완료되었습니다. 바탕화면 AI PRONOTE 아이콘으로 시작하세요. 로그인 없이 노트·녹음·기본 받아쓰기를 사용할 수 있습니다.' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host '격리 설치 점검 완료. 단축아이콘은 만들지 않았습니다.' -ForegroundColor Green
}
