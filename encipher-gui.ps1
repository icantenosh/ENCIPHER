$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:EncoderProcess = $null
$script:Stopping = $false
$script:OutputQueue = New-Object "System.Collections.Concurrent.ConcurrentQueue[string]"
$script:ProcessExitPending = $false
$script:ProcessExitCode = 0
$script:RunStartedAt = [DateTime]::MinValue
$script:CurrentSessionLog = ""
$script:LastSessionLogLength = 0
$script:CurrentRunLog = ""
$script:LastRunLogLength = 0
$script:LastProgressLine = ""
$EncipherHome = if ($env:ENCIPHER_HOME) { [System.IO.Path]::GetFullPath($env:ENCIPHER_HOME) } else { $PSScriptRoot }
$EncipherScript = if ($env:ENCIPHER_SCRIPT -and (Test-Path -LiteralPath $env:ENCIPHER_SCRIPT)) { $env:ENCIPHER_SCRIPT } else { Join-Path $PSScriptRoot "encipher.ps1" }
$GuiCrashLog = Join-Path (Join-Path $EncipherHome "logs") "encipher-gui-crash.log"
$ConfigRoot = if ($env:APPDATA) { Join-Path $env:APPDATA "Encipher" } else { Join-Path $HOME ".encipher" }
$ThemeConfigPath = Join-Path $ConfigRoot "gui-theme.json"
$Themes = [ordered]@{
    "Deep Green" = @{
        Bg = "#07130d"; Panel = "#0d2117"; PanelAlt = "#123222"; Entry = "#020b07"; Ink = "#d8ffe6"; Muted = "#75d79c"; Line = "#1d7041"; Accent = "#00ff7f"; AccentActive = "#42ff9e"; ButtonActive = "#17492f"; ButtonPressed = "#0a2618"; Select = "#145f38"
    }
    "Deep Green / Cyan" = @{
        Bg = "#06120f"; Panel = "#0c211b"; PanelAlt = "#102a33"; Entry = "#020b09"; Ink = "#dbfff2"; Muted = "#00d0ff"; Line = "#00d0ff"; Accent = "#00ff7f"; AccentActive = "#00d0ff"; ButtonActive = "#123947"; ButtonPressed = "#071d25"; Select = "#145f50"; TwoTone = $true
    }
    "Neon Violet" = @{
        Bg = "#10091f"; Panel = "#1b1130"; PanelAlt = "#241541"; Entry = "#090412"; Ink = "#f3eaff"; Muted = "#bca7ff"; Line = "#7b49ff"; Accent = "#dd55ff"; AccentActive = "#f08bff"; ButtonActive = "#39215f"; ButtonPressed = "#1f1236"; Select = "#4b2371"
    }
    "Neon Violet / Cyan" = @{
        Bg = "#0d0a22"; Panel = "#171334"; PanelAlt = "#152b46"; Entry = "#070513"; Ink = "#f1efff"; Muted = "#4cc9f0"; Line = "#4cc9f0"; Accent = "#dd55ff"; AccentActive = "#4cc9f0"; ButtonActive = "#1f3a61"; ButtonPressed = "#101f38"; Select = "#343273"; TwoTone = $true
    }
    "Amber CRT" = @{
        Bg = "#0f0a00"; Panel = "#1b1100"; PanelAlt = "#251800"; Entry = "#050300"; Ink = "#ffe0a3"; Muted = "#d8a647"; Line = "#b87400"; Accent = "#ffb000"; AccentActive = "#ffc84a"; ButtonActive = "#3b2600"; ButtonPressed = "#1c1200"; Select = "#5f3d00"
    }
    "Amber CRT / Green" = @{
        Bg = "#0e0b02"; Panel = "#1b1304"; PanelAlt = "#14351d"; Entry = "#050400"; Ink = "#ffedbb"; Muted = "#00ff7f"; Line = "#00a85a"; Accent = "#ffb000"; AccentActive = "#00ff7f"; ButtonActive = "#1d4a29"; ButtonPressed = "#0d2213"; Select = "#554414"; TwoTone = $true
    }
    "Mocha" = @{
        Bg = "#15100d"; Panel = "#211915"; PanelAlt = "#2b211b"; Entry = "#0b0807"; Ink = "#f1dfd1"; Muted = "#c9a58d"; Line = "#8d654d"; Accent = "#e69b5a"; AccentActive = "#ffb775"; ButtonActive = "#3a2b22"; ButtonPressed = "#1c1511"; Select = "#61412f"
    }
    "Mocha / Rose" = @{
        Bg = "#15100f"; Panel = "#211819"; PanelAlt = "#3a202c"; Entry = "#0b0808"; Ink = "#f3dfdc"; Muted = "#ff8ab3"; Line = "#c45f7f"; Accent = "#e69b5a"; AccentActive = "#ff8ab3"; ButtonActive = "#4c2938"; ButtonPressed = "#25131b"; Select = "#613845"; TwoTone = $true
    }
    "Light" = @{
        Bg = "#eef2f5"; Panel = "#ffffff"; PanelAlt = "#e2e8ef"; Entry = "#ffffff"; Ink = "#17212b"; Muted = "#52616f"; Line = "#8aa0b6"; Accent = "#006d77"; AccentActive = "#008891"; ButtonActive = "#d6e4ec"; ButtonPressed = "#c4d4df"; Select = "#b7d7df"
    }
    "Light / Mint" = @{
        Bg = "#eef5f1"; Panel = "#ffffff"; PanelAlt = "#d7f2e5"; Entry = "#ffffff"; Ink = "#172b24"; Muted = "#00a878"; Line = "#00a878"; Accent = "#006d77"; AccentActive = "#00a878"; ButtonActive = "#c4ead8"; ButtonPressed = "#aee0c9"; Select = "#b4ddcb"; TwoTone = $true
    }
    "Midnight Blue" = @{
        Bg = "#07111f"; Panel = "#0d1b2d"; PanelAlt = "#142943"; Entry = "#030914"; Ink = "#dbeaff"; Muted = "#8bb8e8"; Line = "#2d6da3"; Accent = "#4cc9f0"; AccentActive = "#77dcff"; ButtonActive = "#1d3a5d"; ButtonPressed = "#0c1b2e"; Select = "#1b4f78"
    }
    "Midnight Blue / Violet" = @{
        Bg = "#080f22"; Panel = "#101a32"; PanelAlt = "#2a1f52"; Entry = "#040815"; Ink = "#e3e9ff"; Muted = "#b985ff"; Line = "#8a5cf6"; Accent = "#4cc9f0"; AccentActive = "#b985ff"; ButtonActive = "#352764"; ButtonPressed = "#17102e"; Select = "#294a80"; TwoTone = $true
    }
    "Dark" = @{
        Bg = "#0d0f12"; Panel = "#171a1f"; PanelAlt = "#22262d"; Entry = "#080a0d"; Ink = "#e7edf5"; Muted = "#9aa8b8"; Line = "#4c5968"; Accent = "#7dd3fc"; AccentActive = "#a5e3ff"; ButtonActive = "#2c333d"; ButtonPressed = "#15191f"; Select = "#334155"
    }
    "Dark / Redline" = @{
        Bg = "#0e0e10"; Panel = "#191719"; PanelAlt = "#3a1824"; Entry = "#09080a"; Ink = "#f0e8ec"; Muted = "#ff4d6d"; Line = "#c9184a"; Accent = "#7dd3fc"; AccentActive = "#ff4d6d"; ButtonActive = "#4a1f2e"; ButtonPressed = "#211018"; Select = "#4a2a38"; TwoTone = $true
    }
    "Graphite" = @{
        Bg = "#111315"; Panel = "#1b1f22"; PanelAlt = "#282e33"; Entry = "#090b0d"; Ink = "#edf2f6"; Muted = "#a7b0b8"; Line = "#5f6a73"; Accent = "#b9f18c"; AccentActive = "#d2ffad"; ButtonActive = "#343b40"; ButtonPressed = "#191d20"; Select = "#3d4b43"
    }
    "Graphite / Lime" = @{
        Bg = "#101411"; Panel = "#1a211c"; PanelAlt = "#173a32"; Entry = "#080c09"; Ink = "#eef7ef"; Muted = "#40f3c7"; Line = "#40f3c7"; Accent = "#b9f18c"; AccentActive = "#40f3c7"; ButtonActive = "#1e4c42"; ButtonPressed = "#0d241f"; Select = "#3a503e"; TwoTone = $true
    }
}
$SolidThemes = [string[]]@("Deep Green", "Neon Violet", "Amber CRT", "Mocha", "Light", "Midnight Blue", "Dark", "Graphite")
$TwoToneThemes = [string[]]@("Deep Green / Cyan", "Neon Violet / Cyan", "Amber CRT / Green", "Mocha / Rose", "Light / Mint", "Midnight Blue / Violet", "Dark / Redline", "Graphite / Lime")
$ThemeOptions = [string[]]@(
    "Deep Green", "Deep Green / Cyan",
    "Neon Violet", "Neon Violet / Cyan",
    "Amber CRT", "Amber CRT / Green",
    "Mocha", "Mocha / Rose",
    "Light", "Light / Mint",
    "Midnight Blue", "Midnight Blue / Violet",
    "Dark", "Dark / Redline",
    "Graphite", "Graphite / Lime"
)
$script:CurrentThemeColors = $Themes["Deep Green"]

