# Krom SS Tools - PowerShell GUI
# Usage: irm https://raw.githubusercontent.com/kromilio/krom-ss-tools/main/mc-check.ps1 | iex

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

$c = @{
    Bg     = [System.Drawing.Color]::FromArgb(13,15,18)
    Bg2    = [System.Drawing.Color]::FromArgb(19,22,27)
    Bg3    = [System.Drawing.Color]::FromArgb(26,30,37)
    Border = [System.Drawing.Color]::FromArgb(40,45,55)
    Accent = [System.Drawing.Color]::FromArgb(79,142,247)
    Text   = [System.Drawing.Color]::FromArgb(232,234,240)
    Muted  = [System.Drawing.Color]::FromArgb(107,114,128)
    Red    = [System.Drawing.Color]::FromArgb(247,79,79)
    Amber  = [System.Drawing.Color]::FromArgb(247,169,79)
    Green  = [System.Drawing.Color]::FromArgb(79,247,142)
}

$fontMono   = New-Object System.Drawing.Font("Consolas", 9)
$fontMonoSm = New-Object System.Drawing.Font("Consolas", 8)
$fontMonoLg = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
$fontSans   = New-Object System.Drawing.Font("Segoe UI", 9)
$fontSansSm = New-Object System.Drawing.Font("Segoe UI", 8)

$global:ScanResults    = [ordered]@{}
$global:ActiveSection  = "OVERVIEW"
$global:CustomModsPath = "$env:APPDATA\.minecraft\mods"

# ── Checks ─────────────────────────────────────────────────────────────────────
function Run-Checks {
    $results     = [ordered]@{}
    $knownCheats = @("wurst","meteor","liquidbounce","aristois","sigma","impact","future","inertia","novoline","xaero","baritone","nodus","vape","huzuni","wolfram","rusherhack")
    $modsFolder  = $global:CustomModsPath

    # MOD SCANNER
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
                        $results[$s] += @{ Line="[FLAGGED]  $($jar.Name)  ->  matches '$cheat'"; Type="FLAG" }
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

    # RENAMED JARS
    $s = "RENAMED JARS"; $results[$s] = @()
    if (Test-Path $modsFolder) {
        $jars = Get-ChildItem $modsFolder -Filter "*.jar" -ErrorAction SilentlyContinue
        if ($jars.Count -eq 0) {
            $results[$s] += @{ Line="No jars to check"; Type="OK" }
        } else {
            foreach ($jar in $jars) {
                try {
                    $zip      = [System.IO.Compression.ZipFile]::OpenRead($jar.FullName)
                    $manifest = $zip.Entries | Where-Object { $_.FullName -match "fabric\.mod\.json|mods\.toml|mcmod\.info" }
                    if ($manifest) {
                        $reader  = New-Object System.IO.StreamReader($manifest[0].Open())
                        $content = $reader.ReadToEnd(); $reader.Close()
                        if ($content -match '"modid"\s*:\s*"([^"]+)"') {
                            $id = $matches[1]
                            if ($jar.BaseName -notmatch [regex]::Escape($id) -and $id -notmatch [regex]::Escape($jar.BaseName)) {
                                $results[$s] += @{ Line="[MISMATCH]  $($jar.Name)  ->  internal: '$id'"; Type="FLAG" }
                            } else {
                                $results[$s] += @{ Line="[OK]  $($jar.Name)  ->  '$id'"; Type="OK" }
                            }
                        } else {
                            $results[$s] += @{ Line="[WARN]  $($jar.Name)  ->  no mod ID in manifest"; Type="WARN" }
                        }
                    } else {
                        $results[$s] += @{ Line="[WARN]  $($jar.Name)  ->  no manifest found"; Type="WARN" }
                    }
                    $zip.Dispose()
                } catch {
                    $results[$s] += @{ Line="[WARN]  $($jar.Name)  ->  could not read jar"; Type="WARN" }
                }
            }
        }
    } else {
        $results[$s] += @{ Line="No mods folder to check"; Type="OK" }
    }

    # RECYCLE BIN
    $s = "RECYCLE BIN"; $results[$s] = @()
    try {
        $shell = New-Object -ComObject Shell.Application
        $bin   = $shell.Namespace(0xA)
        $items = $bin.Items()
        if ($items.Count -eq 0) {
            $results[$s] += @{ Line="Recycle bin is empty"; Type="OK" }
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
        $results[$s] += @{ Line="[WARN]  Could not read recycle bin"; Type="WARN" }
    }

    # DELETED FILES
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
        $results[$s] += @{ Line="[WARN]  Run as Administrator for event log access"; Type="WARN" }
    }

    # RECENTLY MODIFIED
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

    return $results
}

