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
                            $results[$s] += @{ Line="[WARN]  $($jar.Name)  ->  no mod ID found"; Type="WARN" }
                        }
                    } else {
                        $results[$s] += @{ Line="[WARN]  $($jar.Name)  ->  no manifest"; Type="WARN" }
                    }
                    $zip.Dispose()
                } catch {
                    $results[$s] += @{ Line="[WARN]  $($jar.Name)  ->  unreadable"; Type="WARN" }
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

                <StackPanel Grid.Row="0" Margin="0,12,0,0">
                    <TextBlock Text="  CHECKS" FontFamily="Consolas" FontSize="8"
                               Foreground="#6B7280" Margin="0,0,0,6"/>

                    <Button x:Name="BtnOverview"      Content="  Overview"       Style="{StaticResource NavBtnActive}" Tag="OVERVIEW"/>
                    <Button x:Name="BtnModScanner"    Content="  Mod Scanner"    Style="{StaticResource NavBtn}"       Tag="MOD SCANNER"/>
                    <Button x:Name="BtnRenamedJars"   Content="  Renamed Jars"   Style="{StaticResource NavBtn}"       Tag="RENAMED JARS"/>
                    <Button x:Name="BtnRecycleBin"    Content="  Recycle Bin"    Style="{StaticResource NavBtn}"       Tag="RECYCLE BIN"/>
                    <Button x:Name="BtnDeletedFiles"  Content="  Deleted Files"  Style="{StaticResource NavBtn}"       Tag="DELETED FILES"/>
                    <Button x:Name="BtnRecentChanges" Content="  Recent Changes" Style="{StaticResource NavBtn}"       Tag="RECENT CHANGES"/>

                    <Rectangle Height="1" Fill="#282D37" Margin="12,10"/>
                </StackPanel>

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

$NavBtns = @{
    "OVERVIEW"       = $window.FindName("BtnOverview")
    "MOD SCANNER"    = $window.FindName("BtnModScanner")
    "RENAMED JARS"   = $window.FindName("BtnRenamedJars")
    "RECYCLE BIN"    = $window.FindName("BtnRecycleBin")
    "DELETED FILES"  = $window.FindName("BtnDeletedFiles")
    "RECENT CHANGES" = $window.FindName("BtnRecentChanges")
}

$PathBox.Text = $global:CustomModsPath

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
    $global:ActiveSection = $key
    $ResultsList.Items.Clear()
    $PathBar.Visibility = if ($key -eq "MOD SCANNER") { "Visible" } else { "Collapsed" }

    foreach ($b in $NavBtns.Values) {
        $b.Style = $window.Resources["NavBtn"]
    }
    if ($NavBtns.ContainsKey($key)) {
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
        if (-not $NavBtns.ContainsKey($sec)) { continue }
        $hasFlag = ($global:ScanResults[$sec] | Where-Object { $_.Type -eq "FLAG" }).Count -gt 0
        $hasWarn = ($global:ScanResults[$sec] | Where-Object { $_.Type -eq "WARN" }).Count -gt 0
        $btn = $NavBtns[$sec]
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
foreach ($kvp in $NavBtns.GetEnumerator()) {
    $key = $kvp.Key
    $kvp.Value.Add_Click({ Show-Section $key }.GetNewClosure())
}

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
