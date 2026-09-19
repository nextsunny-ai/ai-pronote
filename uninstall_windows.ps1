[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$InstallRoot = '',
    [string]$ShortcutDirectory = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw 'Windows 사용자 데이터 폴더를 찾을 수 없습니다.'
    }
    $InstallRoot = Join-Path $localData 'AI_PRONOTE\v1.5\install'
}

$resolvedInstall = [IO.Path]::GetFullPath($InstallRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
if ((Split-Path -Leaf $resolvedInstall) -ne 'install') {
    throw '안전을 위해 install 폴더만 제거할 수 있습니다.'
}
if (-not (Test-Path -LiteralPath $resolvedInstall -PathType Container)) {
    throw '설치 폴더가 없습니다.'
}
foreach ($required in @('active-version.json', 'stable_launcher.py', 'versions')) {
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedInstall $required))) {
        throw "AI PRONOTE 설치 폴더가 아니거나 불완전합니다: $required"
    }
}

$productRoot = Split-Path -Parent $resolvedInstall
$dataRoot = Join-Path $productRoot 'data'
$quarantineRoot = Join-Path $productRoot 'uninstalled'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = Join-Path $quarantineRoot $stamp
if (Test-Path -LiteralPath $runRoot) {
    $runRoot = Join-Path $quarantineRoot ($stamp + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}

if (-not $PSCmdlet.ShouldProcess($resolvedInstall, '프로그램 파일을 복구 가능한 보관 폴더로 이동')) {
    return
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$shortcutBackup = Join-Path $runRoot 'shortcuts'
New-Item -ItemType Directory -Path $shortcutBackup -Force | Out-Null

function Move-OwnedShortcut([string]$ShortcutPath) {
    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) { return }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $owned = ($shortcut.Arguments -like ('*' + $resolvedInstall + '*')) -or
                 ($shortcut.TargetPath -like ($resolvedInstall + '*'))
        if ($owned) {
            Move-Item -LiteralPath $ShortcutPath -Destination (Join-Path $shortcutBackup (Split-Path -Leaf $ShortcutPath))
        }
    } catch {
        throw '바로가기 소유 확인에 실패해 제거를 중단했습니다.'
    }
}

Move-OwnedShortcut (Join-Path $ShortcutDirectory 'AI PRONOTE.lnk')
Move-OwnedShortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'AI PRONOTE.lnk')

$installNeedle = $resolvedInstall.ToLowerInvariant()
$ownedProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessId -ne $PID -and
    $_.CommandLine -and
    $_.CommandLine.ToLowerInvariant().Contains($installNeedle)
}
foreach ($process in $ownedProcesses) {
    Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
}

$archivedInstall = Join-Path $runRoot 'install'
Move-Item -LiteralPath $resolvedInstall -Destination $archivedInstall

$record = [ordered]@{
    schema_version = 1
    removed_at = (Get-Date).ToString('o')
    original_install_root = $resolvedInstall
    archived_install_root = $archivedInstall
    data_root = $dataRoot
    data_preserved = (Test-Path -LiteralPath $dataRoot -PathType Container)
    credentials_preserved = $true
    restore = '보관된 install 폴더를 original_install_root로 되돌린 뒤 바로가기를 복원하세요.'
}
$recordPath = Join-Path $runRoot 'restoration-record.json'
[IO.File]::WriteAllText(
    $recordPath,
    ($record | ConvertTo-Json),
    (New-Object Text.UTF8Encoding($false))
)

Write-Host ''
Write-Host 'AI PRONOTE 프로그램 파일을 복구 가능하게 보관했습니다.' -ForegroundColor Green
Write-Host "보관 위치: $runRoot"
Write-Host "회의·녹음·노트 데이터는 그대로 보존됩니다: $dataRoot"
Write-Host '공식 AI API 키도 Windows 자격 증명 관리자에 보존됩니다.'
