# Krom SS Tools - WPF GUI
# Usage: irm https://raw.githubusercontent.com/kromilio/krom-ss-tools/main/mc-check.ps1 | iex

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.IO.Compression.FileSystem

$global:CustomModsPath = "$env:APPDATA\.minecraft\mods"
$global:ScanResults    = [ordered]@{}

# ── Checks ─────────────────────────────────────────────────────────────────────
function Run-Checks($modsFolder) {
    $results     = [ordered]@{}
    $knownCheats = @("wurst","meteor","liquidbounce","aristois","sigma","impact","future","inertia","novoline","xaero","baritone","nodus","vape","huzuni","wolfram","rusherhack")

    $s = "MOD SCANNER"; $results[$s] = @()
    if (Test-Path $modsFolder) {
        $jars = Get-ChildItem $modsFolder -Filter "*.jar" -ErrorAction SilentlyContinue
        if ($jars.Count -eq 0) {
            $results[$s] += @{ Line="No jars found in mods folder"; Type="OK" }
        } else {
            foreach ($jar in $jars) {
                $flagged = $false
                foreach ($cheat in $knownCheats) {
                    if ($jar.Name -match $cheat) {
                        $results[$s] += @{ Line="[FLAGGED]  $($jar.Name)  ->  '$cheat'"; Type="FLAG" }
                        $flagged = $true; break
                    }
                }
                if (-not $flagged) {
                    $results[$s] += @{ Line="[OK]  $($jar.Name)  |  $($jar.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"; Type="OK" }
                }
            }
        }
    } else {
        $results[$s] += @{ Line="Path not found: $modsFolder"; Type="WARN" }
    }

    $s = "RENAMED JARS"; $results[$s] = @()
    if (Test-Path $modsFolder) {
        $jars = Get-ChildItem $modsFolder -Filter "*.jar" -ErrorAction SilentlyContinue
        if ($jars.Count -eq 0) {
            $results[$s] += @{ Line="No jars to check"; Type="OK" }
        } else {
            foreach ($jar in $jars) {
                try {
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($jar.FullName)
                    $internalNames = @()

                    # fabric.mod.json - id and name fields
                    $fe = $zip.Entries | Where-Object { $_.FullName -eq "fabric.mod.json" }
                    if ($fe) {
                        $r = New-Object System.IO.StreamReader($fe.Open())
                        $c = $r.ReadToEnd(); $r.Close()
                        if ($c -match '"id"\s*:\s*"([^"]+)"')   { $internalNames += $matches[1] }
                        if ($c -match '"name"\s*:\s*"([^"]+)"') { $internalNames += $matches[1] }
                    }

                    # quilt.mod.json
                    $qe = $zip.Entries | Where-Object { $_.FullName -eq "quilt.mod.json" }
                    if ($qe) {
                        $r = New-Object System.IO.StreamReader($qe.Open())
                        $c = $r.ReadToEnd(); $r.Close()
                        if ($c -match '"id"\s*:\s*"([^"]+)"')   { $internalNames += $matches[1] }
                        if ($c -match '"name"\s*:\s*"([^"]+)"') { $internalNames += $matches[1] }
                    }

                    # mods.toml - modId and displayName
                    $te = $zip.Entries | Where-Object { $_.FullName -match "mods\.toml$" }
                    if ($te) {
                        $r = New-Object System.IO.StreamReader($te[0].Open())
                        $c = $r.ReadToEnd(); $r.Close()
                        if ($c -match 'modId\s*=\s*"([^"]+)"')      { $internalNames += $matches[1] }
                        if ($c -match 'displayName\s*=\s*"([^"]+)"') { $internalNames += $matches[1] }
                    }

                    # mcmod.info
                    $me = $zip.Entries | Where-Object { $_.FullName -eq "mcmod.info" }
                    if ($me) {
                        $r = New-Object System.IO.StreamReader($me.Open())
                        $c = $r.ReadToEnd(); $r.Close()
                        if ($c -match '"modid"\s*:\s*"([^"]+)"') { $internalNames += $matches[1] }
                        if ($c -match '"name"\s*:\s*"([^"]+)"')  { $internalNames += $matches[1] }
                    }

                    $zip.Dispose()

                    if ($internalNames.Count -eq 0) {
                        $results[$s] += @{ Line="[WARN]  $($jar.Name)  ->  no manifest found"; Type="WARN" }
                    } else {
                        $fileBase = ($jar.BaseName -replace '[^a-zA-Z0-9]','').ToLower()
                        $matched  = $false
                        foreach ($n in $internalNames) {
                            $cleanN = ($n -replace '[^a-zA-Z0-9]','').ToLower()
                            if ($cleanN.Length -lt 3) { continue }
                            if ($fileBase -match $cleanN -or $cleanN -match $fileBase) {
                                $matched = $true; break
                            }
                            # partial match on first 5+ chars
                            if ($cleanN.Length -ge 5 -and $fileBase -match $cleanN.Substring(0, [Math]::Min(6,$cleanN.Length))) {
                                $matched = $true; break
                            }
                        }
                        $primary = $internalNames[0]
                        $cheatKeywords = @("mace","catlean","meteor","multi","shieldbreak","spear","wurst","xp","fast","accurate")
                        $keywordHit = ""
                        foreach ($kw in $cheatKeywords) {
                            $allText = ($internalNames -join " ").ToLower()
                            if ($allText -match $kw) { $keywordHit = $kw; break }
                        }
                        # Random/gibberish name detection
                        # Strip version suffixes like -1.21.11, +mc1.21, _fabric, -forge etc
                        # so "schlib-1.2.1+1.21.11-fabric" becomes just "schlib"
                        $strippedName = $jar.BaseName
                        $strippedName = $strippedName -replace '-\d[\d\.\+\-mc]+.*$',''
                        $strippedName = $strippedName -replace '[_-](fabric|forge|quilt|neoforge|bukkit|spigot|paper).*$',''
                        $strippedName = $strippedName -replace '\+.*$',''
                        $baseName     = $strippedName -replace '[^a-zA-Z0-9]',''
                        $digitCount   = ($baseName -replace '[^0-9]','').Length
                        $vowelCount   = ($baseName -replace '[^aeiouAEIOU]','').Length
                        $totalLen     = $baseName.Length
                        $isGibberish  = $false
                        if ($totalLen -ge 5) {
                            $digitRatio = if ($totalLen -gt 0) { $digitCount / $totalLen } else { 0 }
                            $vowelRatio = if ($totalLen -gt 0) { $vowelCount / $totalLen } else { 0 }
                            # Only flag if stripped name is still mostly digits or has no vowels at all
                            if ($digitRatio -gt 0.6) { $isGibberish = $true }
                            elseif ($vowelRatio -eq 0 -and $totalLen -ge 6) { $isGibberish = $true }
                            # Flag pure hex strings 8+ chars (e.g. a3f9bc12d7)
                            elseif ($baseName -match '^[0-9a-fA-F]{8,}$') { $isGibberish = $true }
                        }

                        if (-not $matched) {
                            $results[$s] += @{ Line="[MISMATCH]  $($jar.Name)  ->  internal: '$primary'"; Type="FLAG" }
                        } elseif ($isGibberish) {
                            $results[$s] += @{ Line="[FLAGGED]  $($jar.Name)  ->  random/gibberish filename"; Type="FLAG" }
                        } elseif ($keywordHit -ne "") {
                            $results[$s] += @{ Line="[FLAGGED]  $($jar.Name)  ->  keyword match: '$keywordHit' in '$primary'"; Type="FLAG" }
                        } else {
                            $results[$s] += @{ Line="[OK]  $($jar.Name)  ->  '$primary'"; Type="OK" }
                        }
                    }
                } catch {
                    $results[$s] += @{ Line="[WARN]  $($jar.Name)  ->  could not read"; Type="WARN" }
                }
            }
        }
    } else {
        $results[$s] += @{ Line="No mods folder to check"; Type="OK" }
    }

    $s = "RECYCLE BIN"; $results[$s] = @()

    # ── Currently in the bin ──
    $results[$s] += @{ Line="-- CURRENTLY IN BIN --"; Type="HEAD" }
    try {
        $shell = New-Object -ComObject Shell.Application
        $items = $shell.Namespace(0xA).Items()
        if ($items.Count -eq 0) {
            $results[$s] += @{ Line="[OK]  Recycle bin is empty"; Type="OK" }
        } else {
            foreach ($item in $items) {
                if ($item.Name -match "\.jar|minecraft|mods") {
                    $results[$s] += @{ Line="[FLAGGED]  $($item.Name)"; Type="FLAG" }
                } else {
                    $results[$s] += @{ Line="[INFO]  $($item.Name)"; Type="INFO" }
                }
            }
        }
    } catch {
        $results[$s] += @{ Line="[WARN]  Could not read recycle bin contents"; Type="WARN" }
    }

    # ── Currently in bin (still recoverable, before permanent deletion) ──
    # (already scanned above)

    # ── Permanently deleted via $Recycle.Bin metadata (last 3 days) ──
    # Reads $I metadata files which persist briefly even after bin is emptied
    $results[$s] += @{ Line="-- PERMANENTLY DELETED (last 3 days) --"; Type="HEAD" }
    try {
        $cutoff = (Get-Date).AddDays(-3)
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match "^[A-Z]:\\$" -and (Test-Path "$($_.Root)`$Recycle.Bin") }
        $foundCount = 0

        foreach ($drive in $drives) {
            $recyclePath = "$($drive.Root)`$Recycle.Bin"
            $iFiles = Get-ChildItem $recyclePath -Recurse -Filter '$I*' -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt $cutoff }
            foreach ($iFile in $iFiles) {
                try {
                    $bytes    = [System.IO.File]::ReadAllBytes($iFile.FullName)
                    if ($bytes.Length -lt 28) { continue }
                    $nameLen  = [BitConverter]::ToInt32($bytes, 24)
                    $maxRead  = [Math]::Min($nameLen * 2, $bytes.Length - 28)
                    if ($maxRead -le 0) { continue }
                    $origName = [System.Text.Encoding]::Unicode.GetString($bytes, 28, $maxRead).TrimEnd([char]0)
                    $delTime  = $iFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    $display  = if ($origName) { $origName } else { $iFile.Name }
                    $isFlag = $false
                    if ($display -match "\.jar$|minecraft|mods|cheat|hack|wurst|meteor|doomsday|inject|prestige|krypton|vape|catlean|macecore|spearcore") {
                        $isFlag = $true
                    }
                    if ($isFlag) {
                        $results[$s] += @{ Line="[FLAGGED]  $display  |  deleted: $delTime"; Type="FLAG" }
                    } else {
                        $results[$s] += @{ Line="[INFO]  $display  |  deleted: $delTime"; Type="INFO" }
                    }
                    $foundCount++
                } catch {}
            }
        }
        if ($foundCount -eq 0) {
            $results[$s] += @{ Line="[OK]  No permanently deleted files found in last 3 days"; Type="OK" }
        } else {
            $results[$s] += @{ Line="[INFO]  Found $foundCount permanent deletion record(s)"; Type="INFO" }
        }
    } catch {
        $results[$s] += @{ Line="[WARN]  Could not read deletion metadata: $($_.Exception.Message)"; Type="WARN" }
    }

    # ── File system events from event log ──
    # Captures any deletion that left a Windows event behind
    $results[$s] += @{ Line="-- FILE SYSTEM EVENTS (last 3 days) --"; Type="HEAD" }
    try {
        $cutoff = (Get-Date).AddDays(-3)
        $eventCount = 0

        # Try Security log event 4660 (object deleted) - requires audit policy
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName='Security'; ID=4660; StartTime=$cutoff
            } -MaxEvents 50 -ErrorAction Stop
            foreach ($ev in $events) {
                $msg = $ev.Message
                $obj = if ($msg -match "Object Name:\s+([^\r\n]+)") { $matches[1].Trim() } else { "(unknown)" }
                $when = $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                if ($obj -match "\.jar|minecraft|mods|cheat|hack|wurst|meteor|doomsday|prestige|krypton|vape|catlean") {
                    $results[$s] += @{ Line="[FLAGGED]  $when  ->  $obj"; Type="FLAG" }
                    $eventCount++
                }
            }
        } catch {}

        # Try System log for any related events
        try {
            $sysEvents = Get-WinEvent -FilterHashtable @{
                LogName='System'; StartTime=$cutoff
            } -MaxEvents 200 -ErrorAction SilentlyContinue |
                Where-Object { $_.Message -match "\.jar|cheat|inject|wurst|meteor|doomsday|prestige|krypton" }
            foreach ($ev in $sysEvents) {
                $when = $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                $shortMsg = ($ev.Message -split "`n")[0].Trim()
                if ($shortMsg.Length -gt 100) { $shortMsg = $shortMsg.Substring(0, 100) + "..." }
                $results[$s] += @{ Line="[FLAGGED]  $when  ->  $shortMsg"; Type="FLAG" }
                $eventCount++
            }
        } catch {}

        if ($eventCount -eq 0) {
            $results[$s] += @{ Line="[OK]  No suspicious file events in logs"; Type="OK" }
            $results[$s] += @{ Line="  (Tip: enable Object Access auditing for more detail)"; Type="INFO" }
        }
    } catch {
        $results[$s] += @{ Line="[WARN]  Could not query event logs: $($_.Exception.Message)"; Type="WARN" }
    }

    # ── Security Event Log (4660 = object deleted) ──
    $results[$s] += @{ Line="-- SECURITY EVENT LOG (deletions, last 3 days) --"; Type="HEAD" }
    try {
        $cutoff = (Get-Date).AddDays(-3)
        $events = Get-WinEvent -FilterHashtable @{
            LogName='Security'; ID=4660; StartTime=$cutoff
        } -MaxEvents 100 -ErrorAction Stop
        if ($events.Count -eq 0) {
            $results[$s] += @{ Line="[OK]  No deletion events in last 3 days"; Type="OK" }
        } else {
            foreach ($ev in $events) {
                $msg = $ev.Message
                $obj = if ($msg -match "Object Name:\s+([^\r\n]+)") { $matches[1].Trim() } else { "(unknown)" }
                $when = $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                if ($obj -match "\.jar|minecraft|mods|cheat|hack|wurst|meteor|doomsday|inject|prestige|krypton") {
                    $results[$s] += @{ Line="[FLAGGED]  $when  ->  $obj"; Type="FLAG" }
                } else {
                    $results[$s] += @{ Line="[INFO]  $when  ->  $obj"; Type="INFO" }
                }
            }
        }
    } catch {
        $results[$s] += @{ Line="[WARN]  Event 4660 audit not enabled or admin needed — see notes below"; Type="WARN" }
        $results[$s] += @{ Line="  To enable: Local Security Policy > Audit Policy > Audit Object Access = Success+Failure"; Type="INFO" }
    }

    $s = "DELETED FILES"; $results[$s] = @()
    try {
        $events = Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4663]]" -MaxEvents 100 -ErrorAction Stop
        $found  = $events | Where-Object { $_.Message -match "\.jar|\\mods\\|minecraft" }
        if ($found.Count -eq 0) {
            $results[$s] += @{ Line="No relevant deletions in event log"; Type="OK" }
        } else {
            foreach ($ev in $found) {
                if ($ev.Message -match 'Object Name:\s+(.+)') {
                    $results[$s] += @{ Line="[FLAGGED]  $($ev.TimeCreated.ToString('yyyy-MM-dd HH:mm'))  ->  $($matches[1].Trim())"; Type="FLAG" }
                }
            }
        }
    } catch {
        $results[$s] += @{ Line="[WARN]  Run as Administrator for event log"; Type="WARN" }
    }

    $s = "RECENT CHANGES"; $results[$s] = @()
    $mcPath = "$env:APPDATA\.minecraft"
    if (Test-Path $mcPath) {
        $recent = Get-ChildItem $mcPath -Recurse -Filter "*.jar" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) }
        if ($recent.Count -eq 0) {
            $results[$s] += @{ Line="No jars modified in the last 7 days"; Type="OK" }
        } else {
            foreach ($f in $recent) {
                $results[$s] += @{ Line="[WARN]  $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))  ->  $($f.FullName.Replace($env:APPDATA,'%APPDATA%'))"; Type="WARN" }
            }
        }
    } else {
        $results[$s] += @{ Line="No .minecraft folder found"; Type="OK" }
    }

    $s = "PREFETCH SCAN"; $results[$s] = @()
    $prefetchPath = "C:\Windows\Prefetch"
    $cheatExes = @("javaw","minecraft","tlauncher","multimc","prismlauncher","curseforge","gdlauncher")
    if (Test-Path $prefetchPath) {
        try {
            $pfFiles = Get-ChildItem $prefetchPath -Filter "*.pf" -ErrorAction Stop |
                Sort-Object LastWriteTime -Descending
            $mcRelated = $pfFiles | Where-Object {
                $n = $_.Name.ToLower()
                $cheatExes | Where-Object { $n -match $_ }
            }
            $results[$s] += @{ Line="Total prefetch files:  $($pfFiles.Count)"; Type="INFO" }
            $results[$s] += @{ Line="Minecraft-related entries:  $($mcRelated.Count)"; Type="INFO" }
            if ($mcRelated.Count -eq 0) {
                $results[$s] += @{ Line="No Minecraft-related prefetch entries found"; Type="OK" }
            } else {
                foreach ($pf in $mcRelated) {
                    $results[$s] += @{ Line="[INFO]  $($pf.Name)  |  last run: $($pf.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"; Type="INFO" }
                }
            }
            # Flag any suspicious launcher prefetch
            $suspLaunchers = @("cheatbreaker","badlion","lunar","feather","salwyrr")
            foreach ($pf in $pfFiles) {
                foreach ($sus in $suspLaunchers) {
                    if ($pf.Name -match $sus) {
                        $results[$s] += @{ Line="[FLAGGED]  $($pf.Name)  ->  suspicious launcher"; Type="FLAG" }
                    }
                }
            }
            # Show recently run exes (last 24h)
            $recent = $pfFiles | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-24) }
            if ($recent.Count -gt 0) {
                $results[$s] += @{ Line="── Recently run (last 24h) ──"; Type="HEAD" }
                foreach ($pf in $recent) {
                    $results[$s] += @{ Line="  $($pf.Name)  |  $($pf.LastWriteTime.ToString('HH:mm'))"; Type="INFO" }
                }
            }
        } catch {
            $results[$s] += @{ Line="[WARN]  Run as Administrator to access Prefetch"; Type="WARN" }
        }
    } else {
        $results[$s] += @{ Line="[WARN]  Prefetch folder not found or not accessible"; Type="WARN" }
    }

    $s = "LOG SCANNER"; $results[$s] = @()
    # Placeholder — log scanner is manual, results populated separately
    $results[$s] += @{ Line="Use the Log Scanner tab to load a latest.log file"; Type="INFO" }

    # ── DOWNLOADS (last 30 days) ──
    $s = "DOWNLOADS"; $results[$s] = @()
    $cutoff = (Get-Date).AddDays(-30)

    # 1. Downloads folder contents
    $results[$s] += @{ Line="-- DOWNLOADS FOLDER --"; Type="HEAD" }
    $dlPath = "$env:USERPROFILE\Downloads"
    if (Test-Path $dlPath) {
        $dlFiles = Get-ChildItem $dlPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $cutoff } |
            Sort-Object LastWriteTime -Descending
        if ($dlFiles.Count -eq 0) {
            $results[$s] += @{ Line="[OK]  No files in Downloads folder from last 30 days"; Type="OK" }
        } else {
            foreach ($f in $dlFiles) {
                $when = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                $sizeKB = [Math]::Round($f.Length / 1KB, 0)
                $isFlag = $f.Name -match "\.jar$|\.exe$|cheat|hack|wurst|meteor|doomsday|prestige|krypton|vape|catlean|macecore|spearcore|inject|client"
                if ($isFlag) {
                    $results[$s] += @{ Line="[FLAGGED]  $($f.Name)  |  ${sizeKB}KB  |  $when"; Type="FLAG" }
                } else {
                    $results[$s] += @{ Line="[INFO]  $($f.Name)  |  ${sizeKB}KB  |  $when"; Type="INFO" }
                }
            }
        }
    } else {
        $results[$s] += @{ Line="[WARN]  Downloads folder not found"; Type="WARN" }
    }

    # 2. Mark of the Web - shows source URL of downloaded files
    $results[$s] += @{ Line="-- MARK OF THE WEB (source URLs) --"; Type="HEAD" }
    $motwFound = 0
    if (Test-Path $dlPath) {
        $jarsAndExes = Get-ChildItem $dlPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in ".jar",".exe",".zip",".rar",".7z",".msi" -and $_.LastWriteTime -gt $cutoff }
        foreach ($f in $jarsAndExes) {
            try {
                $zoneInfo = Get-Content "$($f.FullName):Zone.Identifier" -ErrorAction SilentlyContinue
                if ($zoneInfo) {
                    $sourceUrl = ($zoneInfo | Where-Object { $_ -match "^HostUrl=" }) -replace "^HostUrl=",""
                    $referrer  = ($zoneInfo | Where-Object { $_ -match "^ReferrerUrl=" }) -replace "^ReferrerUrl=",""
                    if (-not $sourceUrl) { $sourceUrl = ($zoneInfo | Where-Object { $_ -match "^HostUrl=|^ReferrerUrl=" }) -replace "^[^=]+=","" | Select-Object -First 1 }
                    if ($sourceUrl) {
                        $isFlag = $sourceUrl -match "cheat|hack|client|crack|leak|inject|prestige|krypton|doomsday|wurst|meteor|vape"
                        if ($isFlag) {
                            $results[$s] += @{ Line="[FLAGGED]  $($f.Name)  <-  $sourceUrl"; Type="FLAG" }
                        } else {
                            $results[$s] += @{ Line="[INFO]  $($f.Name)  <-  $sourceUrl"; Type="INFO" }
                        }
                        $motwFound++
                    }
                }
            } catch {}
        }
    }
    if ($motwFound -eq 0) {
        $results[$s] += @{ Line="[INFO]  No source URLs recorded for downloaded files"; Type="INFO" }
    }

    # 3. Browser download history
    $results[$s] += @{ Line="-- BROWSER DOWNLOAD HISTORY --"; Type="HEAD" }
    $browsers = @{
        "Chrome"  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History"
        "Edge"    = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History"
        "Brave"   = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\History"
        "Opera"   = "$env:APPDATA\Opera Software\Opera Stable\History"
    }
    $browserFound = 0
    foreach ($browser in $browsers.GetEnumerator()) {
        $histPath = $browser.Value
        if (-not (Test-Path $histPath)) { continue }
        # Copy to temp because browser locks the file
        $tempCopy = "$env:TEMP\krom_$($browser.Key)_history.tmp"
        try {
            Copy-Item $histPath $tempCopy -Force -ErrorAction Stop

            # Use System.Data.SQLite if available, otherwise raw read
            try {
                Add-Type -AssemblyName System.Data
                # PowerShell does not have built-in SQLite - use a lightweight reader
                # Read raw bytes and search for URLs in the downloads table
                $bytes = [System.IO.File]::ReadAllBytes($tempCopy)
                $text  = [System.Text.Encoding]::UTF8.GetString($bytes)

                # Find URL patterns near download markers
                $urls = [regex]::Matches($text, 'https?://[a-zA-Z0-9./?=&_%#:-]{10,300}') | Select-Object -ExpandProperty Value -Unique
                $relevantUrls = $urls | Where-Object {
                    $_ -match "\.jar|\.exe|\.zip|cheat|hack|client|inject|prestige|krypton|doomsday|wurst|meteor|vape|catlean|macecore|spearcore|crack|leak"
                } | Select-Object -First 20

                if ($relevantUrls) {
                    foreach ($url in $relevantUrls) {
                        $shortUrl = if ($url.Length -gt 90) { $url.Substring(0, 90) + "..." } else { $url }
                        $isFlag = $shortUrl -match "cheat|hack|client|crack|leak|inject|prestige|krypton|doomsday|wurst|meteor|vape|catlean|macecore|spearcore"
                        if ($isFlag) {
                            $results[$s] += @{ Line="[FLAGGED]  $($browser.Key)  ->  $shortUrl"; Type="FLAG" }
                        } else {
                            $results[$s] += @{ Line="[INFO]  $($browser.Key)  ->  $shortUrl"; Type="INFO" }
                        }
                        $browserFound++
                    }
                } else {
                    $results[$s] += @{ Line="[OK]  $($browser.Key) - no suspicious URLs found"; Type="OK" }
                }
            } finally {
                if (Test-Path $tempCopy) { Remove-Item $tempCopy -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            $results[$s] += @{ Line="[WARN]  $($browser.Key) - history locked or unreadable (close browser first)"; Type="WARN" }
        }
    }
    if ($browserFound -eq 0) {
        $results[$s] += @{ Line="[INFO]  No suspicious browser downloads found"; Type="INFO" }
    }

    # 4. AmCache - registry record of every executable run
    $results[$s] += @{ Line="-- AMCACHE (executables run, last 30 days) --"; Type="HEAD" }
    try {
        $amcachePath = "C:\Windows\AppCompat\Programs\Amcache.hve"
        if (Test-Path $amcachePath) {
            # AmCache is a registry hive that requires special tools to read offline
            # Use the live registry which has some of the same data
            $amcacheKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages"
            $userAssist = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\UserAssist"
            $amcacheFound = 0

            # Check UserAssist for recently run programs
            $uaKeys = Get-ChildItem $userAssist -ErrorAction SilentlyContinue
            foreach ($uaKey in $uaKeys) {
                $countKey = "$($uaKey.PSPath)\Count"
                if (Test-Path $countKey) {
                    $values = (Get-Item $countKey).Property
                    foreach ($name in $values) {
                        # ROT13 decode the value name
                        $decoded = -join ($name.ToCharArray() | ForEach-Object {
                            $c = [int][char]$_
                            if ($c -ge 65 -and $c -le 90)  { [char](((($c - 65 + 13) % 26) + 65)) }
                            elseif ($c -ge 97 -and $c -le 122) { [char](((($c - 97 + 13) % 26) + 97)) }
                            else { [char]$c }
                        })
                        if ($decoded -match "\.exe$|\.jar$" -and $decoded -match "cheat|hack|client|inject|prestige|krypton|doomsday|wurst|meteor|vape|catlean|macecore|spearcore|launcher") {
                            $isFlag = $decoded -match "cheat|hack|inject|prestige|krypton|doomsday|wurst|meteor|vape|catlean|macecore|spearcore"
                            $shortDec = if ($decoded.Length -gt 100) { $decoded.Substring(0, 100) + "..." } else { $decoded }
                            if ($isFlag) {
                                $results[$s] += @{ Line="[FLAGGED]  $shortDec"; Type="FLAG" }
                            } else {
                                $results[$s] += @{ Line="[INFO]  $shortDec"; Type="INFO" }
                            }
                            $amcacheFound++
                        }
                    }
                }
            }

            if ($amcacheFound -eq 0) {
                $results[$s] += @{ Line="[OK]  No suspicious programs in UserAssist registry"; Type="OK" }
            }
        } else {
            $results[$s] += @{ Line="[WARN]  AmCache.hve not accessible"; Type="WARN" }
        }
    } catch {
        $results[$s] += @{ Line="[WARN]  Could not read AmCache: $($_.Exception.Message)"; Type="WARN" }
    }

    return $results
}

# ── XAML ───────────────────────────────────────────────────────────────────────
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Krom SS Tools" Height="640" Width="980" MinHeight="500" MinWidth="750"
    Background="#0D0F12" Foreground="#E8EAF0"
    WindowStartupLocation="CenterScreen" ResizeMode="CanResize">

    <Window.Resources>
        <Style x:Key="NavBtn" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#6B7280"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Height" Value="36"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Padding" Value="16,0,0,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderThickness="2,0,0,0" BorderBrush="Transparent">
                            <ContentPresenter Margin="{TemplateBinding Padding}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#1A1E25"/>
                                <Setter Property="Foreground" Value="#E8EAF0"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="NavBtnActive" TargetType="Button" BasedOn="{StaticResource NavBtn}">
            <Setter Property="Background" Value="#1A1E25"/>
            <Setter Property="Foreground" Value="#E8EAF0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="#1A1E25" BorderThickness="2,0,0,0" BorderBrush="#4F8EF7">
                            <ContentPresenter Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ActionBtn" TargetType="Button">
            <Setter Property="Background" Value="#1A1E25"/>
            <Setter Property="Foreground" Value="#4F8EF7"/>
            <Setter Property="BorderBrush" Value="#282D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Padding" Value="20,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#22272F"/>
                                <Setter TargetName="bg" Property="BorderBrush" Value="#3A4150"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#13161B"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ScanBtn" TargetType="Button" BasedOn="{StaticResource ActionBtn}">
            <Setter Property="Foreground" Value="#4FF78E"/>
            <Setter Property="BorderBrush" Value="#2A4A38"/>
            <Setter Property="Background" Value="#0F1F16"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#16301F"/>
                                <Setter TargetName="bg" Property="BorderBrush" Value="#3D6B4F"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#0A1A11"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PathBox" TargetType="TextBox">
            <Setter Property="Background" Value="#1A1E25"/>
            <Setter Property="Foreground" Value="#E8EAF0"/>
            <Setter Property="BorderBrush" Value="#282D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Height" Value="28"/>
            <Setter Property="Padding" Value="8,0"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="CaretBrush" Value="#4F8EF7"/>
        </Style>

        <Style x:Key="ResultItem" TargetType="ListBoxItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <ContentPresenter/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="48"/>
            <RowDefinition Height="1"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Titlebar -->
        <Grid Grid.Row="0" Background="#13161B">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
                <Border Background="#4F8EF7" CornerRadius="5" Width="26" Height="26" Margin="0,0,10,0">
                    <TextBlock Text="K" FontFamily="Consolas" FontWeight="Bold" FontSize="13"
                               Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock Text="KROM " FontFamily="Consolas" FontWeight="Bold" FontSize="13"
                           Foreground="#4F8EF7" VerticalAlignment="Center"/>
                <TextBlock Text="SS TOOLS" FontFamily="Consolas" FontWeight="Bold" FontSize="13"
                           Foreground="#E8EAF0" VerticalAlignment="Center"/>
                <Border Background="#1A1E25" BorderBrush="#282D37" BorderThickness="1"
                        CornerRadius="3" Margin="10,0,0,0" Padding="6,2">
                    <TextBlock Text="v1.0" FontFamily="Consolas" FontSize="9" Foreground="#6B7280"/>
                </Border>
            </StackPanel>
            <TextBlock x:Name="StatusLabel" Text="● scanning..." FontFamily="Consolas" FontSize="10"
                       Foreground="#F7A94F" VerticalAlignment="Center" HorizontalAlignment="Right"
                       Margin="0,0,18,0"/>
        </Grid>

        <!-- Title border -->
        <Rectangle Grid.Row="1" Fill="#282D37"/>

        <!-- Main layout -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="195"/>
                <ColumnDefinition Width="1"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Sidebar -->
            <Grid Grid.Column="0" Background="#13161B">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Hidden">
                <StackPanel Margin="0,12,0,0">
                    <TextBlock Text="  CHECKS" FontFamily="Consolas" FontSize="8"
                               Foreground="#6B7280" Margin="0,0,0,6"/>

                    <Button x:Name="BtnOverview"      Content="  Overview"       Style="{StaticResource NavBtnActive}" Tag="OVERVIEW"/>
                    <Button x:Name="BtnModScanner"    Content="  Mod Scanner"    Style="{StaticResource NavBtn}"       Tag="MOD SCANNER"/>
                    <Button x:Name="BtnRenamedJars"   Content="  Renamed Jars"   Style="{StaticResource NavBtn}"       Tag="RENAMED JARS"/>
                    <Button x:Name="BtnRecycleBin"    Content="  Recycle Bin"    Style="{StaticResource NavBtn}"       Tag="RECYCLE BIN"/>
                    <Button x:Name="BtnDeletedFiles"  Content="  Deleted Files"  Style="{StaticResource NavBtn}"       Tag="DELETED FILES"/>
                    <Button x:Name="BtnRecentChanges" Content="  Recent Changes" Style="{StaticResource NavBtn}"       Tag="RECENT CHANGES"/>
                    <Button x:Name="BtnPrefetch"      Content="  Prefetch Scan"  Style="{StaticResource NavBtn}"       Tag="PREFETCH SCAN"/>
                    <Button x:Name="BtnLogScanner"    Content="  Log Scanner"    Style="{StaticResource NavBtn}"       Tag="LOG SCANNER"/>
                    <Button x:Name="BtnMemScan"       Content="  Memory Scan"    Style="{StaticResource NavBtn}"       Tag="MEMORY SCAN"/>
                    <Button x:Name="BtnDownloads"     Content="  Downloads"      Style="{StaticResource NavBtn}"       Tag="DOWNLOADS"/>

                    <Rectangle Height="1" Fill="#282D37" Margin="12,10"/>
                </StackPanel>
                </ScrollViewer>

                <Button x:Name="BtnRescan" Grid.Row="1" Content="↺  Rescan"
                        Style="{StaticResource ActionBtn}" Margin="12,0,12,14" Height="32"/>
            </Grid>

            <!-- Sidebar border -->
            <Rectangle Grid.Column="1" Fill="#282D37"/>

            <!-- Content area -->
            <Grid Grid.Column="2" x:Name="ContentGrid">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Section header -->
                <Grid Grid.Row="0" Margin="22,18,22,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                        <TextBlock x:Name="SectionTitle" Text="// OVERVIEW"
                                   FontFamily="Consolas" FontWeight="Bold" FontSize="15"
                                   Foreground="#E8EAF0"/>
                        <TextBlock x:Name="SectionSub" Text="All scan results"
                                   FontFamily="Segoe UI" FontSize="11" Foreground="#6B7280" Margin="0,3,0,0"/>
                    </StackPanel>

                    <!-- Mini overview card top right -->
                    <Border Grid.Column="1" x:Name="MiniCard" Background="#13161B"
                            BorderBrush="#282D37" BorderThickness="1" CornerRadius="6"
                            Padding="14,8" VerticalAlignment="Top">
                        <StackPanel Orientation="Horizontal">
                            <StackPanel Margin="0,0,16,0">
                                <TextBlock Text="FLAGGED" FontFamily="Consolas" FontSize="8"
                                           Foreground="#6B7280" Margin="0,0,0,2"/>
                                <TextBlock x:Name="MiniFlags" Text="0" FontFamily="Consolas"
                                           FontSize="18" FontWeight="Bold" Foreground="#F74F4F"/>
                            </StackPanel>
                            <StackPanel Margin="0,0,16,0">
                                <TextBlock Text="WARNINGS" FontFamily="Consolas" FontSize="8"
                                           Foreground="#6B7280" Margin="0,0,0,2"/>
                                <TextBlock x:Name="MiniWarns" Text="0" FontFamily="Consolas"
                                           FontSize="18" FontWeight="Bold" Foreground="#F7A94F"/>
                            </StackPanel>
                            <StackPanel>
                                <TextBlock Text="CLEAN" FontFamily="Consolas" FontSize="8"
                                           Foreground="#6B7280" Margin="0,0,0,2"/>
                                <TextBlock x:Name="MiniClean" Text="0" FontFamily="Consolas"
                                           FontSize="18" FontWeight="Bold" Foreground="#4FF78E"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                </Grid>

                <!-- Separator -->
                <Rectangle Grid.Row="1" Height="1" Fill="#282D37" Margin="22,12,22,0"/>

                <!-- Mod Scanner path bar -->
                <Border Grid.Row="2" x:Name="PathBar" Background="#13161B"
                        BorderBrush="#282D37" BorderThickness="0,0,0,1"
                        Padding="22,12" Visibility="Collapsed">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="8"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Mods folder:" FontFamily="Consolas" FontSize="10"
                                       Foreground="#6B7280" VerticalAlignment="Center"
                                       Margin="0,0,10,0" Grid.Column="0"/>
                            <TextBox x:Name="PathBox" Style="{StaticResource PathBox}" Grid.Column="1"/>
                        </Grid>
                        <Button x:Name="BtnScanFolder" Grid.Row="2" Content="Scan this folder"
                                Style="{StaticResource ScanBtn}" HorizontalAlignment="Left" Width="130"/>
                    </Grid>
                </Border>

                <!-- Log Scanner path bar -->
                <Border Grid.Row="2" x:Name="LogBar" Background="#13161B"
                        BorderBrush="#282D37" BorderThickness="0,0,0,1"
                        Padding="22,12" Visibility="Collapsed">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="8"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="latest.log path:" FontFamily="Consolas" FontSize="10"
                                       Foreground="#6B7280" VerticalAlignment="Center"
                                       Margin="0,0,10,0" Grid.Column="0"/>
                            <TextBox x:Name="LogPathBox" Style="{StaticResource PathBox}" Grid.Column="1"/>
                        </Grid>
                        <Button x:Name="BtnScanLog" Grid.Row="2" Content="Scan this log"
                                Style="{StaticResource ScanBtn}" HorizontalAlignment="Left" Width="130"/>
                    </Grid>
                </Border>

                <!-- Results list -->
                <ListBox x:Name="ResultsList" Grid.Row="3"
                         Background="Transparent" BorderThickness="0"
                         ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                         VirtualizingPanel.IsVirtualizing="True"
                         ItemContainerStyle="{StaticResource ResultItem}"
                         Margin="0,6,0,0" Padding="0"/>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

# ── Load window ────────────────────────────────────────────────────────────────
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get controls
$StatusLabel    = $window.FindName("StatusLabel")
$SectionTitle   = $window.FindName("SectionTitle")
$SectionSub     = $window.FindName("SectionSub")
$MiniFlags      = $window.FindName("MiniFlags")
$MiniWarns      = $window.FindName("MiniWarns")
$MiniClean      = $window.FindName("MiniClean")
$MiniCard       = $window.FindName("MiniCard")
$PathBar        = $window.FindName("PathBar")
$PathBox        = $window.FindName("PathBox")
$ResultsList    = $window.FindName("ResultsList")
$BtnRescan      = $window.FindName("BtnRescan")
$BtnScanFolder  = $window.FindName("BtnScanFolder")
$LogBar         = $window.FindName("LogBar")
$LogPathBox     = $window.FindName("LogPathBox")
$BtnScanLog     = $window.FindName("BtnScanLog")

$NavBtns = @{
    "OVERVIEW"       = $window.FindName("BtnOverview")
    "MOD SCANNER"    = $window.FindName("BtnModScanner")
    "RENAMED JARS"   = $window.FindName("BtnRenamedJars")
    "RECYCLE BIN"    = $window.FindName("BtnRecycleBin")
    "DELETED FILES"  = $window.FindName("BtnDeletedFiles")
    "RECENT CHANGES" = $window.FindName("BtnRecentChanges")
    "PREFETCH SCAN"  = $window.FindName("BtnPrefetch")
    "LOG SCANNER"    = $window.FindName("BtnLogScanner")
    "MEMORY SCAN"    = $window.FindName("BtnMemScan")
    "DOWNLOADS"      = $window.FindName("BtnDownloads")
}

$PathBox.Text = $global:CustomModsPath
$global:LogPath = "$env:APPDATA\.minecraft\logs\latest.log"
$LogPathBox.Text = $global:LogPath

# ── Result row builder ─────────────────────────────────────────────────────────
function Add-ResultRow($text, $type) {
    $row = New-Object System.Windows.Controls.Border
    $row.Margin = New-Object System.Windows.Thickness(12, 2, 12, 0)
    $row.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $row.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)

    switch ($type) {
        "FLAG" { $row.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromArgb(255,40,15,15); $fg = "#F7A0A0" }
        "WARN" { $row.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromArgb(255,40,32,14); $fg = "#E0B87A" }
        "OK"   { $row.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromArgb(255,14,32,20); $fg = "#7ADFAA" }
        "HEAD" { $row.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromArgb(255,26,30,37); $fg = "#4F8EF7" }
        "INFO" { $row.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromArgb(255,19,22,27); $fg = "#6B7280" }
        default{ $row.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromArgb(255,19,22,27); $fg = "#9CA3AF" }
    }

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
    $tb.FontSize = 11
    $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($fg)
    $tb.TextWrapping = "Wrap"
    $row.Child = $tb

    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Content = $row
    $item.Background = [System.Windows.Media.Brushes]::Transparent
    $item.BorderThickness = New-Object System.Windows.Thickness(0)
    $item.Padding = New-Object System.Windows.Thickness(0)
    $ResultsList.Items.Add($item) | Out-Null
}

