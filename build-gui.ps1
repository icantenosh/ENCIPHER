$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$launcher = Join-Path $root "build\EncipherGuiLauncher.cs"
$guiScript = Join-Path $root "encipher-gui.ps1"
$script = Join-Path $root "encipher.ps1"
$output = Join-Path $root "encipher-gui.exe"
$compiler = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path -LiteralPath $compiler)) {
    throw "Could not find C# compiler: $compiler"
}

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Could not find GUI launcher source: $launcher"
}

if (-not (Test-Path -LiteralPath $guiScript)) {
    throw "Could not find GUI script: $guiScript"
}

if (-not (Test-Path -LiteralPath $script)) {
    throw "Could not find encipher script: $script"
}

$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source

$compilerArgs = @(
    "/nologo"
    "/target:winexe"
    "/platform:anycpu"
    "/out:$output"
    "/resource:$guiScript,encipher-gui.ps1"
    "/resource:$script,encipher.ps1"
    "/resource:$ffmpeg,ffmpeg.exe"
    "/resource:$ffprobe,ffprobe.exe"
    $launcher
)

& $compiler @compilerArgs
if ($LASTEXITCODE -ne 0) {
    throw "csc.exe failed with exit code $LASTEXITCODE"
}

Write-Host "Built $output"
