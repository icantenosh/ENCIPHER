# Encipher

Encipher is a Windows CLI tool for recursively transcoding a video folder while preserving its directory structure.

It targets:

- HEVC video
- AAC audio
- MKV output
- CPU x265, NVIDIA NVENC, or AMD AMF encoding
- resumable session logs
- benchmark-backed time estimates

## Install

For the easiest GUI install on Windows, open PowerShell and run:

```powershell
iwr https://raw.githubusercontent.com/icantenosh/ENCIPHER/main/install-gui.ps1 -UseB | iex
```

That installs `encipher-gui.exe` for your Windows user and creates Start Menu and Desktop shortcuts.

You can also download `encipher.exe` or `encipher-gui.exe` from the GitHub Releases page and run them directly.

The release executables are self-contained and bundle:

- `encipher.ps1`
- `ffmpeg.exe`
- `ffprobe.exe`

You do not need to install FFmpeg separately when using the bundled release exe.

## Usage

Run interactive mode:

```bat
encipher.exe
```

Run the standalone GUI:

```bat
encipher-gui.exe
```

Encode a folder:

```bat
encipher.exe --input "D:\Videos" --output "D:\Encoded"
```

Use NVIDIA HEVC:

```bat
encipher.exe --input "D:\Videos" --nvenc --cq 21
```

Use AMD HEVC:

```bat
encipher.exe --input "D:\Videos" --amd --qp 22
```

Resume from a log:

```bat
encipher.exe --resume-log ".\logs\enc_260605_220145.txt"
```

## Logs

Encipher creates a `logs` folder next to `encipher.exe`.

Session logs use short names like:

```text
enc_260605_220145.txt
```

Prediction history is stored in:

```text
logs\stats_history.csv
```

That history helps future estimates get better over time.

## Building

To rebuild `encipher.exe` locally, install or provide:

- Windows PowerShell
- .NET Framework compiler, usually already at `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`
- `ffmpeg.exe`
- `ffprobe.exe`

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

To build the standalone GUI, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-gui.ps1
```

The outputs are:

```text
encipher.exe
encipher-gui.exe
```
