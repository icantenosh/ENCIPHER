$ErrorActionPreference = "Stop"

$repo = "icantenosh/ENCIPHER"
$asset = "encipher-gui.exe"
$installDir = Join-Path $env:LOCALAPPDATA "Programs\Encipher"
$installPath = Join-Path $installDir $asset
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Encipher"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Encipher GUI.lnk"
$startShortcut = Join-Path $startMenuDir "Encipher GUI.lnk"

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null

$localAsset = Join-Path $PSScriptRoot $asset
if (Test-Path -LiteralPath $localAsset) {
    Copy-Item -LiteralPath $localAsset -Destination $installPath -Force
} else {
    $url = "https://github.com/$repo/releases/latest/download/$asset"
    Write-Host "Downloading $asset..."
    Invoke-WebRequest -Uri $url -OutFile $installPath
}

$shell = New-Object -ComObject WScript.Shell
foreach ($shortcutPath in @($startShortcut, $desktopShortcut)) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $installPath
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = $installPath
    $shortcut.Save()
}

Write-Host ""
Write-Host "Encipher GUI installed."
Write-Host "Start Menu: Encipher\Encipher GUI"
Write-Host "Desktop shortcut: Encipher GUI"