function Write-GuiCrash([object]$errorInfo) {
    try {
        $logDir = Split-Path -Parent $GuiCrashLog
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        @(
            ""
            "=========================================="
            "Encipher GUI crash $(Get-Date)"
            "=========================================="
            "$errorInfo"
        ) | Add-Content -LiteralPath $GuiCrashLog
    } catch {
    }
}

[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)
    Write-GuiCrash $eventArgs.Exception
    [System.Windows.Forms.MessageBox]::Show("Encipher GUI hit an error. Details were written to:`r`n$GuiCrashLog", "Encipher", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    Write-GuiCrash $eventArgs.ExceptionObject
})

function New-Label($text, $x, $y, $w = 120, $h = 22) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Size = New-Object System.Drawing.Size($w, $h)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $label
}

function New-TextBox($x, $y, $w, $text = "") {
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point($x, $y)
    $box.Size = New-Object System.Drawing.Size($w, 24)
    $box.Text = $text
    return $box
}

function New-ComboBox($x, $y, $w, [string[]]$items, $selectedIndex = 0) {
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point($x, $y)
    $combo.Size = New-Object System.Drawing.Size($w, 24)
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $combo.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $combo.ItemHeight = 22
    $combo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $combo.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    [void]$combo.Items.AddRange($items)
    $combo.SelectedIndex = $selectedIndex
    $combo.Add_DrawItem({
        param($sender, $eventArgs)
        if ($eventArgs.Index -lt 0) { return }

        $colors = $script:CurrentThemeColors
        $isSelected = (($eventArgs.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
        $backColor = if ($isSelected) { Convert-Color $colors.Select } else { Convert-Color $colors.Entry }
        $textColor = Get-ReadableTextColor $backColor

        $backBrush = New-Object System.Drawing.SolidBrush $backColor
        $textBrush = New-Object System.Drawing.SolidBrush $textColor
        try {
            $eventArgs.Graphics.FillRectangle($backBrush, $eventArgs.Bounds)
            $text = [string]$sender.Items[$eventArgs.Index]
            if ($text) {
                $textPoint = New-Object System.Drawing.PointF(($eventArgs.Bounds.X + 6), ($eventArgs.Bounds.Y + 3))
                $eventArgs.Graphics.DrawString($text, $sender.Font, $textBrush, $textPoint)
            }
            $eventArgs.DrawFocusRectangle()
        } finally {
            $backBrush.Dispose()
            $textBrush.Dispose()
        }
    })
    return $combo
}

function Get-EncipherSplashText {
    $b = [string][char]0x2588
    $tr = [string][char]0x2557
    $v = [string][char]0x2551
    $tl = [string][char]0x2554
    $h = [string][char]0x2550
    $br = [string][char]0x255D
    $bl = [string][char]0x255A
    return @(
        ("     " + ($b * 7) + $tr + ($b * 3) + $tr + "   " + ($b * 2) + $tr + " " + ($b * 6) + $tr + ($b * 2) + $tr + ($b * 6) + $tr + " " + ($b * 2) + $tr + "  " + ($b * 2) + $tr + ($b * 7) + $tr + ($b * 6) + $tr)
        ("     " + ($b * 2) + $tl + ($h * 4) + $br + ($b * 4) + $tr + "  " + ($b * 2) + $v + ($b * 2) + $tl + ($h * 4) + $br + ($b * 2) + $v + ($b * 2) + $tl + ($h * 2) + ($b * 2) + $tr + ($b * 2) + $v + "  " + ($b * 2) + $v + ($b * 2) + $tl + ($h * 4) + $br + ($b * 2) + $tl + ($h * 2) + ($b * 2) + $tr)
        ("     " + ($b * 5) + $tr + "  " + ($b * 2) + $tl + ($b * 2) + $tr + " " + ($b * 2) + $v + ($b * 2) + $v + "     " + ($b * 2) + $v + ($b * 6) + $tl + $br + ($b * 7) + $v + ($b * 5) + $tr + "  " + ($b * 6) + $tl + $br)
        ("     " + ($b * 2) + $tl + ($h * 2) + $br + "  " + ($b * 2) + $v + $bl + ($b * 2) + $tr + ($b * 2) + $v + ($b * 2) + $v + "     " + ($b * 2) + $v + ($b * 2) + $tl + ($h * 3) + $br + " " + ($b * 2) + $tl + ($h * 2) + ($b * 2) + $v + ($b * 2) + $tl + ($h * 2) + $br + "  " + ($b * 2) + $tl + ($h * 2) + ($b * 2) + $tr)
        ("     " + ($b * 7) + $tr + ($b * 2) + $v + " " + $bl + ($b * 4) + $v + $bl + ($b * 6) + $tr + ($b * 2) + $v + ($b * 2) + $v + "     " + ($b * 2) + $v + "  " + ($b * 2) + $v + ($b * 7) + $tr + ($b * 2) + $v + "  " + ($b * 2) + $v)
        ("     " + $bl + ($h * 6) + $br + $bl + $h + $br + "  " + $bl + ($h * 3) + $br + " " + $bl + ($h * 5) + $br + $bl + $h + $br + $bl + $h + $br + "     " + $bl + $h + $br + "  " + $bl + $h + $br + $bl + ($h * 6) + $br + $bl + $h + $br + "  " + $bl + $h + $br)
    ) -join [Environment]::NewLine
}

function Convert-Color([string]$hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($hex)
}

function Get-ReadableTextColor([System.Drawing.Color]$background) {
    $brightness = (($background.R * 299) + ($background.G * 587) + ($background.B * 114)) / 1000
    if ($brightness -gt 150) { return [System.Drawing.Color]::FromArgb(20, 28, 36) }
    return [System.Drawing.Color]::White
}

function Set-BoldFont([System.Windows.Forms.Control]$control) {
    if ($control.Font) {
        $control.Font = New-Object System.Drawing.Font($control.Font.FontFamily, $control.Font.Size, [System.Drawing.FontStyle]::Bold)
    }
}

function Apply-ButtonTheme([System.Windows.Forms.Button]$button, [hashtable]$colors) {
    $panelAlt = Convert-Color $colors.PanelAlt
    $buttonText = Get-ReadableTextColor $panelAlt
    $line = if ($colors.ContainsKey("TwoTone") -and $colors.TwoTone) { Convert-Color $colors.Line } else { Convert-Color $colors.Accent }

    $button.BackColor = $panelAlt
    $button.ForeColor = $buttonText
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderColor = $line
    $button.FlatAppearance.MouseOverBackColor = Convert-Color $colors.ButtonActive
    $button.FlatAppearance.MouseDownBackColor = Convert-Color $colors.ButtonPressed
    $button.FlatAppearance.BorderSize = 1
    Set-BoldFont $button
}

function Get-SavedTheme {
    try {
        if (Test-Path -LiteralPath $ThemeConfigPath) {
            $data = Get-Content -Raw -LiteralPath $ThemeConfigPath | ConvertFrom-Json
            if ($data.theme -and $Themes.Contains($data.theme)) { return $data.theme }
        }
    } catch {
    }
    return "Deep Green"
}

function Save-Theme([string]$themeName) {
    try {
        New-Item -ItemType Directory -Force -Path $ConfigRoot | Out-Null
        @{ theme = $themeName } | ConvertTo-Json | Set-Content -LiteralPath $ThemeConfigPath
    } catch {
    }
}

function Apply-ControlTheme([System.Windows.Forms.Control]$control, [hashtable]$colors) {
    $bg = Convert-Color $colors.Bg
    $panel = Convert-Color $colors.Panel
    $panelAlt = Convert-Color $colors.PanelAlt
    $entry = Convert-Color $colors.Entry
    $ink = Convert-Color $colors.Ink
    $muted = Convert-Color $colors.Muted
    $accent = Convert-Color $colors.Accent
    $isTwoTone = $colors.ContainsKey("TwoTone") -and $colors.TwoTone
    $controlLine = if ($isTwoTone) { Convert-Color $colors.Line } else { $accent }
    $bgText = Get-ReadableTextColor $bg
    $panelText = Get-ReadableTextColor $panelAlt
    $entryText = Get-ReadableTextColor $entry
    Set-BoldFont $control

    if ($control -is [System.Windows.Forms.TabControl]) {
        $control.BackColor = $bg
        $control.ForeColor = $bgText
    } elseif ($control -is [System.Windows.Forms.TabPage]) {
        $control.BackColor = $bg
        $control.ForeColor = $bgText
    } elseif ($control -is [System.Windows.Forms.TextBox]) {
        $control.BackColor = $entry
        $control.ForeColor = if ($control -eq $summaryBox -or $control -eq $logBox) { $accent } else { $entryText }
        $control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    } elseif ($control -is [System.Windows.Forms.ComboBox] -or $control -is [System.Windows.Forms.NumericUpDown]) {
        $control.BackColor = $entry
        $control.ForeColor = $entryText
    } elseif ($control -is [System.Windows.Forms.Button]) {
        Apply-ButtonTheme $control $colors
    } elseif ($control -is [System.Windows.Forms.CheckBox]) {
        $control.BackColor = $bg
        $control.ForeColor = $bgText
        $control.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    } elseif ($control -is [System.Windows.Forms.Label]) {
        $control.BackColor = $bg
        $control.ForeColor = if ($control.Tag -eq "muted") { $muted } elseif ($control.Tag -eq "splash") { $accent } else { $bgText }
    } else {
        $control.BackColor = $bg
        $control.ForeColor = $bgText
    }

    foreach ($child in $control.Controls) {
        Apply-ControlTheme $child $colors
    }
}

function Apply-Theme([string]$themeName) {
    if (-not $Themes.Contains($themeName)) { $themeName = "Deep Green" }
    $colors = $Themes[$themeName]
    $script:CurrentThemeColors = $colors
    $form.BackColor = Convert-Color $colors.Bg
    Apply-ControlTheme $form $colors
    if (Get-Variable -Name themeBox -Scope Script -ErrorAction SilentlyContinue) {
        if ($themeBox.Items.Contains($themeName) -and $themeBox.SelectedItem -ne $themeName) {
            $themeBox.SelectedItem = $themeName
        }
    }
    Save-Theme $themeName
}

function Quote-Arg([string]$value) {
    if ($null -eq $value) { return '""' }
    if ($value -notmatch '[\s"]') { return $value }
    return '"' + (($value -replace '\\(?=")', '\\') -replace '"', '\"') + '"'
}

function Add-Log([string]$text) {
    if ($null -eq $text) { return }
    if ($text -match "^STARTED\s*:\s*(.+)$") {
        $statusLabel.Text = "Encoding $($matches[1])"
        $script:LastProgressLine = ""
    } elseif ($text -match "^PROGRESS\s*:\s*frame=([^\s]+)\s+fps=([^\s]+)\s+speed=([^\s]+)") {
        $statusLabel.Text = "Frame $($matches[1])  FPS $($matches[2])  Speed $($matches[3])"
        $lineEnding = [Environment]::NewLine
        if ($script:LastProgressLine -and $logBox.Text.EndsWith($script:LastProgressLine + $lineEnding)) {
            $logBox.Text = $logBox.Text.Substring(0, $logBox.Text.Length - ($script:LastProgressLine.Length + $lineEnding.Length))
        }
        $logBox.AppendText($text + $lineEnding)
        $script:LastProgressLine = $text
        $logBox.SelectionStart = $logBox.TextLength
        $logBox.ScrollToCaret()
        return
    } else {
        $script:LastProgressLine = ""
    }
    $logBox.AppendText($text + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
}

function Queue-Log([string]$text) {
    if ($null -ne $text) {
        $script:OutputQueue.Enqueue($text)
    }
}

function Get-CurrentSessionLog {
    if ($script:CurrentSessionLog -and (Test-Path -LiteralPath $script:CurrentSessionLog)) {
        return $script:CurrentSessionLog
    }

    if ($script:RunStartedAt -eq [DateTime]::MinValue) { return "" }

    $logDir = Join-Path $EncipherHome "logs"
    if (-not (Test-Path -LiteralPath $logDir)) { return "" }

    $log = Get-ChildItem -LiteralPath $logDir -Filter "enc_*.txt" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $script:RunStartedAt.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($log) {
        $script:CurrentSessionLog = $log.FullName
        $script:LastSessionLogLength = 0
        return $script:CurrentSessionLog
    }

    return ""
}

function Poll-SessionLog {
    $path = Get-CurrentSessionLog
    if (-not $path) { return }

    try {
        $info = Get-Item -LiteralPath $path
        if ($info.Length -lt $script:LastSessionLogLength) {
            $script:LastSessionLogLength = 0
        }
        if ($info.Length -eq $script:LastSessionLogLength) { return }

        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            [void]$stream.Seek($script:LastSessionLogLength, [System.IO.SeekOrigin]::Begin)
            $reader = New-Object System.IO.StreamReader($stream)
            $text = $reader.ReadToEnd()
            $script:LastSessionLogLength = $stream.Position
        } finally {
            $stream.Dispose()
        }

        if ($text) {
            foreach ($line in ($text -split "\r?\n")) {
                if ($line) { Add-Log $line }
            }
        }
    } catch {
    }
}

function Poll-TextLog([string]$path, [ref]$lastLength) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }

    try {
        $info = Get-Item -LiteralPath $path
        if ($info.Length -lt $lastLength.Value) {
            $lastLength.Value = 0
        }
        if ($info.Length -eq $lastLength.Value) { return }

        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            [void]$stream.Seek($lastLength.Value, [System.IO.SeekOrigin]::Begin)
            $reader = New-Object System.IO.StreamReader($stream)
            $text = $reader.ReadToEnd()
            $lastLength.Value = $stream.Position
        } finally {
            $stream.Dispose()
        }

        if ($text) {
            foreach ($line in ($text -split "\r?\n")) {
                if ($line) { Add-Log $line }
            }
        }
    } catch {
    }
}

