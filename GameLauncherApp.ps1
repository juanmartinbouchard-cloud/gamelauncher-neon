Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

try {

$script:AppDataDir = Join-Path $env:LOCALAPPDATA "GameLauncherNeon"
$script:LibraryFile = Join-Path $script:AppDataDir "library.json"
$script:LogDir = Join-Path $script:AppDataDir "logs"
$script:LogFile = Join-Path $script:LogDir "app.log"
$script:FilterFavoritesOnly = $false
$script:EditingGameId = $null
$script:CurrentHoveredCard = $null

# Cache en RAM para iconos, caratulas y rutas de Epic Games
$script:ImageCache = @{}
$script:EpicLaunchMap = @{}

function Write-AppLog([string]$Level, [string]$Message) {
    try {
        if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null }
        $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

$script:EpicDirMap = @{}
$script:SteamLaunchMap = @{}
$script:SteamDirMap = @{}
$script:SteamExePath = ""

$script:EpicDirMap = @{}
$script:SteamLaunchMap = @{}
$script:SteamDirMap = @{}
$script:SteamExePath = ""

function Initialize-EpicLaunchCache {
    $script:EpicLaunchMap.Clear()
    $script:EpicDirMap.Clear()
    $script:SteamLaunchMap.Clear()
    $script:SteamDirMap.Clear()

    # 1. Mapear todos los juegos de Epic Games por Titulo y por Carpeta de instalacion
    $epicDir = Join-Path $env:ProgramData "Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path $epicDir) {
        $items = Get-ChildItem -Path $epicDir -Filter "*.item" -File -ErrorAction SilentlyContinue
        foreach ($it in $items) {
            try {
                $j = Get-Content -Path $it.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $dName = [string]$j.DisplayName
                $aName = [string]$j.AppName
                $iLoc  = [string]$j.InstallLocation
                if (-not [string]::IsNullOrWhiteSpace($aName)) {
                    if (-not [string]::IsNullOrWhiteSpace($dName)) {
                        $script:EpicLaunchMap[$dName.Trim().ToLowerInvariant()] = $aName.Trim()
                    }
                    if (-not [string]::IsNullOrWhiteSpace($iLoc)) {
                        $cleanLoc = ($iLoc -replace "/", "\").TrimEnd('\').ToLowerInvariant()
                        $script:EpicDirMap[$cleanLoc] = $aName.Trim()
                    }
                }
            } catch {}
        }
    }

    # 2. Mapear todos los juegos de Steam por Titulo y por Carpeta de instalacion (AppId)
    try {
        $steamRoot = $null
        if (Test-Path "HKCU:\Software\Valve\Steam") {
            $sp = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
            if ($sp) { $steamRoot = $sp -replace "/", "\" }
        }
        if ([string]::IsNullOrWhiteSpace($steamRoot) -or -not (Test-Path $steamRoot)) {
            $defSteam = Join-Path ${env:ProgramFiles(x86)} "Steam"
            if (Test-Path $defSteam) { $steamRoot = $defSteam }
        }

        $steamLibs = @{}
        if (-not [string]::IsNullOrWhiteSpace($steamRoot) -and (Test-Path $steamRoot)) {
            $script:SteamExePath = Join-Path $steamRoot "steam.exe"
            $steamLibs[$steamRoot] = $true
            $vdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                $vdfText = Get-Content -Path $vdf -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $matches = [regex]::Matches($vdfText, '"path"\s+"([^"]+)"')
                foreach ($m in $matches) {
                    $lp = $m.Groups[1].Value -replace "\\\\", "\"
                    if (Test-Path $lp) { $steamLibs[$lp] = $true }
                }
            }
        }

        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }
        foreach ($d in $drives) {
            $sl1 = Join-Path $d.Root "SteamLibrary"
            if (Test-Path $sl1) { $steamLibs[$sl1] = $true }
            $sl2 = Join-Path $d.Root "Program Files (x86)\Steam"
            if (Test-Path $sl2) { $steamLibs[$sl2] = $true }
        }

        foreach ($lib in $steamLibs.Keys) {
            $appsDir = Join-Path $lib "steamapps"
            if (-not (Test-Path $appsDir)) { continue }
            $acfs = Get-ChildItem -Path $appsDir -Filter "appmanifest_*.acf" -File -ErrorAction SilentlyContinue
            foreach ($acf in $acfs) {
                $txt = Get-Content -Path $acf.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $appId = ""
                if ($txt -match '"appid"\s+"([^"]+)"') { $appId = $Matches[1].Trim() }
                $name = ""
                if ($txt -match '"name"\s+"([^"]+)"') { $name = $Matches[1].Trim() }
                $instDir = ""
                if ($txt -match '"installdir"\s+"([^"]+)"') { $instDir = $Matches[1].Trim() }

                if (-not [string]::IsNullOrWhiteSpace($appId)) {
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        $script:SteamLaunchMap[$name.ToLowerInvariant()] = $appId
                    }
                    if (-not [string]::IsNullOrWhiteSpace($instDir)) {
                        $fullGameDir = (Join-Path $appsDir "common\$instDir").TrimEnd('\').ToLowerInvariant()
                        $script:SteamDirMap[$fullGameDir] = $appId
                    }
                }
            }
        }
    } catch {}
}

function Get-GameIconOrCover([string]$ExePath, [string]$CoverPath) {
    $cleanCover = ""
    if (-not [string]::IsNullOrWhiteSpace($CoverPath)) { $cleanCover = $CoverPath.Trim().Trim('"') }
    $cleanExe = ""
    if (-not [string]::IsNullOrWhiteSpace($ExePath)) { $cleanExe = $ExePath.Trim().Trim('"') }

    $cacheKey = "$cleanExe|$cleanCover"
    if ($script:ImageCache.ContainsKey($cacheKey)) {
        return $script:ImageCache[$cacheKey]
    }

    if (-not [string]::IsNullOrWhiteSpace($cleanCover) -and [System.IO.File]::Exists($cleanCover)) {
        # Metodo 1: Si es .ico, usar exactamente el mismo extractor HIcon que funciona con los juegos
        if ($cleanCover.EndsWith(".ico", [StringComparison]::OrdinalIgnoreCase)) {
            try {
                $icoFile = [System.Drawing.Icon]::ExtractAssociatedIcon($cleanCover)
                if ($null -ne $icoFile) {
                    $srcIco = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                        $icoFile.Handle,
                        [System.Windows.Int32Rect]::Empty,
                        [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                    )
                    $srcIco.Freeze()
                    $icoFile.Dispose()
                    $script:ImageCache[$cacheKey] = $srcIco
                    return $srcIco
                }
            } catch {}
        }

        # Metodo 2: Motor GDI+ HBitmap directo para JPG, JPEG, PNG y BMP (sin MemoryStream)
        try {
            $gdiBmp = New-Object System.Drawing.Bitmap($cleanCover)
            if ($null -ne $gdiBmp) {
                $hBmp = $gdiBmp.GetHbitmap()
                $srcGdi = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap(
                    $hBmp,
                    [IntPtr]::Zero,
                    [System.Windows.Int32Rect]::Empty,
                    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                )
                $srcGdi.Freeze()
                $gdiBmp.Dispose()
                $script:ImageCache[$cacheKey] = $srcGdi
                return $srcGdi
            }
        } catch {}

        # Metodo 3: Decodificador nativo WIC por URI (para WEBP o JFIF descargados de navegadores)
        try {
            $uri = [System.Uri]::new($cleanCover)
            $frame = [System.Windows.Media.Imaging.BitmapFrame]::Create(
                $uri,
                [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            )
            $frame.Freeze()
            $script:ImageCache[$cacheKey] = $frame
            return $frame
        } catch {}

        # Metodo 4: Respaldo ExtractAssociatedIcon para cualquier otro formato
        try {
            $icoAny = [System.Drawing.Icon]::ExtractAssociatedIcon($cleanCover)
            if ($null -ne $icoAny) {
                $srcAny = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                    $icoAny.Handle,
                    [System.Windows.Int32Rect]::Empty,
                    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                )
                $srcAny.Freeze()
                $icoAny.Dispose()
                $script:ImageCache[$cacheKey] = $srcAny
                return $srcAny
            }
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($cleanExe) -and [System.IO.File]::Exists($cleanExe)) {
        try {
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($cleanExe)
            if ($null -ne $ico) {
                $img = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                    $ico.Handle,
                    [System.Windows.Int32Rect]::Empty,
                    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                )
                $img.Freeze()
                $ico.Dispose()
                $script:ImageCache[$cacheKey] = $img
                return $img
            }
        } catch {
            Write-AppLog "ERROR" "No se pudo extraer icono de: $cleanExe"
        }
    }
    return $null
}
function New-GameObject {
    param(
        [string]$Id = ([Guid]::NewGuid().ToString("N")),
        [string]$Title = "",
        [string]$ExecutablePath = "",
        [string]$Arguments = "",
        [string]$CustomCoverPath = "",
        [string]$PlatformSource = "PC",
        [bool]$IsFavorite = $false,
        [string]$LastPlayedIso = "",
        [int]$PlayCount = 0
    )
    $avail = (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) -and (Test-Path $ExecutablePath)
    $plat = "PC"
    if (-not [string]::IsNullOrWhiteSpace($PlatformSource)) { $plat = $PlatformSource }

    $statusTxt = "Ruta no disponible"
    $statusCol = "#EF4444"
    if ($avail) {
        $statusTxt = "Disponible ($plat)"
        $statusCol = "#10B981"
    }

    $favSym = [string][char]0x2606
    if ($IsFavorite) { $favSym = [string][char]0x2605 }

    $lastTxt = "Listo para jugar"
    if (-not [string]::IsNullOrWhiteSpace($LastPlayedIso)) {
        $lastTxt = "Ultima vez: $LastPlayedIso ($($PlayCount)x)"
    }

    $iconImg = Get-GameIconOrCover -ExePath $ExecutablePath -CoverPath $CustomCoverPath

    return [PSCustomObject]@{
        Id              = $Id
        Title           = $Title
        ExecutablePath  = $ExecutablePath
        Arguments       = $Arguments
        CustomCoverPath = $CustomCoverPath
        PlatformSource  = $plat
        IsFavorite      = [bool]$IsFavorite
        LastPlayedIso   = $LastPlayedIso
        PlayCount       = [int]$PlayCount
        IsAvailable     = [bool]$avail
        StatusText      = $statusTxt
        StatusColor     = $statusCol
        FavoriteSymbol  = $favSym
        LastPlayedText  = $lastTxt
        DisplayIcon     = $iconImg
    }
}

function Update-GameComputedProps($Game, [bool]$RefreshImage = $false) {
    $avail = (-not [string]::IsNullOrWhiteSpace($Game.ExecutablePath)) -and (Test-Path $Game.ExecutablePath)
    $plat = "PC"
    if (-not [string]::IsNullOrWhiteSpace($Game.PlatformSource)) { $plat = $Game.PlatformSource }

    $Game.IsAvailable = [bool]$avail
    if ($avail) {
        $Game.StatusText = "Disponible ($plat)"
        $Game.StatusColor = "#10B981"
    } else {
        $Game.StatusText = "Ruta no disponible"
        $Game.StatusColor = "#EF4444"
    }

    if ($Game.IsFavorite) {
        $Game.FavoriteSymbol = [string][char]0x2605
    } else {
        $Game.FavoriteSymbol = [string][char]0x2606
    }

    if ([string]::IsNullOrWhiteSpace($Game.LastPlayedIso)) {
        $Game.LastPlayedText = "Listo para jugar"
    } else {
        $Game.LastPlayedText = "Ultima vez: $($Game.LastPlayedIso) ($($Game.PlayCount)x)"
    }

    if ($RefreshImage -or ($null -eq $Game.DisplayIcon)) {
        $Game.DisplayIcon = Get-GameIconOrCover -ExePath $Game.ExecutablePath -CoverPath $Game.CustomCoverPath
    }
}

function Load-LibraryData {
    $defaultData = [PSCustomObject]@{
        Games               = New-Object System.Collections.ArrayList
        History             = New-Object System.Collections.ArrayList
        MinimizeOnLaunch    = $true
        HighContrastBorders = $false
        AutoScanOnStartup   = $true
    }
    try {
        if (-not (Test-Path $script:AppDataDir)) { New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null }
        if (-not (Test-Path $script:LibraryFile)) { return $defaultData }
        $rawJson = Get-Content -Path $script:LibraryFile -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($rawJson)) { return $defaultData }
        $parsed = ConvertFrom-Json -InputObject $rawJson
        if ($null -eq $parsed) { return $defaultData }

        if ($null -ne $parsed.MinimizeOnLaunch) { $defaultData.MinimizeOnLaunch = [bool]$parsed.MinimizeOnLaunch }
        if ($null -ne $parsed.HighContrastBorders) { $defaultData.HighContrastBorders = [bool]$parsed.HighContrastBorders }
        if ($null -ne $parsed.AutoScanOnStartup) { $defaultData.AutoScanOnStartup = [bool]$parsed.AutoScanOnStartup }

        if ($null -ne $parsed.Games) {
            foreach ($g in $parsed.Games) {
                $obj = New-GameObject `
                    -Id ([string]$g.Id) `
                    -Title ([string]$g.Title) `
                    -ExecutablePath ([string]$g.ExecutablePath) `
                    -Arguments ([string]$g.Arguments) `
                    -CustomCoverPath ([string]$g.CustomCoverPath) `
                    -PlatformSource ([string]$g.PlatformSource) `
                    -IsFavorite ([bool]$g.IsFavorite) `
                    -LastPlayedIso ([string]$g.LastPlayedIso) `
                    -PlayCount ([int]$g.PlayCount)
                [void]$defaultData.Games.Add($obj)
            }
        }
        if ($null -ne $parsed.History) {
            foreach ($h in $parsed.History) {
                [void]$defaultData.History.Add([PSCustomObject]@{
                    GameId         = [string]$h.GameId
                    GameTitle      = [string]$h.GameTitle
                    ExecutablePath = [string]$h.ExecutablePath
                    TimestampIso   = [string]$h.TimestampIso
                })
            }
        }
    } catch {
        Write-AppLog "ERROR" "Error al cargar library.json: $($_.Exception.Message)"
    }
    return $defaultData
}

function Save-LibraryData {
    try {
        if (-not (Test-Path $script:AppDataDir)) { New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null }
        $cleanGames = @()
        foreach ($g in $script:AppData.Games) {
            $cleanGames += [PSCustomObject]@{
                Id              = $g.Id
                Title           = $g.Title
                ExecutablePath  = $g.ExecutablePath
                Arguments       = $g.Arguments
                CustomCoverPath = $g.CustomCoverPath
                PlatformSource  = $g.PlatformSource
                IsFavorite      = [bool]$g.IsFavorite
                LastPlayedIso   = $g.LastPlayedIso
                PlayCount       = [int]$g.PlayCount
            }
        }
        $payload = [PSCustomObject]@{
            Games               = $cleanGames
            History             = @($script:AppData.History)
            MinimizeOnLaunch    = [bool]$script:AppData.MinimizeOnLaunch
            HighContrastBorders = [bool]$script:AppData.HighContrastBorders
            AutoScanOnStartup   = [bool]$script:AppData.AutoScanOnStartup
        }
        $json = ConvertTo-Json -InputObject $payload -Depth 5
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($script:LibraryFile, $json, $utf8NoBom)
    } catch {
        Write-AppLog "ERROR" "Error al guardar library.json: $($_.Exception.Message)"
    }
}

$script:IgnoredExePatterns = @(
    "unins", "crash", "redist", "dxsetup", "vcredist", "dotnet",
    "easyanticheat", "battleye", "beclient", "beservice", "cefprocess",
    "unitycrashhandler", "unrealcefsub", "crs-handler", "helper",
    "updater", "patcher", "benchmark", "cleanup", "touchup", "activation",
    "eac_", "prereq", "installer", "setup", "report", "errorhandler",
    "steamerrorreporter", "epicgameslauncher", "riotclientservices"
)

function Test-IsIgnoredExe([string]$FilePath) {
    $name = [System.IO.Path]::GetFileName($FilePath).ToLowerInvariant()
    foreach ($pat in $script:IgnoredExePatterns) {
        if ($name.Contains($pat)) { return $true }
    }
    return $false
}

function Find-BestGameExe([string]$FolderPath, [string]$PreferredTitle) {
    if ([string]::IsNullOrWhiteSpace($FolderPath) -or -not (Test-Path $FolderPath)) { return "" }
    $exes = @()
    try {
        $exes += Get-ChildItem -Path $FolderPath -Filter "*.exe" -File -ErrorAction SilentlyContinue
        $subDirs = Get-ChildItem -Path $FolderPath -Directory -ErrorAction SilentlyContinue | Where-Object {
            $n = $_.Name.ToLowerInvariant()
            $n -notin @("redist", "_commonredist", "directx", "vcredist", "support", "installer", "easyanticheat", "battleye")
        }
        foreach ($sd in $subDirs) {
            $exes += Get-ChildItem -Path $sd.FullName -Filter "*.exe" -File -ErrorAction SilentlyContinue
            $subDirs2 = Get-ChildItem -Path $sd.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($sd2 in $subDirs2) {
                $exes += Get-ChildItem -Path $sd2.FullName -Filter "*.exe" -File -ErrorAction SilentlyContinue
            }
        }
    } catch {}

    if ($exes.Count -eq 0) { return "" }

    $cleanPref = ($PreferredTitle -replace "[^a-zA-Z0-9]", "").ToLowerInvariant()
    $bestExe = ""
    $bestScore = -999999

    foreach ($f in $exes) {
        if (Test-IsIgnoredExe $f.FullName) { continue }
        $score = 0
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $cleanFile = ($baseName -replace "[^a-zA-Z0-9]", "").ToLowerInvariant()

        if (-not [string]::IsNullOrEmpty($cleanPref)) {
            if ($cleanFile -eq $cleanPref) { $score += 500 }
            elseif ($cleanFile.Contains($cleanPref) -or $cleanPref.Contains($cleanFile)) { $score += 250 }
        }

        $lowerFull = $f.FullName.ToLowerInvariant()
        if ($lowerFull.Contains("win64") -or $lowerFull.Contains("x64")) { $score += 80 }
        if ($lowerFull.Contains("shipping")) { $score += 90 }
        if ($f.DirectoryName -eq $FolderPath) { $score += 60 }

        $mb = [int]($f.Length / 1MB)
        if ($mb -gt 150) { $mb = 150 }
        $score += $mb

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestExe = $f.FullName
        }
    }
    return $bestExe
}

function Find-FolderCoverImage([string]$FolderPath) {
    if ([string]::IsNullOrWhiteSpace($FolderPath) -or -not (Test-Path $FolderPath)) { return "" }
    try {
        $imgs = Get-ChildItem -Path $FolderPath -File -Include "*.jpg","*.png","*.jpeg" -ErrorAction SilentlyContinue
        foreach ($img in $imgs) {
            $n = $img.Name.ToLowerInvariant()
            if ($n.Contains("cover") -or $n.Contains("header") -or $n.Contains("banner") -or $n.Contains("poster") -or $n.Contains("splash") -or $n.Contains("logo")) {
                return $img.FullName
            }
        }
    } catch {}
    return ""
}

function Find-SteamCover([string]$SteamRoot, [string]$AppId, [string]$GameDir) {
    if (-not [string]::IsNullOrWhiteSpace($SteamRoot) -and -not [string]::IsNullOrWhiteSpace($AppId)) {
        $cacheDir = Join-Path $SteamRoot "appcache\librarycache"
        if (Test-Path $cacheDir) {
            $candidates = @(
                (Join-Path $cacheDir "$($AppId)_header.jpg"),
                (Join-Path $cacheDir "$($AppId)_library_600x900.jpg"),
                (Join-Path $cacheDir "$($AppId)_hero.jpg"),
                (Join-Path $cacheDir "$($AppId)_logo.png")
            )
            foreach ($c in $candidates) {
                if (Test-Path $c) { return $c }
            }
            $subCache = Join-Path $cacheDir $AppId
            if (Test-Path $subCache) {
                $foundImgs = Get-ChildItem -Path $subCache -Include "*.jpg","*.png" -Recurse -File -ErrorAction SilentlyContinue
                $header = $foundImgs | Where-Object { $_.Name -match "header|library_600x900" } | Select-Object -First 1
                if ($null -ne $header) { return $header.FullName }
                $anyImg = $foundImgs | Select-Object -First 1
                if ($null -ne $anyImg) { return $anyImg.FullName }
            }
        }
    }
    return (Find-FolderCoverImage $GameDir)
}

function Invoke-ScanAllGames {
    Initialize-EpicLaunchCache
    $discovered = New-Object System.Collections.ArrayList
    $knownPaths = @{}
    $knownTitles = @{}

    foreach ($g in $script:AppData.Games) {
        if (-not [string]::IsNullOrWhiteSpace($g.ExecutablePath)) { $knownPaths[$g.ExecutablePath.ToLowerInvariant()] = $true }
        if (-not [string]::IsNullOrWhiteSpace($g.Title)) { $knownTitles[$g.Title.Trim().ToLowerInvariant()] = $true }
    }

    # 1. STEAM
    try {
        $steamRoot = $null
        if (Test-Path "HKCU:\Software\Valve\Steam") {
            $sp = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
            if ($sp) { $steamRoot = $sp -replace "/", "\" }
        }
        if ([string]::IsNullOrWhiteSpace($steamRoot) -or -not (Test-Path $steamRoot)) {
            $defSteam = Join-Path ${env:ProgramFiles(x86)} "Steam"
            if (Test-Path $defSteam) { $steamRoot = $defSteam }
        }

        $steamLibs = @{}
        if (-not [string]::IsNullOrWhiteSpace($steamRoot) -and (Test-Path $steamRoot)) {
            $steamLibs[$steamRoot] = $true
            $vdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                $vdfText = Get-Content -Path $vdf -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $matches = [regex]::Matches($vdfText, '"path"\s+"([^"]+)"')
                foreach ($m in $matches) {
                    $lp = $m.Groups[1].Value -replace "\\\\", "\"
                    if (Test-Path $lp) { $steamLibs[$lp] = $true }
                }
            }
        }

        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }
        foreach ($d in $drives) {
            $sl1 = Join-Path $d.Root "SteamLibrary"
            if (Test-Path $sl1) { $steamLibs[$sl1] = $true }
            $sl2 = Join-Path $d.Root "Program Files (x86)\Steam"
            if (Test-Path $sl2) { $steamLibs[$sl2] = $true }
        }

        foreach ($lib in $steamLibs.Keys) {
            $appsDir = Join-Path $lib "steamapps"
            if (-not (Test-Path $appsDir)) { continue }
            $acfs = Get-ChildItem -Path $appsDir -Filter "appmanifest_*.acf" -File -ErrorAction SilentlyContinue
            foreach ($acf in $acfs) {
                $txt = Get-Content -Path $acf.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $appId = ""
                if ($txt -match '"appid"\s+"([^"]+)"') { $appId = $Matches[1] }
                $name = ""
                if ($txt -match '"name"\s+"([^"]+)"') { $name = $Matches[1] }
                $instDir = ""
                if ($txt -match '"installdir"\s+"([^"]+)"') { $instDir = $Matches[1] }

                if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($instDir)) { continue }
                if ($appId -eq "228980" -or $name -match "Steamworks Common Redistributables|Steam Linux Runtime|Proton ") { continue }

                $fullDir = Join-Path $appsDir "common\$instDir"
                if (-not (Test-Path $fullDir)) { continue }

                $bestExe = Find-BestGameExe -FolderPath $fullDir -PreferredTitle $name
                if (-not [string]::IsNullOrWhiteSpace($bestExe) -and (Test-Path $bestExe)) {
                    $kPath = $bestExe.ToLowerInvariant()
                    $kTitle = $name.Trim().ToLowerInvariant()
                    if (-not $knownPaths.ContainsKey($kPath) -and -not $knownTitles.ContainsKey($kTitle)) {
                        $cover = Find-SteamCover -SteamRoot $steamRoot -AppId $appId -GameDir $fullDir
                        $newObj = New-GameObject -Title $name.Trim() -ExecutablePath $bestExe -CustomCoverPath $cover -PlatformSource "Steam"
                        [void]$discovered.Add($newObj)
                        $knownPaths[$kPath] = $true
                        $knownTitles[$kTitle] = $true
                    }
                }
            }
        }
    } catch {}

    # 2. EPIC GAMES
    try {
        $epicDir = Join-Path $env:ProgramData "Epic\EpicGamesLauncher\Data\Manifests"
        if (Test-Path $epicDir) {
            $items = Get-ChildItem -Path $epicDir -Filter "*.item" -File -ErrorAction SilentlyContinue
            foreach ($it in $items) {
                try {
                    $j = Get-Content -Path $it.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $dName = [string]$j.DisplayName
                    $iLoc = [string]$j.InstallLocation
                    $lExe = [string]$j.LaunchExecutable
                    if ([string]::IsNullOrWhiteSpace($dName) -or [string]::IsNullOrWhiteSpace($iLoc)) { continue }
                    $fullExe = ""
                    if (-not [string]::IsNullOrWhiteSpace($lExe)) { $fullExe = Join-Path $iLoc ($lExe -replace "/", "\") }
                    if ([string]::IsNullOrWhiteSpace($fullExe) -or -not (Test-Path $fullExe)) {
                        $fullExe = Find-BestGameExe -FolderPath $iLoc -PreferredTitle $dName
                    }
                    if (-not [string]::IsNullOrWhiteSpace($fullExe) -and (Test-Path $fullExe)) {
                        $kPath = $fullExe.ToLowerInvariant()
                        $kTitle = $dName.Trim().ToLowerInvariant()
                        if (-not $knownPaths.ContainsKey($kPath) -and -not $knownTitles.ContainsKey($kTitle)) {
                            $cover = Find-FolderCoverImage $iLoc
                            $newObj = New-GameObject -Title $dName.Trim() -ExecutablePath $fullExe -CustomCoverPath $cover -PlatformSource "Epic Games"
                            [void]$discovered.Add($newObj)
                            $knownPaths[$kPath] = $true
                            $knownTitles[$kTitle] = $true
                        }
                    }
                } catch {}
            }
        }
    } catch {}

    # 3. FIVEM & ACCESOS DIRECTOS DEL ESCRITORIO
    try {
        $fivemExe = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.exe"
        if ((Test-Path $fivemExe) -and (-not $knownPaths.ContainsKey($fivemExe.ToLowerInvariant()))) {
            $newObj = New-GameObject -Title "FiveM" -ExecutablePath $fivemExe -PlatformSource "FiveM"
            [void]$discovered.Add($newObj)
            $knownPaths[$fivemExe.ToLowerInvariant()] = $true
            $knownTitles["fivem"] = $true
        }

        $wsh = New-Object -ComObject WScript.Shell
        $desks = @([Environment]::GetFolderPath("Desktop"), "$env:PUBLIC\Desktop")
        foreach ($dk in $desks) {
            if (-not (Test-Path $dk)) { continue }
            $lnks = Get-ChildItem -Path $dk -Filter "*.lnk" -File -ErrorAction SilentlyContinue
            foreach ($lnk in $lnks) {
                try {
                    $scName = [System.IO.Path]::GetFileNameWithoutExtension($lnk.Name)
                    if ($scName -match "GameLauncher") { continue }
                    $sc = $wsh.CreateShortcut($lnk.FullName)
                    $target = [string]$sc.TargetPath
                    if ([string]::IsNullOrWhiteSpace($target) -or (-not $target.EndsWith(".exe", [StringComparison]::OrdinalIgnoreCase)) -or (-not (Test-Path $target))) { continue }
                    $lowT = $target.ToLowerInvariant()
                    if ($lowT -match "\\windows\\|\\microsoft\\|chrome|msedge|firefox|brave|opera|discord|spotify|obs64|vscode|code\.exe|winrar|7z|vlc|acrobat|office|teams|zoom|anydesk|teamviewer|cpu-z|gpu-z|afterburner|geforce") { continue }
                    if ($lowT -match "steamapps|epic games|riot games|ubisoft|ea games|origin|gog games|xboxgames|\\games\\|\\juegos\\|fivem|minecraft|rockstar|battlenet|battle\.net|genshin|hoyoverse|ryujinx|sudachi|suyu|eden|assetto|cuphead|cyberpunk|counter-strike|rocketleague") {
                        if (-not (Test-IsIgnoredExe $target)) {
                            $kTitle = $scName.Trim().ToLowerInvariant()
                            if (-not $knownPaths.ContainsKey($lowT) -and -not $knownTitles.ContainsKey($kTitle)) {
                                $cov = Find-FolderCoverImage ([System.IO.Path]::GetDirectoryName($target))
                                $newObj = New-GameObject -Title $scName.Trim() -ExecutablePath $target -CustomCoverPath $cov -PlatformSource "PC"
                                [void]$discovered.Add($newObj)
                                $knownPaths[$lowT] = $true
                                $knownTitles[$kTitle] = $true
                            }
                        }
                    }
                } catch {}
            }
        }
    } catch {}

    # 4. CARPETAS DE JUEGOS EN TODOS LOS DISCOS DUROS
    try {
        $relRoots = @(
            "Games", "Juegos", "PC Games", "XboxGames", "GOG Games", "Riot Games",
            "Program Files\Epic Games", "Program Files\EA Games",
            "Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games",
            "Program Files\Rockstar Games"
        )
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 }
        foreach ($d in $drives) {
            foreach ($r in $relRoots) {
                $cand = Join-Path $d.Root $r
                if (-not (Test-Path $cand)) { continue }
                $subFolders = Get-ChildItem -Path $cand -Directory -ErrorAction SilentlyContinue
                foreach ($sf in $subFolders) {
                    if ($sf.Name -match "^(Riot Client|Steamworks Shared|DirectXRedist)$") { continue }
                    $bestExe = Find-BestGameExe -FolderPath $sf.FullName -PreferredTitle $sf.Name
                    if (-not [string]::IsNullOrWhiteSpace($bestExe) -and (Test-Path $bestExe)) {
                        $kPath = $bestExe.ToLowerInvariant()
                        $kTitle = $sf.Name.Trim().ToLowerInvariant()
                        if (-not $knownPaths.ContainsKey($kPath) -and -not $knownTitles.ContainsKey($kTitle)) {
                            $cov = Find-FolderCoverImage $sf.FullName
                            $newObj = New-GameObject -Title $sf.Name.Trim() -ExecutablePath $bestExe -CustomCoverPath $cov -PlatformSource "PC"
                            [void]$discovered.Add($newObj)
                            $knownPaths[$kPath] = $true
                            $knownTitles[$kTitle] = $true
                        }
                    }
                }
            }
        }
    } catch {}

    return $discovered
}

function Invoke-ScanCustomDirectory([string]$RootFolder) {
    $discovered = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($RootFolder) -or -not (Test-Path $RootFolder)) { return $discovered }

    $knownPaths = @{}
    $knownTitles = @{}
    foreach ($g in $script:AppData.Games) {
        if (-not [string]::IsNullOrWhiteSpace($g.ExecutablePath)) { $knownPaths[$g.ExecutablePath.ToLowerInvariant()] = $true }
        if (-not [string]::IsNullOrWhiteSpace($g.Title)) { $knownTitles[$g.Title.Trim().ToLowerInvariant()] = $true }
    }

    $subDirs = Get-ChildItem -Path $RootFolder -Directory -ErrorAction SilentlyContinue
    foreach ($sd in $subDirs) {
        $bestExe = Find-BestGameExe -FolderPath $sd.FullName -PreferredTitle $sd.Name
        if (-not [string]::IsNullOrWhiteSpace($bestExe) -and (Test-Path $bestExe)) {
            $kPath = $bestExe.ToLowerInvariant()
            $kTitle = $sd.Name.Trim().ToLowerInvariant()
            if (-not $knownPaths.ContainsKey($kPath) -and -not $knownTitles.ContainsKey($kTitle)) {
                $cov = Find-FolderCoverImage $sd.FullName
                $newObj = New-GameObject -Title $sd.Name.Trim() -ExecutablePath $bestExe -CustomCoverPath $cov -PlatformSource "Carpeta PC"
                [void]$discovered.Add($newObj)
                $knownPaths[$kPath] = $true
                $knownTitles[$kTitle] = $true
            }
        }
    }

    if ($discovered.Count -eq 0) {
        $fName = [System.IO.Path]::GetFileName($RootFolder)
        $bestExe = Find-BestGameExe -FolderPath $RootFolder -PreferredTitle $fName
        if (-not [string]::IsNullOrWhiteSpace($bestExe) -and (Test-Path $bestExe)) {
            $kPath = $bestExe.ToLowerInvariant()
            if (-not $knownPaths.ContainsKey($kPath)) {
                $cov = Find-FolderCoverImage $RootFolder
                $newObj = New-GameObject -Title $fName -ExecutablePath $bestExe -CustomCoverPath $cov -PlatformSource "Carpeta PC"
                [void]$discovered.Add($newObj)
            }
        }
    }
    return $discovered
}

$XamlString = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GameLauncher Neon"
        Width="1220" Height="770"
        MinWidth="940" MinHeight="600"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="CanResizeWithGrip"
        Background="#090A10"
        Foreground="#F8FAFC"
        FontFamily="Segoe UI"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True">

    <Window.Resources>
        <Style x:Key="NeonPrimaryButton" TargetType="Button">
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="14,9"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="btnBorder" CornerRadius="8" Padding="{TemplateBinding Padding}" BorderThickness="1.2" BorderBrush="#A78BFA">
                            <Border.Background>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                    <GradientStop Color="#7C3AED" Offset="0"/>
                                    <GradientStop Color="#2563EB" Offset="1"/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="btnBorder" Property="BorderBrush" Value="#06B6D4"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="btnBorder" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="NeonCyanButton" TargetType="Button">
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="14,9"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="cyanBorder" CornerRadius="8" Padding="{TemplateBinding Padding}" BorderThickness="1.5" BorderBrush="#06B6D4">
                            <Border.Background>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                    <GradientStop Color="#0891B2" Offset="0"/>
                                    <GradientStop Color="#2563EB" Offset="1"/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="cyanBorder" Property="BorderBrush" Value="#A78BFA"/>
                                <Setter TargetName="cyanBorder" Property="Opacity" Value="0.92"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="NeonSecondaryButton" TargetType="Button">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="12,7"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="secBorder" Background="#191D30" CornerRadius="7" Padding="{TemplateBinding Padding}" BorderThickness="1" BorderBrush="#2E3656">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="secBorder" Property="Background" Value="#232842"/>
                                <Setter TargetName="secBorder" Property="BorderBrush" Value="#8B5CF6"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="TitleBarButton" TargetType="Button">
            <Setter Property="Width" Value="42"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="tbBorder" Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="tbBorder" Property="Background" Value="#232842"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border x:Name="MainWindowBorder" Background="#090A10" BorderBrush="#2D2B52" BorderThickness="1.5" CornerRadius="10">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="54"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="32"/>
            </Grid.RowDefinitions>

            <Border x:Name="TopTitleBar" Grid.Row="0" Background="#0C0E18" BorderBrush="#1E2238" BorderThickness="0,0,0,1" CornerRadius="10,10,0,0">
                <Grid Margin="16,0,10,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Width="34" Height="34" CornerRadius="8" BorderBrush="#06B6D4" BorderThickness="1.5" Margin="0,0,12,0">
                            <Border.Background>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                    <GradientStop Color="#1E1533" Offset="0"/>
                                    <GradientStop Color="#0F172A" Offset="1"/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <Path Data="M10,7 L25,16 L10,25 L13,16 Z" Fill="#3B82F6" Stroke="#06B6D4" StrokeThickness="1.5" Stretch="Uniform" Margin="6"/>
                        </Border>
                        <StackPanel VerticalAlignment="Center">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="GAMELAUNCHER" FontWeight="Bold" FontSize="15" Foreground="#F8FAFC"/>
                                <TextBlock Text=" NEON" FontWeight="ExtraBold" FontSize="15" Foreground="#06B6D4" Margin="4,0,0,0"/>
                            </StackPanel>
                            <TextBlock Text="TURBO ENGINE &#x2022; GPU ACCELERATED" FontSize="9.5" Foreground="#64748B" FontWeight="SemiBold"/>
                        </StackPanel>
                    </StackPanel>

                    <Border Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center" Background="#131626" BorderBrush="#262B47" BorderThickness="1" CornerRadius="14" Padding="14,5">
                        <StackPanel Orientation="Horizontal">
                            <Ellipse Width="8" Height="8" Fill="#06B6D4" VerticalAlignment="Center" Margin="0,0,8,0"/>
                            <TextBlock x:Name="TopStatusText" Text="Biblioteca lista" FontSize="12" Foreground="#CBD5E1"/>
                        </StackPanel>
                    </Border>

                    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button x:Name="MinimizeBtn" Style="{StaticResource TitleBarButton}" ToolTip="Minimizar">
                            <TextBlock Text="&#x2014;" FontSize="13" FontWeight="Bold"/>
                        </Button>
                        <Button x:Name="MaximizeBtn" Style="{StaticResource TitleBarButton}" ToolTip="Maximizar / Restaurar" Margin="4,0">
                            <TextBlock x:Name="MaxRestoreIcon" Text="&#x25A2;" FontSize="13"/>
                        </Button>
                        <Button x:Name="CloseBtn" Style="{StaticResource TitleBarButton}" ToolTip="Cerrar aplicacion">
                            <TextBlock Text="&#x2715;" FontSize="13" Foreground="#F87171"/>
                        </Button>
                    </StackPanel>
                </Grid>
            </Border>

            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="245"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" Background="#0E101A" BorderBrush="#1E2238" BorderThickness="0,0,1,0" Padding="14,16">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Margin="0,0,0,16">
                            <Button x:Name="AutoDetectSidebarBtn" Style="{StaticResource NeonCyanButton}" Height="42" Margin="0,0,0,10" ToolTip="Busca automaticamente tus juegos en Steam, Epic Games, FiveM y discos duros">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#x26A1;" FontSize="14" Margin="0,0,7,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="DETECTAR MIS JUEGOS" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>

                            <Button x:Name="AddGameSidebarBtn" Style="{StaticResource NeonPrimaryButton}" Height="38" Margin="0,0,0,8" ToolTip="Anadir un juego manualmente eligiendo su .exe">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xFF0B;" FontSize="14" FontWeight="Bold" Margin="0,0,7,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="ANADIR MANUALMENTE" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>

                            <Button x:Name="ScanFolderSidebarBtn" Style="{StaticResource NeonSecondaryButton}" Height="34" ToolTip="Elegir una carpeta especifica de tu PC para detectar todos los juegos dentro de ella">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#x1F4C2;" FontSize="13" Margin="0,0,7,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="Escanear otra carpeta..." VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                        </StackPanel>

                        <StackPanel Grid.Row="1">
                            <TextBlock Text="NAVEGACION" FontSize="10.5" FontWeight="Bold" Foreground="#64748B" Margin="8,0,0,8"/>

                            <Button x:Name="NavAllBtn" Style="{StaticResource NeonSecondaryButton}" HorizontalContentAlignment="Left" Margin="0,0,0,6" Padding="12,9">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#x2756;" Foreground="#8B5CF6" Margin="0,0,10,0" FontSize="14"/>
                                    <TextBlock Text="Todos los Juegos"/>
                                </StackPanel>
                            </Button>

                            <Button x:Name="NavFavBtn" Style="{StaticResource NeonSecondaryButton}" HorizontalContentAlignment="Left" Margin="0,0,0,6" Padding="12,9">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#x2605;" Foreground="#F59E0B" Margin="0,0,10,0" FontSize="14"/>
                                    <TextBlock Text="Favoritos"/>
                                </StackPanel>
                            </Button>

                            <Button x:Name="NavHistoryBtn" Style="{StaticResource NeonSecondaryButton}" HorizontalContentAlignment="Left" Margin="0,0,0,6" Padding="12,9">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#x25F7;" Foreground="#06B6D4" Margin="0,0,10,0" FontSize="14"/>
                                    <TextBlock Text="Historial de Inicio"/>
                                </StackPanel>
                            </Button>

                            <Button x:Name="NavSettingsBtn" Style="{StaticResource NeonSecondaryButton}" HorizontalContentAlignment="Left" Margin="0,0,0,14" Padding="12,9">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#x2699;" Foreground="#3B82F6" Margin="0,0,10,0" FontSize="14"/>
                                    <TextBlock Text="Configuracion y Datos"/>
                                </StackPanel>
                            </Button>

                            <TextBlock Text="MANTENIMIENTO" FontSize="10.5" FontWeight="Bold" Foreground="#64748B" Margin="8,4,0,8"/>

                            <Button x:Name="VerifyPathsBtn" Style="{StaticResource NeonSecondaryButton}" HorizontalContentAlignment="Left" Margin="0,0,0,6" Padding="12,8" ToolTip="Comprobar si todos los ejecutables existen en el disco">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#x21BB;" Foreground="#10B981" Margin="0,0,10,0" FontSize="14"/>
                                    <TextBlock Text="Verificar Rutas"/>
                                </StackPanel>
                            </Button>
                        </StackPanel>

                        <Border Grid.Row="2" Background="#141829" BorderBrush="#262C49" BorderThickness="1" CornerRadius="8" Padding="12">
                            <StackPanel>
                                <TextBlock Text="ESTADO DE BIBLIOTECA" FontSize="10" FontWeight="Bold" Foreground="#8B5CF6" Margin="0,0,0,6"/>
                                <TextBlock x:Name="StatsTotalText" Text="Total: 0 juegos" FontSize="12" Foreground="#E2E8F0"/>
                                <TextBlock x:Name="StatsAvailableText" Text="Disponibles: 0" FontSize="11.5" Foreground="#10B981" Margin="0,2,0,0"/>
                                <TextBlock x:Name="StatsMissingText" Text="No disponibles: 0" FontSize="11.5" Foreground="#94A3B8" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </Border>

                <Grid x:Name="MainViewHost" Grid.Column="1" Margin="22,18,22,14">
                    <Grid x:Name="LibraryView" Visibility="Visible">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row="0" Margin="0,0,0,18">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <Border Grid.Column="0" Background="#141726" BorderBrush="#2A3152" BorderThickness="1" CornerRadius="8" Padding="12,6" Margin="0,0,12,0">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="&#x1F50D;" Foreground="#64748B" VerticalAlignment="Center" Margin="0,0,8,0"/>
                                    <TextBox x:Name="SearchBox" Grid.Column="1" Background="Transparent" BorderThickness="0" Foreground="#F8FAFC" CaretBrush="#06B6D4" FontSize="13" VerticalContentAlignment="Center"/>
                                    <TextBlock x:Name="SearchPlaceholder" Grid.Column="1" Text="Buscar juegos por nombre o plataforma..." Foreground="#64748B" FontSize="13" VerticalAlignment="Center" IsHitTestVisible="False"/>
                                </Grid>
                            </Border>

                            <Border Grid.Column="1" Background="#141726" BorderBrush="#2A3152" BorderThickness="1" CornerRadius="8" Padding="12,6" Margin="0,0,12,0" VerticalAlignment="Center">
                                <CheckBox x:Name="OnlyAvailableCheck" Content="Solo disponibles" Foreground="#E2E8F0" VerticalContentAlignment="Center"/>
                            </Border>

                            <Border Grid.Column="2" Background="#141726" BorderBrush="#2A3152" BorderThickness="1" CornerRadius="8" Padding="10,4" VerticalAlignment="Center">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Text="Ordenar:" Foreground="#94A3B8" FontSize="12" VerticalAlignment="Center" Margin="0,0,8,0"/>
                                    <ComboBox x:Name="SortComboBox" Width="155" SelectedIndex="0" VerticalContentAlignment="Center">
                                        <ComboBoxItem Content="Nombre (A - Z)"/>
                                        <ComboBoxItem Content="Jugados recientemente"/>
                                        <ComboBoxItem Content="Mas veces jugados"/>
                                        <ComboBoxItem Content="Disponibilidad"/>
                                    </ComboBox>
                                </StackPanel>
                            </Border>
                        </Grid>

                        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                            <Grid Margin="4,6,4,6">
                                <ItemsControl x:Name="GamesItemsControl">
                                    <ItemsControl.ItemsPanel>
                                        <ItemsPanelTemplate>
                                            <WrapPanel Orientation="Horizontal"/>
                                        </ItemsPanelTemplate>
                                    </ItemsControl.ItemsPanel>
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border Uid="GameCard" Width="270" Margin="0,0,16,16" CornerRadius="12" Background="#141828" BorderThickness="1.5" Padding="14">
                                                <Border.Style>
                                                    <Style TargetType="Border">
                                                        <Setter Property="BorderBrush" Value="#252B48"/>
                                                        <Style.Triggers>
                                                            <Trigger Property="IsMouseOver" Value="True">
                                                                <Setter Property="BorderBrush" Value="#06B6D4"/>
                                                                <Setter Property="Background" Value="#1B2138"/>
                                                            </Trigger>
                                                        </Style.Triggers>
                                                    </Style>
                                                </Border.Style>

                                                <StackPanel>
                                                    <Grid Height="125" Margin="0,0,0,12">
                                                        <Border Background="#0D101C" CornerRadius="8" BorderBrush="#1F243D" BorderThickness="1" ClipToBounds="True">
                                                            <Grid>
                                                                <Path Data="M6,12 L10,8 L22,8 L26,12 L25,22 L20,22 L18,19 L14,19 L12,22 L7,22 Z"
                                                                      Stroke="#3B82F6" StrokeThickness="1.5" Fill="#17203A"
                                                                      Width="54" Height="54" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                                                <Image Source="{Binding DisplayIcon}" Stretch="Uniform" MaxHeight="118" MaxWidth="240" HorizontalAlignment="Center" VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality"/>
                                                            </Grid>
                                                        </Border>

                                                        <Border HorizontalAlignment="Left" VerticalAlignment="Top" Margin="8,8,0,0" CornerRadius="6" Padding="8,3" Background="#D9090A10" BorderThickness="1" BorderBrush="{Binding StatusColor}">
                                                            <TextBlock Text="{Binding StatusText}" FontSize="10.5" FontWeight="SemiBold" Foreground="{Binding StatusColor}"/>
                                                        </Border>

                                                        <Button Uid="Fav" Tag="{Binding Id}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,6,6,0" Style="{StaticResource NeonSecondaryButton}" Padding="7,3" ToolTip="Marcar o desmarcar como favorito">
                                                            <TextBlock Text="{Binding FavoriteSymbol}" Foreground="#FBBF24" FontSize="14"/>
                                                        </Button>
                                                    </Grid>

                                                    <TextBlock Text="{Binding Title}" FontSize="15" FontWeight="Bold" Foreground="#F8FAFC" TextTrimming="CharacterEllipsis" ToolTip="{Binding Title}"/>
                                                    <TextBlock Text="{Binding ExecutablePath}" FontSize="11" Foreground="#64748B" TextTrimming="CharacterEllipsis" Margin="0,3,0,4" ToolTip="{Binding ExecutablePath}"/>
                                                    <TextBlock Text="{Binding LastPlayedText}" FontSize="11" Foreground="#94A3B8" Margin="0,0,0,12"/>

                                                    <Grid>
                                                        <Grid.ColumnDefinitions>
                                                            <ColumnDefinition Width="*"/>
                                                            <ColumnDefinition Width="Auto"/>
                                                            <ColumnDefinition Width="Auto"/>
                                                        </Grid.ColumnDefinitions>

                                                        <Button Grid.Column="0" Uid="Play" Tag="{Binding Id}" Style="{StaticResource NeonPrimaryButton}" Padding="10,8" Margin="0,0,6,0" ToolTip="Iniciar juego">
                                                            <TextBlock Text="&#x25B6; JUGAR" FontWeight="Bold" FontSize="12.5"/>
                                                        </Button>

                                                        <Button Grid.Column="1" Uid="Edit" Tag="{Binding Id}" Style="{StaticResource NeonSecondaryButton}" Padding="10,8" Margin="0,0,6,0" ToolTip="Cambiar imagen/caratula, nombre o ruta del ejecutable">
                                                            <TextBlock Text="&#x270E; Imagen / Ruta" FontSize="11.5"/>
                                                        </Button>

                                                        <Button Grid.Column="2" Uid="Remove" Tag="{Binding Id}" Style="{StaticResource NeonSecondaryButton}" Padding="9,8" ToolTip="Quitar de la biblioteca (no borra archivos del PC)">
                                                            <TextBlock Text="&#x1F5D1;" Foreground="#F87171" FontSize="13"/>
                                                        </Button>
                                                    </Grid>
                                                </StackPanel>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>

                                <Border x:Name="EmptyStatePanel" Background="#111422" BorderBrush="#232946" BorderThickness="1" CornerRadius="12" Padding="40" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
                                    <StackPanel HorizontalAlignment="Center" MaxWidth="460">
                                        <TextBlock Text="&#x1F3AE;" FontSize="42" HorizontalAlignment="Center" Margin="0,0,0,12"/>
                                        <TextBlock Text="Detecta tus juegos automaticamente o anadelos" FontSize="18" FontWeight="Bold" Foreground="#F8FAFC" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                                        <TextBlock Text="Pulsa &#xAB;&#x26A1; DETECTAR MIS JUEGOS&#xBB; para buscar automaticamente tus juegos de Steam, Epic Games, FiveM y discos duros, o elige una carpeta." FontSize="13" Foreground="#94A3B8" TextAlignment="Center" TextWrapping="Wrap" Margin="0,0,0,20"/>
                                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                                            <Button x:Name="EmptyAutoDetectBtn" Style="{StaticResource NeonCyanButton}" Padding="18,10" Margin="0,0,10,0" Content="&#x26A1; Detectar Mis Juegos"/>
                                            <Button x:Name="EmptyAddGameBtn" Style="{StaticResource NeonPrimaryButton}" Padding="18,10" Content="&#xFF0B; Anadir Manualmente"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </ScrollViewer>
                    </Grid>

                    <Grid x:Name="HistoryView" Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <DockPanel Grid.Row="0" Margin="0,0,0,16">
                            <StackPanel>
                                <TextBlock Text="HISTORIAL DE SESIONES" FontSize="18" FontWeight="Bold" Foreground="#F8FAFC"/>
                                <TextBlock Text="Registro cronologico de los ultimos juegos iniciados desde GameLauncher." FontSize="12.5" Foreground="#94A3B8"/>
                            </StackPanel>
                            <Button x:Name="ClearHistoryBtn" Style="{StaticResource NeonSecondaryButton}" HorizontalAlignment="Right" VerticalAlignment="Center" Content="Limpiar Historial"/>
                        </DockPanel>

                        <Border Grid.Row="1" Background="#131626" BorderBrush="#252B48" BorderThickness="1" CornerRadius="10" Padding="14">
                            <ListBox x:Name="HistoryListBox" Background="Transparent" BorderThickness="0" Foreground="#E2E8F0" FontSize="13"/>
                        </Border>
                    </Grid>

                    <ScrollViewer x:Name="SettingsView" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
                        <StackPanel MaxWidth="760" HorizontalAlignment="Left">
                            <TextBlock Text="CONFIGURACION Y GESTION DE DATOS" FontSize="18" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,0,0,6"/>
                            <TextBlock Text="Personaliza el comportamiento de GameLauncher y gestiona tus copias de seguridad locales." FontSize="12.5" Foreground="#94A3B8" Margin="0,0,0,20"/>

                            <Border Background="#131626" BorderBrush="#252B48" BorderThickness="1" CornerRadius="10" Padding="18" Margin="0,0,0,16">
                                <StackPanel>
                                    <TextBlock Text="DETECCION AUTOMATICA Y COMPORTAMIENTO" FontSize="13" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,12"/>
                                    <CheckBox x:Name="AutoScanStartupCheck" Content="Buscar automaticamente juegos nuevos en segundo plano al abrir GameLauncher" Foreground="#E2E8F0" Margin="0,0,0,10"/>
                                    <CheckBox x:Name="MinimizeOnLaunchCheck" Content="Minimizar GameLauncher automaticamente al abrir un juego" Foreground="#E2E8F0" Margin="0,0,0,10"/>
                                    <CheckBox x:Name="HighContrastBorderCheck" Content="Realzar bordes luminosos neon en la ventana principal" Foreground="#E2E8F0"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#131626" BorderBrush="#252B48" BorderThickness="1" CornerRadius="10" Padding="18" Margin="0,0,0,16">
                                <StackPanel>
                                    <TextBlock Text="PORTABILIDAD DE BIBLIOTECA (IMPORTAR / EXPORTAR)" FontSize="13" FontWeight="Bold" Foreground="#8B5CF6" Margin="0,0,0,6"/>
                                    <TextBlock Text="Guarda tu lista de juegos en un archivo JSON o cargala en otro ordenador sin perder tu configuracion." FontSize="12" Foreground="#94A3B8" Margin="0,0,0,14"/>
                                    <StackPanel Orientation="Horizontal">
                                        <Button x:Name="ExportLibraryBtn" Style="{StaticResource NeonPrimaryButton}" Content="Exportar Biblioteca (.json)" Margin="0,0,12,0"/>
                                        <Button x:Name="ImportLibraryBtn" Style="{StaticResource NeonSecondaryButton}" Content="Importar Biblioteca (.json)"/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <Border Background="#131626" BorderBrush="#252B48" BorderThickness="1" CornerRadius="10" Padding="18">
                                <StackPanel>
                                    <TextBlock Text="PRIVACIDAD, CACHE EN MEMORIA Y ALMACENAMIENTO" FontSize="13" FontWeight="Bold" Foreground="#10B981" Margin="0,0,0,6"/>
                                    <TextBlock Text="GameLauncher utiliza cache de imagenes congeladas en GPU y guarda tus datos exclusivamente en LocalAppData." FontSize="12" Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,0,0,10"/>
                                    <TextBlock x:Name="LocalDataPathText" FontSize="11.5" Foreground="#CBD5E1" Margin="0,0,0,12"/>
                                    <StackPanel Orientation="Horizontal">
                                        <Button x:Name="OpenDataFolderBtn" Style="{StaticResource NeonSecondaryButton}" Content="Abrir Carpeta de Datos"/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </Grid>

            <Border Grid.Row="2" Background="#0C0E18" BorderBrush="#1E2238" BorderThickness="0,1,0,0" CornerRadius="0,0,10,10" Padding="16,0">
                <DockPanel VerticalAlignment="Center">
                    <TextBlock x:Name="FooterStatusText" Text="Listo. Motor grafico acelerado por GPU." FontSize="11.5" Foreground="#64748B"/>
                    <TextBlock Text="v1.3.1 Turbo &#x2022; GPU Animations &#x2022; Smart Cache" FontSize="11" Foreground="#475569" HorizontalAlignment="Right"/>
                </DockPanel>
            </Border>

            <Border x:Name="GameModalOverlay" Grid.Row="0" Grid.RowSpan="3" Background="#CC06070B" Visibility="Collapsed" CornerRadius="10">
                <Border x:Name="GameModalCard" Width="560" VerticalAlignment="Center" HorizontalAlignment="Center" Background="#131728" BorderBrush="#06B6D4" BorderThickness="1.5" CornerRadius="12" Padding="24">
                    <StackPanel>
                        <TextBlock x:Name="ModalHeaderTitle" Text="PERSONALIZAR JUEGO (IMAGEN, RUTA Y NOMBRE)" FontSize="16" FontWeight="Bold" Foreground="#06B6D4" Margin="0,0,0,16"/>

                        <TextBlock Text="Nombre del juego *" FontSize="12" Foreground="#CBD5E1" Margin="0,0,0,6"/>
                        <Border Background="#0B0D17" BorderBrush="#2E3656" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,0,0,14">
                            <TextBox x:Name="ModalTitleBox" Background="Transparent" BorderThickness="0" Foreground="#F8FAFC" CaretBrush="#06B6D4" FontSize="13"/>
                        </Border>

                        <TextBlock Text="Ruta del archivo ejecutable (.exe) *" FontSize="12" Foreground="#CBD5E1" Margin="0,0,0,6"/>
                        <Grid Margin="0,0,0,14">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Border Grid.Column="0" Background="#0B0D17" BorderBrush="#2E3656" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,0,8,0">
                                <TextBox x:Name="ModalExePathBox" Background="Transparent" BorderThickness="0" Foreground="#F8FAFC" CaretBrush="#06B6D4" FontSize="12.5"/>
                            </Border>
                            <Button x:Name="BrowseExeBtn" Grid.Column="1" Style="{StaticResource NeonSecondaryButton}" Content="Cambiar .exe..."/>
                        </Grid>

                        <TextBlock Text="Imagen o caratula personalizada (PNG / JPG / BMP)" FontSize="12" Foreground="#CBD5E1" Margin="0,0,0,6"/>
                        <Grid Margin="0,0,0,14">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <Border Grid.Column="0" Background="#0B0D17" BorderBrush="#2E3656" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,0,8,0">
                                <TextBox x:Name="ModalCoverPathBox" Background="Transparent" BorderThickness="0" Foreground="#F8FAFC" CaretBrush="#06B6D4" FontSize="12"/>
                            </Border>
                            <Button x:Name="BrowseCoverBtn" Grid.Column="1" Style="{StaticResource NeonCyanButton}" Padding="12,7" Margin="0,0,6,0" Content="Elegir Imagen..."/>
                            <Button x:Name="ClearCoverBtn" Grid.Column="2" Style="{StaticResource NeonSecondaryButton}" Padding="10,7" Content="Usar Icono" ToolTip="Quitar caratula y usar el icono original del archivo .exe"/>
                        </Grid>

                        <TextBlock Text="Parametros adicionales de lanzamiento (Opcional)" FontSize="12" Foreground="#CBD5E1" Margin="0,0,0,6"/>
                        <Border Background="#0B0D17" BorderBrush="#2E3656" BorderThickness="1" CornerRadius="6" Padding="8,6" Margin="0,0,0,22">
                            <TextBox x:Name="ModalArgsBox" Background="Transparent" BorderThickness="0" Foreground="#F8FAFC" CaretBrush="#06B6D4" FontSize="12"/>
                        </Border>

                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                            <Button x:Name="CancelModalBtn" Style="{StaticResource NeonSecondaryButton}" Content="Cancelar" Margin="0,0,10,0" Padding="16,8"/>
                            <Button x:Name="SaveModalBtn" Style="{StaticResource NeonPrimaryButton}" Content="Guardar Cambios" Padding="20,8"/>
                        </StackPanel>
                    </StackPanel>
                </Border>
            </Border>
        </Grid>
    </Border>
</Window>
"@

Initialize-EpicLaunchCache
$script:AppData = Load-LibraryData
$Window = [System.Windows.Markup.XamlReader]::Parse($XamlString)

$icoPath = Join-Path $PSScriptRoot "Assets\app.ico"
if (Test-Path $icoPath) {
    try { $Window.Icon = New-Object System.Windows.Media.Imaging.BitmapImage((New-Object System.Uri($icoPath, [System.UriKind]::Absolute))) } catch {}
}

$MainWindowBorder        = $Window.FindName("MainWindowBorder")
$TopTitleBar             = $Window.FindName("TopTitleBar")
$TopStatusText           = $Window.FindName("TopStatusText")
$MaxRestoreIcon          = $Window.FindName("MaxRestoreIcon")
$StatsTotalText          = $Window.FindName("StatsTotalText")
$StatsAvailableText      = $Window.FindName("StatsAvailableText")
$StatsMissingText        = $Window.FindName("StatsMissingText")
$MainViewHost            = $Window.FindName("MainViewHost")
$LibraryView             = $Window.FindName("LibraryView")
$HistoryView             = $Window.FindName("HistoryView")
$SettingsView            = $Window.FindName("SettingsView")
$SearchBox               = $Window.FindName("SearchBox")
$SearchPlaceholder       = $Window.FindName("SearchPlaceholder")
$OnlyAvailableCheck      = $Window.FindName("OnlyAvailableCheck")
$SortComboBox            = $Window.FindName("SortComboBox")
$GamesItemsControl       = $Window.FindName("GamesItemsControl")
$EmptyStatePanel         = $Window.FindName("EmptyStatePanel")
$HistoryListBox          = $Window.FindName("HistoryListBox")
$AutoScanStartupCheck    = $Window.FindName("AutoScanStartupCheck")
$MinimizeOnLaunchCheck   = $Window.FindName("MinimizeOnLaunchCheck")
$HighContrastBorderCheck = $Window.FindName("HighContrastBorderCheck")
$LocalDataPathText       = $Window.FindName("LocalDataPathText")
$FooterStatusText        = $Window.FindName("FooterStatusText")

$GameModalOverlay        = $Window.FindName("GameModalOverlay")
$GameModalCard           = $Window.FindName("GameModalCard")
$ModalHeaderTitle        = $Window.FindName("ModalHeaderTitle")
$ModalExePathBox         = $Window.FindName("ModalExePathBox")
$ModalTitleBox           = $Window.FindName("ModalTitleBox")
$ModalCoverPathBox       = $Window.FindName("ModalCoverPathBox")
$ModalArgsBox            = $Window.FindName("ModalArgsBox")

# =========================================================================
# SISTEMA DE ANIMACIONES GPU POR CODIGO .NET (CERO RIESGO XAML)
# =========================================================================
function Invoke-ViewAnimation {
    try {
        if ($null -eq $MainViewHost) { return }
        if (-not ($MainViewHost.RenderTransform -is [System.Windows.Media.TranslateTransform])) {
            $MainViewHost.RenderTransform = New-Object System.Windows.Media.TranslateTransform(0.0, 0.0)
        }
        $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(160))
        $ease = New-Object System.Windows.Media.Animation.QuadraticEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut

        $animOp = New-Object System.Windows.Media.Animation.DoubleAnimation(0.25, 1.0, $dur)
        $animOp.EasingFunction = $ease
        $animY = New-Object System.Windows.Media.Animation.DoubleAnimation(8.0, 0.0, $dur)
        $animY.EasingFunction = $ease

        $MainViewHost.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animOp)
        $MainViewHost.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $animY)
    } catch {}
}

function Invoke-ModalAnimation {
    try {
        if ($null -eq $GameModalCard) { return }
        if (-not ($GameModalCard.RenderTransform -is [System.Windows.Media.ScaleTransform])) {
            $GameModalCard.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
            $GameModalCard.RenderTransform = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
        }
        $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(150))
        $ease = New-Object System.Windows.Media.Animation.QuadraticEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut

        $animS = New-Object System.Windows.Media.Animation.DoubleAnimation(0.92, 1.0, $dur)
        $animS.EasingFunction = $ease
        $GameModalCard.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $animS)
        $GameModalCard.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $animS)
    } catch {}
}

function Set-CardHoverAnimation($CardBorder, [bool]$IsHover) {
    if ($null -eq $CardBorder) { return }
    try {
        if (-not ($CardBorder.RenderTransform -is [System.Windows.Media.TransformGroup])) {
            $tg = New-Object System.Windows.Media.TransformGroup
            $st = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
            $tt = New-Object System.Windows.Media.TranslateTransform(0.0, 0.0)
            [void]$tg.Children.Add($st)
            [void]$tg.Children.Add($tt)
            $CardBorder.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
            $CardBorder.RenderTransform = $tg
        }
        $tg = [System.Windows.Media.TransformGroup]$CardBorder.RenderTransform
        $scaleT = [System.Windows.Media.ScaleTransform]$tg.Children[0]
        $transT = [System.Windows.Media.TranslateTransform]$tg.Children[1]

        $targetScale = 1.0
        $targetY = 0.0
        if ($IsHover) {
            $targetScale = 1.028
            $targetY = -4.0
        }

        $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(130))
        $ease = New-Object System.Windows.Media.Animation.QuadraticEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut

        $animScale = New-Object System.Windows.Media.Animation.DoubleAnimation($targetScale, $dur)
        $animScale.EasingFunction = $ease
        $animY = New-Object System.Windows.Media.Animation.DoubleAnimation($targetY, $dur)
        $animY.EasingFunction = $ease

        $scaleT.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $animScale)
        $scaleT.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $animScale)
        $transT.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $animY)
    } catch {}
}

function Enable-ButtonHoverAnimation($Btn) {
    if ($null -eq $Btn) { return }
    try {
        $st = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
        $Btn.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
        $Btn.RenderTransform = $st
        $Btn.Add_MouseEnter({
            param($sender, $e)
            try {
                $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(110))
                $anim = New-Object System.Windows.Media.Animation.DoubleAnimation(1.03, $dur)
                $sender.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $anim)
                $sender.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $anim)
            } catch {}
        })
        $Btn.Add_MouseLeave({
            param($sender, $e)
            try {
                $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(110))
                $anim = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, $dur)
                $sender.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $anim)
                $sender.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $anim)
            } catch {}
        })
    } catch {}
}

# Activar micro-animaciones en botones principales
$btnNames = @(
    "AutoDetectSidebarBtn", "AddGameSidebarBtn", "ScanFolderSidebarBtn",
    "NavAllBtn", "NavFavBtn", "NavHistoryBtn", "NavSettingsBtn", "VerifyPathsBtn",
    "EmptyAutoDetectBtn", "EmptyAddGameBtn", "SaveModalBtn", "CancelModalBtn",
    "BrowseCoverBtn", "BrowseExeBtn", "ClearCoverBtn", "ExportLibraryBtn", "ImportLibraryBtn"
)
foreach ($bn in $btnNames) {
    Enable-ButtonHoverAnimation ($Window.FindName($bn))
}

# Detector global de hover para animar las tarjetas de juegos en GPU
$GamesItemsControl.Add_PreviewMouseMove({
    param($s, $e)
    try {
        $dep = $e.OriginalSource
        $foundCard = $null
        while ($null -ne $dep) {
            if (($dep -is [System.Windows.Controls.Border]) -and ($dep.Uid -eq "GameCard")) {
                $foundCard = [System.Windows.Controls.Border]$dep
                break
            }
            if ($dep -is [System.Windows.Media.Visual]) {
                $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
            } elseif ($dep -is [System.Windows.FrameworkContentElement]) {
                $dep = $dep.Parent
            } else {
                break
            }
        }
        if ($foundCard -ne $script:CurrentHoveredCard) {
            if ($null -ne $script:CurrentHoveredCard) {
                Set-CardHoverAnimation $script:CurrentHoveredCard $false
            }
            $script:CurrentHoveredCard = $foundCard
            if ($null -ne $script:CurrentHoveredCard) {
                Set-CardHoverAnimation $script:CurrentHoveredCard $true
            }
        }
    } catch {}
})

$GamesItemsControl.Add_MouseLeave({
    if ($null -ne $script:CurrentHoveredCard) {
        Set-CardHoverAnimation $script:CurrentHoveredCard $false
        $script:CurrentHoveredCard = $null
    }
})

function Update-VisualTheme {
    $hex = "#2D2B52"
    if ($script:AppData.HighContrastBorders) { $hex = "#06B6D4" }
    $MainWindowBorder.BorderBrush = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex)
}

function Update-GamesView {
    $script:CurrentHoveredCard = $null
    $q = ""
    if ($null -ne $SearchBox.Text) { $q = $SearchBox.Text.Trim() }
    if ([string]::IsNullOrEmpty($q)) {
        $SearchPlaceholder.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $SearchPlaceholder.Visibility = [System.Windows.Visibility]::Collapsed
    }

    $list = @($script:AppData.Games)
    if ($script:FilterFavoritesOnly) {
        $list = @($list | Where-Object { $_.IsFavorite -eq $true })
    }
    if ($OnlyAvailableCheck.IsChecked -eq $true) {
        $list = @($list | Where-Object { $_.IsAvailable -eq $true })
    }
    if (-not [string]::IsNullOrWhiteSpace($q)) {
        $escapedQ = [regex]::Escape($q)
        $list = @($list | Where-Object { $_.Title -match $escapedQ -or $_.PlatformSource -match $escapedQ })
    }

    switch ($SortComboBox.SelectedIndex) {
        1 { $list = @($list | Sort-Object -Property @{Expression={$_.LastPlayedIso}; Descending=$true}, @{Expression={$_.Title}; Descending=$false}) }
        2 { $list = @($list | Sort-Object -Property @{Expression={$_.PlayCount}; Descending=$true}, @{Expression={$_.Title}; Descending=$false}) }
        3 { $list = @($list | Sort-Object -Property @{Expression={$_.IsAvailable}; Descending=$true}, @{Expression={$_.Title}; Descending=$false}) }
        default { $list = @($list | Sort-Object -Property Title) }
    }

    $GamesItemsControl.ItemsSource = $null
    $GamesItemsControl.ItemsSource = $list
    if ($list.Count -eq 0) {
        $EmptyStatePanel.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $EmptyStatePanel.Visibility = [System.Windows.Visibility]::Collapsed
    }

    $total = $script:AppData.Games.Count
    $avail = @($script:AppData.Games | Where-Object { $_.IsAvailable -eq $true }).Count
    $missing = $total - $avail

    $StatsTotalText.Text = "Total: $total juego(s)"
    $StatsAvailableText.Text = "Disponibles: $avail"
    $StatsMissingText.Text = "No disponibles: $missing"

    $lastPlayedGame = $script:AppData.Games | Where-Object { -not [string]::IsNullOrWhiteSpace($_.LastPlayedIso) } | Sort-Object -Property LastPlayedIso -Descending | Select-Object -First 1
    if ($null -ne $lastPlayedGame) {
        $TopStatusText.Text = "Ultimo jugado: $($lastPlayedGame.Title)"
    } else {
        $TopStatusText.Text = "Biblioteca activa ($avail juegos listos)"
    }
}

function Update-HistoryView {
    $HistoryListBox.Items.Clear()
    if ($script:AppData.History.Count -eq 0) {
        [void]$HistoryListBox.Items.Add("Aun no se ha iniciado ningun juego desde GameLauncher.")
        return
    }
    $items = @($script:AppData.History)
    [array]::Reverse($items)
    foreach ($h in ($items | Select-Object -First 100)) {
        [void]$HistoryListBox.Items.Add("[$($h.TimestampIso)]  >>  $($h.GameTitle)   ($($h.ExecutablePath))")
    }
}

function Show-AppSection([string]$Sec) {
    if ($Sec -eq "Library") {
        $LibraryView.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $LibraryView.Visibility = [System.Windows.Visibility]::Collapsed
    }
    if ($Sec -eq "History") {
        $HistoryView.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $HistoryView.Visibility = [System.Windows.Visibility]::Collapsed
    }
    if ($Sec -eq "Settings") {
        $SettingsView.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $SettingsView.Visibility = [System.Windows.Visibility]::Collapsed
    }
    Invoke-ViewAnimation
}

function Start-AutoScanGames([bool]$SilentOnZero) {
    $FooterStatusText.Text = "Escaneando rapidamente Steam, Epic Games, FiveM y discos..."
    $found = Invoke-ScanAllGames
    if ($found.Count -gt 0) {
        foreach ($item in $found) {
            [void]$script:AppData.Games.Add($item)
        }
        Save-LibraryData
        Update-GamesView
        Invoke-ViewAnimation
        $FooterStatusText.Text = "Se detectaron y anadieron $($found.Count) juego(s) nuevos."
        if (-not $SilentOnZero) {
            [System.Windows.MessageBox]::Show(
                "Se han detectado y configurado automaticamente $($found.Count) juego(s) nuevos.`n`nPuedes cambiar la imagen, la ruta o el nombre de cualquiera pulsando 'Imagen / Ruta' en su tarjeta.",
                "Deteccion Automatica Completada",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        }
    } else {
        $FooterStatusText.Text = "Biblioteca sincronizada y optimizada en RAM."
        if (-not $SilentOnZero) {
            [System.Windows.MessageBox]::Show(
                "Todos los juegos de las rutas estandar ya estan en tu biblioteca.`n`nSi tienes juegos en otra carpeta especial, pulsa 'Escanear otra carpeta...' en el panel izquierdo.",
                "Deteccion Automatica",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        }
    }
}

function Open-EditModal($Game) {
    $script:EditingGameId = $Game.Id
    $ModalHeaderTitle.Text = "PERSONALIZAR JUEGO (CAMBIAR IMAGEN, RUTA O NOMBRE)"
    $ModalTitleBox.Text = $Game.Title
    $ModalExePathBox.Text = $Game.ExecutablePath
    $ModalCoverPathBox.Text = $Game.CustomCoverPath
    $ModalArgsBox.Text = $Game.Arguments
    $GameModalOverlay.Visibility = [System.Windows.Visibility]::Visible
    Invoke-ModalAnimation
}

function Invoke-PlayGame($Game) {
    Update-GameComputedProps -Game $Game -RefreshImage $false
    if (-not $Game.IsAvailable) {
        $res = [System.Windows.MessageBox]::Show(
            "No se puede iniciar '$($Game.Title)' porque el ejecutable no se encuentra en:`n`n$($Game.ExecutablePath)`n`n¿Deseas cambiar la ruta ahora?",
            "Ruta no disponible",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
            Open-EditModal $Game
        }
        return
    }
    try {
        if ($script:EpicLaunchMap.Count -eq 0 -and $script:SteamLaunchMap.Count -eq 0) {
            Initialize-EpicLaunchCache
        }

        $exeFull = $Game.ExecutablePath.Trim().Replace("/", "\")
        $exeLower = $exeFull.ToLowerInvariant()
        $titleKey = $Game.Title.Trim().ToLowerInvariant()
        $workDir = [System.IO.Path]::GetDirectoryName($exeFull)
        if ([string]::IsNullOrWhiteSpace($workDir)) { $workDir = $PSScriptRoot }

        $launchedViaPlatform = $false

        # A) COMPROBAR SI ES UN JUEGO DE EPIC GAMES (Por carpeta de instalacion o por titulo)
        $epicAppName = ""
        foreach ($dirKey in $script:EpicDirMap.Keys) {
            if ($exeLower.StartsWith($dirKey + "\")) {
                $epicAppName = $script:EpicDirMap[$dirKey]
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($epicAppName) -and $script:EpicLaunchMap.ContainsKey($titleKey)) {
            $epicAppName = $script:EpicLaunchMap[$titleKey]
        }

        if (-not [string]::IsNullOrWhiteSpace($epicAppName) -and [string]::IsNullOrWhiteSpace($Game.Arguments)) {
            $Game.PlatformSource = "Epic Games"
            $epicUri = "com.epicgames.launcher://apps/$($epicAppName)?action=launch&silent=true"
            Start-Process -FilePath "explorer.exe" -ArgumentList "`"$epicUri`""
            $launchedViaPlatform = $true
        }

        # B) COMPROBAR SI ES UN JUEGO DE STEAM (Por carpeta steamapps\common, por titulo o por steam_appid.txt)
        if (-not $launchedViaPlatform) {
            $steamAppId = ""
            foreach ($sDirKey in $script:SteamDirMap.Keys) {
                if ($exeLower.StartsWith($sDirKey + "\")) {
                    $steamAppId = $script:SteamDirMap[$sDirKey]
                    break
                }
            }
            if ([string]::IsNullOrWhiteSpace($steamAppId) -and $script:SteamLaunchMap.ContainsKey($titleKey)) {
                $steamAppId = $script:SteamLaunchMap[$titleKey]
            }
            if ([string]::IsNullOrWhiteSpace($steamAppId)) {
                $appIdTxt = Join-Path $workDir "steam_appid.txt"
                if (Test-Path $appIdTxt) {
                    $rawId = (Get-Content $appIdTxt -Raw -ErrorAction SilentlyContinue).Trim()
                    if ($rawId -match "^\d+$") { $steamAppId = $rawId }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($steamAppId) -and [string]::IsNullOrWhiteSpace($Game.Arguments)) {
                $Game.PlatformSource = "Steam"
                $steamUri = "steam://rungameid/$steamAppId"
                Start-Process -FilePath "explorer.exe" -ArgumentList "`"$steamUri`""
                $launchedViaPlatform = $true
            } elseif ($exeLower.Contains("\steamapps\common\")) {
                # Si esta en steamapps pero no tiene manifiesto, abrir Steam primero si esta cerrado
                if (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
                    if (-not [string]::IsNullOrWhiteSpace($script:SteamExePath) -and (Test-Path $script:SteamExePath)) {
                        Start-Process -FilePath $script:SteamExePath
                        Start-Sleep -Seconds 3
                    }
                }
            }
        }

        # C) SI ES UN JUEGO INDEPENDIENTE / FIVEM / EMULADOR
        if (-not $launchedViaPlatform) {
            # Si es FiveM y Steam esta instalado pero cerrado, abrir Steam en segundo plano para autenticar
            if ($exeLower.Contains("fivem") -and (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue))) {
                if (-not [string]::IsNullOrWhiteSpace($script:SteamExePath) -and (Test-Path $script:SteamExePath)) {
                    Start-Process -FilePath $script:SteamExePath -ArgumentList "-silent"
                    Start-Sleep -Seconds 2
                }
            }

            if ([string]::IsNullOrWhiteSpace($Game.Arguments)) {
                Start-Process -FilePath $exeFull -WorkingDirectory $workDir
            } else {
                Start-Process -FilePath $exeFull -ArgumentList $Game.Arguments -WorkingDirectory $workDir
            }
        }

        $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $Game.LastPlayedIso = $nowStr
        $Game.PlayCount = [int]$Game.PlayCount + 1
        Update-GameComputedProps -Game $Game -RefreshImage $false

        [void]$script:AppData.History.Add([PSCustomObject]@{
            GameId         = $Game.Id
            GameTitle      = $Game.Title
            ExecutablePath = $Game.ExecutablePath
            TimestampIso   = $nowStr
        })
        Save-LibraryData
        Update-GamesView
        $FooterStatusText.Text = "Iniciando a traves de $($Game.PlatformSource): $($Game.Title)"
        if ($script:AppData.MinimizeOnLaunch) {
            $Window.WindowState = [System.Windows.WindowState]::Minimized
        }
    } catch {
        [System.Windows.MessageBox]::Show(
            "No se pudo iniciar '$($Game.Title)':`n$($_.Exception.Message)",
            "Error al iniciar juego",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
}

function Remove-GameEntry($Game) {
    $res = [System.Windows.MessageBox]::Show(
        "¿Quieres quitar '$($Game.Title)' de tu biblioteca de GameLauncher?`n`n(Los archivos originales del juego en tu PC NO se borraran).",
        "Quitar de la biblioteca",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
        [void]$script:AppData.Games.Remove($Game)
        Save-LibraryData
        Update-GamesView
        $FooterStatusText.Text = "Se quito '$($Game.Title)' de la biblioteca."
    }
}

$TopTitleBar.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.ClickCount -eq 2) {
        if ($Window.WindowState -eq [System.Windows.WindowState]::Maximized) {
            $Window.WindowState = [System.Windows.WindowState]::Normal
        } else {
            $Window.WindowState = [System.Windows.WindowState]::Maximized
        }
    } elseif ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        $Window.DragMove()
    }
})

($Window.FindName("MinimizeBtn")).Add_Click({ $Window.WindowState = [System.Windows.WindowState]::Minimized })
($Window.FindName("MaximizeBtn")).Add_Click({
    if ($Window.WindowState -eq [System.Windows.WindowState]::Maximized) {
        $Window.WindowState = [System.Windows.WindowState]::Normal
    } else {
        $Window.WindowState = [System.Windows.WindowState]::Maximized
    }
})
($Window.FindName("CloseBtn")).Add_Click({ $Window.Close() })

($Window.FindName("AutoDetectSidebarBtn")).Add_Click({ Start-AutoScanGames $false })
($Window.FindName("EmptyAutoDetectBtn")).Add_Click({ Start-AutoScanGames $false })

$openAddModalAction = {
    $script:EditingGameId = $null
    $ModalHeaderTitle.Text = "ANADIR JUEGO MANUALMENTE"
    $ModalTitleBox.Text = ""
    $ModalExePathBox.Text = ""
    $ModalCoverPathBox.Text = ""
    $ModalArgsBox.Text = ""
    $GameModalOverlay.Visibility = [System.Windows.Visibility]::Visible
    Invoke-ModalAnimation
}
($Window.FindName("AddGameSidebarBtn")).Add_Click($openAddModalAction)
($Window.FindName("EmptyAddGameBtn")).Add_Click($openAddModalAction)

($Window.FindName("ScanFolderSidebarBtn")).Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecciona la carpeta donde tengas tus juegos instalados"
    $fbd.ShowNewFolderButton = $false
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selPath = $fbd.SelectedPath
        if (-not [string]::IsNullOrWhiteSpace($selPath) -and (Test-Path $selPath)) {
            $found = Invoke-ScanCustomDirectory $selPath
            if ($found.Count -gt 0) {
                foreach ($item in $found) {
                    [void]$script:AppData.Games.Add($item)
                }
                Save-LibraryData
                Update-GamesView
                Invoke-ViewAnimation
                $FooterStatusText.Text = "Se anadieron $($found.Count) juego(s) desde $selPath"
                [System.Windows.MessageBox]::Show("Se detectaron y anadieron $($found.Count) juego(s) desde la carpeta seleccionada.", "Carpeta Escaneada", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            } else {
                [System.Windows.MessageBox]::Show("No se encontraron juegos nuevos en esa carpeta (o ya estaban en tu biblioteca).", "Carpeta Escaneada", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            }
        }
    }
})

($Window.FindName("NavAllBtn")).Add_Click({
    $script:FilterFavoritesOnly = $false
    Update-GamesView
    Show-AppSection "Library"
    $FooterStatusText.Text = "Mostrando todos los juegos de la biblioteca."
})

($Window.FindName("NavFavBtn")).Add_Click({
    $script:FilterFavoritesOnly = $true
    Update-GamesView
    Show-AppSection "Library"
    $FooterStatusText.Text = "Mostrando tus juegos favoritos."
})

($Window.FindName("NavHistoryBtn")).Add_Click({
    Update-HistoryView
    Show-AppSection "History"
    $FooterStatusText.Text = "Mostrando el historial de juegos iniciados."
})

($Window.FindName("NavSettingsBtn")).Add_Click({
    Show-AppSection "Settings"
    $FooterStatusText.Text = "Configuracion y copias de seguridad."
})

($Window.FindName("VerifyPathsBtn")).Add_Click({
    $missing = 0
    foreach ($g in $script:AppData.Games) {
        Update-GameComputedProps -Game $g -RefreshImage $false
        if (-not $g.IsAvailable) { $missing++ }
    }
    Update-GamesView
    if ($missing -eq 0) {
        [System.Windows.MessageBox]::Show("Todos los juegos de tu biblioteca tienen rutas validas y estan listos para jugar.", "Verificacion Completada", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    } else {
        [System.Windows.MessageBox]::Show("Se detectaron $missing juego(s) cuya ruta ya no existe.`nPulsa 'Imagen / Ruta' en su tarjeta para actualizarla.", "Verificacion Completada", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
})

$SearchBox.Add_TextChanged({ Update-GamesView })
$OnlyAvailableCheck.Add_Checked({ Update-GamesView })
$OnlyAvailableCheck.Add_Unchecked({ Update-GamesView })
$SortComboBox.Add_SelectionChanged({ Update-GamesView })

[System.Windows.RoutedEventHandler]$cardBtnHandler = {
    param($sender, $e)
    $dep = $e.OriginalSource
    while ($null -ne $dep -and -not ($dep -is [System.Windows.Controls.Button])) {
        if ($dep -is [System.Windows.Media.Visual]) {
            $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
        } elseif ($dep -is [System.Windows.FrameworkContentElement]) {
            $dep = $dep.Parent
        } else {
            $dep = $null
        }
    }
    if ($null -eq $dep) { return }
    $btn = [System.Windows.Controls.Button]$dep
    $gid = [string]$btn.Tag
    if ([string]::IsNullOrWhiteSpace($gid)) { return }
    $game = $script:AppData.Games | Where-Object { $_.Id -eq $gid } | Select-Object -First 1
    if ($null -eq $game) { return }

    switch ($btn.Uid) {
        "Play"   { Invoke-PlayGame $game }
        "Edit"   { Open-EditModal $game }
        "Remove" { Remove-GameEntry $game }
        "Fav"    {
            $game.IsFavorite = -not [bool]$game.IsFavorite
            Update-GameComputedProps -Game $game -RefreshImage $false
            Save-LibraryData
            Update-GamesView
        }
    }
}
$GamesItemsControl.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $cardBtnHandler)

($Window.FindName("BrowseExeBtn")).Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Seleccionar archivo ejecutable del juego (.exe)"
    $dlg.Filter = "Ejecutables de Windows (*.exe)|*.exe|Todos los archivos (*.*)|*.*"
    if ($dlg.ShowDialog() -eq $true) {
        $ModalExePathBox.Text = $dlg.FileName
        if ([string]::IsNullOrWhiteSpace($ModalTitleBox.Text)) {
            try {
                $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dlg.FileName)
                if (-not [string]::IsNullOrWhiteSpace($vi.ProductName)) {
                    $ModalTitleBox.Text = $vi.ProductName.Trim()
                } else {
                    $ModalTitleBox.Text = [System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
                }
            } catch {
                $ModalTitleBox.Text = [System.IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
            }
        }
    }
})

($Window.FindName("BrowseCoverBtn")).Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Seleccionar imagen (.jpg, .jpeg, .png, .ico, .webp)"
    $dlg.Filter = "Imagenes e Iconos (*.jpg;*.jpeg;*.png;*.ico;*.webp;*.jfif;*.bmp)|*.jpg;*.jpeg;*.png;*.ico;*.webp;*.jfif;*.bmp|Todos los archivos (*.*)|*.*"
    if ($dlg.ShowDialog() -eq $true) {
        try {
            $coversDir = Join-Path $script:AppDataDir "covers"
            if (-not (Test-Path $coversDir)) { New-Item -ItemType Directory -Path $coversDir -Force | Out-Null }
            $ext = [System.IO.Path]::GetExtension($dlg.FileName)
            if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".png" }
            $destCover = Join-Path $coversDir ("cover_" + [Guid]::NewGuid().ToString("N") + $ext)
            Copy-Item -LiteralPath $dlg.FileName -Destination $destCover -Force
            $ModalCoverPathBox.Text = $destCover
        } catch {
            $ModalCoverPathBox.Text = $dlg.FileName
        }
    }
})

