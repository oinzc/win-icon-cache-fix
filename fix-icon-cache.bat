@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-icon-cache.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %EXIT_CODE%
