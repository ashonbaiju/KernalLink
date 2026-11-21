@echo off
title Build KernalLink Standalone Executable
color 0A
cd /d "%~dp0"

echo ======================================================================
echo              BUILDING KERNALLINK STANDALONE EXECUTABLE
echo ======================================================================
echo.

pyinstaller --noconfirm KernalLink.spec
copy /y dist\KernalLink.exe ..\KernalLink.exe >nul 2>&1
copy /y ViGEmClient.dll ..\ >nul 2>&1

echo.
echo ======================================================================
echo [SUCCESS] Standalone Executable Built:
echo   • Master Server: KernalLink.exe (in root folder)
echo   • Quick Launcher: start_server.bat
echo ======================================================================
pause
