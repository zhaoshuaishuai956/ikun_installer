using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace ikun_installer;

/// <summary>
/// 管理 NX 插件部署目录。已注册的活动目录优先原位更新，使立即卸载的既有插件
/// 可在当前 NX 会话内热更新；只有首次安装才创建新部署槽并修改 custom_dirs.dat。
/// </summary>
public static class DeploymentLayout
{
    public const string Marker = "# ikun_tools";
    private const string LegacyMarker = "# nx_tools_deploy";

    /// <summary>
    /// legacy 检测路径 (规范 M6): 由宿主程序启动时从 AppConfig 注入 (Program.Main),
    /// 默认值兼容旧 custom_dirs.dat。放在本类避免纯逻辑依赖注册表 → 测试可在 CI 容器跑。
    /// </summary>
    public static string LegacyDeployDir { get; set; } = @"E:\NX二次开发\项目\nx_tools_deploy";

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

    /// <summary>从 custom_dirs.dat 找到当前注册的爱坤工具箱目录；无可用目录时返回 null。</summary>
    public static string? FindActiveRoot(IEnumerable<string> existingLines, string toolsDir)
    {
        var toolsFull = Normalize(toolsDir);
        var deployments = Path.Combine(toolsFull, "deployments") + Path.DirectorySeparatorChar;
        var legacyFull = Normalize(LegacyDeployDir);
        var lines = existingLines.Select(line => line.Trim()).ToList();

        for (var i = 0; i < lines.Count; i++)
        {
            if (!lines[i].Equals(Marker, StringComparison.OrdinalIgnoreCase) &&
                !lines[i].Equals(LegacyMarker, StringComparison.OrdinalIgnoreCase))
                continue;

            var j = i + 1;
            while (j < lines.Count && string.IsNullOrWhiteSpace(lines[j])) j++;
            if (j < lines.Count && IsManagedRoot(lines[j], toolsFull, deployments, legacyFull))
                return Normalize(lines[j]);
        }

        // 兼容早期没有 marker、直接写入 tools 根目录或部署槽的配置。
        for (var i = lines.Count - 1; i >= 0; i--)
        {
            if (IsManagedRoot(lines[i], toolsFull, deployments, legacyFull))
                return Normalize(lines[i]);
        }
        return null;
    }

    /// <summary>在同目录写临时文件后原子替换，失败时保留原文件。</summary>
    public static void WriteFileAtomic(string targetPath, byte[] content)
    {
        var fullTarget = Path.GetFullPath(targetPath);
        var directory = Path.GetDirectoryName(fullTarget)
            ?? throw new ArgumentException("目标文件路径无效。", nameof(targetPath));
        Directory.CreateDirectory(directory);
        var temp = Path.Combine(directory, $".{Path.GetFileName(fullTarget)}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(temp, content);
            if (File.Exists(fullTarget)) File.Replace(temp, fullTarget, null);
            else File.Move(temp, fullTarget);
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); } catch { }
        }
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
                // M6: legacy 检测路径可配置 (规范 §11.4; 由 Program.Main 从 AppConfig 注入)
                normalized.Equals(LegacyDeployDir, StringComparison.OrdinalIgnoreCase))
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

    private static string Normalize(string path) => Path.GetFullPath(path)
        .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

    private static bool IsManagedRoot(string candidate, string toolsFull,
        string deployments, string legacyFull)
    {
        if (string.IsNullOrWhiteSpace(candidate) || !Path.IsPathRooted(candidate)) return false;
        var normalized = Normalize(candidate);
        return normalized.Equals(toolsFull, StringComparison.OrdinalIgnoreCase) ||
               normalized.StartsWith(deployments, StringComparison.OrdinalIgnoreCase) ||
               normalized.Equals(legacyFull, StringComparison.OrdinalIgnoreCase);
    }

}
