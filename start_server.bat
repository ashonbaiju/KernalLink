@echo off
title KernalLink Server
color 0B
cd /d "%~dp0"

echo ======================================================================
echo                     KERNALLINK MASTER SERVER (Windows)
echo ======================================================================
echo.

:: 1. Self-Elevate to Administrator (Required for Virtual Display Driver management)
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [*] Requesting Administrator Privileges for driver control...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }" >nul 2>&1
    if %ERRORLEVEL% equ 0 exit /b
    echo [*] Running with standard permissions (prompts will appear when toggling display)...
) else (
    echo [*] Administrator Privileges confirmed.
)

:: Configure KernalLink Virtual Speaker Name in Windows Audio
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{453af68f-cac6-475f-b868-c4a3e025511f}\Properties" /v "{a45c254e-df1c-4efd-8020-67d146a850e0},2" /t REG_SZ /d "KernalLink Virtual Speaker" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{453af68f-cac6-475f-b868-c4a3e025511f}\Properties" /v "{b3f8fa53-0004-438e-9003-51a46e139bfc},6" /t REG_SZ /d "Phone Audio" /f >nul 2>&1

:: 1.5 Configure Windows Firewall for KernalLink (Ports 8889, 8890, 8891 on all network profiles)
netsh advfirewall firewall show rule name="KernalLink Ports TCP" >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [*] Adding Windows Firewall exceptions for ports 8889, 8890, 8891...
    netsh advfirewall firewall add rule name="KernalLink Ports TCP" dir=in action=allow protocol=TCP localport=8889,8891 profile=any >nul 2>&1
    netsh advfirewall firewall add rule name="KernalLink Ports UDP" dir=in action=allow protocol=UDP localport=8890 profile=any >nul 2>&1
)
netsh advfirewall firewall add rule name="KernalLink App Allow" dir=in action=allow program="%~dp0KernalLink.exe" profile=any enable=yes >nul 2>&1

:: 2. Setup Android Platform-Tools for USB Zero-Latency
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools" (
    set "PATH=%LOCALAPPDATA%\Android\Sdk\platform-tools;%PATH%"
)
if exist "C:\platform-tools" (
    set "PATH=C:\platform-tools;%PATH%"
)

:: 3. Terminate Stale Server Instances & Free Ports 8889 / 8890
echo [*] Checking and freeing ports 8889 and 8890...
taskkill /f /im KernalLink.exe >nul 2>&1
taskkill /f /im TouchPCServer.exe >nul 2>&1
taskkill /f /im TouchPCServer_Console.exe >nul 2>&1
taskkill /f /im TouchPC_Console.exe >nul 2>&1

for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr :8889') do (
    taskkill /f /pid %%p >nul 2>&1
)
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr :8890') do (
    taskkill /f /pid %%p >nul 2>&1
)
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr :8891') do (
    taskkill /f /pid %%p >nul 2>&1
)
ping 127.0.0.1 -n 2 >nul 2>&1

:: Sync newly built executable if present
if exist "%~dp0server\dist\KernalLink.exe" (
    copy /y "%~dp0server\dist\KernalLink.exe" "%~dp0KernalLink.exe" >nul 2>&1
)

:: 4. Locate Python Executable or Prebuilt Binary
set "PY_EXE="
if exist "%LOCALAPPDATA%\Programs\Python\Python314\python.exe" (
    set "PY_EXE=%LOCALAPPDATA%\Programs\Python\Python314\python.exe"
)
if "%PY_EXE%"=="" (
    where python >nul 2>&1
    if %ERRORLEVEL% equ 0 set "PY_EXE=python"
)

:: 5. Launch KernalLink Server
echo [*] Starting KernalLink Master Server...
echo.

if not "%PY_EXE%"=="" (
    cd server
    "%PY_EXE%" server.py
) else if exist "%~dp0KernalLink.exe" (
    "%~dp0KernalLink.exe"
) else (
    color 0C
    echo [ERROR] Neither Python nor KernalLink.exe was found.
    echo Please install Python 3.14 or run KernalLink.exe.
    pause
    exit /b 1
)

echo.
echo ======================================================================
echo [!] KernalLink Server has stopped.
echo ======================================================================
echo.
pause
