using Microsoft.Win32;

namespace ikun_installer;

/// <summary>
/// 运行时可配置项 (规范 §11.4/M6): 注册表 HKCU\Software\ikun_tools 优先,
/// 其次环境变量 (IKUN_&lt;NAME&gt;), 最后内置默认值。
/// 消灭硬编码的机器路径/代理/API 地址; 安装器安装时写回 install_dir (Form1)。
/// </summary>
public static class AppConfig
{
    public const string RegistryKeyPath = @"Software\ikun_tools";

    /// <summary>按 注册表 > 环境变量 > 默认值 取字符串配置。</summary>
    public static string GetString(string valueName, string fallback)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath);
            if (key?.GetValue(valueName) is string s && !string.IsNullOrWhiteSpace(s))
                return s.Trim();
        }
        catch { /* 注册表不可用则回退 */ }
        var env = Environment.GetEnvironmentVariable("IKUN_" + valueName.ToUpperInvariant());
        return string.IsNullOrWhiteSpace(env) ? fallback : env.Trim();
    }

    /// <summary>安装目录 (默认 D:\Program Files\ikun tools; 注册表 install_dir / IKUN_INSTALL_DIR 可覆盖)。</summary>
    public static string InstallDir => GetString("install_dir", @"D:\Program Files\ikun tools");

    /// <summary>Gitea latest release API (默认自托管地址; 可覆盖)。</summary>
    public static string GiteaLatestApi => GetString("gitea_api",
        "https://gt.h.zss.fan:2233/api/v1/repos/zhaoshen/ikun_installer/releases/tags/latest");

    /// <summary>默认更新代理 (可覆盖; 空=直连)。</summary>
    public static string DefaultProxy => GetString("default_proxy", "192.168.1.5:6666");
}
