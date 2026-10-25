<#
.SYNOPSIS
    Diagnóstico de Firma Digital Authenticode y Smart App Control en Windows
#>
$ExePath = Join-Path $PSScriptRoot "..\GameLauncher.exe"
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "   DIAGNÓSTICO DE FIRMA Y SMART APP CONTROL - GAMELAUNCHER NEON             " -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

# 1. Comprobar estado de Smart App Control en el registro de Windows
$sacKey = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
if (Test-Path $sacKey) {
    $sacVal = (Get-ItemProperty -Path $sacKey -Name "VerifiedAndReputablePolicyState" -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
    $sacStatus = switch ($sacVal) {
        0 { "Desactivado (0)" }
        1 { "ACTIVO - Modo de cumplimiento estricto (1)" }
        2 { "Modo de evaluación (2)" }
        default { "No definido ($sacVal)" }
    }
    Write-Host "Estado Smart App Control : $sacStatus" -ForegroundColor Yellow
}

# 2. Comprobar ejecutable
if (-not (Test-Path $ExePath)) {
    Write-Host "Estado del Ejecutable    : Aún no generado. Abre 'ABRIR_GAMELAUNCHER.bat' primero." -ForegroundColor Yellow
    exit 0
}

$sig = Get-AuthenticodeSignature -FilePath $ExePath
Write-Host "Archivo analizado        : $($sig.Path)"
Write-Host "Estado de Firma Digital  : $($sig.Status) ($($sig.StatusMessage))"
if ($sig.SignerCertificate) {
    Write-Host "Publicador (Subject)     : $($sig.SignerCertificate.Subject)" -ForegroundColor Green
    Write-Host "Autoridad Emisora (CA)   : $($sig.SignerCertificate.Issuer)"
    Write-Host "Huella Digital (SHA1)    : $($sig.SignerCertificate.Thumbprint)"
} else {
    Write-Host "Publicador               : SIN FIRMAR (Compilado localmente en este PC)" -ForegroundColor Yellow
}

# 3. Comprobar flujo Zone.Identifier (Mark of the Web)
$zone = Get-Item -Path $ExePath -Stream "Zone.Identifier" -ErrorAction SilentlyContinue
if ($zone) {
    Write-Host "Etiqueta Internet (MOTW) : PRESENTE (El archivo proviene de una descarga externa)" -ForegroundColor Red
} else {
    Write-Host "Etiqueta Internet (MOTW) : LIMPIO (Creado localmente en este ordenador)" -ForegroundColor Green
}
