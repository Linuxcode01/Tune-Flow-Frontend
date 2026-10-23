@echo off
REM ---------------------------------------------------------------------------------------------
REM  TuneFlow Flutter client - run on a physical Android phone over USB.
REM
REM  adb reverse maps the phone's localhost:8080 back to this PC, so the app can talk to a backend
REM  running on this machine without Wi-Fi, without knowing the PC's IP address and without a
REM  Windows Firewall rule. Re-run this after unplugging the cable, as the mapping is per-connection.
REM
REM  Start the backend first:  ..\backend\run-dev.cmd
REM
REM  Usage:  run-android.cmd
REM ---------------------------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

where adb >nul 2>nul
if errorlevel 1 (
    echo [tuneflow] adb was not found on PATH.
    echo [tuneflow] It ships with the Android SDK platform-tools, usually at
    echo [tuneflow]   %LOCALAPPDATA%\Android\Sdk\platform-tools
    echo [tuneflow] Add that folder to PATH, or run this script from a shell where it is available.
    exit /b 1
)

echo [tuneflow] Connected devices:
adb devices
echo.
echo [tuneflow] Forwarding phone port 8080 -^> PC port 8080 ...
adb reverse tcp:8080 tcp:8080
if errorlevel 1 (
    echo [tuneflow] adb reverse failed - is the phone connected, unlocked and USB-debugging authorised?
    exit /b 1
)

echo [tuneflow] Launching the app. First Android build takes several minutes.
echo.
flutter run --dart-define=API_BASE_URL=http://localhost:8080/api/v1 %*

endlocal
