$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host 'AI PRONOTE v1.5 비공개 베타 설치 점검' -ForegroundColor Cyan
try { $python = Get-Command python.exe -ErrorAction Stop } catch {
    Write-Host 'Python이 없습니다. Python 3.12 64비트를 먼저 설치해 주세요.' -ForegroundColor Red
    Start-Process 'https://www.python.org/downloads/windows/'
    exit 2
}
$versionText = & $python.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')"
if ($LASTEXITCODE -ne 0) { throw 'Python 실행에 실패했습니다.' }
$parts = $versionText.Split('.')
if ([int]$parts[0] -ne 3 -or [int]$parts[1] -lt 10) {
    throw "Python 3.10 이상이 필요합니다. 현재: $versionText"
}
Write-Host "Python $versionText 확인"
$venvPython = Join-Path $Root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host 'AI PRONOTE 전용 Python 환경을 만듭니다.'
    & $python.Source -m venv (Join-Path $Root '.venv')
    if ($LASTEXITCODE -ne 0) { throw '전용 Python 환경 생성에 실패했습니다.' }
}
& $venvPython -m pip install --disable-pip-version-check --upgrade pip
if ($LASTEXITCODE -ne 0) { throw 'pip 준비에 실패했습니다.' }
& $venvPython -m pip install --disable-pip-version-check --requirement (Join-Path $Root 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw '필수 구성요소 설치에 실패했습니다.' }
& $venvPython -c "import fastapi, uvicorn, multipart, faster_whisper, requests; print('핵심 구성요소 확인 완료')"
if ($LASTEXITCODE -ne 0) { throw '설치 후 구성요소 확인에 실패했습니다.' }
Write-Host ''
Write-Host '1단계 완료. 다음으로 2_AI_LOGIN.cmd를 실행하세요.' -ForegroundColor Green
