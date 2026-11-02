@echo off
rem One-click: keep the PRO X 2 Logitech driver installed/running, but present the headset as stereo so Dolby Atmos works.
rem Self-elevates, applies the fix, and registers a SYSTEM task that re-applies it at every boot/logon
rem (Logitech's driver rewrites the 7.1 / HX2E settings, which is what breaks Atmos again).
chcp 65001 >nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atmos-fix.ps1" -Install
echo.
echo Restarting Windows Audio service...
powershell -NoProfile -Command "Restart-Service audiosrv -Force"
echo.
echo Done. If Atmos is still not offered, reboot once.
echo Settings ^> Sound ^> PRO X 2 ^> Spatial sound ^> Dolby Atmos for Headphones
pause
