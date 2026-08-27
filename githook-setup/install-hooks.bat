@echo off
setlocal

rem ---------------------------------------------------------------------------
rem  Git commit message convention -- Windows installer entry
rem
rem  Double-click, or run from cmd:
rem      githook-setup\install-hooks.bat            interactive menu
rem      githook-setup\install-hooks.bat -Project   install for current repo only
rem      githook-setup\install-hooks.bat -Global    install for all repos of this user
rem      githook-setup\install-hooks.bat -Status    show current status
rem      githook-setup\install-hooks.bat -Uninstall uninstall
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

rem Windows PowerShell 5.1 decodes a BOM-less .ps1 using the system ANSI
rem codepage (936/GBK on zh-CN). The ps1 contains UTF-8 Chinese, so without
rem a BOM the bytes get mis-paired, a closing quote is swallowed as a GBK
rem trail byte, and the parse explodes into dozens of confusing errors.
rem Detect the missing BOM up front and say so plainly instead.
rem  ReadAllBytes works on both Windows PowerShell 5.1 and PowerShell 7+.
rem  (Get-Content -Encoding Byte is 5.1-only; -AsByteStream is 7-only.)
set "BOMOK=0"
for /f %%A in ('%PSEXE% -NoProfile -Command "$b=[System.IO.File]::ReadAllBytes('%PS1%'); if ($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) { 1 } else { 0 }" 2^>nul') do set "BOMOK=%%A"

if "%BOMOK%"=="0" (
    echo [!!]   install-hooks.ps1 is missing its UTF-8 BOM.
    echo.
    echo        Windows PowerShell 5.1 would read it as GBK and fail with
    echo        many bogus syntax errors. The BOM was probably stripped by
    echo        an editor, or the file was re-saved as ANSI/UTF-8-no-BOM.
    echo.
    echo        Fix: re-clone the package, or re-save install-hooks.ps1 as
    echo        "UTF-8 with BOM" ^(VS Code: bottom-right encoding selector^).
    goto :fail
)

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
