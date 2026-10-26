@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Open the adjacent PowerShell script; wildcard lookup preserves Unicode paths.
set "JOBS_RELEASE_SCRIPT="
set "JOBS_RELEASE_COUNT=0"
for %%F in ("%~dp0*.ps1") do (
    set "JOBS_RELEASE_SCRIPT=%%~fF"
    set /a JOBS_RELEASE_COUNT+=1 >nul
)
if not "%JOBS_RELEASE_COUNT%"=="1" (
    echo ERROR: Keep exactly one Release Replace .ps1 beside this launcher.
    pause
    exit /b 1
)
where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell 5.1 is required.
    pause
    exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%JOBS_RELEASE_SCRIPT%" %*
set "JOBS_RELEASE_EXIT=%ERRORLEVEL%"
echo.
echo Exit code: %JOBS_RELEASE_EXIT%
pause
exit /b %JOBS_RELEASE_EXIT%
