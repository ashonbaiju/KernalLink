@echo off
title KernalLink - Clean Intermediate Build Files
color 0B
cd /d "%~dp0"

echo ======================================================================
echo           KERNALLINK - CLEAN BUILD CACHES FOR SHARING
echo ======================================================================
echo.
echo This script removes bulky compiler build caches and temporary files:
echo   - server\build\       (PyInstaller object cache: ~266 MB)
echo   - server\dist\        (Duplicate executable staging: ~490 MB)
echo   - server\__pycache__\ (Python bytecode caches)
echo   - mobile_client\build (Gradle/Flutter compile artifacts)
echo.
echo Essential files KEPT intact:
echo   [OK] KernalLink.exe   (Ready-to-run PC server in root)
echo   [OK] KernalLink.apk   (Ready-to-install Android app in root)
echo   [OK] ViGEmClient.dll  (Controller support DLL)
echo   [OK] All source code in server\ and mobile_client\
echo.
echo Reducing project size from ~1.1 GB to ~145 MB for easy sharing!
echo.
pause

echo.
echo [*] Cleaning server intermediate build folders...
if exist "server\build" (
    rmdir /s /q "server\build"
    echo    -> Removed server\build\
)
if exist "server\dist" (
    rmdir /s /q "server\dist"
    echo    -> Removed server\dist\
)
if exist "server\dist_new" (
    rmdir /s /q "server\dist_new"
    echo    -> Removed server\dist_new\
)
for /d /r "server" %%d in (__pycache__) do (
    if exist "%%d" (
        rmdir /s /q "%%d" >nul 2>&1
        echo    -> Removed %%d
    )
)

echo.
echo [*] Cleaning Flutter mobile client intermediate build folders...
if exist "mobile_client\build" (
    rmdir /s /q "mobile_client\build"
    echo    -> Removed mobile_client\build\
)
if exist "mobile_client\.dart_tool" (
    rmdir /s /q "mobile_client\.dart_tool"
    echo    -> Removed mobile_client\.dart_tool\
)

echo.
echo ======================================================================
echo [SUCCESS] Clean complete!
echo Ready to zip and share the full project folder.
echo ======================================================================
pause