# ── Form ───────────────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text          = "Krom SS Tools"
$form.Size          = New-Object System.Drawing.Size(920, 620)
$form.MinimumSize   = New-Object System.Drawing.Size(700, 500)
$form.BackColor     = $c.Bg
$form.ForeColor     = $c.Text
$form.Font          = $fontSans
$form.StartPosition = "CenterScreen"

# ── Titlebar (Dock Top) ────────────────────────────────────────────────────────
$titlePanel           = New-Object System.Windows.Forms.Panel
$titlePanel.Dock      = "Top"
$titlePanel.Height    = 46
$titlePanel.BackColor = $c.Bg2
$form.Controls.Add($titlePanel)

$titleLabel          = New-Object System.Windows.Forms.Label
$titleLabel.Text     = "KROM SS TOOLS"
$titleLabel.Font     = $fontMonoLg
$titleLabel.ForeColor = $c.Accent
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(16, 12)
$titlePanel.Controls.Add($titleLabel)

$verLabel           = New-Object System.Windows.Forms.Label
$verLabel.Text      = "v1.0"
$verLabel.Font      = $fontMonoSm
$verLabel.ForeColor = $c.Muted
$verLabel.AutoSize  = $true
$verLabel.Location  = New-Object System.Drawing.Point(178, 16)
$titlePanel.Controls.Add($verLabel)

$statusLabel          = New-Object System.Windows.Forms.Label
$statusLabel.Text     = "● scanning..."
$statusLabel.Font     = $fontMonoSm
$statusLabel.ForeColor = $c.Amber
$statusLabel.AutoSize = $true
$statusLabel.Anchor   = [System.Windows.Forms.AnchorStyles]"Top,Right"
$statusLabel.Location = New-Object System.Drawing.Point(780, 16)
$titlePanel.Controls.Add($statusLabel)

$titleBorder           = New-Object System.Windows.Forms.Panel
$titleBorder.Dock      = "Top"
$titleBorder.Height    = 1
$titleBorder.BackColor = $c.Border
$form.Controls.Add($titleBorder)

# ── Sidebar (Dock Left) ────────────────────────────────────────────────────────
# Add Fill panel FIRST, then Left panels — WinForms docking order matters
# We add sidebar last so it claims Left correctly

# Sidebar border
$sidebarBorder           = New-Object System.Windows.Forms.Panel
$sidebarBorder.Dock      = "Left"
$sidebarBorder.Width     = 1
$sidebarBorder.BackColor = $c.Border

# Sidebar
$sidebar           = New-Object System.Windows.Forms.Panel
$sidebar.Dock      = "Left"
$sidebar.Width     = 190
$sidebar.BackColor = $c.Bg2

# Nav label
$navLabel          = New-Object System.Windows.Forms.Label
$navLabel.Text     = "  CHECKS"
$navLabel.Font     = New-Object System.Drawing.Font("Consolas", 7)
$navLabel.ForeColor = $c.Muted
$navLabel.Location = New-Object System.Drawing.Point(0, 10)
$navLabel.Size     = New-Object System.Drawing.Size(190, 20)
$sidebar.Controls.Add($navLabel)

# Nav buttons
$global:NavButtons = @{}
function New-NavButton($label, $yPos, $key) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text      = "  $label"
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor  = $c.Bg3
    $btn.FlatAppearance.MouseDownBackColor  = $c.Bg3
    $btn.BackColor  = $c.Bg2
    $btn.ForeColor  = $c.Muted
    $btn.Font       = $fontSans
    $btn.TextAlign  = "MiddleLeft"
    $btn.Location   = New-Object System.Drawing.Point(0, $yPos)
    $btn.Size       = New-Object System.Drawing.Size(190, 34)
    $btn.Cursor     = "Hand"
    $btn.Tag        = $key
    $btn.Add_Click({
        param($s, $e)
        foreach ($b in $global:NavButtons.Values) { $b.BackColor = $c.Bg2 }
        $s.BackColor = $c.Bg3
        Show-Section $s.Tag
    })
    $sidebar.Controls.Add($btn)
    $global:NavButtons[$key] = $btn
}

