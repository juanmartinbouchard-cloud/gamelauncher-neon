@echo off
chcp 65001 >nul
cd /d "%~dp0.."

echo ============================================================================
echo   COMPILANDO GAMELAUNCHER.EXE (MODO RELEASE OPTIMIZADO)
echo ============================================================================

set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
set "FWDIR=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319"

if not exist "%CSC%" (
    echo [ERROR] No se encontro el compilador nativo de Windows en %CSC%.
    if "%~1" NEQ "no_pause" pause
    exit /b 1
)

"%CSC%" /nologo /target:winexe /optimize+ ^
    /out:"%~dp0..\GameLauncher.exe" ^
    /win32icon:"%~dp0..\Assets\app.ico" ^
    /win32manifest:"%~dp0..\Assets\app.manifest" ^
    /r:"%FWDIR%\System.dll" ^
    /r:"%FWDIR%\System.Core.dll" ^
    /r:"%FWDIR%\System.Drawing.dll" ^
    /r:"%FWDIR%\System.Xaml.dll" ^
    /r:"%FWDIR%\System.Web.Extensions.dll" ^
    /r:"%FWDIR%\WPF\WindowsBase.dll" ^
    /r:"%FWDIR%\WPF\PresentationCore.dll" ^
    /r:"%FWDIR%\WPF\PresentationFramework.dll" ^
    "%~dp0..\src\GameLauncherStandalone.cs"

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] La compilacion ha fallado.
    if "%~1" NEQ "no_pause" pause
    exit /b %ERRORLEVEL%
)

echo [OK] Binario compilado con exito en: %~dp0..\GameLauncher.exe
if "%~1" NEQ "no_pause" pause
exit /b 0
