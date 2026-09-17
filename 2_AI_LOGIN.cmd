@echo off
chcp 65001 >nul
title AI PRONOTE v1.5 - AI 로그인
cd /d "%~dp0"

:menu
cls
echo AI PRONOTE에서 사용할 AI를 선택하세요.
echo.
echo   1. Claude
echo   2. Gemini
echo   3. ChatGPT / Codex
echo   4. 세 가지 모두 준비
echo   0. 종료
echo.
set /p choice=번호 입력: 
if "%choice%"=="1" goto claude
if "%choice%"=="2" goto gemini
if "%choice%"=="3" goto codex
if "%choice%"=="4" goto all
if "%choice%"=="0" goto end
goto menu

:claude
where claude >nul 2>nul
if errorlevel 1 (
  echo Claude Code가 없어 Anthropic 공식 설치 스크립트를 실행합니다.
  pause
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
  if errorlevel 1 goto failed
)
echo Claude 로그인 화면을 엽니다. 로그인 뒤 /exit를 입력하세요.
claude
if "%choice%"=="4" goto gemini
goto done

:gemini
where node >nul 2>nul
if errorlevel 1 goto node_missing
where gemini >nul 2>nul
if errorlevel 1 call npm install -g @google/gemini-cli
if errorlevel 1 goto failed
echo Gemini 로그인 화면을 엽니다. 로그인 뒤 /quit를 입력하세요.
call gemini
if "%choice%"=="4" goto codex
goto done

:codex
where node >nul 2>nul
if errorlevel 1 goto node_missing
where codex >nul 2>nul
if errorlevel 1 call npm install -g @openai/codex
if errorlevel 1 goto failed
echo ChatGPT / Codex 로그인 화면을 엽니다. 로그인 뒤 /exit를 입력하세요.
call codex
goto done

:all
set choice=4
goto claude

:node_missing
echo Gemini와 Codex 설치에는 Node.js가 필요합니다.
echo https://nodejs.org/ 에서 LTS 버전을 설치한 뒤 다시 실행하세요.
goto pause_end

:failed
echo 설치 또는 로그인 실행에 실패했습니다. 인터넷 연결을 확인하세요.
goto pause_end

:done
echo.
echo 로그인이 끝났습니다. AI PRONOTE 설정에서 같은 AI를 선택하세요.

:pause_end
echo.
pause
:end
