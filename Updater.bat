@echo off
setlocal EnableDelayedExpansion

:: ============================================================
::  Updater.bat — Enhanced Winget Upgrade Script
::  - No junk files / no logs written to disk
::  - Optional end-of-run summary (user is prompted)
::  - Optional skip list via updater_skip.txt (next to .bat)
::  - Per-package upgrade with live status + winget exit codes
:: ============================================================

title Winget Updater

:: Counters
set /a SUCCESS=0
set /a SKIPPED=0
set /a FAILED=0
set /a ALREADY_UP=0

:: Accumulate names for optional summary report
set "FAILED_LIST="
set "SKIPPED_LIST="

:: ============================================================
call :CheckAdmin
call :CheckWinget
call :LoadSkipList
call :RunUpgrades
call :AskSummary
goto :EOF

:: ============================================================
:CheckAdmin
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  [!] Not running as Administrator.
    echo      Some installers may trigger UAC prompts mid-upgrade.
    echo      Recommended: right-click ^> "Run as administrator"
    echo.
    echo      Press Ctrl+C to cancel and relaunch as admin,
    echo      or press any key to continue anyway...
    pause >nul
) else (
    echo  [OK] Running as Administrator.
)
goto :EOF

:: ============================================================
:CheckWinget
echo.
where winget >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo  [ERROR] winget not found.
    echo          Install "App Installer" from the Microsoft Store:
    echo          https://aka.ms/getwinget
    echo.
    pause & exit /b 1
)
for /f "tokens=*" %%v in ('winget --version 2^>nul') do set "WINGET_VER=%%v"
echo  [OK] winget %WINGET_VER% detected.
goto :EOF

:: ============================================================
:LoadSkipList
set "SKIP_LIST_FILE=%~dp0updater_skip.txt"
set /a SKIP_COUNT=0

if not exist "%SKIP_LIST_FILE%" goto :EOF

for /f "usebackq eol=# tokens=*" %%s in ("%SKIP_LIST_FILE%") do (
    if not "%%s"=="" (
        set "SKIP_%%s=1"
        set /a SKIP_COUNT+=1
    )
)
if !SKIP_COUNT! GTR 0 (
    echo  [INFO] Skip list loaded — !SKIP_COUNT! package(s) will be excluded.
)
goto :EOF

:: ============================================================
:RunUpgrades
echo.
echo  [INFO] Checking for available upgrades...
echo.

:: Capture winget upgrade list into a temp file (in-memory processing only;
:: file is deleted immediately after parsing — no permanent junk left behind).
:: --source winget  : query the official winget source only (faster, reliable)
:: --include-unknown: include packages whose current version winget can't read
set "TMPFILE=%TEMP%\_wu_%RANDOM%.txt"
winget upgrade --source winget --include-unknown > "%TMPFILE%" 2>&1

:: Detect "nothing to do" early
findstr /i "No applicable upgrades" "%TMPFILE%" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    echo  [DONE] All packages are already up to date.
    del "%TMPFILE%" >nul 2>&1
    goto :EOF
)

:: Parse each upgradable package.
:: winget columns: Name | Id | Version | Available | Source
:: We start parsing after the "----" separator line.
set "PARSING=0"
for /f "usebackq tokens=1,2,3,4 delims= " %%a in ("%TMPFILE%") do (

    if "%%a"=="----" (
        set "PARSING=1"
        goto :next
    )

    if "!PARSING!"=="1" (
        set "PKG_ID=%%b"
        set "PKG_VER=%%c"
        set "PKG_NEW=%%d"

        :: Ignore empty lines and the "X upgrades available" footer
        if not "!PKG_ID!"=="" if not "!PKG_ID!"=="upgrades" (

            if defined SKIP_!PKG_ID! (
                echo  [-] SKIP      !PKG_ID!
                set /a SKIPPED+=1
                set "SKIPPED_LIST=!SKIPPED_LIST! !PKG_ID!"
            ) else (
                echo  [^>] Upgrading !PKG_ID!  ^(!PKG_VER! -^> !PKG_NEW!^)

                :: Upgrade flags explained:
                ::   --exact                 match the ID precisely (no fuzzy)
                ::   --silent                suppress all installer UI windows
                ::   --force                 upgrade even when same ver detected
                ::   --accept-source-agreements / --accept-package-agreements
                ::                           auto-accept EULA prompts
                ::   --disable-interactivity block any mid-install prompts
                winget upgrade ^
                    --id "!PKG_ID!" ^
                    --exact ^
                    --silent ^
                    --force ^
                    --accept-source-agreements ^
                    --accept-package-agreements ^
                    --disable-interactivity >nul 2>&1

                set "EC=!ERRORLEVEL!"

                :: Winget exit codes:
                ::   0            = success
                ::  -1978335189  (0x8A150007) = no update found / already latest
                ::  -1978335212  (0x8A1500F4) = install in progress elsewhere
                ::  -1978334879  (0x8A150121) = reboot required
                if "!EC!"=="0" (
                    echo  [OK] Done      !PKG_ID!
                    set /a SUCCESS+=1
                ) else if "!EC!"=="-1978335189" (
                    echo  [--] Up-to-date !PKG_ID!
                    set /a ALREADY_UP+=1
                ) else if "!EC!"=="-1978334879" (
                    echo  [OK] Done ^(reboot needed^) !PKG_ID!
                    set /a SUCCESS+=1
                ) else (
                    echo  [!!] FAILED    !PKG_ID!  ^(exit !EC!^)
                    set /a FAILED+=1
                    set "FAILED_LIST=!FAILED_LIST! !PKG_ID!"
                )
            )
        )
    )
    :next
)

:: Clean up the only temp file we ever touched
del "%TMPFILE%" >nul 2>&1
goto :EOF

:: ============================================================
:AskSummary
echo.
echo  ============================================
echo   Upgrades finished.
echo  ============================================
echo.
set /p "SHOW_SUMMARY= Show detailed summary? [Y/N]: "
if /i "!SHOW_SUMMARY!"=="Y" goto :PrintSummary

echo.
echo  Exiting. Have a great day!
echo.
pause
goto :EOF

:PrintSummary
echo.
echo  ============================================
echo   SUMMARY
echo  ============================================
echo   Upgraded successfully  : !SUCCESS!
echo   Already up to date     : !ALREADY_UP!
echo   Skipped (skip list)    : !SKIPPED!
echo   Failed                 : !FAILED!
echo  ============================================

if not "!FAILED_LIST!"=="" (
    echo.
    echo   Failed packages:
    for %%p in (!FAILED_LIST!) do echo     - %%p
    echo.
    echo   Tip: Re-run as Administrator, or manually upgrade via:
    echo        winget upgrade --id ^<PackageID^> --exact --silent
)

if not "!SKIPPED_LIST!"=="" (
    echo.
    echo   Skipped packages:
    for %%p in (!SKIPPED_LIST!) do echo     - %%p
    echo.
    echo   To un-skip, remove the entry from: updater_skip.txt
)

if !FAILED! EQU 0 if !SKIPPED! EQU 0 (
    echo.
    echo   Everything looks great — no issues to report!
)

echo.
echo  ============================================
echo.
pause
goto :EOF
