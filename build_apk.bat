@echo off
title Build Mobile Client APK
color 0E
cd /d "%~dp0\mobile_client"

echo ======================================================================
echo                     BUILDING FLUTTER ANDROID APK
echo ======================================================================
echo.

if exist "C:\flutter_windows_3.41.8-stable\flutter\bin" (
    set "PATH=C:\flutter_windows_3.41.8-stable\flutter\bin;%PATH%"
)

call flutter build apk --release

if %ERRORLEVEL% equ 0 (
    echo.
    echo ======================================================================
    echo [SUCCESS] Release APK built successfully!
    echo Output: mobile_client\build\app\outputs\flutter-apk\app-release.apk
    echo ======================================================================
    copy /y build\app\outputs\flutter-apk\app-release.apk ..\KernalLink.apk
    echo Copied to root as: KernalLink.apk
) else (
    echo.
    echo [!] Build failed with error code %ERRORLEVEL%
)

pause