function Set-Running([bool]$running) {
    $startButton.Enabled = -not $running
    $stopButton.Enabled = $true
    $inputBrowse.Enabled = -not $running
    $outputBrowse.Enabled = -not $running
    $statusLabel.Text = if ($running) { "Encoding..." } else { "Ready" }
    Apply-ButtonTheme $startButton $script:CurrentThemeColors
    Apply-ButtonTheme $stopButton $script:CurrentThemeColors
    Apply-ButtonTheme $inputBrowse $script:CurrentThemeColors
    Apply-ButtonTheme $outputBrowse $script:CurrentThemeColors
}

function Stop-EncoderProcessTree {
    if (-not $script:EncoderProcess -or $script:EncoderProcess.HasExited) { return }

    $script:Stopping = $true
    $pidText = "$($script:EncoderProcess.Id)"
    try {
        $taskkill = New-Object System.Diagnostics.ProcessStartInfo
        $taskkill.FileName = "taskkill.exe"
        $taskkill.Arguments = "/PID $pidText /T /F"
        $taskkill.UseShellExecute = $false
        $taskkill.CreateNoWindow = $true
        $taskkill.RedirectStandardOutput = $true
        $taskkill.RedirectStandardError = $true
        $killer = [System.Diagnostics.Process]::Start($taskkill)
        $killer.WaitForExit(5000) | Out-Null
    } catch {
        try { $script:EncoderProcess.Kill() } catch { }
    }
}

