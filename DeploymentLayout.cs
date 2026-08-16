using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace ikun_installer;

/// <summary>
/// 管理 NX 插件的不可变部署槽。运行中的 NX 可以继续持有旧槽里的 DLL，安装器只写
/// 新槽并切换 custom_dirs.dat；新槽会在下一次 NX 启动时生效。
/// </summary>
public static class DeploymentLayout
{
    public const string Marker = "# ikun_tools";
    private const string LegacyMarker = "# nx_tools_deploy";

    public static string CreateUniqueRoot(string toolsDir, string version,
        DateTime? now = null, string? nonce = null)
    {
        var safeVersion = new string((version ?? "0").Select(c =>
            char.IsLetterOrDigit(c) || c is '.' or '-' or '_' ? c : '_').ToArray());
        if (string.IsNullOrWhiteSpace(safeVersion)) safeVersion = "0";
        var generatedNonce = Guid.NewGuid().ToString("N").Substring(0, 8);
        var safeNonce = new string((nonce ?? generatedNonce).Where(char.IsLetterOrDigit).ToArray());
        if (safeNonce.Length < 4) safeNonce = generatedNonce;
        var stamp = (now ?? DateTime.Now).ToString("yyyyMMdd-HHmmss");
        return Path.Combine(Path.GetFullPath(toolsDir), "deployments", $"{safeVersion}-{stamp}-{safeNonce}");
    }

    public static List<string> BuildCustomDirs(IEnumerable<string> existingLines,
        string toolsDir, string activeRoot)
    {
        var toolsFull = Path.GetFullPath(toolsDir).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var deployments = Path.Combine(toolsFull, "deployments") + Path.DirectorySeparatorChar;
        var activeFull = Path.GetFullPath(activeRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (!activeFull.StartsWith(deployments, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("活动部署目录必须位于 ikun tools\\deployments 下。", nameof(activeRoot));

        var result = new List<string>();
        var skipManagedValue = false;
        foreach (var original in existingLines)
        {
            var line = original.Trim();
            if (line.Equals(Marker, StringComparison.OrdinalIgnoreCase) ||
                line.Equals(LegacyMarker, StringComparison.OrdinalIgnoreCase))
            {
                skipManagedValue = true;
                continue;
            }
            if (skipManagedValue)
            {
                if (line.Length == 0) continue;
                if (Path.IsPathRooted(line)) { skipManagedValue = false; continue; }
                skipManagedValue = false;
            }

            var normalized = line.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (normalized.Equals(toolsFull, StringComparison.OrdinalIgnoreCase) ||
                normalized.StartsWith(deployments, StringComparison.OrdinalIgnoreCase) ||
                // M6: legacy 检测路径可配置 (规范 §11.4); 默认值兼容旧 custom_dirs.dat
                normalized.Equals(AppConfig.GetString("legacy_nx_deploy_dir",
                    @"E:\NX二次开发\项目\nx_tools_deploy"), StringComparison.OrdinalIgnoreCase))
                continue;
            if (line.Length > 0) result.Add(original);
        }

        if (result.Count > 0) result.Add("");
        result.Add(Marker);
        result.Add(activeFull);
        return result;
    }

    public static void WriteCustomDirsAtomic(string datFile, IEnumerable<string> lines)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(datFile))
            ?? throw new ArgumentException("custom_dirs.dat 路径无效。", nameof(datFile));
        Directory.CreateDirectory(directory);
        var temp = Path.Combine(directory, $".{Path.GetFileName(datFile)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllLines(temp, lines, new UTF8Encoding(false));
            if (File.Exists(datFile)) File.Replace(temp, datFile, null);
            else File.Move(temp, datFile);
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); } catch { }
        }
    }

    public static bool IsNxRunning()
    {
        foreach (var name in new[] { "ugraf", "nx" })
        {
            Process[] processes;
            try { processes = Process.GetProcessesByName(name); }
            catch { continue; }
            try { if (processes.Length > 0) return true; }
            finally { foreach (var process in processes) process.Dispose(); }
        }
        return false;
    }

}