($Window.FindName("ClearCoverBtn")).Add_Click({
    $ModalCoverPathBox.Text = ""
})

($Window.FindName("CancelModalBtn")).Add_Click({
    $GameModalOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $script:EditingGameId = $null
})

($Window.FindName("SaveModalBtn")).Add_Click({
    $exeP = ""
    if ($null -ne $ModalExePathBox.Text) { $exeP = $ModalExePathBox.Text.Trim().Trim('"') }
    $titleP = ""
    if ($null -ne $ModalTitleBox.Text) { $titleP = $ModalTitleBox.Text.Trim() }
    $covP = ""
    if ($null -ne $ModalCoverPathBox.Text) { $covP = $ModalCoverPathBox.Text.Trim().Trim('"') }
    $argsP = ""
    if ($null -ne $ModalArgsBox.Text) { $argsP = $ModalArgsBox.Text.Trim() }

    if ([string]::IsNullOrWhiteSpace($exeP)) {
        [System.Windows.MessageBox]::Show("Debes seleccionar o escribir la ruta del archivo ejecutable (.exe).", "Datos incompletos", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($titleP)) {
        $titleP = [System.IO.Path]::GetFileNameWithoutExtension($exeP)
    }

    $script:ImageCache.Clear()

    if ([string]::IsNullOrWhiteSpace($script:EditingGameId)) {
        $newG = New-GameObject -Title $titleP -ExecutablePath $exeP -CustomCoverPath $covP -Arguments $argsP -PlatformSource "Personalizado"
        [void]$script:AppData.Games.Add($newG)
        $FooterStatusText.Text = "Juego anadido: $titleP"
    } else {
        for ($i = 0; $i -lt $script:AppData.Games.Count; $i++) {
            if ($script:AppData.Games[$i].Id -eq $script:EditingGameId) {
                $oldG = $script:AppData.Games[$i]
                $script:AppData.Games[$i] = New-GameObject `
                    -Id $oldG.Id `
                    -Title $titleP `
                    -ExecutablePath $exeP `
                    -Arguments $argsP `
                    -CustomCoverPath $covP `
                    -PlatformSource $oldG.PlatformSource `
                    -IsFavorite ([bool]$oldG.IsFavorite) `
                    -LastPlayedIso $oldG.LastPlayedIso `
                    -PlayCount ([int]$oldG.PlayCount)
                $FooterStatusText.Text = "Imagen actualizada correctamente para: $titleP"
                break
            }
        }
    }
    Save-LibraryData
    $GameModalOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $script:EditingGameId = $null
    Update-GamesView
})

($Window.FindName("ClearHistoryBtn")).Add_Click({
    $script:AppData.History.Clear()
    Save-LibraryData
    Update-HistoryView
    $FooterStatusText.Text = "Historial limpiado."
})

$settingsChangedAction = {
    $script:AppData.AutoScanOnStartup = ($AutoScanStartupCheck.IsChecked -eq $true)
    $script:AppData.MinimizeOnLaunch = ($MinimizeOnLaunchCheck.IsChecked -eq $true)
    $script:AppData.HighContrastBorders = ($HighContrastBorderCheck.IsChecked -eq $true)
    Save-LibraryData
    Update-VisualTheme
}
$AutoScanStartupCheck.Add_Click($settingsChangedAction)
$MinimizeOnLaunchCheck.Add_Click($settingsChangedAction)
$HighContrastBorderCheck.Add_Click($settingsChangedAction)

($Window.FindName("ExportLibraryBtn")).Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title = "Exportar biblioteca de GameLauncher"
    $dlg.Filter = "Archivo JSON (*.json)|*.json"
    $dlg.FileName = "GameLauncher_Backup_{0:yyyyMMdd}.json" -f (Get-Date)
    if ($dlg.ShowDialog() -eq $true) {
        Copy-Item -Path $script:LibraryFile -Destination $dlg.FileName -Force
        [System.Windows.MessageBox]::Show("Biblioteca exportada correctamente.", "Exportacion completada", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    }
})

($Window.FindName("ImportLibraryBtn")).Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Importar biblioteca de GameLauncher"
    $dlg.Filter = "Archivo JSON (*.json)|*.json"
    if ($dlg.ShowDialog() -eq $true) {
        try {
            $raw = Get-Content -Path $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
            $added = 0
            if ($null -ne $raw.Games) {
                foreach ($ig in $raw.Games) {
                    $exists = $script:AppData.Games | Where-Object { $_.ExecutablePath -eq $ig.ExecutablePath } | Select-Object -First 1
                    if ($null -eq $exists) {
                        $obj = New-GameObject -Title ([string]$ig.Title) -ExecutablePath ([string]$ig.ExecutablePath) -CustomCoverPath ([string]$ig.CustomCoverPath) -Arguments ([string]$ig.Arguments) -PlatformSource ([string]$ig.PlatformSource) -IsFavorite ([bool]$ig.IsFavorite)
                        [void]$script:AppData.Games.Add($obj)
                        $added++
                    }
                }
                Save-LibraryData
                Update-GamesView
                [System.Windows.MessageBox]::Show("Se importaron $added juego(s) nuevo(s).", "Importacion completada", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
        } catch {
            [System.Windows.MessageBox]::Show("Error al importar el archivo JSON:`n$($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    }
})

($Window.FindName("OpenDataFolderBtn")).Add_Click({
    if (-not (Test-Path $script:AppDataDir)) { New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null }
    Start-Process -FilePath $script:AppDataDir
})

$AutoScanStartupCheck.IsChecked = [bool]$script:AppData.AutoScanOnStartup
$MinimizeOnLaunchCheck.IsChecked = [bool]$script:AppData.MinimizeOnLaunch
$HighContrastBorderCheck.IsChecked = [bool]$script:AppData.HighContrastBorders
$LocalDataPathText.Text = "Ubicacion de datos: $script:AppDataDir"

Update-VisualTheme
Update-GamesView
Update-HistoryView

# Temporizador de inicio seguro para animar la entrada y buscar juegos sin bloquear la ventana
$script:StartupTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:StartupTimer.Interval = [TimeSpan]::FromMilliseconds(160)
$script:StartupTimer.Add_Tick({
    $script:StartupTimer.Stop()
    Invoke-ViewAnimation
    if ($script:AppData.AutoScanOnStartup -or $script:AppData.Games.Count -eq 0) {
        Start-AutoScanGames $true
    }
})
$script:StartupTimer.Start()

[void]$Window.ShowDialog()

} catch {
    [System.Windows.MessageBox]::Show("Error al abrir GameLauncher Neon:`n`n" + $_.Exception.Message + "`n`nLinea: " + $_.InvocationInfo.ScriptLineNumber, "Diagnostico GameLauncher Neon", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
}