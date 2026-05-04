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
    try {
        $shell = New-Object -ComObject Shell.Application
        $items = $shell.Namespace(0xA).Items()
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
            <Setter Property="Background" Value="#13161B"/>
            <Setter Property="Foreground" Value="#4F8EF7"/>
            <Setter Property="BorderBrush" Value="#282D37"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Height" Value="28"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#1A1E25"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ScanBtn" TargetType="Button" BasedOn="{StaticResource ActionBtn}">
            <Setter Property="Foreground" Value="#4FF78E"/>
            <Setter Property="BorderBrush" Value="#2A4A38"/>
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
$NavBtns["LOG SCANNER"].Add_Click(   { Show-Section "LOG SCANNER" })
$NavBtns["MEMORY SCAN"].Add_Click(   { Show-Section "MEMORY SCAN" })

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
    Title="Memory Scan — Krom SS Tools" Height="580" Width="780"
    MinHeight="400" MinWidth="600"
    Background="#0D0F12" Foreground="#E8EAF0"
    WindowStartupLocation="CenterScreen" ResizeMode="CanResize">
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
                <TextBlock Text="MEMORY SCAN" FontFamily="Consolas" FontWeight="Bold" FontSize="13"
                           Foreground="#E8EAF0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="MemStatus" Text="● idle" FontFamily="Consolas" FontSize="10"
                       Foreground="#6B7280" VerticalAlignment="Center"
                       HorizontalAlignment="Right" Margin="0,0,18,0"/>
        </Grid>
        <Rectangle Grid.Row="1" Fill="#282D37"/>

        <!-- Info bar -->
        <Grid Grid.Row="2" Background="#13161B" Margin="0,0,0,0">
            <StackPanel Orientation="Horizontal" Margin="18,10,18,10">
                <TextBlock Text="Scans: " FontFamily="Consolas" FontSize="10" Foreground="#6B7280" VerticalAlignment="Center"/>
                <TextBlock Text="javaw.exe memory  " FontFamily="Consolas" FontSize="10" Foreground="#9CA3AF" VerticalAlignment="Center"/>
                <TextBlock Text="•  " Foreground="#282D37" VerticalAlignment="Center"/>
                <TextBlock Text="temp artifacts  " FontFamily="Consolas" FontSize="10" Foreground="#9CA3AF" VerticalAlignment="Center"/>
                <TextBlock Text="•  " Foreground="#282D37" VerticalAlignment="Center"/>
                <TextBlock Text="recent files  " FontFamily="Consolas" FontSize="10" Foreground="#9CA3AF" VerticalAlignment="Center"/>
                <TextBlock Text="•  " Foreground="#282D37" VerticalAlignment="Center"/>
                <TextBlock Text="registry" FontFamily="Consolas" FontSize="10" Foreground="#9CA3AF" VerticalAlignment="Center"/>
                <TextBlock Text="   |   Requires Administrator for memory read"
                           FontFamily="Consolas" FontSize="10" Foreground="#F7A94F" VerticalAlignment="Center"/>
            </StackPanel>
        </Grid>
        <Rectangle Grid.Row="3" Fill="#282D37"/>

        <!-- Results -->
        <ListBox x:Name="MemList" Grid.Row="4"
                 Background="Transparent" BorderThickness="0"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                 VirtualizingPanel.IsVirtualizing="True"
                 Margin="0,6,0,0" Padding="0">
            <ListBox.ItemContainerStyle>
                <Style TargetType="ListBoxItem">
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
            </ListBox.ItemContainerStyle>
        </ListBox>

        <!-- Bottom bar -->
        <Grid Grid.Row="5" Background="#13161B" Height="52">
            <Rectangle Height="1" VerticalAlignment="Top" Fill="#282D37"/>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,18,0">
                <Button x:Name="BtnStartMemScan" Content="  Run Memory Scan"
                        FontFamily="Consolas" FontSize="11"
                        Background="#1A1E25" Foreground="#4FF78E"
                        BorderBrush="#2A4A38" BorderThickness="1"
                        Height="32" Padding="16,0" Cursor="Hand">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="4">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#1F2A22"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
                <Button x:Name="BtnClearMem" Content="  Clear"
                        FontFamily="Consolas" FontSize="11"
                        Background="#1A1E25" Foreground="#6B7280"
                        BorderBrush="#282D37" BorderThickness="1"
                        Height="32" Padding="16,0" Cursor="Hand" Margin="8,0,0,0">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="4">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
                <TextBlock x:Name="MemSummary" Text="" FontFamily="Consolas" FontSize="10"
                           Foreground="#6B7280" VerticalAlignment="Center" Margin="16,0,0,0"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

    $memReader = New-Object System.Xml.XmlNodeReader $memXaml
    $memWin    = [Windows.Markup.XamlReader]::Load($memReader)

    $script:mMemList         = $memWin.FindName("MemList")
    $script:mMemStatus       = $memWin.FindName("MemStatus")
    $script:mMemSummary      = $memWin.FindName("MemSummary")
    $script:mBtnStartMemScan = $memWin.FindName("BtnStartMemScan")
    $script:mBtnClearMem     = $memWin.FindName("BtnClearMem")
    $script:mMemWin          = $memWin
    $script:mBrush           = [System.Windows.Media.BrushConverter]::new()

    function Add-MemRow($text, $type) {
        $row = New-Object System.Windows.Controls.Border
        $row.Margin       = New-Object System.Windows.Thickness(12,2,12,0)
        $row.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $row.Padding      = New-Object System.Windows.Thickness(10,6,10,6)
        switch ($type) {
            "FLAG" { $row.Background = $script:mBrush.ConvertFrom("#281010"); $fg = "#F7A0A0" }
            "WARN" { $row.Background = $script:mBrush.ConvertFrom("#28200E"); $fg = "#E0B87A" }
            "OK"   { $row.Background = $script:mBrush.ConvertFrom("#0E2014"); $fg = "#7ADFAA" }
            "HEAD" { $row.Background = $script:mBrush.ConvertFrom("#1A1E25"); $fg = "#4F8EF7" }
            default{ $row.Background = $script:mBrush.ConvertFrom("#13161B"); $fg = "#6B7280" }
        }
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text         = $text
        $tb.FontFamily   = New-Object System.Windows.Media.FontFamily("Consolas")
        $tb.FontSize     = 11
        $tb.Foreground   = $script:mBrush.ConvertFrom($fg)
        $tb.TextWrapping = "Wrap"
        $row.Child = $tb
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content         = $row
        $item.Background      = [System.Windows.Media.Brushes]::Transparent
        $item.BorderThickness = New-Object System.Windows.Thickness(0)
        $item.Padding         = New-Object System.Windows.Thickness(0)
        $script:mMemList.Items.Add($item) | Out-Null
    }

    $script:mBtnClearMem.Add_Click({
        $script:mMemList.Items.Clear()
        $script:mMemSummary.Text      = ""
        $script:mMemStatus.Text       = "● idle"
        $script:mMemStatus.Foreground = $script:mBrush.ConvertFrom("#6B7280")
    })

    $script:mBtnStartMemScan.Add_Click({
        $script:mBtnStartMemScan.IsEnabled = $false
        $script:mMemList.Items.Clear()
        $script:mMemStatus.Text       = "● scanning..."
        $script:mMemStatus.Foreground = $script:mBrush.ConvertFrom("#F7A94F")
        $script:mMemSummary.Text      = ""
        $script:mMemWin.Dispatcher.Invoke([action]{}, "Render")

        $doomStrings = @(
            "selfdestruct","self_destruct","selfdestructing",
            "deleteself","delete_self","deleteonshutdown",
            "cleanupfiles","cleanup_jar","purgefiles",
            "Files.delete","deleteOnExit","file.deleteonexit",
            "Runtime.exec","ProcessBuilder","cmd.exe /c del",
            "powershell -c del","rmdir /s","rm -rf",
            "javaagent","java.lang.instrument","Instrumentation",
            "retransformClasses","redefineClasses",
            "ClassFileTransformer","premain",
            "sun.misc.Unsafe","theUnsafe",
            "net.bytebuddy","javassist.ClassPool",
            "org.objectweb.asm.ClassWriter"
        )

        $rows = [System.Collections.Generic.List[hashtable]]::new()
        $totalFound = 0

        # Memory strings
        $rows.Add(@{ T="  -- MEMORY STRINGS (javaw.exe) --"; K="HEAD" })
        $javaProcs = Get-Process -Name "javaw" -ErrorAction SilentlyContinue
        if (-not $javaProcs) {
            $rows.Add(@{ T="  [INFO]  No javaw.exe running -- start Minecraft first"; K="INFO" })
        } else {
            $PROCESS_ALL_ACCESS = 0x1F0FFF
            foreach ($proc in $javaProcs) {
                $pid = $proc.Id
                $rows.Add(@{ T="  Scanning PID $pid..."; K="INFO" })
                try {
                    $hProc = [MemAPI]::OpenProcess($PROCESS_ALL_ACCESS, $false, $pid)
                    if ($hProc -eq [IntPtr]::Zero) {
                        $rows.Add(@{ T="  [WARN]  Cannot open PID $pid -- run as Administrator"; K="WARN" })
                        continue
                    }
                    $mbi     = New-Object MemAPI+MEMORY_BASIC_INFORMATION
                    $mbiSize = [System.Runtime.InteropServices.Marshal]::SizeOf($mbi)
                    $addr    = [IntPtr]::Zero
                    $hitCount = 0
                    while ([MemAPI]::VirtualQueryEx($hProc, $addr, [ref]$mbi, $mbiSize)) {
                        if ($mbi.State -eq 0x1000 -and ($mbi.Protect -band 0x02 -or $mbi.Protect -band 0x04 -or $mbi.Protect -band 0x20 -or $mbi.Protect -band 0x40)) {
                            $size = $mbi.RegionSize.ToInt64()
                            if ($size -gt 0 -and $size -lt 50MB) {
                                $buf  = New-Object byte[] $size
                                $read = 0
                                if ([MemAPI]::ReadProcessMemory($hProc, $mbi.BaseAddress, $buf, $size, [ref]$read) -and $read -gt 0) {
                                    $text = [System.Text.Encoding]::ASCII.GetString($buf, 0, $read)
                                    foreach ($sig in $doomStrings) {
                                        if ($text -match [regex]::Escape($sig)) {
                                            $rows.Add(@{ T="  [FLAGGED]  PID $pid  ->  string: '$sig'"; K="FLAG" })
                                            $hitCount++; $totalFound++; break
                                        }
                                    }
                                }
                            }
                        }
                        $next = $mbi.BaseAddress.ToInt64() + $mbi.RegionSize.ToInt64()
                        if ($next -le 0) { break }
                        try { $addr = [IntPtr]::new($next) } catch { break }
                    }
                    [MemAPI]::CloseHandle($hProc) | Out-Null
                    if ($hitCount -eq 0) { $rows.Add(@{ T="  [OK]  PID $pid -- no suspicious strings found"; K="OK" }) }
                } catch {
                    $rows.Add(@{ T="  [WARN]  Error scanning PID $($pid): $($_.Exception.Message)"; K="WARN" })
                }
            }
        }

        # Temp artifacts
        $rows.Add(@{ T="  -- TEMP FOLDER ARTIFACTS --"; K="HEAD" })
        $tempPaths = @($env:TEMP, "$env:LOCALAPPDATA\Temp", "$env:APPDATA\.minecraft\crash-reports")
        $tempFound = 0
        foreach ($tp in $tempPaths) {
            if (-not (Test-Path $tp)) { continue }
            foreach ($ext in @("*.jar","*.tmp","*.class","*.dll")) {
                $files = Get-ChildItem $tp -Filter $ext -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) }
                foreach ($f in $files) {
                    $isSusp = $false
                    foreach ($sig in @("doomsday","ddclient","cheat","hack","inject","wurst","meteor")) {
                        if ($f.Name -match $sig) { $isSusp = $true; break }
                    }
                    $bn = ($f.BaseName -replace "[^a-zA-Z]","")
                    if ($bn.Length -lt 3 -and $f.Extension -eq ".jar") { $isSusp = $true }
                    $line = "$($f.FullName)  |  $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
                    if ($isSusp) { $rows.Add(@{ T="  [FLAGGED]  $line"; K="FLAG" }); $tempFound++; $totalFound++ }
                    else         { $rows.Add(@{ T="  [WARN]  $line"; K="WARN" }) }
                }
            }
        }
        if ($tempFound -eq 0) { $rows.Add(@{ T="  [OK]  No suspicious temp artifacts found"; K="OK" }) }

        # Recent files
        $rows.Add(@{ T="  -- RECENT FILES --"; K="HEAD" })
        $recentPath = "$env:APPDATA\Microsoft\Windows\Recent"
        if (Test-Path $recentPath) {
            $recentFiles = Get-ChildItem $recentPath -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-14) } |
                Sort-Object LastWriteTime -Descending
            $recentFlags = 0
            foreach ($rf in $recentFiles) {
                foreach ($sig in @("doomsday","ddclient","cheat","hack","wurst","meteor","inject","liquidbounce")) {
                    if ($rf.Name.ToLower() -match $sig) {
                        $rows.Add(@{ T="  [FLAGGED]  $($rf.Name)  |  $($rf.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"; K="FLAG" })
                        $recentFlags++; $totalFound++; break
                    }
                }
            }
            $rows.Add(@{ T="  [INFO]  $($recentFiles.Count) entries checked, $recentFlags flagged"; K="INFO" })
        } else {
            $rows.Add(@{ T="  [WARN]  Recent files folder not accessible"; K="WARN" })
        }

        # Registry
        $rows.Add(@{ T="  -- REGISTRY CHECK --"; K="HEAD" })
        $regPaths = @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
            "HKCU:\Software\JavaSoft",
            "HKLM:\Software\JavaSoft"
        )
        $regFlags = 0
        foreach ($rp in $regPaths) {
            if (-not (Test-Path $rp)) { continue }
            try {
                $vals = Get-ItemProperty $rp -ErrorAction SilentlyContinue
                if ($vals) {
                    $vals.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                        $valStr = "$($_.Name) = $($_.Value)"
                        foreach ($sig in @("doomsday","ddclient","cheat","hack","inject","wurst","meteor","javaagent")) {
                            if ($valStr.ToLower() -match $sig) {
                                $rows.Add(@{ T="  [FLAGGED]  $rp  ->  $valStr"; K="FLAG" })
                                $regFlags++; $totalFound++; break
                            }
                        }
                    }
                }
            } catch {}
        }
        if ($regFlags -eq 0) { $rows.Add(@{ T="  [OK]  No suspicious registry entries found"; K="OK" }) }

        # Push all to UI at once on the dispatcher
        $tf = $totalFound
        $capturedRows = $rows
        $script:mMemWin.Dispatcher.Invoke([action]{
            foreach ($row in $capturedRows) {
                $r = New-Object System.Windows.Controls.Border
                $r.Margin       = New-Object System.Windows.Thickness(12,2,12,0)
                $r.CornerRadius = New-Object System.Windows.CornerRadius(4)
                $r.Padding      = New-Object System.Windows.Thickness(10,6,10,6)
                switch ($row.K) {
                    "FLAG" { $r.Background = $script:mBrush.ConvertFrom("#281010"); $fg = "#F7A0A0" }
                    "WARN" { $r.Background = $script:mBrush.ConvertFrom("#28200E"); $fg = "#E0B87A" }
                    "OK"   { $r.Background = $script:mBrush.ConvertFrom("#0E2014"); $fg = "#7ADFAA" }
                    "HEAD" { $r.Background = $script:mBrush.ConvertFrom("#1A1E25"); $fg = "#4F8EF7" }
                    default{ $r.Background = $script:mBrush.ConvertFrom("#13161B"); $fg = "#6B7280" }
                }
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text         = $row.T
                $tb.FontFamily   = New-Object System.Windows.Media.FontFamily("Consolas")
                $tb.FontSize     = 11
                $tb.Foreground   = $script:mBrush.ConvertFrom($fg)
                $tb.TextWrapping = "Wrap"
                $r.Child = $tb
                $li = New-Object System.Windows.Controls.ListBoxItem
                $li.Content         = $r
                $li.Background      = [System.Windows.Media.Brushes]::Transparent
                $li.BorderThickness = New-Object System.Windows.Thickness(0)
                $li.Padding         = New-Object System.Windows.Thickness(0)
                $script:mMemList.Items.Add($li) | Out-Null
            }
            $script:mMemStatus.Text       = if ($tf -gt 0) { "● $tf finding(s)" } else { "● clean" }
            $script:mMemStatus.Foreground = if ($tf -gt 0) { $script:mBrush.ConvertFrom("#F74F4F") } else { $script:mBrush.ConvertFrom("#4FF78E") }
            $script:mMemSummary.Text      = "Scan complete -- $tf suspicious finding(s)"
            $script:mBtnStartMemScan.IsEnabled = $true
        }.GetNewClosure(), "Normal")
    })

    # Run the window on its own thread so it doesn't block main UI
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
