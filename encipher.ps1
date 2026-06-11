$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$CliArgs = @($args)

$InputDir = ""
$OutputDir = ""
$Encoder = "x265"
$Crf = 24
$Cq = 24
$Qp = 24
$Preset = "medium"
$Tune = ""
$X265Params = ""
$VideoBitrate = ""
$Maxrate = ""
$Bufsize = ""
$Profile = ""
$PixFmt = ""
$Scale = ""
$Fps = ""
$VideoFilter = ""
$NvencPreset = "p5"
$NvencRc = "vbr"
$Gpu = -1
$AmfQuality = "quality"
$AmfRc = "cqp"
$AudioLayout = ""
$AudioChannels = 0
$AudioBitrate = "160k"
$AudioFilter = ""
$AudioCopy = $false
$AudioNone = $false
$SubsNone = $false
$Overwrite = $false
$Help = $false
$ResumeLog = ""
$ResumeMode = $false
$ResumeVideoArgLine = ""
$ResumeAudioArgLine = ""
$ResumeSubtitleArgLine = ""
$ResumeFilterLine = ""
$CompletedRelativePaths = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
$InteractiveMode = $false
$EncipherHome = if ($env:ENCIPHER_HOME) { [System.IO.Path]::GetFullPath($env:ENCIPHER_HOME) } else { $PSScriptRoot }
$EncipherFfmpeg = if ($env:ENCIPHER_FFMPEG -and (Test-Path -LiteralPath $env:ENCIPHER_FFMPEG)) { $env:ENCIPHER_FFMPEG } else { "ffmpeg" }
$EncipherFfprobe = if ($env:ENCIPHER_FFPROBE -and (Test-Path -LiteralPath $env:ENCIPHER_FFPROBE)) { $env:ENCIPHER_FFPROBE } else { "ffprobe" }

function Show-Help {
    @"
encipher - recursively transcode videos to HEVC video and AAC audio

Usage:
  encipher.bat
  encipher.bat -InputDir "D:\Videos" -OutputDir "D:\Encoded" [options]

Input:
  -InputDir DIR              Source directory to scan recursively.
  -OutputDir DIR             Output directory. Defaults to INPUT\converted.
                              Folder structure is mirrored here.

Encoder selection:
  -Encoder x265|nvenc|amf    CPU x265, NVIDIA NVENC, or AMD AMF. Default: x265.
  -Nvenc                     Shortcut for -Encoder nvenc.
  -Amf                       Shortcut for -Encoder amf.

Video quality:
  -Crf N                     x265 quality, lower is better/larger. Default: 24.
  -Cq N                      NVENC constant quality. Default: 24.
  -Qp N                      AMD AMF CQP quality. Default: 24.
  -Preset NAME               x265 preset. Default: medium.
  -Grain                     Shortcut for -Tune grain on x265.
  -Tune NAME                 x265 tune, such as grain, film, animation.
  -X265Params TEXT           Extra x265 params, e.g. "aq-mode=3:psy-rd=2.0".
  -VideoBitrate RATE         Target bitrate, e.g. 6000k.
  -Maxrate RATE              VBV max rate.
  -Bufsize RATE              VBV buffer size.
  -Profile NAME              HEVC profile, e.g. main, main10.
  -PixFmt NAME               Pixel format, e.g. yuv420p10le.
  -Scale WxH                 Resize, e.g. 1920:-2.
  -Fps N                     Change frame rate.
  -VideoFilter TEXT          ffmpeg video filter, e.g. "hqdn3d=1.2:1.2:5:5".

Hardware encoder options:
  -NvencPreset NAME          NVENC preset p1-p7. Default: p5.
  -NvencRc NAME              NVENC rate control. Default: vbr.
  -Gpu N                     NVIDIA GPU index.
  -AmfQuality NAME           AMF quality: speed, balanced, quality. Default: quality.
  -AmfRc NAME                AMF rate control, e.g. cqp, vbr_peak, vbr_latency.

Audio:
  -AudioLayout LAYOUT        mono, stereo, 5.1, or 7.1.
  -AudioChannels N           Channel count, usually 1, 2, 6, or 8.
  -AudioBitrate RATE         AAC bitrate. Default: 160k.
  -AudioFilter TEXT          ffmpeg audio filter, e.g. "loudnorm".
  -AudioCopy                 Copy audio instead of encoding AAC.
  -AudioNone                 Remove audio.

Other:
  -SubsCopy                  Copy subtitles. Default.
  -SubsNone                  Remove subtitles.
  -Overwrite                 Replace existing output files.
  -ResumeLog PATH            Resume from a previous encipher session log.
  -Help                      Show this help.

Output files are written as .mkv so subtitles and extra streams can be copied safely.
"@
}

function Resolve-AudioChannels([string]$layout, [int]$channels) {
    if ($channels -gt 0) { return $channels }
    switch -Regex ($layout) {
        "^(mono|1)$" { return 1 }
        "^(stereo|2|2\.0)$" { return 2 }
        "^(5\.1|6)$" { return 6 }
        "^(7\.1|8)$" { return 8 }
        "^$" { return 0 }
        default { throw "Unknown audio layout '$layout'. Use mono, stereo, 5.1, or 7.1." }
    }
}

function Add-OptionalArg([System.Collections.ArrayList]$list, [string]$name, [object]$value) {
    if ($null -ne $value -and "$value" -ne "") {
        [void]$list.Add($name)
        [void]$list.Add("$value")
    }
}

