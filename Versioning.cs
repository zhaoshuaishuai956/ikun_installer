using System.Diagnostics;
using System.Text.RegularExpressions;

namespace ikun_installer;

/// <summary>
/// 版本解析/比较/哈希提取纯逻辑 (规范 M9)。
/// 与 WinForms/注册表完全解耦 → 可在 CI 容器 (linux, dotnet sdk) 直接编译测试。
/// </summary>
public static class Versioning
{
    /// <summary>本地程序集 FileVersion (如 2.1.0.40; 本地构建可能为 2.1.0.0)</summary>
    public static Version GetLocalVersion()
    {
        try
        {
            var path = Environment.ProcessPath;
            if (path != null)
            {
                var fv = FileVersionInfo.GetVersionInfo(path).FileVersion;
                if (!string.IsNullOrEmpty(fv) && Version.TryParse(fv, out var v))
                    return v;
            }
        }
        catch { }
        return new Version(0, 0, 0);
    }

    /// <summary>
    /// 从 release name(外部输入, 不可信)提取 x.y.z(.w)。
    /// 锚点规则 (规范 §6.6/M9, 红队批2): 前后不得是数字或点, 拒绝 "1.2.3.4.5"、"v9"、
    /// 预发布后缀 "-beta"、尾点 "2.1.0."; 允许 "爱坤工具箱 v2.1.0.54" 与 "v2.1.0.54 (修复)"。
    /// 数字用 TryParse 防溢出 (P2-2)。失败返回 null。
    /// </summary>
    public static Version? ParseRemoteVersion(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var m = Regex.Match(name, @"(?<![0-9.])(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?=\s*(?:\(|$))");
        if (!m.Success) return null;
        if (!int.TryParse(m.Groups[1].Value, out var major) ||
            !int.TryParse(m.Groups[2].Value, out var minor) ||
            !int.TryParse(m.Groups[3].Value, out var build))
            return null;
        var rev = 0;
        if (m.Groups[4].Success && !int.TryParse(m.Groups[4].Value, out rev))
            return null;
        return new Version(major, minor, build, rev);
    }

    /// <summary>仅当远端严格大于本地才视为有更新 (防降级/重放, 规范 §9.3.2)。</summary>
    public static bool IsNewer(Version remote, Version local)
        => remote > local;

    /// <summary>从 Release 正文提取 sha256 (发布脚本写入 "- SHA256: &lt;hex&gt;"); 无则返回 null (过渡期放行)。</summary>
    public static string? ExtractSha256(string? body)
    {
        if (string.IsNullOrWhiteSpace(body)) return null;
        var m = Regex.Match(body, @"(?im)^\s*(?:-\s*)?SHA256[:\s]+([0-9a-fA-F]{64})\s*$");
        return m.Success ? m.Groups[1].Value.ToUpperInvariant() : null;
    }
}
