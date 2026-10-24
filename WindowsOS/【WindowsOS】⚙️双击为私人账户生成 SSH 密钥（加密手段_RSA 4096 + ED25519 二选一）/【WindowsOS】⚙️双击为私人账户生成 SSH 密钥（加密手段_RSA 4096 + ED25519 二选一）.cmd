@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
set "JOBS_EXIT_CODE=%ERRORLEVEL%"
if not defined JOBS_NO_PAUSE pause
exit /b %JOBS_EXIT_CODE%
