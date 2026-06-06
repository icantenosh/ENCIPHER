using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

internal static class EncipherLauncher
{
    private static int Main(string[] args)
    {
        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        string tempDir = Path.Combine(Path.GetTempPath(), "encipher_" + Guid.NewGuid().ToString("N"));
        string scriptPath = Path.Combine(tempDir, "encipher.ps1");
        string ffmpegPath = Path.Combine(tempDir, "ffmpeg.exe");
        string ffprobePath = Path.Combine(tempDir, "ffprobe.exe");

        try
        {
            Directory.CreateDirectory(tempDir);
            ExtractEmbeddedFile("encipher.ps1", scriptPath);
            ExtractEmbeddedFile("ffmpeg.exe", ffmpegPath);
            ExtractEmbeddedFile("ffprobe.exe", ffprobePath);

            if (!File.Exists(scriptPath))
            {
                Console.Error.WriteLine("Could not extract embedded encipher.ps1.");
                return 1;
            }

            string powershellPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershellPath)) powershellPath = "powershell.exe";

            var command = new StringBuilder();
            command.Append("-NoProfile -ExecutionPolicy Bypass -File ");
            command.Append(Quote(scriptPath));
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
                CreateNoWindow = false
            };
            startInfo.EnvironmentVariables["ENCIPHER_HOME"] = exeDir;
            if (File.Exists(ffmpegPath)) startInfo.EnvironmentVariables["ENCIPHER_FFMPEG"] = ffmpegPath;
            if (File.Exists(ffprobePath)) startInfo.EnvironmentVariables["ENCIPHER_FFPROBE"] = ffprobePath;

            using (var process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
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
