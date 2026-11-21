@echo off
title KernalLink PC Control Panel
cd /d "%~dp0"

if exist "%~dp0KernalLink.exe" (
    start "" "%~dp0KernalLink.exe" --panel
    exit /b 0
)

if exist "%LOCALAPPDATA%\Programs\Python\Python314\python.exe" (
    cd server
    start "" "%LOCALAPPDATA%\Programs\Python\Python314\pythonw.exe" pc_console.py
    exit /b 0
)

cd server
start "" pythonw pc_console.py