function Browse-Folder([System.Windows.Forms.TextBox]$target) {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($target.Text -and (Test-Path -LiteralPath $target.Text)) {
        $dialog.SelectedPath = $target.Text
    }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $target.Text = $dialog.SelectedPath
    }
}

function Build-EncipherArgs {
    if (-not $inputBox.Text.Trim()) { throw "Choose an input folder." }
    if (-not (Test-Path -LiteralPath $inputBox.Text.Trim())) { throw "Input folder does not exist." }

    $args = New-Object System.Collections.ArrayList
    [void]$args.AddRange(@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $EncipherScript, "-InputDir", $inputBox.Text.Trim()))

    if ($outputBox.Text.Trim()) {
        [void]$args.AddRange(@("-OutputDir", $outputBox.Text.Trim()))
    }

    $quality = [int]$qualityBox.Value
    switch ($encoderBox.SelectedItem) {
        "CPU x265" {
            [void]$args.AddRange(@("-Encoder", "x265", "-Preset", $presetBox.SelectedItem, "-Crf", "$quality"))
        }
        "NVIDIA NVENC" {
            [void]$args.AddRange(@("-Nvenc", "-Cq", "$quality"))
        }
        "AMD AMF" {
            [void]$args.AddRange(@("-Amf", "-Qp", "$quality"))
        }
    }

    if ($bitDepthBox.SelectedItem -eq "10-bit") {
        [void]$args.AddRange(@("-Profile", "main10", "-PixFmt", "yuv420p10le"))
    } else {
        [void]$args.AddRange(@("-Profile", "main", "-PixFmt", "yuv420p"))
    }

    switch ($audioBox.SelectedItem) {
        "Stereo 2.0" { [void]$args.AddRange(@("-AudioChannels", "2", "-AudioBitrate", $audioRateBox.SelectedItem)) }
        "Surround 5.1" { [void]$args.AddRange(@("-AudioChannels", "6", "-AudioBitrate", $audioRateBox.SelectedItem)) }
        "Surround 7.1" { [void]$args.AddRange(@("-AudioChannels", "8", "-AudioBitrate", $audioRateBox.SelectedItem)) }
        "Copy audio" { [void]$args.Add("-AudioCopy") }
        "No audio" { [void]$args.Add("-AudioNone") }
    }

    if ($subsBox.SelectedItem -eq "No subtitles") {
        [void]$args.Add("-SubsNone")
    } else {
        [void]$args.Add("-SubsCopy")
    }

    switch ($denoiseBox.SelectedItem) {
        "Ultra light" { [void]$args.AddRange(@("-VideoFilter", "hqdn3d=0.8:0.8:4:4")) }
        "Light" { [void]$args.AddRange(@("-VideoFilter", "hqdn3d=1.2:1.2:5:5")) }
        "Light-medium" { [void]$args.AddRange(@("-VideoFilter", "hqdn3d=1.6:1.6:5.5:5.5")) }
        "Medium" { [void]$args.AddRange(@("-VideoFilter", "hqdn3d=2:2:6:6")) }
        "Strong" { [void]$args.AddRange(@("-VideoFilter", "hqdn3d=3:3:8:8")) }
    }

    if ($overwriteCheck.Checked) { [void]$args.Add("-Overwrite") }
    return $args
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Encipher"
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(940, 820)
$form.Size = New-Object System.Drawing.Size(1040, 860)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 248, 248)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$form.Controls.Add($tabs)

