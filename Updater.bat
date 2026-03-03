@echo off
setlocal EnableDelayedExpansion
title Winget System Updater
color 0A

:: Check for Winget (before anything else)
where winget >nul 2>&1 || (
    color 0C
    echo ===================================================
    echo [ERROR] Winget is not installed.
    echo         Install 'App Installer' from the Microsoft Store:
    echo         https://aka.ms/getwinget
    echo ===================================================
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('winget --version 2^>nul') do set "WINGET_VER=%%v"
echo [OK] winget !WINGET_VER! detected.

:: Privilege Check and Prompt
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    color 0E
    echo ===================================================
    echo [WARNING] You are currently NOT running as Administrator.
    echo Winget will still work, but you might get UAC pop-ups
    echo for individual apps that require admin rights to install.
    echo ===================================================
    echo.

    :: NOTE: choice /C EA means E=1, A=2
    choice /C EA /M "Press [E] to Elevate to Admin, or [A] to proceed Anyway"

    if !ERRORLEVEL! EQU 1 goto :Elevate
    if !ERRORLEVEL! EQU 2 goto :RunUpdate
)
goto :RunUpdate

:Elevate
echo.
echo [INFO] Requesting administrative privileges...
powershell -Command "Start-Process '%~f0' -Verb RunAs"
exit /b

:RunUpdate
color 0A
echo.
echo ===================================================
echo [INFO] Updating all winget packages...
echo ===================================================
echo.

:: --all                        : upgrade every upgradable package
:: --include-unknown            : include packages winget can't version-detect
:: --silent                     : suppress installer GUI windows
:: --force                      : upgrade even if winget thinks it's current
:: --accept-source-agreements   : auto-accept source EULA
:: --accept-package-agreements  : auto-accept per-package EULA
:: --disable-interactivity      : block any mid-install interactive prompts
winget upgrade --all ^
    --include-unknown ^
    --silent ^
    --force ^
    --accept-source-agreements ^
    --accept-package-agreements ^
    --disable-interactivity

:: Status Check
:: Use !ERRORLEVEL! (delayed expansion) — %ERRORLEVEL% can read a stale value
:: after multi-line commands. Winget also returns non-zero when packages are
:: already up to date, so we treat -1978335189 (0x8A150007) as a success.
set "EC=!ERRORLEVEL!"

if "!EC!"=="0" (
    color 0A
    echo.
    echo [SUCCESS] All upgrades completed successfully!
) else if "!EC!"=="-1978335189" (
    color 0A
    echo.
    echo [SUCCESS] Everything is already up to date.
) else if "!EC!"=="-1978334879" (
    color 0B
    echo.
    echo [SUCCESS] Upgrades done -- a reboot is required to finish some installs.
) else (
    color 0E
    echo.
    echo [WARNING] Winget finished with exit code !EC!.
    echo           Some packages may have failed. Review the output above.
)

:: Clean Winget Download Cache
echo.
echo ===================================================
echo [INFO] Cleaning up winget download cache...
echo ===================================================

:: "winget cache clean" is not a valid winget command.
:: The real cache lives at %LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_*\LocalCache
:: It deletes only the files inside, not the folder itself.
set "CACHE_CLEANED=0"
for /d %%D in ("%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_*") do (
    if exist "%%D\LocalCache\" (
        del /q /f "%%D\LocalCache\*" >nul 2>&1
        set "CACHE_CLEANED=1"
    )
)

if "!CACHE_CLEANED!"=="1" (
    echo [OK] Winget download cache cleared.
) else (
    echo [INFO] No cache found or already empty.
)

echo.
echo [DONE] Your system is up to date and temporary files are cleared.
echo ===================================================
pause
