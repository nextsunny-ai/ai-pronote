@echo off
chcp 65001 >nul
title AI PRONOTE v1.5 - 처음 설치
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_external_beta.ps1"
echo.
pause
