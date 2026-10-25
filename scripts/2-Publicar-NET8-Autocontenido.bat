@echo off
chcp 65001 >nul
echo ============================================================================
echo   PUBLICANDO PROYECTO .NET 8 AUTOCONTENIDO (WIN-X64)
echo ============================================================================
where dotnet >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [AVISO] No tienes instalado el SDK de .NET 8 en este ordenador.
    echo No es necesario para usar la aplicacion: puedes usar directamente
    echo ABRIR_GAMELAUNCHER.bat o 1-Compilar-Release.bat que usan el motor integrado de Windows.
    pause
    exit /b 1
)

cd /d "%~dp0..\src\Proyecto_NET8_WPF"
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -o "%~dp0..\dist\NET8_Portable_x64"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Fallo la publicacion con dotnet publish.
    pause
    exit /b %ERRORLEVEL%
)
echo [OK] Publicacion .NET 8 completada en dist\NET8_Portable_x64\GameLauncher.exe
pause
