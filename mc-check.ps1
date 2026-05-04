# mc-check.ps1 - Krom SS Tools
# Usage: irm https://raw.githubusercontent.com/kromilio/krom-ss-tools/main/mc-check.ps1 | iex

$results = @{}

# --- MOD SCANNER ---
$section = "MOD SCANNER"
$results[$section] = @()
$knownCheats = @("wurst","meteor","liquidbounce","aristois","sigma","impact","future","inertia","novoline","xaero","baritone","nodus","vape","huzuni","cheating-essentials","wolfram","rusherhack")
$modsFolder = "$env:APPDATA\.minecraft\mods"
if (Test-Path $modsFolder) {
    $jars = Get-ChildItem $modsFolder -Filter "*.jar" -ErrorAction SilentlyContinue
    if ($jars.Count -eq 0) {
        $results[$section] += "[OK] No jars found in mods folder"
    } else {
        $jars | ForEach-Object {
            $flagged = $false
            foreach ($cheat in $knownCheats) {
                if ($_.Name -match $cheat) {
                    $results[$section] += "[FLAGGED] $($_.Name) -> matches known cheat '$cheat'"
                    $flagged = $true
                }
            }
            if (-not $flagged) {
                $results[$section] += "[OK] $($_.Name) | modified: $($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
            }
        }
    }
} else {
    $results[$section] += "[OK] No mods folder found at $modsFolder"
}

# --- RENAMED JARS ---
$section = "RENAMED JARS"
$results[$section] = @()
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $modsFolder) {
        $jars = Get-ChildItem $modsFolder -Filter "*.jar" -ErrorAction SilentlyContinue
        if ($jars.Count -eq 0) {
            $results[$section] += "[OK] No jars to check"
        } else {
            $jars | ForEach-Object {
                try {
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($_.FullName)
                    $manifest = $zip.Entries | Where-Object { $_.FullName -match "fabric.mod.json|mods.toml|mcmod.info" }
                    if ($manifest) {
                        $reader = New-Object System.IO.StreamReader($manifest[0].Open())
                        $content = $reader.ReadToEnd()
                        $reader.Close()
                        if ($content -match '"modid"\s*:\s*"([^"]+)"') {
                            $internalId = $matches[1]
                            if ($_.BaseName -notmatch $internalId -and $internalId -notmatch $_.BaseName) {
                                $results[$section] += "[MISMATCH] $($_.Name) -> internal ID: '$internalId'"
                            } else {
                                $results[$section] += "[OK] $($_.Name) -> ID matches: '$internalId'"
                            }
                        } else {
                            $results[$section] += "[WARN] $($_.Name) -> no mod ID found in manifest"
                        }
                    } else {
                        $results[$section] += "[WARN] $($_.Name) -> no manifest found inside jar"
                    }
                    $zip.Dispose()
                } catch {
                    $results[$section] += "[WARN] $($_.Name) -> could not read jar"
                }
            }
        }
    } else {
        $results[$section] += "[OK] No mods folder to check"
    }
} catch {
    $results[$section] += "[WARN] Could not load compression library"
}

# --- RECYCLE BIN ---
$section = "RECYCLE BIN"
$results[$section] = @()
try {
    $shell = New-Object -ComObject Shell.Application
    $bin = $shell.Namespace(0xA)
    $binItems = $bin.Items()
    if ($binItems.Count -eq 0) {
        $results[$section] += "[OK] Recycle bin is empty"
    } else {
        $binItems | ForEach-Object {
            $name = $_.Name
            $path = $_.Path
            if ($name -match "\.jar|minecraft|mods") {
                $results[$section] += "[FLAGGED] $name (from: $path)"
            } else {
                $results[$section] += "[INFO] $name"
            }
        }
    }
} catch {
    $results[$section] += "[WARN] Could not read recycle bin"
}

# --- DELETED FILES (Event Log) ---
$section = "DELETED FILES"
$results[$section] = @()
try {
    $events = Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4663]]" -MaxEvents 100 -ErrorAction Stop
    $found = $events | Where-Object { $_.Message -match "\.jar|\\mods\\|minecraft" }
    if ($found.Count -eq 0) {
        $results[$section] += "[OK] No relevant deletions found in event log"
    } else {
        $found | ForEach-Object {
            $msg = $_.Message
            if ($msg -match 'Object Name:\s+(.+)') {
                $results[$section] += "[FLAGGED] $($_.TimeCreated.ToString('yyyy-MM-dd HH:mm')) - $($matches[1].Trim())"
            }
        }
    }
} catch {
    $results[$section] += "[WARN] Security log not accessible - run as administrator for this check"
}

# --- RECENTLY MODIFIED ---
$section = "RECENTLY MODIFIED"
$results[$section] = @()
$mcPath = "$env:APPDATA\.minecraft"
if (Test-Path $mcPath) {
    $recent = Get-ChildItem $mcPath -Recurse -Filter "*.jar" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) }
    if ($recent.Count -eq 0) {
        $results[$section] += "[OK] No jars modified in the last 7 days"
    } else {
        $recent | ForEach-Object {
            $results[$section] += "[WARN] $($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) - $($_.FullName.Replace($env:APPDATA, '%APPDATA%'))"
        }
    }
} else {
    $results[$section] += "[OK] No .minecraft folder found"
}

# --- BUILD JSON ---
$jsonParts = @()
foreach ($key in $results.Keys) {
    $lines = $results[$key] | ForEach-Object { $_ -replace '\\', '\\' -replace '"', '\"' }
    $linesJson = ($lines | ForEach-Object { "`"$_`"" }) -join ","
    $jsonParts += "`"$key`": [$linesJson]"
}
$json = "{" + ($jsonParts -join ",") + "}"

# --- DOWNLOAD HTML AND INJECT RESULTS ---
$htmlUrl = "https://raw.githubusercontent.com/kromilio/krom-ss-tools/main/index.html"
$html = (Invoke-RestMethod -Uri $htmlUrl)
$html = $html -replace '%%SCAN_RESULTS%%', $json
$html = $html -replace '%%SCAN_TIME%%', (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

# --- SAVE TO TEMP AND OPEN ---
$tempPath = "$env:TEMP\krom-ss-report-$(Get-Random).html"
$html | Out-File -FilePath $tempPath -Encoding UTF8
Start-Process $tempPath

Write-Host ""
Write-Host "===== KROM SS TOOLS =====" -ForegroundColor Cyan
Write-Host "Scan complete. Opening report in browser..." -ForegroundColor Green
Write-Host "Temp file: $tempPath" -ForegroundColor DarkGray
Write-Host ""