# ── Show section ───────────────────────────────────────────────────────────────
function Show-Section($key) {
    if (-not $key) { return }
    $global:ActiveSection = $key
    $ResultsList.Items.Clear()
    $PathBar.Visibility = if ($key -eq "MOD SCANNER") { "Visible" } else { "Collapsed" }
    $LogBar.Visibility  = if ($key -eq "LOG SCANNER")  { "Visible" } else { "Collapsed" }

    foreach ($b in $NavBtns.Values) {
        if ($b) { $b.Style = $window.Resources["NavBtn"] }
    }
    if ($NavBtns.ContainsKey($key) -and $NavBtns[$key]) {
        $NavBtns[$key].Style = $window.Resources["NavBtnActive"]
    }

    if ($key -eq "OVERVIEW") {
        $SectionTitle.Text = "// OVERVIEW"
        $SectionSub.Text   = "Scanned at $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        foreach ($sec in $global:ScanResults.Keys) {
            Add-ResultRow "  $sec" "HEAD"
            foreach ($item in $global:ScanResults[$sec]) {
                Add-ResultRow "    $($item.Line)" $item.Type
            }
        }
    } elseif ($key -eq "MOD SCANNER") {
        $SectionTitle.Text = "// MOD SCANNER"
        $items = $global:ScanResults["MOD SCANNER"]
        if ($items -and $items.Count -gt 0) {
            $flags = ($items | Where-Object { $_.Type -eq "FLAG" }).Count
            $SectionSub.Text = "$($items.Count) result(s) — $flags flagged"
            foreach ($item in $items) { Add-ResultRow "  $($item.Line)" $item.Type }
        } else {
            $SectionSub.Text = "Enter mods folder path and click Scan"
        }
    } elseif ($key -eq "LOG SCANNER") {
        $SectionTitle.Text = "// LOG SCANNER"
        $SectionSub.Text   = "Load a latest.log to scan for cheat client signatures"
        Add-ResultRow "  Enter the path to latest.log above and click Scan this log" "INFO"
        Add-ResultRow "  Default path: %APPDATA%\.minecraft\logs\latest.log" "INFO"
    } elseif ($key -eq "MEMORY SCAN") {
        $SectionTitle.Text = "// MEMORY SCAN"
        $SectionSub.Text   = "Scan for Doomsday Client traces — requires Administrator"
        Add-ResultRow "  Click Run Memory Scan below to start" "INFO"
        Add-ResultRow "  Scans: javaw.exe memory strings, temp artifacts, recent files, registry" "INFO"
        Add-ResultRow "  Requires Minecraft to be running for memory scan" "INFO"
    } else {
        $SectionTitle.Text = "// $key"
        $items = $global:ScanResults[$key]
        if ($items -and $items.Count -gt 0) {
            $flags = ($items | Where-Object { $_.Type -eq "FLAG" }).Count
            $SectionSub.Text = "$($items.Count) result(s) — $flags flagged"
            foreach ($item in $items) { Add-ResultRow "  $($item.Line)" $item.Type }
        } else {
            $SectionSub.Text = "No data"
            Add-ResultRow "  No results for this section." "INFO"
        }
    }
}

