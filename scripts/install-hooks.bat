@echo off
setlocal

rem ---------------------------------------------------------------------------
rem  Git commit message convention -- Windows installer entry
rem
rem  Double-click, or run from cmd:
rem      scripts\install-hooks.bat            interactive menu
rem      scripts\install-hooks.bat -Project   install for current repo only
rem      scripts\install-hooks.bat -Global    install for all repos of this user
rem      scripts\install-hooks.bat -Status    show current status
rem      scripts\install-hooks.bat -Uninstall uninstall
rem
rem  The real work is done by install-hooks.ps1 in this same directory.
rem  This file only handles two Windows quirks:
rem    1. On double-click the working directory is C:\Windows\System32, not the
rem       repo -- pushd fixes that so the ps1 can detect "current repository".
rem    2. PowerShell blocks unsigned scripts by default -- -ExecutionPolicy
rem       Bypass applies to this process only, it does not change the system.
rem
rem  NOTE: messages below are intentionally ASCII-only. A .bat file is parsed
rem  with the active console codepage (usually 936/GBK on zh-CN Windows), so
rem  UTF-8 Chinese here would show up as mojibake. All Chinese output comes
rem  from the PowerShell script instead, which handles encoding correctly.
rem ---------------------------------------------------------------------------

set "RC=1"
set "PS1=%~dp0install-hooks.ps1"

if not exist "%PS1%" (
    echo [!!]   Not found: %PS1%
    echo        Please keep the whole package directory intact;
    echo        copying this .bat alone will not work.
    goto :fail
)

rem Switch to the repo root so the ps1 can detect the current repository.
pushd "%~dp0.."

rem Prefer PowerShell 7+ (pwsh); fall back to built-in Windows PowerShell 5.1.
set "PSEXE=powershell"
where pwsh >nul 2>&1 && set "PSEXE=pwsh"

%PSEXE% -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

popd

if not "%RC%"=="0" goto :fail

rem On double-click the window closes instantly; pause so the result is
rem readable. When invoked with arguments (scripted use) do not pause.
if "%~1"=="" pause
exit /b 0

:fail
echo.
echo [!!]   Installation did not complete (exit code %RC%)
if "%~1"=="" pause
exit /b 1
