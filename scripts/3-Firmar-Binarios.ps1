<#
.SYNOPSIS
    Firma Digital Authenticode para GameLauncher Neon (SHA-256 + Timestamp RFC 3161)
.DESCRIPTION
    Firma GameLauncher.exe (y el instalador si existe) usando SignTool del Windows SDK.
    Se detiene si ocurre cualquier error. No inventa certificados ni usa autofirmados.
#>
param(
    [string]$CertThumbprint = "",
    [string]$PfxFilePath = "",
    [string]$TimestampServer = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "   FIRMA DIGITAL DE CÓDIGO (SIGNTOOL SHA-256) - GAMELAUNCHER NEON          " -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

$sdkPaths = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
if (-not $sdkPaths) {
    Write-Error "[ERROR] No se encontró 'signtool.exe'. Instala 'Windows SDK Signing Tools for Desktop Apps' desde el instalador oficial de Windows SDK."
    exit 1
}
$SignTool = $sdkPaths[0].FullName
Write-Host "[INFO] Usando SignTool: $SignTool" -ForegroundColor Gray

$ExePath = Join-Path $PSScriptRoot "..\GameLauncher.exe"
if (-not (Test-Path $ExePath)) {
    Write-Error "[ERROR] No existe GameLauncher.exe en la raíz. Ejecuta primero 1-Compilar-Release.bat."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($CertThumbprint) -and [string]::IsNullOrWhiteSpace($PfxFilePath)) {
    Write-Host "[ACCIÓN REQUERIDA] No se ha proporcionado un certificado de firma de código." -ForegroundColor Yellow
    Write-Host "Uso con Token USB / Almacén de Certificados de Windows:"
    Write-Host "   .\3-Firmar-Binarios.ps1 -CertThumbprint 'HUELLA_SHA1_DE_TU_CERTIFICADO'"
    Write-Host "Uso con archivo .PFX:"
    Write-Host "   .\3-Firmar-Binarios.ps1 -PfxFilePath 'C:\Ruta\Certificado.pfx'"
    exit 1
}

Write-Host "[1/2] Firmando digitalmente $ExePath con SHA-256 y sello de tiempo..." -ForegroundColor Yellow
if (-not [string]::IsNullOrWhiteSpace($CertThumbprint)) {
    & $SignTool sign /sha1 $CertThumbprint /fd sha256 /tr $TimestampServer /td sha256 /d "GameLauncher Neon" /v $ExePath
} else {
    & $SignTool sign /f $PfxFilePath /fd sha256 /tr $TimestampServer /td sha256 /d "GameLauncher Neon" /v $ExePath
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERROR] La operación de firma digital falló (Código $LASTEXITCODE)."
    exit $LASTEXITCODE
}

Write-Host "[2/2] Verificando firma contra la directiva de confianza de Windows (/pa)..." -ForegroundColor Cyan
& $SignTool verify /pa /v $ExePath
if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERROR] La verificación /pa falló. El certificado utilizado no emana de una Autoridad de Certificación (CA) pública reconocida por Windows."
    exit $LASTEXITCODE
}

Write-Host "[OK] GameLauncher.exe ha sido firmado y verificado correctamente." -ForegroundColor Green
