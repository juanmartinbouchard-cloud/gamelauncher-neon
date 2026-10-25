@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Subiendo cambios de GameLauncher Neon a GitHub (y desplegando en Cloudflare)...
git add -A
git commit -m "Actualizacion de GameLauncher Neon (%DATE% %TIME%)"
git push origin main
echo.
echo [OK] Cambios subidos a GitHub. Cloudflare Pages actualizara tu version en unos segundos.
pause
