@echo off
start "" powershell.exe -Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0GameLauncherApp.ps1"
exit /b 0