$encodeTab = New-Object System.Windows.Forms.TabPage
$encodeTab.Text = "Encode"
$encodeTab.BackColor = $form.BackColor
$tabs.TabPages.Add($encodeTab)

$logTab = New-Object System.Windows.Forms.TabPage
$logTab.Text = "Output"
$logTab.BackColor = $form.BackColor
$tabs.TabPages.Add($logTab)

$splashLabel = New-Object System.Windows.Forms.Label
$splashLabel.Text = Get-EncipherSplashText
$splashLabel.Tag = "splash"
$splashLabel.Location = New-Object System.Drawing.Point(18, 14)
$splashLabel.Size = New-Object System.Drawing.Size(660, 112)
$splashLabel.Font = New-Object System.Drawing.Font("Consolas", 8.5, [System.Drawing.FontStyle]::Bold)
$splashLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$encodeTab.Controls.Add($splashLabel)

$themeLabel = New-Label "THEME" 700 18 90 18
$themeLabel.Tag = "muted"
$encodeTab.Controls.Add($themeLabel)
$themeBox = New-ComboBox 700 40 295 $ThemeOptions 0
$themeBox.Tag = "chrome"
$encodeTab.Controls.Add($themeBox)

$encodeTab.Controls.Add((New-Label "Input folder" 18 20))
$inputBox = New-TextBox 140 20 660
$encodeTab.Controls.Add($inputBox)
$inputBrowse = New-Object System.Windows.Forms.Button
$inputBrowse.Text = "Browse"
$inputBrowse.Location = New-Object System.Drawing.Point(815, 18)
$inputBrowse.Size = New-Object System.Drawing.Size(95, 28)
$inputBrowse.Add_Click({ Browse-Folder $inputBox })
$encodeTab.Controls.Add($inputBrowse)

