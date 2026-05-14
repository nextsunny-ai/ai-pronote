@echo off
chcp 65001 > nul
title AI PRONOTE — 제거

echo.
echo  ================================================================
echo                  AI PRONOTE 제거
echo  ================================================================
echo.
echo   다음을 제거합니다:
echo     - 바탕화면 바로가기
echo     - 시작 메뉴 등록
echo     - 실행 중인 서버
echo.
echo   ★ 프로그램 폴더(C:\AI_PRONOTE_proto)는 = 수동 삭제 (라이브러리 데이터 보존용)
echo.
pause

REM ─── 서버 종료 ───
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :8765 ^| findstr LISTENING') do (
  taskkill /PID %%a /F > nul 2>&1
)

REM ─── 바탕화면 바로가기 제거 ───
powershell -NoProfile -Command "$p = [Environment]::GetFolderPath('Desktop') + '\AI PRONOTE.lnk'; if (Test-Path $p) { Remove-Item $p -Force }"
powershell -NoProfile -Command "$p = [Environment]::GetFolderPath('Programs') + '\AI PRONOTE.lnk'; if (Test-Path $p) { Remove-Item $p -Force }"

echo.
echo  제거 완료. 폴더는 수동 삭제하세요.
echo.
pause
