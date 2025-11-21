@echo off

:: Check for admin privileges
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] You're not running as administrator.
    echo Winget will prompt for each upgrade if not run as admin.
    echo.
    echo Press Ctrl+C to cancel and restart as admin, or
    pause
)

where winget >nul 2>&1 || (
    echo Winget is not installed—install App Installer from Microsoft Store first.
    pause & exit /b 1
)

echo [INFO] Updating all winget packages...
winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
echo [DONE] Upgrades complete.
pause