New-NavButton "Overview"       32  "OVERVIEW"
New-NavButton "Mod Scanner"    66  "MOD SCANNER"
New-NavButton "Renamed Jars"   100 "RENAMED JARS"
New-NavButton "Recycle Bin"    134 "RECYCLE BIN"
New-NavButton "Deleted Files"  168 "DELETED FILES"
New-NavButton "Recent Changes" 202 "RECENT CHANGES"

$sdivider           = New-Object System.Windows.Forms.Panel
$sdivider.Location  = New-Object System.Drawing.Point(10, 242)
$sdivider.Size      = New-Object System.Drawing.Size(170, 1)
$sdivider.BackColor = $c.Border
$sidebar.Controls.Add($sdivider)

$rescanBtn = New-Object System.Windows.Forms.Button
$rescanBtn.Text     = "  Rescan"
$rescanBtn.FlatStyle = "Flat"
$rescanBtn.FlatAppearance.BorderColor = $c.Border
$rescanBtn.FlatAppearance.BorderSize  = 1
$rescanBtn.FlatAppearance.MouseOverBackColor = $c.Bg3
$rescanBtn.BackColor = $c.Bg2
$rescanBtn.ForeColor = $c.Accent
$rescanBtn.Font      = $fontSans
$rescanBtn.Location  = New-Object System.Drawing.Point(10, 252)
$rescanBtn.Size      = New-Object System.Drawing.Size(170, 32)
$rescanBtn.Cursor    = "Hand"
$sidebar.Controls.Add($rescanBtn)

# ── Content panel (Dock Fill) ──────────────────────────────────────────────────
$contentPanel           = New-Object System.Windows.Forms.Panel
$contentPanel.Dock      = "Fill"
$contentPanel.BackColor = $c.Bg

# -- Header strip (Dock Top) inside content
$headerStrip           = New-Object System.Windows.Forms.Panel
$headerStrip.Dock      = "Top"
$headerStrip.Height    = 66
$headerStrip.BackColor = $c.Bg

$sectionTitle          = New-Object System.Windows.Forms.Label
$sectionTitle.Text     = "// OVERVIEW"
$sectionTitle.Font     = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$sectionTitle.ForeColor = $c.Text
$sectionTitle.AutoSize = $true
$sectionTitle.Location = New-Object System.Drawing.Point(20, 12)
$headerStrip.Controls.Add($sectionTitle)

$sectionSub           = New-Object System.Windows.Forms.Label
$sectionSub.Text      = "All scan results"
$sectionSub.Font      = $fontSansSm
$sectionSub.ForeColor = $c.Muted
$sectionSub.AutoSize  = $true
$sectionSub.Location  = New-Object System.Drawing.Point(20, 40)
$headerStrip.Controls.Add($sectionSub)

$sepLine           = New-Object System.Windows.Forms.Panel
$sepLine.Dock      = "Top"
$sepLine.Height    = 1
$sepLine.BackColor = $c.Border

# -- Path bar (Dock Top, hidden by default)
$pathBar           = New-Object System.Windows.Forms.Panel
$pathBar.Dock      = "Top"
$pathBar.Height    = 72
$pathBar.BackColor = $c.Bg2
$pathBar.Padding   = New-Object System.Windows.Forms.Padding(16, 10, 16, 10)
$pathBar.Visible   = $false

$pathLabel          = New-Object System.Windows.Forms.Label
$pathLabel.Text     = "Mods folder:"
$pathLabel.Font     = $fontMonoSm
$pathLabel.ForeColor = $c.Muted
$pathLabel.AutoSize = $true
$pathLabel.Location = New-Object System.Drawing.Point(16, 14)
$pathBar.Controls.Add($pathLabel)

$pathBox              = New-Object System.Windows.Forms.TextBox
$pathBox.Text         = $global:CustomModsPath
$pathBox.Font         = $fontMono
$pathBox.BackColor    = $c.Bg3
$pathBox.ForeColor    = $c.Text
$pathBox.BorderStyle  = "FixedSingle"
$pathBox.Location     = New-Object System.Drawing.Point(102, 10)
$pathBox.Size         = New-Object System.Drawing.Size(500, 24)
$pathBox.Anchor       = [System.Windows.Forms.AnchorStyles]"Top,Left,Right"
$pathBar.Controls.Add($pathBox)

