@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title DeskHider Plus Builder

set "SRC=%~dp0DeskHiderPlus.ahk"
set "OUT=%~dp0DeskHiderPlus.exe"
set "LOG=%~dp0build_log.txt"
set "AHK_VERSION=1.1.37.02"
set "AHK_ZIP=AutoHotkey_1.1.37.02.zip"
set "AHK_URL1=https://www.autohotkey.com/download/1.1/AutoHotkey_1.1.37.02.zip"
set "AHK_URL2=https://github.com/AutoHotkey/AutoHotkey/releases/download/v1.1.37.02/AutoHotkey_1.1.37.02.zip"
set "AHK_SHA256=6F3663F7CDD25063C8C8728F5D9B07813CED8780522FD1F124BA539E2854215F"
set "WORK=%TEMP%\DeskHiderPlus_Build"
set "ZIP=%WORK%\%AHK_ZIP%"
set "AHKDIR=%WORK%\AutoHotkey"

if exist "%LOG%" del /q "%LOG%" >nul 2>&1
call :BUILD > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"

echo.
echo ============================================================
type "%LOG%"
echo ============================================================
echo.
if "%RC%"=="0" (
    echo SUCCESS: DeskHiderPlus.exe was created in this folder.
    echo.
    echo File: %OUT%
    echo Starting DeskHiderPlus.exe...
    start "" "%OUT%"
) else (
    echo BUILD FAILED. Error code: %RC%
    echo A diagnostic file was saved as: build_log.txt
    echo Please send build_log.txt or a screenshot of this window.
)
echo.
pause
exit /b %RC%

:BUILD
echo [1/5] Checking source file...
if not exist "%SRC%" (
    echo ERROR: DeskHiderPlus.ahk is missing.
    exit /b 10
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    exit /b 11
)

echo [INFO] Closing any running DeskHiderPlus.exe before updating...
taskkill /F /IM DeskHiderPlus.exe >nul 2>&1

if not exist "%WORK%" mkdir "%WORK%"
if errorlevel 1 (
    echo ERROR: Cannot create temporary build folder: %WORK%
    exit /b 12
)

if not exist "%AHKDIR%\Compiler\Ahk2Exe.exe" (
    echo [2/5] Downloading official AutoHotkey v1.1.37.02...
    if exist "%ZIP%" del /q "%ZIP%" >nul 2>&1

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('%AHK_URL1%','%ZIP%')"
    if errorlevel 1 (
        echo Primary download failed. Trying GitHub mirror...
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('%AHK_URL2%','%ZIP%')"
        if errorlevel 1 (
            echo ERROR: Both AutoHotkey download locations failed.
            exit /b 20
        )
    )

    echo [3/5] Verifying SHA256 and extracting...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $h=(Get-FileHash -LiteralPath '%ZIP%' -Algorithm SHA256).Hash; if($h -ne '%AHK_SHA256%'){ Write-Host ('Actual SHA256: '+$h); throw 'SHA256 mismatch' }"
    if errorlevel 1 (
        echo ERROR: AutoHotkey ZIP SHA256 verification failed.
        exit /b 21
    )

    if exist "%AHKDIR%" rmdir /s /q "%AHKDIR%"
    mkdir "%AHKDIR%"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%AHKDIR%' -Force"
    if errorlevel 1 (
        echo ERROR: Failed to extract AutoHotkey ZIP.
        exit /b 22
    )
)

if not exist "%AHKDIR%\Compiler\Ahk2Exe.exe" (
    echo ERROR: Ahk2Exe.exe was not found after extraction.
    exit /b 23
)

set "BASE=%AHKDIR%\Compiler\Unicode 64-bit.bin"
if /I "%PROCESSOR_ARCHITECTURE%"=="x86" if "%PROCESSOR_ARCHITEW6432%"=="" set "BASE=%AHKDIR%\Compiler\Unicode 32-bit.bin"
if not exist "%BASE%" (
    echo ERROR: Compiler base file was not found: %BASE%
    exit /b 24
)

if exist "%OUT%" del /q "%OUT%" >nul 2>&1

echo [4/5] Compiling DeskHiderPlus.exe...
"%AHKDIR%\Compiler\Ahk2Exe.exe" /in "%SRC%" /out "%OUT%" /base "%BASE%"
set "COMPILE_RC=%ERRORLEVEL%"
if not "%COMPILE_RC%"=="0" (
    echo ERROR: Ahk2Exe returned error code %COMPILE_RC%.
    exit /b 30
)
if not exist "%OUT%" (
    echo ERROR: Compiler returned success but DeskHiderPlus.exe does not exist.
    exit /b 31
)

for %%F in ("%OUT%") do set "OUTSIZE=%%~zF"
if "%OUTSIZE%"=="0" (
    echo ERROR: Output EXE is empty.
    exit /b 32
)

echo [5/5] Build complete.
powershell.exe -NoProfile -Command "$h=(Get-FileHash -LiteralPath '%OUT%' -Algorithm SHA256).Hash; Write-Host ('DeskHiderPlus.exe SHA256: '+$h)"
echo Output size: %OUTSIZE% bytes
exit /b 0
