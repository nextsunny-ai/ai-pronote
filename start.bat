@echo off
chcp 65001 > nul
title AI PRONOTE
cd /d "%~dp0"

echo.
echo ============================================
echo   AI PRONOTE — 회의·노트·AI 비서
echo ============================================
echo.
echo 서버 시작 중... (port 8765)
echo.

REM 기존 서버 = 종료 후 재시작
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :8765 ^| findstr LISTENING') do (
  taskkill /PID %%a /F > nul 2>&1
)

REM 서버 백그라운드 시작
start "AI PRONOTE Server" /MIN cmd /c python main.py

REM 서버 준비 대기
timeout /t 3 /nobreak > nul

REM 브라우저 자동 열기
start "" "http://localhost:8765"

echo.
echo ============================================
echo   브라우저가 열렸습니다.
echo   끝낼 때 = 이 창을 닫으면 서버도 종료됩니다.
echo ============================================
echo.
pause > nul
