@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
set "JOBS_RELEASE_EXIT=%ERRORLEVEL%"
echo.
echo Exit code: %JOBS_RELEASE_EXIT%
if not defined JOBS_NO_PAUSE pause
exit /b %JOBS_RELEASE_EXIT%
