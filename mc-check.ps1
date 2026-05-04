# minecraft-cheat-check.ps1

Write-Host "===== MINECRAFT CHEAT MOD DETECTOR =====" -ForegroundColor Cyan

# --- RECYCLE BIN HISTORY ---
Write-Host "`n[RECYCLE BIN]" -ForegroundColor Yellow
$shell = New-Object -ComObject Shell.Application
$bin = $shell.Namespace(0xA)
$binItems = $bin.Items()

if ($binItems.Count -eq 0) {
    Write-Host "  Recycle Bin is empty"
} else {
    $binItems | ForEach-Object {
        Write-Host "  $($_.Name) (deleted from: $($_.ExtendedProperty('infotip')))"
    }
}

# --- RECENTLY DELETED FILES (Event Log method) ---
Write-Host "`n[RECENTLY DELETED FILES - Event Log]" -ForegroundColor Yellow
try {
    Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4663]]" -MaxEvents 50 -ErrorAction Stop |
    Where-Object { $_.Message -match "\.jar|mods|minecraft" } |
    ForEach-Object {
        Write-Host "  $($_.TimeCreated) - $($_.Message -match 'Object Name:\s+(.+)' | Out-Null; $matches[1])"
    }
} catch {
    Write-Host "  (Security log not accessible - run as admin)" -ForegroundColor DarkGray
}

# --- MINECRAFT MODS FOLDER ---
Write-Host "`n[CURRENT MODS]" -ForegroundColor Yellow
$modPaths = @(
    "$env:APPDATA\.minecraft\mods",
    "$env:APPDATA\.minecraft\mods\1.*"
)
foreach ($path in $modPaths) {
    if (Test-Path $path) {
        Get-ChildItem $path -Filter "*.jar" | ForEach-Object {
            Write-Host "  $($_.Name) | Modified: $($_.LastWriteTime)"
        }
    }
}

# --- RENAMED FILES ---
Write-Host "`n[SUSPICIOUS RENAMED JARS]" -ForegroundColor Yellow
$modsFolder = "$env:APPDATA\.minecraft\mods"
if (Test-Path $modsFolder) {
    Get-ChildItem $modsFolder -Filter "*.jar" | ForEach-Object {
        $jar = $_.FullName
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($jar)
            $manifest = $zip.Entries | Where-Object { $_.FullName -match "fabric.mod.json|mods.toml|mcmod.info" }
            if ($manifest) {
                $reader = New-Object System.IO.StreamReader($manifest[0].Open())
                $content = $reader.ReadToEnd()
                $reader.Close()
                if ($content -match '"modid"\s*:\s*"([^"]+)"') {
                    $internalId = $matches[1]
                    if ($_.BaseName -notmatch $internalId -and $internalId -notmatch $_.BaseName) {
                        Write-Host "  MISMATCH: $($_.Name) -> internal ID: '$internalId'" -ForegroundColor Red
                    }
                }
            }
            $zip.Dispose()
        } catch {}
    }
}

# --- KNOWN CHEAT SIGNATURES ---
Write-Host "`n[KNOWN CHEAT SIGNATURES]" -ForegroundColor Yellow
$knownCheats = @("wurst", "meteor", "xaero", "baritone", "liquidbounce", "aristois", "sigma", "impact", "future", "inertia", "novoline")
$modsFolder = "$env:APPDATA\.minecraft\mods"
if (Test-Path $modsFolder) {
    Get-ChildItem $modsFolder -Filter "*.jar" | ForEach-Object {
        foreach ($cheat in $knownCheats) {
            if ($_.Name -match $cheat) {
                Write-Host "  FLAGGED: $($_.Name) matches '$cheat'" -ForegroundColor Red
            }
        }
    }
}

# --- RECENTLY MODIFIED FILES ---
Write-Host "`n[RECENTLY MODIFIED .minecraft FILES (last 7 days)]" -ForegroundColor Yellow
Get-ChildItem "$env:APPDATA\.minecraft" -Recurse -Filter "*.jar" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
    ForEach-Object {
        Write-Host "  $($_.LastWriteTime) - $($_.FullName.Replace($env:APPDATA, '%APPDATA%'))"
    }

Write-Host "`n===== DONE =====" -ForegroundColor Cyan