$encodeTab.Controls.Add((New-Label "Output folder" 18 58))
$outputBox = New-TextBox 140 58 660
$encodeTab.Controls.Add($outputBox)
$outputBrowse = New-Object System.Windows.Forms.Button
$outputBrowse.Text = "Browse"
$outputBrowse.Location = New-Object System.Drawing.Point(815, 56)
$outputBrowse.Size = New-Object System.Drawing.Size(95, 28)
$outputBrowse.Add_Click({ Browse-Folder $outputBox })
$encodeTab.Controls.Add($outputBrowse)

$encodeTab.Controls.Add((New-Label "Encoder" 18 112))
$encoderBox = New-ComboBox 140 112 180 @("CPU x265", "NVIDIA NVENC", "AMD AMF") 0
$encodeTab.Controls.Add($encoderBox)

$encodeTab.Controls.Add((New-Label "CPU preset" 350 112))
$presetBox = New-ComboBox 465 112 150 @("veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow") 2
$encodeTab.Controls.Add($presetBox)

$encodeTab.Controls.Add((New-Label "Quality" 645 112 70))
$qualityBox = New-Object System.Windows.Forms.NumericUpDown
$qualityBox.Location = New-Object System.Drawing.Point(715, 112)
$qualityBox.Size = New-Object System.Drawing.Size(70, 24)
$qualityBox.Minimum = 0
$qualityBox.Maximum = 51
$qualityBox.Value = 22
$qualityBox.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$qualityBox.ForeColor = [System.Drawing.Color]::White
$encodeTab.Controls.Add($qualityBox)

