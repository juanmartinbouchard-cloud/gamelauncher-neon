$ErrorActionPreference = 'Stop'
Write-Host 'Descargando la ultima version de GameLauncher Neon desde Cloudflare/GitHub...' -ForegroundColor Cyan

$searchPaths = @("$env:USERPROFILE\Desktop\GameLauncher_Neon_App", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Documents")
$existing = Get-ChildItem -Path $searchPaths -Filter 'GameLauncherApp.ps1' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($existing) {
    $targetDir = $existing.DirectoryName
} else {
    $targetDir = "$env:USERPROFILE\Desktop\GameLauncher_Neon_App\GameLauncher_Neon"
    New-Item -ItemType Directory -Path "$targetDir\Assets" -Force | Out-Null
}

# Cerrar instancia previa si esta abierta
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessId -ne $PID -and $_.CommandLine -match 'GameLauncherApp\.ps1'
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$cfgPath = Join-Path $targetDir 'cloud_config.json'
$baseUrl = 'https://raw.githubusercontent.com/juanmartinbouchard-cloud/gamelauncher-neon/main'
if (Test-Path $cfgPath) {
    try {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($cfg.CloudflareUrl)) { $baseUrl = $cfg.CloudflareUrl.TrimEnd('/') }
    } catch {}
}

$cacheBuster = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
try {
    Invoke-RestMethod -Uri "$baseUrl/GameLauncherApp.ps1?v=$cacheBuster" -OutFile (Join-Path $targetDir 'GameLauncherApp.ps1')
    Write-Host '¡Codigo actualizado desde Cloudflare!' -ForegroundColor Green
} catch {
    Write-Host 'Usando respaldo directo de GitHub...' -ForegroundColor Yellow
    Invoke-RestMethod -Uri "https://raw.githubusercontent.com/juanmartinbouchard-cloud/gamelauncher-neon/main/GameLauncherApp.ps1?v=$cacheBuster" -OutFile (Join-Path $targetDir 'GameLauncherApp.ps1')
    Write-Host '¡Codigo actualizado desde GitHub!' -ForegroundColor Green
}

Start-Process -FilePath 'powershell.exe' -ArgumentList "-Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$(Join-Path $targetDir 'GameLauncherApp.ps1')"" -WorkingDirectory $targetDir