$pathScanBtn = New-Object System.Windows.Forms.Button
$pathScanBtn.Text     = "Scan this folder"
$pathScanBtn.FlatStyle = "Flat"
$pathScanBtn.FlatAppearance.BorderColor = $c.Border
$pathScanBtn.FlatAppearance.BorderSize  = 1
$pathScanBtn.FlatAppearance.MouseOverBackColor = $c.Bg3
$pathScanBtn.BackColor = $c.Bg2
$pathScanBtn.ForeColor = $c.Green
$pathScanBtn.Font      = $fontSans
$pathScanBtn.Location  = New-Object System.Drawing.Point(16, 42)
$pathScanBtn.Size      = New-Object System.Drawing.Size(140, 24)
$pathScanBtn.Cursor    = "Hand"
$pathScanBtn.Add_Click({
    $newPath = $pathBox.Text.Trim()
    if (Test-Path $newPath) {
        $global:CustomModsPath = $newPath
        $pathBox.ForeColor = $c.Green
        Start-Scan
        Show-Section "MOD SCANNER"
    } else {
        $pathBox.ForeColor = $c.Red
    }
})
$pathBar.Controls.Add($pathScanBtn)

# -- ListBox (Dock Fill)
$listBox              = New-Object System.Windows.Forms.ListBox
$listBox.Dock         = "Fill"
$listBox.BackColor    = $c.Bg
$listBox.ForeColor    = $c.Text
$listBox.Font         = $fontMono
$listBox.BorderStyle  = "None"
$listBox.DrawMode     = "OwnerDrawFixed"
$listBox.ItemHeight   = 24
$listBox.SelectionMode = "One"
$listBox.IntegralHeight = $false

$listBox.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $item = $sender.Items[$e.Index]
    $bgColor = $c.Bg; $fgColor = $c.Muted
    if     ($item -match "\[FLAGGED\]|\[MISMATCH\]") { $bgColor = [System.Drawing.Color]::FromArgb(40,15,15);  $fgColor = $c.Red }
    elseif ($item -match "\[WARN\]")                 { $bgColor = [System.Drawing.Color]::FromArgb(40,32,14);  $fgColor = $c.Amber }
    elseif ($item -match "\[OK\]")                   { $bgColor = [System.Drawing.Color]::FromArgb(14,32,20);  $fgColor = $c.Green }
    elseif ($item -match "^//")                      { $bgColor = $c.Bg3;                                       $fgColor = $c.Accent }
    elseif ($item -match "^─+$")                     { $bgColor = $c.Bg;                                        $fgColor = $c.Border }
    elseif ($item -match "^\s*(Flagged|Warnings|Clean)\s+:") { $bgColor = $c.Bg2; $fgColor = $c.Text }
    else                                             { $bgColor = $c.Bg2;                                       $fgColor = $c.Muted }
    $br = New-Object System.Drawing.SolidBrush($bgColor)
    $e.Graphics.FillRectangle($br, $e.Bounds); $br.Dispose()
    $tb = New-Object System.Drawing.SolidBrush($fgColor)
    $e.Graphics.DrawString($item, $fontMono, $tb, [float]($e.Bounds.X+10), [float]($e.Bounds.Y+4)); $tb.Dispose()
})

# Add controls to contentPanel in REVERSE dock order: Fill first, then Tops last
$contentPanel.Controls.Add($listBox)      # Fill — added first
$contentPanel.Controls.Add($pathBar)      # Top  — added after Fill
$contentPanel.Controls.Add($sepLine)      # Top
$contentPanel.Controls.Add($headerStrip)  # Top  — added last, renders at very top

# Add panels to form in correct order
$form.Controls.Add($contentPanel)   # Fill — first
$form.Controls.Add($sidebarBorder)  # Left
$form.Controls.Add($sidebar)        # Left — last