# ── Update mini card ───────────────────────────────────────────────────────────
function Update-MiniCard {
    $flags = 0; $warns = 0; $ok = 0
    foreach ($sec in $global:ScanResults.Keys) {
        foreach ($item in $global:ScanResults[$sec]) {
            if     ($item.Type -eq "FLAG") { $flags++ }
            elseif ($item.Type -eq "WARN") { $warns++ }
            else                           { $ok++ }
        }
    }
    $MiniFlags.Text = "$flags"
    $MiniWarns.Text = "$warns"
    $MiniClean.Text = "$ok"

    foreach ($sec in $global:ScanResults.Keys) {
        if (-not $sec) { continue }
        if (-not $NavBtns.ContainsKey($sec)) { continue }
        $hasFlag = ($global:ScanResults[$sec] | Where-Object { $_.Type -eq "FLAG" }).Count -gt 0
        $hasWarn = ($global:ScanResults[$sec] | Where-Object { $_.Type -eq "WARN" }).Count -gt 0
        $btn = $NavBtns[$sec]
        if (-not $btn) { continue }
        if ($hasFlag)     { $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F74F4F") }
        elseif ($hasWarn) { $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F7A94F") }
        else              { $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#4FF78E") }
    }
}

# ── Start scan ─────────────────────────────────────────────────────────────────
function Start-Scan {
    $StatusLabel.Text       = "● scanning..."
    $StatusLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F7A94F")
    $window.Dispatcher.Invoke([action]{}, "Render")

    $global:ScanResults = Run-Checks $global:CustomModsPath
    Update-MiniCard

    $totalFlags = ($global:ScanResults.Values | ForEach-Object { $_ } | Where-Object { $_.Type -eq "FLAG" }).Count
    if ($totalFlags -gt 0) {
        $StatusLabel.Text       = "● $totalFlags flag(s) found"
        $StatusLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F74F4F")
    } else {
        $StatusLabel.Text       = "● scan complete"
        $StatusLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#4FF78E")
    }
    Show-Section $global:ActiveSection
}

# ── Wire up buttons ────────────────────────────────────────────────────────────
$NavBtns["OVERVIEW"].Add_Click(      { Show-Section "OVERVIEW" })
$NavBtns["MOD SCANNER"].Add_Click(   { Show-Section "MOD SCANNER" })
$NavBtns["RENAMED JARS"].Add_Click(  { Show-Section "RENAMED JARS" })
$NavBtns["RECYCLE BIN"].Add_Click(   { Show-Section "RECYCLE BIN" })
$NavBtns["DELETED FILES"].Add_Click( { Show-Section "DELETED FILES" })
$NavBtns["RECENT CHANGES"].Add_Click({ Show-Section "RECENT CHANGES" })
$NavBtns["PREFETCH SCAN"].Add_Click( { Show-Section "PREFETCH SCAN" })
$NavBtns["DOWNLOADS"].Add_Click(     { Show-Section "DOWNLOADS" })
$NavBtns["LOG SCANNER"].Add_Click(   { Show-Section "LOG SCANNER" })

function Scan-Log($logPath) {
    $ResultsList.Items.Clear()
    $SectionTitle.Text = "// LOG SCANNER"

    if (-not (Test-Path $logPath)) {
        $SectionSub.Text = "File not found"
        Add-ResultRow "  Could not find: $logPath" "WARN"
        return
    }

    $lines = Get-Content $logPath -ErrorAction SilentlyContinue
    if (-not $lines) {
        $SectionSub.Text = "Could not read log file"
        Add-ResultRow "  File empty or unreadable" "WARN"
        return
    }

    $cheatSigs = @(
        "wurst","meteor","liquidbounce","aristois","sigma","impact","future","inertia",
        "novoline","baritone","nodus","wolfram","rusherhack","doomsday","catlean",
        "mace","shieldbreak","spear","xray","killaura","kill aura","aimbot","autoclicker",
        "auto clicker","blink","velocity","nofall","no fall","esp","wallhack","scaffold",
        "speed hack","flyhack","freecam","cavefinder","tracers","cheatbreaker","badlion",
        "lunarclient","lunar client","salwyrr","feather","labymod","5zig"
    )

    $flaggedLines = @()
    $warnLines    = @()
    $lineNum      = 0

    foreach ($line in $lines) {
        $lineNum++
        $lower = $line.ToLower()
        foreach ($sig in $cheatSigs) {
            if ($lower -match [regex]::Escape($sig)) {
                $flaggedLines += @{ Line="[FLAGGED] Line $lineNum  ->  '$sig'  |  $($line.Trim())"; Type="FLAG" }
                break
            }
        }
        # Warn on unusual class loads that might indicate injected clients
        if ($lower -match "classloader|inject|agent|transform|asm|mixin" -and $lower -match "error|warn|unknown") {
            $warnLines += @{ Line="[WARN] Line $lineNum  ->  $($line.Trim())"; Type="WARN" }
        }
    }

    $SectionSub.Text = "$($lines.Count) lines scanned — $($flaggedLines.Count) flagged — $($warnLines.Count) suspicious"

    if ($flaggedLines.Count -eq 0 -and $warnLines.Count -eq 0) {
        Add-ResultRow "  No cheat signatures found in log" "OK"
    } else {
        if ($flaggedLines.Count -gt 0) {
            Add-ResultRow "  FLAGGED SIGNATURES" "HEAD"
            foreach ($item in $flaggedLines) { Add-ResultRow "  $($item.Line)" "FLAG" }
        }
        if ($warnLines.Count -gt 0) {
            Add-ResultRow "  SUSPICIOUS ENTRIES" "HEAD"
            foreach ($item in $warnLines) { Add-ResultRow "  $($item.Line)" "WARN" }
        }
    }
}

$BtnScanLog.Add_Click({
    $logPath = $LogPathBox.Text.Trim()
    $global:LogPath = $logPath
    Scan-Log $logPath
})

# ── Memory Scan Window ────────────────────────────────────────────────────────
# Opens as a separate WPF window so it doesn't block the main UI
# Scan runs on a background runspace thread

$memSig = @"
using System;
using System.Runtime.InteropServices;
public class MemAPI {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(
        IntPtr hProcess, IntPtr lpBaseAddress,
        byte[] lpBuffer, int nSize, out int lpNumberOfBytesRead);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(
        uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
    [DllImport("kernel32.dll")]
    public static extern bool VirtualQueryEx(
        IntPtr hProcess, IntPtr lpAddress,
        ref MEMORY_BASIC_INFORMATION lpBuffer, uint dwLength);
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint AllocationProtect;
        public IntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
    }
}
"@
Add-Type -TypeDefinition $memSig -ErrorAction SilentlyContinue

function Open-MemoryScanWindow {
    [xml]$memXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Memory Scan - Krom SS Tools" Height="600" Width="820"
    MinHeight="450" MinWidth="650"
    Background="#0D0F12" Foreground="#E8EAF0"
    WindowStartupLocation="CenterScreen" ResizeMode="CanResize">

    <Window.Resources>
        <Style x:Key="ActionBtn" TargetType="Button">
            <Setter Property="Background" Value="#1A1E25"/>
            <Setter Property="Foreground" Value="#4F8EF7"/>
            <Setter Property="BorderBrush" Value="#282D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="Padding" Value="22,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#22272F"/>
                                <Setter TargetName="bg" Property="BorderBrush" Value="#3A4150"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#13161B"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScanBtn" TargetType="Button" BasedOn="{StaticResource ActionBtn}">
            <Setter Property="Foreground" Value="#4FF78E"/>
            <Setter Property="BorderBrush" Value="#2A4A38"/>
            <Setter Property="Background" Value="#0F1F16"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#16301F"/>
                                <Setter TargetName="bg" Property="BorderBrush" Value="#3D6B4F"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#0A1A11"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ResultItem" TargetType="ListBoxItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <ContentPresenter/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="48"/>
            <RowDefinition Height="1"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="1"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Titlebar -->
        <Grid Grid.Row="0" Background="#13161B">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
                <Border Background="#F74F4F" CornerRadius="5" Width="26" Height="26" Margin="0,0,10,0">
                    <TextBlock Text="M" FontFamily="Consolas" FontWeight="Bold" FontSize="13"
                               Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock Text="MEMORY " FontFamily="Consolas" FontWeight="Bold" FontSize="13"
                           Foreground="#F74F4F" VerticalAlignment="Center"/>
                <TextBlock Text="SCAN" FontFamily="Consolas" FontWeight="Bold" FontSize="13"
                           Foreground="#E8EAF0" VerticalAlignment="Center"/>
                <Border Background="#1A1E25" BorderBrush="#282D37" BorderThickness="1"
                        CornerRadius="3" Margin="10,0,0,0" Padding="6,2">
                    <TextBlock Text="separate window" FontFamily="Consolas" FontSize="9" Foreground="#6B7280"/>
                </Border>
            </StackPanel>
            <TextBlock Name="MemStatus" Text="idle" FontFamily="Consolas" FontSize="10"
                       Foreground="#6B7280" VerticalAlignment="Center"
                       HorizontalAlignment="Right" Margin="0,0,18,0"/>
        </Grid>

        <Rectangle Grid.Row="1" Fill="#282D37"/>

        <!-- Section header (matches main panel) -->
        <Grid Grid.Row="2" Margin="22,18,22,16">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
                <TextBlock Text="// MEMORY SCAN" FontFamily="Consolas" FontWeight="Bold" FontSize="15"
                           Foreground="#E8EAF0"/>
                <TextBlock Name="MemSub" Text="Scan for traces of self-destructed cheats" FontFamily="Segoe UI" FontSize="11"
                           Foreground="#6B7280" Margin="0,3,0,0"/>
            </StackPanel>
            <Border Grid.Column="1" Background="#13161B"
                    BorderBrush="#282D37" BorderThickness="1" CornerRadius="6"
                    Padding="14,8" VerticalAlignment="Top">
                <StackPanel Orientation="Horizontal">
                    <StackPanel Margin="0,0,16,0">
                        <TextBlock Text="FLAGGED" FontFamily="Consolas" FontSize="8"
                                   Foreground="#6B7280" Margin="0,0,0,2"/>
                        <TextBlock Name="MemFlags" Text="0" FontFamily="Consolas"
                                   FontSize="18" FontWeight="Bold" Foreground="#F74F4F"/>
                    </StackPanel>
                    <StackPanel Margin="0,0,16,0">
                        <TextBlock Text="WARNINGS" FontFamily="Consolas" FontSize="8"
                                   Foreground="#6B7280" Margin="0,0,0,2"/>
                        <TextBlock Name="MemWarns" Text="0" FontFamily="Consolas"
                                   FontSize="18" FontWeight="Bold" Foreground="#F7A94F"/>
                    </StackPanel>
                    <StackPanel>
                        <TextBlock Text="CLEAN" FontFamily="Consolas" FontSize="8"
                                   Foreground="#6B7280" Margin="0,0,0,2"/>
                        <TextBlock Name="MemClean" Text="0" FontFamily="Consolas"
                                   FontSize="18" FontWeight="Bold" Foreground="#4FF78E"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </Grid>

        <Rectangle Grid.Row="3" Height="1" Fill="#282D37" Margin="22,0"/>

        <!-- Results list (matches main panel style) -->
        <ListBox Name="MemList" Grid.Row="4"
                 Background="Transparent" BorderThickness="0"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                 VirtualizingPanel.IsVirtualizing="True"
                 ItemContainerStyle="{StaticResource ResultItem}"
                 Margin="0,8,0,0" Padding="0"/>

        <!-- Bottom action bar -->
        <Grid Grid.Row="5" Background="#13161B" Height="56">
            <Rectangle Height="1" VerticalAlignment="Top" Fill="#282D37"/>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="22,0">
                <Button Name="BtnStartMem" Content="Run Memory Scan" Style="{StaticResource ScanBtn}"/>
                <Button Name="BtnClearMem" Content="Clear" Style="{StaticResource ActionBtn}" Margin="10,0,0,0">
                    <Button.Foreground>
                        <SolidColorBrush Color="#6B7280"/>
                    </Button.Foreground>
                </Button>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

    $memReader = New-Object System.Xml.XmlNodeReader $memXaml
    $memWin    = [Windows.Markup.XamlReader]::Load($memReader)

    $global:memList   = $memWin.FindName("MemList")
    $global:memStatus = $memWin.FindName("MemStatus")
    $global:memSub    = $memWin.FindName("MemSub")
    $global:memWinRef = $memWin
    $global:brush     = [System.Windows.Media.BrushConverter]::new()
    $btnStart  = $memWin.FindName("BtnStartMem")
    $btnClear  = $memWin.FindName("BtnClearMem")

    function Add-MemRow {
        param($text, $type, $list, $br)
        $row = New-Object System.Windows.Controls.Border
        $row.Margin       = New-Object System.Windows.Thickness(12,2,12,0)
        $row.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $row.Padding      = New-Object System.Windows.Thickness(10,6,10,6)
        switch ($type) {
            "FLAG" { $row.Background = $br.ConvertFrom("#281010"); $fg = "#F7A0A0" }
            "WARN" { $row.Background = $br.ConvertFrom("#28200E"); $fg = "#E0B87A" }
            "OK"   { $row.Background = $br.ConvertFrom("#0E2014"); $fg = "#7ADFAA" }
            "HEAD" { $row.Background = $br.ConvertFrom("#1A1E25"); $fg = "#4F8EF7" }
            default{ $row.Background = $br.ConvertFrom("#13161B"); $fg = "#9CA3AF" }
        }
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text         = $text
        $tb.FontFamily   = New-Object System.Windows.Media.FontFamily("Consolas")
        $tb.FontSize     = 11
        $tb.Foreground   = $br.ConvertFrom($fg)
        $tb.TextWrapping = "Wrap"
        $row.Child = $tb
        $li = New-Object System.Windows.Controls.ListBoxItem
        $li.Content         = $row
        $li.Background      = [System.Windows.Media.Brushes]::Transparent
        $li.BorderThickness = New-Object System.Windows.Thickness(0)
        $li.Padding         = New-Object System.Windows.Thickness(0)
        $list.Items.Add($li) | Out-Null
    }

    $btnClear.Add_Click({
        $global:memList.Items.Clear()
        $global:memStatus.Text = "idle"
        $global:memSub.Text    = "Scan for traces of self-destructed cheats"
    }.GetNewClosure())

    $btnStart.Add_Click({
        $global:memList.Items.Clear()
        $global:memStatus.Text = "scanning..."
        $global:memStatus.Foreground = $global:brush.ConvertFrom("#F7A94F")
        $global:memSub.Text = "Reading javaw.exe process memory..."
        $global:memWinRef.Dispatcher.Invoke([action]{}, "Render")

        # Strings to search for in javaw memory
        # Universal Java agent / injection markers - these MUST exist in any
        # injectable cheat jar regardless of client name or version
        # Zero false positives - legitimate Minecraft mods do not use Java agents
        $signatures = @(
            # Java agent JAR manifest entries (required by JVM to load as agent)
            "Premain-Class:",
            "Agent-Class:",
            "Can-Retransform-Classes:",
            "Can-Redefine-Classes:",
            "Can-Set-Native-Method-Prefix:",
            # Java agent method signatures (required by Instrumentation API)
            "premain(Ljava/lang/String;Ljava/lang/instrument/Instrumentation;)V",
            "agentmain(Ljava/lang/String;Ljava/lang/instrument/Instrumentation;)V",
            "premain(Ljava/lang/String;)V",
            "agentmain(Ljava/lang/String;)V",
            # Common bytecode manipulation libraries used to inject cheats at runtime
            # These have legitimate uses but are extremely rare in normal mods
            "net/bytebuddy/agent/ByteBuddyAgent",
            "javassist/util/proxy/ProxyFactory",
            # VirtualMachine attach API used by injectors to attach to running javaw
            "com/sun/tools/attach/VirtualMachine",
            "loadAgent(Ljava/lang/String;",
            # Self-attaching agent (cheat injects itself into its own JVM)
            "VirtualMachine.attach"
        )

        # Collect rows first, push to UI at the end
        $rows = [System.Collections.Generic.List[hashtable]]::new()
        $flagCount = 0
        $okCount   = 0
        $warnCount = 0

        $rows.Add(@{ T="  -- JAVAW.EXE MEMORY SCAN --"; K="HEAD" })

        $javaProcs = Get-Process -Name "javaw" -ErrorAction SilentlyContinue
        if (-not $javaProcs) {
            $rows.Add(@{ T="  [WARN]  No javaw.exe running -- start Minecraft first"; K="WARN" })
            $warnCount++
        } else {
            $PROCESS_VM_READ        = 0x0010
            $PROCESS_QUERY_INFO     = 0x0400

            foreach ($proc in $javaProcs) {
                $javaPid = $proc.Id
                $rows.Add(@{ T="  Scanning PID $javaPid ..."; K="INFO" })

                try {
                    $hProc = [MemAPI]::OpenProcess($PROCESS_VM_READ -bor $PROCESS_QUERY_INFO, $false, $javaPid)
                    if ($hProc -eq [IntPtr]::Zero) {
                        $rows.Add(@{ T="  [WARN]  Cannot open PID $javaPid -- run as Administrator"; K="WARN" })
                        $warnCount++
                        continue
                    }

                    $mbi      = New-Object MemAPI+MEMORY_BASIC_INFORMATION
                    $mbiSize  = [System.Runtime.InteropServices.Marshal]::SizeOf($mbi)
                    $addr     = [IntPtr]::Zero
                    $hits     = @{}

                    while ([MemAPI]::VirtualQueryEx($hProc, $addr, [ref]$mbi, $mbiSize)) {
                        # Only committed, readable, non-image pages
                        $isCommit = $mbi.State -eq 0x1000
                        $isReadable = ($mbi.Protect -band 0x02) -or ($mbi.Protect -band 0x04) -or ($mbi.Protect -band 0x20) -or ($mbi.Protect -band 0x40)
                        if ($isCommit -and $isReadable) {
                            $size = [int64]$mbi.RegionSize.ToInt64()
                            if ($size -gt 0 -and $size -lt 50MB) {
                                $buf  = New-Object byte[] $size
                                $read = 0
                                if ([MemAPI]::ReadProcessMemory($hProc, $mbi.BaseAddress, $buf, $size, [ref]$read) -and $read -gt 0) {
                                    $text = [System.Text.Encoding]::ASCII.GetString($buf, 0, $read).ToLower()
                                    foreach ($sig in $signatures) {
                                        if ($text.Contains($sig)) {
                                            if (-not $hits.ContainsKey($sig)) { $hits[$sig] = 0 }
                                            $hits[$sig]++
                                        }
                                    }
                                }
                            }
                        }
                        $next = $mbi.BaseAddress.ToInt64() + $mbi.RegionSize.ToInt64()
                        if ($next -le $addr.ToInt64()) { break }
                        try { $addr = [IntPtr]::new($next) } catch { break }
                    }
                    [MemAPI]::CloseHandle($hProc) | Out-Null

                    if ($hits.Count -eq 0) {
                        $rows.Add(@{ T="  [OK]  PID $javaPid -- no suspicious strings found"; K="OK" })
                        $okCount++
                    } else {
                        foreach ($k in $hits.Keys) {
                            $count = $hits[$k]
                            $rows.Add(@{ T="  [FLAGGED]  PID $javaPid  ->  '$k' found in $count region(s)"; K="FLAG" })
                            $flagCount++
                        }
                    }
                } catch {
                    $rows.Add(@{ T="  [WARN]  Error scanning PID $javaPid : $($_.Exception.Message)"; K="WARN" })
                    $warnCount++
                }
            }
        }

        # Push results to UI - inlined since closure can't see Add-MemRow
        $tf = $flagCount; $tw = $warnCount; $to = $okCount
        $capturedRows = $rows
        $global:memWinRef.Dispatcher.Invoke([action]{
            foreach ($row in $capturedRows) {
                $r = New-Object System.Windows.Controls.Border
                $r.Margin       = New-Object System.Windows.Thickness(12,2,12,0)
                $r.CornerRadius = New-Object System.Windows.CornerRadius(4)
                $r.Padding      = New-Object System.Windows.Thickness(10,6,10,6)
                switch ($row.K) {
                    "FLAG" { $r.Background = $global:brush.ConvertFrom("#281010"); $fg = "#F7A0A0" }
                    "WARN" { $r.Background = $global:brush.ConvertFrom("#28200E"); $fg = "#E0B87A" }
                    "OK"   { $r.Background = $global:brush.ConvertFrom("#0E2014"); $fg = "#7ADFAA" }
                    "HEAD" { $r.Background = $global:brush.ConvertFrom("#1A1E25"); $fg = "#4F8EF7" }
                    default{ $r.Background = $global:brush.ConvertFrom("#13161B"); $fg = "#9CA3AF" }
                }
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text         = $row.T
                $tb.FontFamily   = New-Object System.Windows.Media.FontFamily("Consolas")
                $tb.FontSize     = 11
                $tb.Foreground   = $global:brush.ConvertFrom($fg)
                $tb.TextWrapping = "Wrap"
                $r.Child = $tb
                $li = New-Object System.Windows.Controls.ListBoxItem
                $li.Content         = $r
                $li.Background      = [System.Windows.Media.Brushes]::Transparent
                $li.BorderThickness = New-Object System.Windows.Thickness(0)
                $li.Padding         = New-Object System.Windows.Thickness(0)
                $global:memList.Items.Add($li) | Out-Null
            }
            $memFlags = $global:memWinRef.FindName("MemFlags")
            $memWarns = $global:memWinRef.FindName("MemWarns")
            $memClean = $global:memWinRef.FindName("MemClean")
            if ($memFlags) { $memFlags.Text = "$tf" }
            if ($memWarns) { $memWarns.Text = "$tw" }
            if ($memClean) { $memClean.Text = "$to" }

            if ($tf -gt 0) {
                $global:memStatus.Text = "$tf finding(s)"
                $global:memStatus.Foreground = $global:brush.ConvertFrom("#F74F4F")
                $global:memSub.Text = "Suspicious strings found in javaw memory"
            } else {
                $global:memStatus.Text = "clean"
                $global:memStatus.Foreground = $global:brush.ConvertFrom("#4FF78E")
                $global:memSub.Text = "No suspicious strings found in javaw memory"
            }
        }.GetNewClosure(), "Normal")
    }.GetNewClosure())

    $memWin.Show()
}
$NavBtns["MEMORY SCAN"].Add_Click({ Open-MemoryScanWindow })

$BtnRescan.Add_Click({ Start-Scan })

$BtnScanFolder.Add_Click({
    $newPath = $PathBox.Text.Trim()
    if (Test-Path $newPath) {
        $global:CustomModsPath = $newPath
        $PathBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#4FF78E")
        Start-Scan
        Show-Section "MOD SCANNER"
    } else {
        $PathBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F74F4F")
    }
})

$window.Add_Loaded({ Start-Scan })
$window.ShowDialog() | Out-Null