$encodeTab.Controls.Add((New-Label "Bit depth" 18 154))
$bitDepthBox = New-ComboBox 140 154 180 @("10-bit", "8-bit") 0
$encodeTab.Controls.Add($bitDepthBox)

$encodeTab.Controls.Add((New-Label "Denoise" 350 154))
$denoiseBox = New-ComboBox 465 154 150 @("Off", "Ultra light", "Light", "Light-medium", "Medium", "Strong") 0
$encodeTab.Controls.Add($denoiseBox)

$encodeTab.Controls.Add((New-Label "Audio" 18 210))
$audioBox = New-ComboBox 140 210 180 @("Surround 5.1", "Stereo 2.0", "Surround 7.1", "Copy audio", "No audio") 0
$encodeTab.Controls.Add($audioBox)

$encodeTab.Controls.Add((New-Label "AAC bitrate" 350 210))
$audioRateBox = New-ComboBox 465 210 150 @("128k", "192k", "256k", "320k", "384k", "448k", "512k", "640k") 4
$encodeTab.Controls.Add($audioRateBox)

$encodeTab.Controls.Add((New-Label "Subtitles" 645 210 70))
$subsBox = New-ComboBox 715 210 140 @("Copy subtitles", "No subtitles") 0
$encodeTab.Controls.Add($subsBox)

