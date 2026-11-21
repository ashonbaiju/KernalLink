@echo off
title KernalLink - Stop All
color 0E
cd /d "%~dp0"

:: ======================================================================
:: 1. Self-Elevate to Administrator (Required to terminate elevated processes)
:: ======================================================================
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [*] Requesting Administrator Privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }" >nul 2>&1
    if %ERRORLEVEL% equ 0 exit /b
    echo [*] Running with current user permissions...
)

:: ======================================================================
:: 2. Execute PowerShell Stop Controller Script
:: ======================================================================
if exist "%~dp0stop_server.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop_server.ps1"
) else (
    echo [*] Terminating KernalLink processes and windows...
    taskkill /F /FI "WINDOWTITLE eq KernalLink*" /T >nul 2>&1
    taskkill /F /FI "WINDOWTITLE eq Touch PC Controller*" /T >nul 2>&1
    taskkill /F /IM KernalLink.exe >nul 2>&1
    taskkill /F /IM TouchPCServer.exe >nul 2>&1
    taskkill /F /IM TouchPCServer_Console.exe >nul 2>&1
    taskkill /F /IM TouchPC_Console.exe >nul 2>&1
    
    for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr :8889') do (
        taskkill /F /PID %%p >nul 2>&1
    )
    for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr :8890') do (
        taskkill /F /PID %%p >nul 2>&1
    )
    
    DisplaySwitch.exe /internal >nul 2>&1
    echo [OK] Display reverted to PC screen & all processes stopped.
    echo [OK] Done.
)

echo.
pause
