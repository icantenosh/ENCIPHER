using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

internal static class EncipherGuiLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        string logDir = Path.Combine(exeDir, "logs");
        string launcherLog = Path.Combine(logDir, "encipher-gui-launcher.log");
        string tempDir = Path.Combine(Path.GetTempPath(), "encipher_gui_" + Guid.NewGuid().ToString("N"));
        string guiScriptPath = Path.Combine(tempDir, "encipher-gui.ps1");
        string scriptPath = Path.Combine(tempDir, "encipher.ps1");
        string ffmpegPath = Path.Combine(tempDir, "ffmpeg.exe");
        string ffprobePath = Path.Combine(tempDir, "ffprobe.exe");

        try
        {
            Directory.CreateDirectory(logDir);
            Log(launcherLog, "Starting Encipher GUI launcher");
            Log(launcherLog, "EXE dir: " + exeDir);
            Log(launcherLog, "Temp dir: " + tempDir);

            Directory.CreateDirectory(tempDir);
            ExtractEmbeddedFile("encipher-gui.ps1", guiScriptPath);
            ExtractEmbeddedFile("encipher.ps1", scriptPath);
            ExtractEmbeddedFile("ffmpeg.exe", ffmpegPath);
            ExtractEmbeddedFile("ffprobe.exe", ffprobePath);

            if (!File.Exists(guiScriptPath) || !File.Exists(scriptPath))
            {
                Console.Error.WriteLine("Could not extract embedded Encipher GUI scripts.");
                return 1;
            }

            string powershellPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershellPath)) powershellPath = "powershell.exe";

            var command = new StringBuilder();
            command.Append("-NoProfile -STA -ExecutionPolicy Bypass -File ");
            command.Append(Quote(guiScriptPath));
            foreach (string arg in args)
            {
                command.Append(' ');
                command.Append(Quote(arg));
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = powershellPath,
                Arguments = command.ToString(),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            startInfo.EnvironmentVariables["ENCIPHER_HOME"] = exeDir;
            startInfo.EnvironmentVariables["ENCIPHER_SCRIPT"] = scriptPath;
            if (File.Exists(ffmpegPath)) startInfo.EnvironmentVariables["ENCIPHER_FFMPEG"] = ffmpegPath;
            if (File.Exists(ffprobePath)) startInfo.EnvironmentVariables["ENCIPHER_FFPROBE"] = ffprobePath;

            Log(launcherLog, "PowerShell: " + powershellPath);
            Log(launcherLog, "Arguments: " + command.ToString());

            using (var process = new Process())
            {
                process.StartInfo = startInfo;
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs eventArgs)
                {
                    if (!String.IsNullOrEmpty(eventArgs.Data)) Log(launcherLog, "[stdout] " + eventArgs.Data);
                };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs eventArgs)
                {
                    if (!String.IsNullOrEmpty(eventArgs.Data)) Log(launcherLog, "[stderr] " + eventArgs.Data);
                };
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                process.WaitForExit();
                Log(launcherLog, "PowerShell exit code: " + process.ExitCode);
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            try { Log(launcherLog, "Launcher exception: " + ex); } catch { }
            return 1;
        }
        finally
        {
            try
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
            catch
            {
            }
        }
    }

    private static void Log(string path, string message)
    {
        File.AppendAllText(
            path,
            Environment.NewLine +
            "==========================================" + Environment.NewLine +
            DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + Environment.NewLine +
            message + Environment.NewLine);
    }

    private static void ExtractEmbeddedFile(string resourceName, string outputPath)
    {
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
        {
            if (stream == null) return;
            using (var output = File.Create(outputPath))
            {
                stream.CopyTo(output);
            }
        }
    }

    private static string Quote(string value)
    {
        if (value == null || value.Length == 0) return "\"\"";
        if (value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0) return value;
        var result = new StringBuilder();
        result.Append('"');
        int slashCount = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashCount++; continue; }
            if (c == '"')
            {
                result.Append('\\', slashCount * 2 + 1);
                result.Append('"');
                slashCount = 0;
                continue;
            }
            if (slashCount > 0)
            {
                result.Append('\\', slashCount);
                slashCount = 0;
            }
            result.Append(c);
        }
        if (slashCount > 0) result.Append('\\', slashCount * 2);
        result.Append('"');
        return result.ToString();
    }
}