$overwriteCheck = New-Object System.Windows.Forms.CheckBox
$overwriteCheck.Text = "Overwrite existing output"
$overwriteCheck.Location = New-Object System.Drawing.Point(140, 260)
$overwriteCheck.Size = New-Object System.Drawing.Size(210, 24)
$overwriteCheck.Checked = $true
$encodeTab.Controls.Add($overwriteCheck)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start Encode"
$startButton.Location = New-Object System.Drawing.Point(140, 315)
$startButton.Size = New-Object System.Drawing.Size(140, 36)
$encodeTab.Controls.Add($startButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop"
$stopButton.Location = New-Object System.Drawing.Point(295, 315)
$stopButton.Size = New-Object System.Drawing.Size(100, 36)
$stopButton.Enabled = $true
$encodeTab.Controls.Add($stopButton)

$openLogsButton = New-Object System.Windows.Forms.Button
$openLogsButton.Text = "Open Logs"
$openLogsButton.Location = New-Object System.Drawing.Point(410, 315)
$openLogsButton.Size = New-Object System.Drawing.Size(110, 36)
$openLogsButton.Add_Click({
    $logs = Join-Path $EncipherHome "logs"
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    Start-Process explorer.exe $logs
})
$encodeTab.Controls.Add($openLogsButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready"
$statusLabel.Location = New-Object System.Drawing.Point(140, 375)
$statusLabel.Size = New-Object System.Drawing.Size(700, 24)
$encodeTab.Controls.Add($statusLabel)

$summaryBox = New-Object System.Windows.Forms.TextBox
$summaryBox.Location = New-Object System.Drawing.Point(140, 420)
$summaryBox.Size = New-Object System.Drawing.Size(720, 130)
$summaryBox.Multiline = $true
$summaryBox.ReadOnly = $true
$summaryBox.Text = "Choose folders and settings, then start encoding. Live FFmpeg output appears on the Output tab."
$encodeTab.Controls.Add($summaryBox)

foreach ($control in $encodeTab.Controls) {
    if ($control -ne $splashLabel -and $control -ne $themeLabel -and $control -ne $themeBox) {
        $control.Location = New-Object System.Drawing.Point($control.Location.X, ($control.Location.Y + 125))
    }
}

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$logBox.WordWrap = $false
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logTab.Controls.Add($logBox)

$encoderBox.Add_SelectedIndexChanged({
    $presetBox.Enabled = ($encoderBox.SelectedItem -eq "CPU x265")
})

$savedTheme = Get-SavedTheme
if ($themeBox.Items.Contains($savedTheme)) {
    $themeBox.SelectedItem = $savedTheme
}
$themeBox.Add_SelectedIndexChanged({
    Apply-Theme $themeBox.SelectedItem
})

$startButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $EncipherScript)) { throw "Could not find encipher.ps1." }
        $args = Build-EncipherArgs
        $commandLine = ($args | ForEach-Object { Quote-Arg "$_" }) -join " "
        $summaryBox.Text = "powershell $commandLine"
        $logBox.Clear()
        Add-Log "Starting Encipher..."
        Add-Log $summaryBox.Text
        $tabs.SelectedTab = $logTab

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = $commandLine
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false
        $psi.RedirectStandardInput = $false
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables["ENCIPHER_HOME"] = $EncipherHome
        if ($env:ENCIPHER_FFMPEG) { $psi.EnvironmentVariables["ENCIPHER_FFMPEG"] = $env:ENCIPHER_FFMPEG }
        if ($env:ENCIPHER_FFPROBE) { $psi.EnvironmentVariables["ENCIPHER_FFPROBE"] = $env:ENCIPHER_FFPROBE }

        $script:EncoderProcess = New-Object System.Diagnostics.Process
        $script:EncoderProcess.StartInfo = $psi
        $script:EncoderProcess.EnableRaisingEvents = $true
        $script:Stopping = $false
        $script:ProcessExitPending = $false
        $script:ProcessExitCode = 0
        $script:RunStartedAt = Get-Date
        $script:CurrentSessionLog = ""
        $script:LastSessionLogLength = 0
        $logDir = Join-Path $EncipherHome "logs"
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $script:CurrentRunLog = Join-Path $logDir ("encipher-gui-run_{0}.log" -f (Get-Date -Format "yyMMdd_HHmmss"))
        $script:LastRunLogLength = 0

        $exitHandler = [System.EventHandler]{
            try { $script:ProcessExitCode = $script:EncoderProcess.ExitCode } catch { $script:ProcessExitCode = -1 }
            $script:ProcessExitPending = $true
        }

        $script:EncoderProcess.add_Exited($exitHandler)
        [void]$script:EncoderProcess.Start()
        Add-Content -LiteralPath $script:CurrentRunLog -Value "Started: powershell $commandLine"
        Set-Running $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Encipher", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$stopButton.Add_Click({
    if ($script:EncoderProcess -and -not $script:EncoderProcess.HasExited) {
        Add-Log "Stopping..."
        Stop-EncoderProcessTree
    }
})

$form.Add_FormClosing({
    if ($script:EncoderProcess -and -not $script:EncoderProcess.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show($form, "An encode is still running. Stop it and close?", "Encipher", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            $_.Cancel = $true
            return
        }
        Stop-EncoderProcessTree
    }
})

$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 100
$uiTimer.Add_Tick({
    try {
        Poll-TextLog $script:CurrentRunLog ([ref]$script:LastRunLogLength)
        Poll-SessionLog

        $line = ""
        while ($script:OutputQueue.TryDequeue([ref]$line)) {
            Add-Log $line
        }

        if ($script:ProcessExitPending) {
            $script:ProcessExitPending = $false
            Set-Running $false
            $code = $script:ProcessExitCode
            $statusLabel.Text = if ($script:Stopping) { "Stopped" } elseif ($code -eq 0) { "Completed" } else { "Failed with exit code $code" }
            Add-Log ""
            Add-Log $statusLabel.Text
        }
    } catch {
        Write-GuiCrash $_
    }
})
$uiTimer.Start()

Apply-Theme $savedTheme

[void][System.Windows.Forms.Application]::Run($form)
