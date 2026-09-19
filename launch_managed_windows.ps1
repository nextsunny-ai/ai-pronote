$ErrorActionPreference = 'Stop'
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StatePath = Join-Path $InstallRoot 'active-version.json'

try {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        throw '설치 정보가 없습니다. 1_FIRST_SETUP.cmd를 다시 실행하세요.'
    }
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $version = [string]$state.active_version
    if ([string]::IsNullOrWhiteSpace($version) -or $version -notmatch '^v?[0-9A-Za-z][0-9A-Za-z.-]{0,79}$') {
        throw '설치 버전 정보가 올바르지 않습니다.'
    }
    $runtime = Join-Path $InstallRoot "runtime\versions\$version"
    $python = Join-Path $runtime 'Scripts\pythonw.exe'
    $marker = Join-Path $runtime '.runtime-complete.json'
    $launcher = Join-Path $InstallRoot 'stable_launcher.py'
    if (-not (Test-Path -LiteralPath $python -PathType Leaf) -or
        -not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        -not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw 'AI PRONOTE 실행환경이 완전하지 않습니다. 1_FIRST_SETUP.cmd를 다시 실행하세요.'
    }
    $env:PRONOTE_INSTALL_ROOT = $InstallRoot
    Start-Process -FilePath $python -ArgumentList ('"' + $launcher + '"') -WorkingDirectory $InstallRoot -WindowStyle Hidden
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'AI PRONOTE 시작 실패') | Out-Null
    exit 1
}
