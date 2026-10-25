@echo off
chcp 65001 >nul
cd /d "%~dp0"

:: Asegurar que GameLauncher.exe este compilado antes de crear el acceso directo
if not exist "%~dp0GameLauncher.exe" (
    call "%~dp0scripts\1-Compilar-Release.bat" no_pause
)

echo Creando acceso directo "GameLauncher Neon" en tu Escritorio...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ws = New-Object -ComObject WScript.Shell; " ^
    "$desk = [Environment]::GetFolderPath('Desktop'); " ^
    "$sc = $ws.CreateShortcut((Join-Path $desk 'GameLauncher Neon.lnk')); " ^
    "if (Test-Path '%~dp0GameLauncher.exe') { $sc.TargetPath = '%~dp0GameLauncher.exe' } else { $sc.TargetPath = '%~dp0ABRIR_GAMELAUNCHER.bat' }; " ^
    "$sc.WorkingDirectory = '%~dp0'; " ^
    "$sc.IconLocation = '%~dp0Assets\app.ico'; " ^
    "$sc.Description = 'Biblioteca de Juegos GameLauncher Neon'; " ^
    "$sc.Save();"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [OK] ¡Listo! Ya tienes el icono "GameLauncher Neon" en tu Escritorio.
) else (
    echo [ERROR] No se pudo crear el acceso directo.
)
pause
