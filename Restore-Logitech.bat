@echo off
chcp 65001 >nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atmos-fix.ps1" -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atmos-fix.ps1" -Restore
echo.
echo Restored. Reboot now.
pause
