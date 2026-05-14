@echo off
chcp 65001 > nul
title AI PRONOTE — 설치
color 0F

echo.
echo  ================================================================
echo                  AI PRONOTE 설치 마법사
echo                  회의 · 노트 · AI 비서
echo  ================================================================
echo.
echo   이 프로그램은 다음을 자동 설치합니다:
echo     1. Python 의존성 (FastAPI · faster-whisper)
echo     2. 바탕화면 바로가기
echo.
echo   설치 위치: %~dp0
echo.
pause

REM ─── Python 확인 ───
echo.
echo [1/4] Python 확인 중...
python --version > nul 2>&1
if errorlevel 1 (
  echo.
  echo  [!] Python이 설치되어 있지 않습니다.
  echo      https://www.python.org/downloads/ 에서 Python 3.10+ 설치 후 다시 실행해주세요.
  echo      ★ 설치 시 "Add Python to PATH" 체크 필수.
  echo.
  pause
  exit /b 1
)
python --version
echo  - OK

REM ─── pip 의존성 설치 ───
echo.
echo [2/4] Python 의존성 설치 중... (faster-whisper · FastAPI · uvicorn)
echo  처음 1회 = 약 2~5분 소요 (인터넷 연결 필요)
echo.
python -m pip install --upgrade pip > nul 2>&1
python -m pip install -r "%~dp0requirements.txt"
if errorlevel 1 (
  echo  [!] 의존성 설치 실패. 인터넷 연결 또는 권한 확인.
  pause
  exit /b 1
)
echo  - OK

REM ─── 아이콘 생성 (.ico 없으면 만듦) ───
echo.
echo [3/4] 바탕화면 바로가기 생성 중...
if not exist "%~dp0icon.ico" (
  python "%~dp0make_icon.py" > nul 2>&1
)
powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\AI PRONOTE.lnk'); $sc.TargetPath = 'wscript.exe'; $sc.Arguments = '\"%~dp0start.vbs\"'; $sc.WorkingDirectory = '%~dp0'; $sc.Description = 'AI PRONOTE — 회의·노트·AI 비서'; $sc.IconLocation = '%~dp0icon.ico,0'; $sc.WindowStyle = 7; $sc.Save()"
if errorlevel 1 (
  echo  [!] 바로가기 생성 실패. 수동으로 start.vbs를 바탕화면에 복사하세요.
) else (
  echo  - OK ^(바탕화면에 'AI PRONOTE' 아이콘 silent 실행^)
)

REM ─── 시작 메뉴 등록 ───
echo.
echo [4/4] 시작 메뉴 등록 중...
powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $startMenu = [Environment]::GetFolderPath('Programs'); $sc = $ws.CreateShortcut($startMenu + '\AI PRONOTE.lnk'); $sc.TargetPath = 'wscript.exe'; $sc.Arguments = '\"%~dp0start.vbs\"'; $sc.WorkingDirectory = '%~dp0'; $sc.Description = 'AI PRONOTE — 회의·노트·AI 비서'; $sc.IconLocation = '%~dp0icon.ico,0'; $sc.WindowStyle = 7; $sc.Save()"
echo  - OK

REM ─── 완료 ───
echo.
echo  ================================================================
echo                  설치 완료
echo  ================================================================
echo.
echo   바탕화면의 'AI PRONOTE' 아이콘을 더블클릭하면 시작됩니다.
echo   또는 시작 메뉴에서 'AI PRONOTE' 검색.
echo.
echo   지금 바로 시작할까요? (Y/N)
choice /c YN /n /m "선택: "
if errorlevel 2 goto end
if errorlevel 1 (
  start "" "%~dp0start.bat"
)

:end
echo.
echo  설치 마법사를 종료합니다.
timeout /t 3 /nobreak > nul
exit /b 0