function Get-RelativePathCompat([string]$root, [string]$path) {
    $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd("\") + "\"
    $pathFull = [System.IO.Path]::GetFullPath($path)
    if ($pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $pathFull.Substring($rootFull.Length)
    }
    return [System.IO.Path]::GetFileName($pathFull)
}

function Get-OptionValue([string[]]$items, [int]$index, [string]$option) {
    if ($index + 1 -ge $items.Count -or $items[$index + 1].StartsWith("-")) {
        throw "Missing value for $option"
    }
    return $items[$index + 1]
}

function Get-NormalizedDecimal([string]$value, [string]$name, [double]$min, [double]$max) {
    $clean = $value.Trim().Replace(",", ".")
    $number = 0.0
    if (-not [double]::TryParse($clean, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        throw "$name must be a number."
    }
    if ($number -gt 1 -and $number -le 100) {
        $number = $number / 100
    }
    if ($number -lt $min -or $number -gt $max) {
        throw "$name must be between $min and $max."
    }
    return $number.ToString("0.##", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-NormalizedInteger([string]$value, [string]$name, [int]$min, [int]$max) {
    $number = 0
    if (-not [int]::TryParse($value.Trim(), [ref]$number)) {
        throw "$name must be a whole number."
    }
    if ($number -lt $min -or $number -gt $max) {
        throw "$name must be between $min and $max."
    }
    return "$number"
}

function Format-ByteSize([double]$bytes) {
    if ($bytes -ge 1TB) { return ("{0:N2} TB" -f ($bytes / 1TB)) }
    if ($bytes -ge 1GB) { return ("{0:N2} GB" -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ("{0:N2} MB" -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ("{0:N2} KB" -f ($bytes / 1KB)) }
    return ("{0:N0} B" -f $bytes)
}

function Format-Duration([double]$seconds) {
    if ($seconds -le 0) { return "Unknown" }
    $span = [TimeSpan]::FromSeconds($seconds)
    if ($span.TotalHours -ge 1) {
        return ("{0}h {1}m {2}s" -f [Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds)
    }
    if ($span.TotalMinutes -ge 1) {
        return ("{0}m {1}s" -f [Math]::Floor($span.TotalMinutes), $span.Seconds)
    }
    return ("{0}s" -f [Math]::Max(1, [Math]::Round($span.TotalSeconds)))
}

function Get-TotalInputBytes([object[]]$items) {
    $total = 0.0
    foreach ($item in $items) {
        $total += [double]$item.Length
    }
    return $total
}

function Get-TotalOutputBytes([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 0.0 }
    $total = 0.0
    foreach ($item in Get-ChildItem -LiteralPath $path -Recurse -File -Filter "*.mkv" -ErrorAction SilentlyContinue) {
        $total += [double]$item.Length
    }
    return $total
}

function Get-TotalRuntimeSeconds([object[]]$items) {
    if (-not (Get-Command $EncipherFfprobe -ErrorAction SilentlyContinue)) { return 0.0 }
    $total = 0.0
    foreach ($item in $items) {
        try {
            $duration = & $EncipherFfprobe -v error -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 $item.FullName
            if ($duration) {
                $total += [double]::Parse($duration, [System.Globalization.CultureInfo]::InvariantCulture)
            }
        } catch {
        }
    }
    return $total
}

function Get-EstimateProfile([string]$encoderName, [string]$presetName) {
    $reduction = 40.0
    $speed = 1.0

    switch ($encoderName) {
        "x265" {
            $reduction = 48.0
            switch ($presetName) {
                "ultrafast" { $speed = 1.20 }
                "superfast" { $speed = 1.00 }
                "veryfast" { $speed = 0.85 }
                "faster" { $speed = 0.65 }
                "fast" { $speed = 0.42 }
                "medium" { $speed = 0.28 }
                "slow" { $speed = 0.13 }
                "slower" { $speed = 0.08 }
                "veryslow" { $speed = 0.05 }
                default { $speed = 0.28 }
            }
        }
        "nvenc" {
            $reduction = 38.0
            $speed = 3.0
        }
        "amf" {
            $reduction = 38.0
            $speed = 2.5
        }
    }

    return @{
        Reduction = $reduction
        Speed = $speed
    }
}

function Write-StatsPanel([string]$title, [hashtable]$stats, [string]$logPath) {
    $lines = @(
        ""
        "=========================================="
        $title
        "=========================================="
        ("Files              : {0}" -f $stats.Files)
        ("Source Size        : {0}" -f $stats.SourceSize)
        ("Media Runtime      : {0}" -f $stats.Runtime)
        ("Encoder            : {0}" -f $stats.Encoder)
        ("Estimated Output   : {0}" -f $stats.EstimatedOutput)
        ("Estimated Saved    : {0}" -f $stats.EstimatedSaved)
        ("Estimated Reduction: {0}" -f $stats.EstimatedReduction)
        ("Estimated Time     : {0}" -f $stats.EstimatedTime)
    )

    foreach ($line in $lines) { Write-Host $line }
    if ($logPath) { $lines | Add-Content -LiteralPath $logPath }
}

function Write-FinalStatsPanel([hashtable]$stats, [string]$logPath) {
    $lines = @(
        ""
        "=========================================="
        "FINAL STATS"
        "=========================================="
        ("Files Encoded      : {0}" -f $stats.Encoded)
        ("Files Skipped      : {0}" -f $stats.Skipped)
        ("Files Failed       : {0}" -f $stats.Failed)
        ("Elapsed Time       : {0}" -f $stats.Elapsed)
        ("Beginning Size     : {0}" -f $stats.SourceSize)
        ("Final Output Size  : {0}" -f $stats.OutputSize)
        ("Space Saved        : {0}" -f $stats.SavedSize)
        ("Actual Reduction   : {0}" -f $stats.Reduction)
    )

    foreach ($line in $lines) { Write-Host $line }
    if ($logPath) { $lines | Add-Content -LiteralPath $logPath }
}

function Show-Section([string]$title) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host $title
    Write-Host "=========================================="
    Write-Host ""
}

function Show-Splash {
    Clear-Host
    $b = [string][char]0x2588
    $tr = [string][char]0x2557
    $v = [string][char]0x2551
    $tl = [string][char]0x2554
    $h = [string][char]0x2550
    $br = [string][char]0x255D
    $bl = [string][char]0x255A
    $banner = @(
        ("     " + ($b * 7) + $tr + ($b * 3) + $tr + "   " + ($b * 2) + $tr + " " + ($b * 6) + $tr + ($b * 2) + $tr + ($b * 6) + $tr + " " + ($b * 2) + $tr + "  " + ($b * 2) + $tr + ($b * 7) + $tr + ($b * 6) + $tr)
        ("     " + ($b * 2) + $tl + ($h * 4) + $br + ($b * 4) + $tr + "  " + ($b * 2) + $v + ($b * 2) + $tl + ($h * 4) + $br + ($b * 2) + $v + ($b * 2) + $tl + ($h * 2) + ($b * 2) + $tr + ($b * 2) + $v + "  " + ($b * 2) + $v + ($b * 2) + $tl + ($h * 4) + $br + ($b * 2) + $tl + ($h * 2) + ($b * 2) + $tr)
        ("     " + ($b * 5) + $tr + "  " + ($b * 2) + $tl + ($b * 2) + $tr + " " + ($b * 2) + $v + ($b * 2) + $v + "     " + ($b * 2) + $v + ($b * 6) + $tl + $br + ($b * 7) + $v + ($b * 5) + $tr + "  " + ($b * 6) + $tl + $br)
        ("     " + ($b * 2) + $tl + ($h * 2) + $br + "  " + ($b * 2) + $v + $bl + ($b * 2) + $tr + ($b * 2) + $v + ($b * 2) + $v + "     " + ($b * 2) + $v + ($b * 2) + $tl + ($h * 3) + $br + " " + ($b * 2) + $tl + ($h * 2) + ($b * 2) + $v + ($b * 2) + $tl + ($h * 2) + $br + "  " + ($b * 2) + $tl + ($h * 2) + ($b * 2) + $tr)
        ("     " + ($b * 7) + $tr + ($b * 2) + $v + " " + $bl + ($b * 4) + $v + $bl + ($b * 6) + $tr + ($b * 2) + $v + ($b * 2) + $v + "     " + ($b * 2) + $v + "  " + ($b * 2) + $v + ($b * 7) + $tr + ($b * 2) + $v + "  " + ($b * 2) + $v)
        ("     " + $bl + ($h * 6) + $br + $bl + $h + $br + "  " + $bl + ($h * 3) + $br + " " + $bl + ($h * 5) + $br + $bl + $h + $br + $bl + $h + $br + "     " + $bl + $h + $br + "  " + $bl + $h + $br + $bl + ($h * 6) + $br + $bl + $h + $br + "  " + $bl + $h + $br)
    )
    Write-Host ""
    foreach ($line in $banner) {
        Write-Host $line -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "                Press any key to continue . . ." -ForegroundColor Red
    [void][Console]::ReadKey($true)
    Clear-Host
}

function Read-EncipherInput([string]$prompt) {
    return Read-Host $prompt
}

function ConvertTo-CommandLineArg([string]$value) {
    if ($null -eq $value) { return '""' }
    if ($value -notmatch '[\s"]') { return $value }
    $escaped = $value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Get-FfmpegProgressValues([string]$progressPath) {
    $values = @{}
    if (-not $progressPath -or -not (Test-Path -LiteralPath $progressPath)) { return $values }

    try {
        $stream = [System.IO.File]::Open($progressPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $reader = New-Object System.IO.StreamReader($stream)
            $text = $reader.ReadToEnd()
        } finally {
            $stream.Dispose()
        }

        foreach ($line in ($text -split "\r?\n")) {
            $idx = $line.IndexOf("=")
            if ($idx -gt 0) {
                $name = $line.Substring(0, $idx)
                $value = $line.Substring($idx + 1)
                $values[$name] = $value
            }
        }
    } catch {
    }

    return $values
}

function Invoke-FfmpegWithQuit([object[]]$ffmpegArgs, [string]$progressPath = "", [string]$logPath = "") {
    $script:LastFfmpegCancelled = $false

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $EncipherFfmpeg
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $false
    $startInfo.RedirectStandardError = $false
    $startInfo.Arguments = ($ffmpegArgs | ForEach-Object { ConvertTo-CommandLineArg "$_" }) -join " "

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    [void]$process.Start()
    $progressTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $lastProgressLine = ""

    while (-not $process.HasExited) {
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -eq "q" -or $key.KeyChar -eq "Q") {
                    $script:LastFfmpegCancelled = $true
                    Write-Host ""
                    Write-Host "Stopping ffmpeg..."
                    $process.StandardInput.WriteLine("q")
                }
            }
        } catch {
            # Some hosted terminals do not expose KeyAvailable. Ctrl+C still stops the process.
        }

        if ($progressPath -and $logPath -and $progressTimer.ElapsedMilliseconds -ge 1000) {
            $progressTimer.Restart()
            $progress = Get-FfmpegProgressValues $progressPath
            if ($progress.Count -gt 0 -and $progress.frame) {
                $frame = $progress.frame
                $fps = if ($progress.fps) { $progress.fps } else { "0" }
                $speed = if ($progress.speed) { $progress.speed } else { "0x" }
                $outTime = if ($progress.out_time) { $progress.out_time } else { "" }
                $progressLine = "PROGRESS : frame=$frame fps=$fps speed=$speed time=$outTime"
                if ($progressLine -ne $lastProgressLine) {
                    Add-Content -LiteralPath $logPath -Value $progressLine
                    $lastProgressLine = $progressLine
                }
            }
        }

        Start-Sleep -Milliseconds 100
    }

    $process.WaitForExit()
    if ($progressPath -and $logPath) {
        $progress = Get-FfmpegProgressValues $progressPath
        if ($progress.Count -gt 0 -and $progress.frame) {
            $frame = $progress.frame
            $fps = if ($progress.fps) { $progress.fps } else { "0" }
            $speed = if ($progress.speed) { $progress.speed } else { "0x" }
            $outTime = if ($progress.out_time) { $progress.out_time } else { "" }
            $progressLine = "PROGRESS : frame=$frame fps=$fps speed=$speed time=$outTime"
            if ($progressLine -ne $lastProgressLine) {
                Add-Content -LiteralPath $logPath -Value $progressLine
            }
        }
    }
    return $process.ExitCode
}

function Get-LogValue([string[]]$lines, [string]$name) {
    $pattern = "^\s*" + [regex]::Escape($name) + "\s*:\s*(.*)$"
    foreach ($line in $lines) {
        $match = [regex]::Match($line, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ""
}

function Convert-ArgLineToArrayList([string]$line) {
    $list = New-Object System.Collections.ArrayList
    if ($line) {
        foreach ($item in ($line -split "\s+")) {
            if ($item) { [void]$list.Add($item) }
        }
    }
    return $list
}

for ($idx = 0; $idx -lt $CliArgs.Count; $idx++) {
    $option = $CliArgs[$idx]
    $key = $option.TrimStart("-").ToLowerInvariant()

    switch ($key) {
        "h" { $Help = $true }
        "help" { $Help = $true }
        "i" { $InputDir = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "input" { $InputDir = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "inputdir" { $InputDir = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "input-dir" { $InputDir = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "o" { $OutputDir = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "output" { $OutputDir = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "outputdir" { $OutputDir = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "output-dir" { $OutputDir = Get-OptionValue $CliArgs $idx $option; $idx++ }

        "encoder" { $Encoder = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "crf" { $Crf = [int](Get-OptionValue $CliArgs $idx $option); $idx++ }
        "cq" { $Cq = [int](Get-OptionValue $CliArgs $idx $option); $idx++ }
        "qp" { $Qp = [int](Get-OptionValue $CliArgs $idx $option); $idx++ }
        "preset" { $Preset = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "tune" { $Tune = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "grain" { $Tune = "grain" }
        "x265params" { $X265Params = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "x265-params" { $X265Params = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "video-bitrate" { $VideoBitrate = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "videobitrate" { $VideoBitrate = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "maxrate" { $Maxrate = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "bufsize" { $Bufsize = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "profile" { $Profile = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "pix-fmt" { $PixFmt = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "pixfmt" { $PixFmt = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "scale" { $Scale = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "fps" { $Fps = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "video-filter" { $VideoFilter = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "videofilter" { $VideoFilter = Get-OptionValue $CliArgs $idx $option; $idx++ }

        "nvenc" { $Encoder = "nvenc" }
        "nvidia" { $Encoder = "nvenc" }
        "amf" { $Encoder = "amf" }
        "amd" { $Encoder = "amf" }
        "nvenc-preset" { $NvencPreset = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "nvencpreset" { $NvencPreset = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "nvenc-rc" { $NvencRc = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "nvencrc" { $NvencRc = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "gpu" { $Gpu = [int](Get-OptionValue $CliArgs $idx $option); $idx++ }
        "amf-quality" { $AmfQuality = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "amfquality" { $AmfQuality = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "amf-rc" { $AmfRc = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "amfrc" { $AmfRc = Get-OptionValue $CliArgs $idx $option; $idx++ }

        "audio-layout" { $AudioLayout = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "audiolayout" { $AudioLayout = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "audio-channels" { $AudioChannels = [int](Get-OptionValue $CliArgs $idx $option); $idx++ }
        "audiochannels" { $AudioChannels = [int](Get-OptionValue $CliArgs $idx $option); $idx++ }
        "audio-bitrate" { $AudioBitrate = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "audiobitrate" { $AudioBitrate = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "audio-filter" { $AudioFilter = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "audiofilter" { $AudioFilter = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "audio-copy" { $AudioCopy = $true }
        "audiocopy" { $AudioCopy = $true }
        "audio-none" { $AudioNone = $true }
        "audionone" { $AudioNone = $true }

        "subs-copy" { $SubsNone = $false }
        "subscopy" { $SubsNone = $false }
        "subs-none" { $SubsNone = $true }
        "subsnone" { $SubsNone = $true }
        "overwrite" { $Overwrite = $true }
        "resume" { $ResumeLog = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "resume-log" { $ResumeLog = Get-OptionValue $CliArgs $idx $option; $idx++ }
        "resumelog" { $ResumeLog = Get-OptionValue $CliArgs $idx $option; $idx++ }
        default { throw "Unknown option: $option" }
    }
}

if ($Help) {
    Show-Help
    exit 0
}

$InteractiveMode = (-not $InputDir -and -not $ResumeLog)

if ($InteractiveMode) {
    Show-Splash
    Write-Host "ENCIPHER"
    Write-Host "Recursive HEVC + AAC Converter"
    Write-Host ""

    $interactiveLogRoot = Join-Path $EncipherHome "logs"
    $availableLogs = @(Get-ChildItem -LiteralPath $interactiveLogRoot -Filter "*.txt" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "enc_*.txt" -or $_.Name -like "encode_session_*.txt" } |
        Sort-Object LastWriteTime -Descending)

    if ($availableLogs.Count -gt 0) {
        Show-Section "RESUME SESSION"
        Write-Host "Previous session logs found."
        Write-Host ""
        Write-Host "1 = Resume latest log"
        Write-Host "2 = Pick from previous logs"
        Write-Host "3 = Paste a log path"
        Write-Host "4 = Start fresh"
        Write-Host ""
        Write-Host "Latest:"
        Write-Host $availableLogs[0].FullName
        Write-Host ""

        $resumeChoice = Read-EncipherInput "Choose resume option, or press Enter for start fresh"
        if (-not $resumeChoice) { $resumeChoice = "4" }

        switch ($resumeChoice) {
            "1" {
                $ResumeLog = $availableLogs[0].FullName
            }
            "2" {
                Show-Section "PICK SESSION LOG"
                $maxLogs = [Math]::Min($availableLogs.Count, 20)
                for ($logIndex = 0; $logIndex -lt $maxLogs; $logIndex++) {
                    $log = $availableLogs[$logIndex]
                    $displayIndex = $logIndex + 1
                    Write-Host ("{0,2} = {1}  {2}" -f $displayIndex, $log.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), $log.Name)
                }
                Write-Host ""
                $pickedLog = Read-EncipherInput "Choose log number, or press Enter to start fresh"
                if ($pickedLog) {
                    $pickedIndex = 0
                    if (-not [int]::TryParse($pickedLog, [ref]$pickedIndex) -or $pickedIndex -lt 1 -or $pickedIndex -gt $maxLogs) {
                        throw "Invalid log selection: $pickedLog"
                    }
                    $ResumeLog = $availableLogs[$pickedIndex - 1].FullName
                }
            }
            "3" {
                $pastedLog = Read-EncipherInput "Paste previous session log path"
                if ($pastedLog) {
                    $ResumeLog = $pastedLog.Trim('"')
                }
            }
            "4" { }
            default {
                throw "Invalid resume option: $resumeChoice"
            }
        }
    }
}

if ($ResumeLog) {
    $ResumeLog = (Resolve-Path -LiteralPath $ResumeLog -ErrorAction Stop).Path
    $resumeLines = Get-Content -LiteralPath $ResumeLog
    $InputDir = Get-LogValue $resumeLines "Source Root"
    $OutputDir = Get-LogValue $resumeLines "Output Root"
    $Encoder = Get-LogValue $resumeLines "Encoder"
    $ResumeVideoArgLine = Get-LogValue $resumeLines "Video Args"
    $ResumeAudioArgLine = Get-LogValue $resumeLines "Audio Args"
    $ResumeSubtitleArgLine = Get-LogValue $resumeLines "Subtitle Args"
    $ResumeFilterLine = Get-LogValue $resumeLines "Filters"

    if (-not $InputDir -or -not $OutputDir -or -not $ResumeVideoArgLine -or -not $ResumeAudioArgLine) {
        throw "Resume log is missing Source Root, Output Root, Video Args, or Audio Args: $ResumeLog"
    }

    foreach ($line in $resumeLines) {
        $match = [regex]::Match($line, "^SUCCESS\s*:\s*(.*?)\s*->\s*")
        if ($match.Success) {
            [void]$CompletedRelativePaths.Add($match.Groups[1].Value.Trim())
        }
    }

    $ResumeMode = $true
    $Overwrite = $true
    Write-Host "Resuming from log:"
    Write-Host $ResumeLog
    Write-Host "Already successful: $($CompletedRelativePaths.Count)"
    Write-Host ""
}

if ($InteractiveMode -and -not $ResumeMode) {
    $InputDir = Read-EncipherInput "Enter folder to encode"
    if (-not $InputDir) {
        Write-Error "No input folder selected."
        exit 2
    }

    $defaultOutput = Join-Path $InputDir "converted"
    $chosenOutput = Read-EncipherInput "Output folder, or press Enter for $defaultOutput"
    if ($chosenOutput) { $OutputDir = $chosenOutput } else { $OutputDir = $defaultOutput }

    Show-Section "ADVANCED VIDEO QUALITY SETTINGS"
    Write-Host "CRF/CQ controls overall video quality."
    Write-Host ""
    Write-Host "Range: 0-51"
    Write-Host ""
    Write-Host "Lower = higher quality / bigger file"
    Write-Host "Higher = lower quality / smaller file"
    Write-Host ""
    Write-Host "Recommended:"
    Write-Host "18 = visually near-lossless"
    Write-Host "20 = very high quality"
    Write-Host "22 = balanced smaller files"
    Write-Host "24 = smaller files"
    Write-Host "26 = aggressive compression"
    Write-Host ""
    $quality = Read-EncipherInput "Enter CRF/CQ value, or press Enter for 22"
    if (-not $quality) { $quality = "22" }
    $Crf = [int]$quality
    $Cq = [int]$quality
    $Qp = [int]$quality

    Show-Section "HEVC BIT DEPTH"
    Write-Host "1 = HEVC 8-bit  - maximum compatibility"
    Write-Host "2 = HEVC 10-bit - better gradients, better compression, recommended"
    Write-Host ""
    $bitDepth = Read-EncipherInput "Choose 1 or 2, or press Enter for 10-bit"
    if (-not $bitDepth) { $bitDepth = "2" }
    if ($bitDepth -eq "1") {
        $PixFmt = "yuv420p"
        $Profile = "main"
    } elseif ($bitDepth -eq "2") {
        $PixFmt = "yuv420p10le"
        $Profile = "main10"
    } else {
        Write-Error "Invalid bit-depth selection."
        exit 2
    }

    Show-Section "ANIME DENOISE / SOFTENING OPTIONS"
    Write-Host "[1] OFF           - Original grain / larger files"
    Write-Host "[2] ULTRA LIGHT   - Tiny cleanup / almost no downside"
    Write-Host "[3] LIGHT         - Best for anime / slight softening"
    Write-Host "[4] LIGHT-MEDIUM  - Cleaner image / minor detail loss"
    Write-Host "[5] MEDIUM        - Strong cleanup / softer lines"
    Write-Host "[6] STRONG        - Heavy cleanup / noticeable blur"
    Write-Host ""
    $denoise = Read-EncipherInput "Select denoise/softening level [1-6], or press Enter for 1"
    switch ($denoise) {
        "" { }
        "1" { }
        "2" { $VideoFilter = "hqdn3d=0.8:0.8:4:4" }
        "3" { $VideoFilter = "hqdn3d=1.2:1.2:5:5" }
        "4" { $VideoFilter = "hqdn3d=1.6:1.6:5.5:5.5" }
        "5" { $VideoFilter = "hqdn3d=2:2:6:6" }
        "6" { $VideoFilter = "hqdn3d=3:3:8:8" }
        default {
            Write-Error "Invalid denoise selection."
            exit 2
        }
    }

    Show-Section "AUDIO CHANNEL MODE"
    Write-Host "1 = Stereo 2.0"
    Write-Host "2 = Surround 5.1"
    Write-Host "3 = Surround 7.1"
    Write-Host "4 = Keep Original Channels"
    Write-Host ""
    $audioMode = Read-EncipherInput "Choose audio mode, or press Enter for 5.1"
    if (-not $audioMode) { $audioMode = "2" }
    switch ($audioMode) {
        "1" { $AudioChannels = 2; $AudioLayout = "stereo" }
        "2" { $AudioChannels = 6; $AudioLayout = "5.1" }
        "3" { $AudioChannels = 8; $AudioLayout = "7.1" }
        "4" { $AudioChannels = 0; $AudioLayout = "" }
        default {
            Write-Error "Invalid audio mode."
            exit 2
        }
    }

    Show-Section "AUDIO QUALITY"
    Write-Host "AAC uses bitrate."
    Write-Host ""
    Write-Host "128k = small stereo"
    Write-Host "192k = good stereo"
    Write-Host "256k = high stereo"
    Write-Host "320k = max normal stereo / smaller 5.1"
    Write-Host "384k = good 5.1"
    Write-Host "448k = high 5.1"
    Write-Host "512k = very high 5.1"
    Write-Host "640k = max common AAC 5.1"
    Write-Host ""
    $audioRate = Read-EncipherInput "Enter AAC bitrate, or press Enter for 384k"
    if ($audioRate) { $AudioBitrate = $audioRate } else { $AudioBitrate = "384k" }

    Show-Section "ENCODER SELECTION"
    Write-Host "1 = AMD GPU HEVC AMF"
    Write-Host "2 = NVIDIA GPU HEVC NVENC"
    Write-Host "3 = CPU x265 HEVC"
    Write-Host ""
    Write-Host "NOTE: Advanced x265 options only fully apply to CPU x265."
    Write-Host "AMD/NVIDIA use GPU quality controls and ignore x265-only tuning."
    Write-Host ""
    $encoderChoice = Read-EncipherInput "Choose encoder, or press Enter for CPU x265"
    if (-not $encoderChoice) { $encoderChoice = "3" }
    switch ($encoderChoice) {
        "1" { $Encoder = "amf"; $AmfQuality = "balanced" }
        "2" { $Encoder = "nvenc"; $NvencPreset = "p5"; $VideoBitrate = "0" }
        "3" { $Encoder = "x265" }
        default {
            Write-Error "Invalid encoder selection."
            exit 2
        }
    }

    if ($Encoder -eq "x265") {
        Show-Section "CPU x265 PRESET"
        Write-Host "1 = very fast - much faster CPU encode, larger files"
        Write-Host "2 = faster    - faster CPU encode, larger files"
        Write-Host "3 = fast      - recommended CPU balance for 4K"
        Write-Host "4 = medium    - better compression, slower"
        Write-Host "5 = slow      - smaller files, very slow"
        Write-Host "6 = slower    - extremely slow"
        Write-Host "7 = veryslow  - smallest, impractically slow for 4K"
        Write-Host ""
        $presetChoice = Read-EncipherInput "Choose CPU preset, or press Enter for fast"
        if (-not $presetChoice) { $presetChoice = "3" }
        switch ($presetChoice) {
            "1" { $Preset = "veryfast" }
            "2" { $Preset = "faster" }
            "3" { $Preset = "fast" }
            "4" { $Preset = "medium" }
            "5" { $Preset = "slow" }
            "6" { $Preset = "slower" }
            "7" { $Preset = "veryslow" }
            default {
                Write-Error "Invalid CPU preset."
                exit 2
            }
        }

        Show-Section "FILM GRAIN OPTIMIZATION"
        Write-Host "Film grain optimization attempts to preserve grain structure."
        Write-Host ""
        Write-Host "N = disabled, best for anime / digital content"
        Write-Host "Y = enabled, best for film grain / Blu-ray remuxes"
        Write-Host ""
        $grainChoice = Read-EncipherInput "Preserve film grain with x265 tune grain? Y/N, default N"
        if ($grainChoice -match "^[Yy]") { $Tune = "grain" }

        Show-Section "QCOMP"
        Write-Host "QComp controls bitrate distribution between scenes."
        Write-Host ""
        Write-Host "Lower values:"
        Write-Host "- flatter bitrate"
        Write-Host "- smaller files"
        Write-Host "- weaker hard-scene retention"
        Write-Host ""
        Write-Host "Higher values:"
        Write-Host "- better dark scenes"
        Write-Host "- better action scenes"
        Write-Host "- larger files"
        Write-Host ""
        Write-Host "Common values:"
        Write-Host "0.60 = stronger compression"
        Write-Host "0.70 = balanced high quality"
        Write-Host "0.80 = preserve difficult scenes"
        Write-Host ""
        $qcomp = Read-EncipherInput "x265 qcomp, or press Enter for 0.70"
        if (-not $qcomp) { $qcomp = "0.70" }
        $qcomp = Get-NormalizedDecimal $qcomp "x265 qcomp" 0.5 1.0

        Show-Section "ADAPTIVE QUANTIZATION MODE"
        Write-Host "AQ redistributes bitrate intelligently."
        Write-Host ""
        Write-Host "0 = disabled"
        Write-Host "1 = variance AQ"
        Write-Host "2 = auto-variance AQ"
        Write-Host "3 = auto-variance AQ + dark scene bias, recommended"
        Write-Host "4 = edge-aware AQ"
        Write-Host ""
        $aqMode = Read-EncipherInput "x265 AQ mode, or press Enter for 3"
        if (-not $aqMode) { $aqMode = "3" }
        $aqMode = Get-NormalizedInteger $aqMode "x265 AQ mode" 0 4

        Show-Section "AQ STRENGTH"
        Write-Host "AQ strength controls how aggressive AQ becomes."
        Write-Host ""
        Write-Host "0.70 = balanced"
        Write-Host "1.00 = stronger detail retention"
        Write-Host "1.20 = aggressive detail preservation"
        Write-Host ""
        $aqStrength = Read-EncipherInput "x265 AQ strength, or press Enter for 0.70"
        if (-not $aqStrength) { $aqStrength = "0.70" }
        $aqStrength = Get-NormalizedDecimal $aqStrength "x265 AQ strength" 0.0 3.0

        Show-Section "MBTREE / CUTREE"
        Write-Host "CUTree controls intelligent bitrate placement."
        Write-Host ""
        Write-Host "0 = disabled"
        Write-Host "1 = enabled, recommended"
        Write-Host ""
        $cutree = Read-EncipherInput "x265 cutree 0/1, or press Enter for 1"
        if (-not $cutree) { $cutree = "1" }
        $cutree = Get-NormalizedInteger $cutree "x265 cutree" 0 1
        $X265Params = "qcomp=${qcomp}:aq-mode=${aqMode}:aq-strength=${aqStrength}:cutree=${cutree}"
    }

    $Overwrite = $true
}

$Encoder = $Encoder.ToLowerInvariant()
if (@("x265", "nvenc", "amf") -notcontains $Encoder) {
    throw "Unknown encoder '$Encoder'. Use x265, nvenc, or amf."
}
if (@("speed", "balanced", "quality") -notcontains $AmfQuality.ToLowerInvariant()) {
    throw "Unknown AMF quality '$AmfQuality'. Use speed, balanced, or quality."
}

if (-not $InputDir) {
    Write-Error "Missing required option: -InputDir"
    Show-Help
    exit 2
}

if (-not (Get-Command $EncipherFfmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg was not found in PATH. Install ffmpeg or add ffmpeg.exe to PATH, then try again."
    exit 1
}

$inputPath = (Resolve-Path -LiteralPath $InputDir -ErrorAction Stop).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $inputPath "converted"
}
$outputPath = [System.IO.Path]::GetFullPath($OutputDir)

if ($inputPath.TrimEnd("\") -ieq $outputPath.TrimEnd("\")) {
    Write-Error "Output directory must be different from input directory."
    exit 1
}

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$logRoot = Join-Path $EncipherHome "logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$sessionLog = $ResumeLog
if (-not $ResumeMode) {
    $sessionStamp = Get-Date -Format "yyMMdd_HHmmss"
    $sessionLog = Join-Path $logRoot "enc_$sessionStamp.txt"
}

$videoArgs = New-Object System.Collections.ArrayList
$filterParts = New-Object System.Collections.ArrayList
$audioArgs = New-Object System.Collections.ArrayList
$subtitleArgs = New-Object System.Collections.ArrayList

if ($ResumeMode) {
    $videoArgs = Convert-ArgLineToArrayList $ResumeVideoArgLine
    $audioArgs = Convert-ArgLineToArrayList $ResumeAudioArgLine
    $subtitleArgs = Convert-ArgLineToArrayList $ResumeSubtitleArgLine
    if ($ResumeFilterLine) {
        foreach ($filter in ($ResumeFilterLine -split ",")) {
            if ($filter) { [void]$filterParts.Add($filter) }
        }
    }
} else {
    if ($VideoFilter) { [void]$filterParts.Add($VideoFilter) }
    if ($Scale) { [void]$filterParts.Add("scale=$Scale") }
    if ($Fps) { [void]$filterParts.Add("fps=$Fps") }

    switch ($Encoder) {
        "x265" {
            $videoArgs.AddRange(@("-c:v", "libx265", "-preset", $Preset, "-crf", "$Crf"))
            Add-OptionalArg $videoArgs "-tune" $Tune
            Add-OptionalArg $videoArgs "-x265-params" $X265Params
        }
        "nvenc" {
            $videoArgs.AddRange(@("-c:v", "hevc_nvenc", "-preset", $NvencPreset, "-rc", $NvencRc, "-cq:v", "$Cq"))
            if ($Gpu -ge 0) { $videoArgs.AddRange(@("-gpu", "$Gpu")) }
        }
        "amf" {
            $videoArgs.AddRange(@("-c:v", "hevc_amf", "-quality", $AmfQuality, "-rc", $AmfRc))
            if ($AmfRc -ieq "cqp") {
                $videoArgs.AddRange(@("-qp_i", "$Qp", "-qp_p", "$Qp", "-qp_b", "$Qp"))
            }
        }
    }

    Add-OptionalArg $videoArgs "-b:v" $VideoBitrate
    Add-OptionalArg $videoArgs "-maxrate" $Maxrate
    Add-OptionalArg $videoArgs "-bufsize" $Bufsize
    Add-OptionalArg $videoArgs "-profile:v" $Profile
    Add-OptionalArg $videoArgs "-pix_fmt" $PixFmt

    if ($AudioNone) {
        [void]$audioArgs.Add("-an")
    } elseif ($AudioCopy) {
        $audioArgs.AddRange(@("-c:a", "copy"))
    } else {
        $audioArgs.AddRange(@("-c:a", "aac", "-b:a", $AudioBitrate))
        $channels = Resolve-AudioChannels $AudioLayout $AudioChannels
        if ($channels -gt 0) { $audioArgs.AddRange(@("-ac:a", "$channels")) }
        Add-OptionalArg $audioArgs "-af" $AudioFilter
    }

    if ($SubsNone) {
        [void]$subtitleArgs.Add("-sn")
    } else {
        $subtitleArgs.AddRange(@("-c:s", "copy"))
    }
}

$extensions = @(".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v", ".ts", ".mts", ".m2ts", ".wmv", ".flv")
$outputScanPath = [System.IO.Path]::GetFullPath($outputPath).TrimEnd("\") + "\"
$logScanPath = [System.IO.Path]::GetFullPath($logRoot).TrimEnd("\") + "\"
$files = Get-ChildItem -LiteralPath $inputPath -Recurse -File |
    Where-Object {
        $full = [System.IO.Path]::GetFullPath($_.FullName)
        ($extensions -contains $_.Extension.ToLowerInvariant()) -and
        (-not $full.StartsWith($outputScanPath, [System.StringComparison]::OrdinalIgnoreCase)) -and
        (-not $full.StartsWith($logScanPath, [System.StringComparison]::OrdinalIgnoreCase))
    }

Write-Host "Scanning `"$inputPath`"..."
if ($files.Count -eq 0) {
    Write-Host "No supported video files found."
    @(
        "=========================================="
        "ENCIPHER ENCODE SESSION LOG"
        "=========================================="
        "Session Started : $(Get-Date)"
        "Source Root     : $inputPath"
        "Output Root     : $outputPath"
        "Files Found     : 0"
        "Encoder         : $Encoder"
        "Video Args      : $($videoArgs -join ' ')"
        "Audio Args      : $($audioArgs -join ' ')"
        "Subtitle Args   : $($subtitleArgs -join ' ')"
        "Filters         : $($filterParts -join ',')"
        ""
        "No supported video files found."
        "Supported Extensions: $($extensions -join ', ')"
    ) | Set-Content -LiteralPath $sessionLog
    Write-Host "Session log: $sessionLog"
    exit 0
}

$sourceBytes = Get-TotalInputBytes $files
$runtimeSeconds = Get-TotalRuntimeSeconds $files
$estimateProfile = Get-EstimateProfile $Encoder $Preset
$estimatedOutputBytes = $sourceBytes * ((100.0 - [double]$estimateProfile.Reduction) / 100.0)
$estimatedSavedBytes = $sourceBytes - $estimatedOutputBytes
$estimatedEncodeSeconds = 0.0
if ($runtimeSeconds -gt 0 -and [double]$estimateProfile.Speed -gt 0) {
    $estimatedEncodeSeconds = $runtimeSeconds / [double]$estimateProfile.Speed
}

$estimateStats = @{
    Files = $files.Count
    SourceSize = Format-ByteSize $sourceBytes
    Runtime = Format-Duration $runtimeSeconds
    Encoder = $Encoder
    EstimatedOutput = Format-ByteSize $estimatedOutputBytes
    EstimatedSaved = Format-ByteSize $estimatedSavedBytes
    EstimatedReduction = ("{0:N0}%" -f [double]$estimateProfile.Reduction)
    EstimatedTime = Format-Duration $estimatedEncodeSeconds
}

Write-Host "Found $($files.Count) video file(s)."
Write-Host "Encoder: $Encoder"
Write-Host "Video: $($videoArgs -join ' ')"
Write-Host "Audio: $($audioArgs -join ' ')"
Write-Host "Press q while ffmpeg is encoding to stop the current file and resume later from the log."
Write-Host ""

if ($ResumeMode) {
    @(
        ""
        "=========================================="
        "RESUME SESSION STARTED"
        "=========================================="
        "Resume Started : $(Get-Date)"
        "Using Same Log : $sessionLog"
        "Already Done   : $($CompletedRelativePaths.Count)"
        ""
    ) | Add-Content -LiteralPath $sessionLog
} else {
    @(
        "=========================================="
        "ENCIPHER ENCODE SESSION LOG"
        "=========================================="
        "Session Started : $(Get-Date)"
        "Source Root     : $inputPath"
        "Output Root     : $outputPath"
        "Files Found     : $($files.Count)"
        "Encoder         : $Encoder"
        "Video Args      : $($videoArgs -join ' ')"
        "Audio Args      : $($audioArgs -join ' ')"
        "Subtitle Args   : $($subtitleArgs -join ' ')"
        "Filters         : $($filterParts -join ',')"
        ""
        "FILE ENCODE RESULTS"
        "=========================================="
    ) | Set-Content -LiteralPath $sessionLog
}

Write-StatsPanel "ESTIMATED STATS" $estimateStats $sessionLog
Write-Host ""

$done = 0
$failed = 0
$skipped = 0
$overwriteArg = if ($Overwrite) { "-y" } else { "-n" }
$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($file in $files) {
    $relative = Get-RelativePathCompat $inputPath $file.FullName
    $relativeDir = [System.IO.Path]::GetDirectoryName($relative)
    $targetDir = if ($relativeDir) { Join-Path $outputPath $relativeDir } else { $outputPath }
    $target = Join-Path $targetDir ([System.IO.Path]::GetFileNameWithoutExtension($file.Name) + ".mkv")
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    $current = $done + $failed + $skipped + 1
    $targetRelative = Get-RelativePathCompat $outputPath $target

    if ($ResumeMode -and $CompletedRelativePaths.Contains($relative)) {
        $skipped++
        Write-Host "[$current/$($files.Count)] SKIPPED already successful: `"$relative`""
        continue
    }

    Write-Host "[$current/$($files.Count)] `"$relative`" -> `"$targetRelative`""
    Add-Content -LiteralPath $sessionLog -Value "STARTED : [$current/$($files.Count)] $relative -> $targetRelative"

    $progressPath = Join-Path ([System.IO.Path]::GetTempPath()) ("encipher_progress_{0}.txt" -f ([System.Guid]::NewGuid().ToString("N")))
    $ffmpegArgs = New-Object System.Collections.ArrayList
    $ffmpegArgs.AddRange(@($overwriteArg, "-hide_banner", "-loglevel", "error", "-stats", "-progress", $progressPath, "-i", $file.FullName, "-map", "0"))
    if ($filterParts.Count -gt 0) {
        $ffmpegArgs.AddRange(@("-vf", ($filterParts -join ",")))
    }
    $ffmpegArgs.AddRange($videoArgs)
    $ffmpegArgs.AddRange($audioArgs)
    $ffmpegArgs.AddRange($subtitleArgs)
    [void]$ffmpegArgs.Add($target)

    $ffmpegExitCode = Invoke-FfmpegWithQuit -ffmpegArgs @($ffmpegArgs) -progressPath $progressPath -logPath $sessionLog
    try {
        if (Test-Path -LiteralPath $progressPath) { Remove-Item -LiteralPath $progressPath -Force }
    } catch {
    }
    if ($ffmpegExitCode -eq 0 -and -not $LastFfmpegCancelled) {
        $done++
        Add-Content -LiteralPath $sessionLog -Value "SUCCESS : $relative -> $targetRelative"
    } elseif ($LastFfmpegCancelled -or $ffmpegExitCode -eq 255 -or $ffmpegExitCode -eq -1073741510) {
        Write-Host "Cancelled during encode."
        Add-Content -LiteralPath $sessionLog -Value "CANCELLED : $relative -> $targetRelative"
        Add-Content -LiteralPath $sessionLog -Value ""
        Add-Content -LiteralPath $sessionLog -Value "Session Cancelled : $(Get-Date)"
        Write-Host "Session log: $sessionLog"
        exit 130
    } else {
        Write-Host "Failed: $relative"
        $failed++
        Add-Content -LiteralPath $sessionLog -Value "FAILED  : $relative -> $targetRelative"
        Add-Content -LiteralPath $sessionLog -Value "ERROR   : FFmpeg exit code $ffmpegExitCode"
    }
}

$runStopwatch.Stop()
$outputBytes = Get-TotalOutputBytes $outputPath
$savedBytes = $sourceBytes - $outputBytes
$reductionText = "Unknown"
if ($sourceBytes -gt 0) {
    $reductionText = ("{0:N2}%" -f ((($sourceBytes - $outputBytes) / $sourceBytes) * 100.0))
}

$finalStats = @{
    Encoded = $done
    Skipped = $skipped
    Failed = $failed
    Elapsed = Format-Duration $runStopwatch.Elapsed.TotalSeconds
    SourceSize = Format-ByteSize $sourceBytes
    OutputSize = Format-ByteSize $outputBytes
    SavedSize = Format-ByteSize $savedBytes
    Reduction = $reductionText
}

Write-Host ""
Write-Host "Done. Encoded: $done  Skipped: $skipped  Failed: $failed  Total: $($files.Count)"
Add-Content -LiteralPath $sessionLog -Value ""
Add-Content -LiteralPath $sessionLog -Value "Done. Encoded: $done  Skipped: $skipped  Failed: $failed  Total: $($files.Count)"
Write-FinalStatsPanel $finalStats $sessionLog
Write-Host "Session log: $sessionLog"
if ($failed -gt 0) { exit 1 }
exit 0