# ── Show Section ───────────────────────────────────────────────────────────────
function Show-Section($key) {
    $global:ActiveSection = $key
    $listBox.Items.Clear()
    $pathBar.Visible = ($key -eq "MOD SCANNER")

    if ($key -eq "OVERVIEW") {
        $sectionTitle.Text = "// OVERVIEW"
        $sectionSub.Text   = "Scanned at $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        $totalFlags = 0; $totalWarns = 0; $totalOk = 0
        foreach ($sec in $global:ScanResults.Keys) {
            foreach ($item in $global:ScanResults[$sec]) {
                if     ($item.Type -eq "FLAG") { $totalFlags++ }
                elseif ($item.Type -eq "WARN") { $totalWarns++ }
                else                           { $totalOk++ }
            }
        }
        $listBox.Items.Add("  Flagged    :  $totalFlags item(s)") | Out-Null
        $listBox.Items.Add("  Warnings   :  $totalWarns item(s)") | Out-Null
        $listBox.Items.Add("  Clean      :  $totalOk item(s)")    | Out-Null
        $listBox.Items.Add("─────────────────────────────────────────────────────") | Out-Null
        foreach ($sec in $global:ScanResults.Keys) {
            $listBox.Items.Add("// $sec") | Out-Null
            foreach ($item in $global:ScanResults[$sec]) {
                $listBox.Items.Add("  $($item.Line)") | Out-Null
            }
            $listBox.Items.Add("") | Out-Null
        }
    } elseif ($key -eq "MOD SCANNER") {
        $sectionTitle.Text = "// MOD SCANNER"
        $items = $global:ScanResults["MOD SCANNER"]
        if ($items -and $items.Count -gt 0) {
            $flags = ($items | Where-Object { $_.Type -eq "FLAG" }).Count
            $sectionSub.Text = "$($items.Count) result(s)  —  $flags flagged"
            foreach ($item in $items) { $listBox.Items.Add("  $($item.Line)") | Out-Null }
        } else {
            $sectionSub.Text = "Enter your mods folder path and click Scan"
        }
    } else {
        $sectionTitle.Text = "// $key"
        $items = $global:ScanResults[$key]
        if ($items -and $items.Count -gt 0) {
            $flags = ($items | Where-Object { $_.Type -eq "FLAG" }).Count
            $sectionSub.Text = "$($items.Count) result(s)  —  $flags flagged"
            foreach ($item in $items) { $listBox.Items.Add("  $($item.Line)") | Out-Null }
        } else {
            $sectionSub.Text = "No data"
            $listBox.Items.Add("  No results for this section.") | Out-Null
        }
    }
}

# ── Resize ─────────────────────────────────────────────────────────────────────
$form.Add_Resize({
    $statusLabel.Location = New-Object System.Drawing.Point(($titlePanel.Width - $statusLabel.Width - 16), 15)
    $pathBox.Width = $pathBar.Width - 102 - 20
})

# ── Start Scan ─────────────────────────────────────────────────────────────────
function Start-Scan {
    $statusLabel.Text     = "● scanning..."
    $statusLabel.ForeColor = $c.Amber
    $form.Refresh()
    $global:ScanResults = Run-Checks
    $totalFlags = 0
    foreach ($sec in $global:ScanResults.Keys) {
        $flags = ($global:ScanResults[$sec] | Where-Object { $_.Type -eq "FLAG" }).Count
        $totalFlags += $flags
        if ($global:NavButtons.ContainsKey($sec)) {
            $hasWarn = ($global:ScanResults[$sec] | Where-Object { $_.Type -eq "WARN" }).Count -gt 0
            if ($flags -gt 0)  { $global:NavButtons[$sec].ForeColor = $c.Red }
            elseif ($hasWarn)  { $global:NavButtons[$sec].ForeColor = $c.Amber }
            else               { $global:NavButtons[$sec].ForeColor = $c.Green }
        }
    }
    if ($totalFlags -gt 0) { $statusLabel.Text = "● $totalFlags flag(s) found"; $statusLabel.ForeColor = $c.Red }
    else                   { $statusLabel.Text = "● scan complete";              $statusLabel.ForeColor = $c.Green }
    $statusLabel.Location = New-Object System.Drawing.Point(($titlePanel.Width - $statusLabel.Width - 16), 15)
    $global:NavButtons["OVERVIEW"].BackColor = $c.Bg3
    Show-Section "OVERVIEW"
}

$rescanBtn.Add_Click({ Start-Scan })
$form.Add_Shown({ Start-Scan })
[System.Windows.Forms.Application]::Run($form)
