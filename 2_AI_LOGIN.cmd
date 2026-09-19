@echo off
chcp 65001 >nul
title AI PRONOTE v1.5 - AI 로그인
cd /d "%~dp0"

:menu
cls
echo AI PRONOTE에서 사용할 AI를 선택하세요.
echo.
echo   AI 연결 없이도 녹음, 영상, 기본 받아쓰기와 필기를 사용할 수 있습니다.
echo   AI 회의록과 에이전트 기능이 필요할 때 연결하세요.
echo.
echo   1. Claude
echo   2. ChatGPT / Codex
echo   0. 종료
echo   Gemini 연결은 준비 중입니다.
echo.
set /p choice=번호 입력: 
if "%choice%"=="1" goto claude
if "%choice%"=="2" goto codex
if "%choice%"=="0" goto end
goto menu

:claude
where claude >nul 2>nul
if errorlevel 1 (
  echo Claude Code가 설치되어 있지 않습니다.
  echo Anthropic 공식 안내에서 설치한 뒤 다시 실행하세요.
  start "" "https://docs.anthropic.com/en/docs/claude-code/setup"
  goto pause_end
)
echo Claude 로그인 화면을 엽니다. 완료 후 종료하세요.
claude
goto done

:codex
where codex >nul 2>nul
if errorlevel 1 (
  echo Codex CLI가 설치되어 있지 않습니다.
  echo OpenAI 공식 안내에서 설치한 뒤 다시 실행하세요.
  start "" "https://developers.openai.com/codex/cli"
  goto pause_end
)
echo ChatGPT / Codex 로그인 화면을 엽니다. 완료 후 종료하세요.
call codex
goto done

:done
echo.
echo 로그인이 끝났습니다. AI PRONOTE 설정에서 같은 AI를 선택하세요.

:pause_end
echo.
pause
:end
