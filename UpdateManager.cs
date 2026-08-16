using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace ikun_installer;

/// <summary>
///  更新管理: Gitea latest release 版本对比 / 代理配置 / 下载
///  设计(第一性原理):
///   - 远端版本 = Gitea 滚动 release(latest tag) 的 name 中提取的 x.y.z(.w)
///   - 本地版本 = 程序集 FileVersion(CI 以 -p:Version=2.1.0.<run> 注入)
///   - 代理 = HKCU\Software\ikun_tools\proxy (可空=直连); 默认见 AppConfig
///   - 下载目标文件名固定, 内容来自 Gitea 附件(https + 系统证书校验)
///   - M9/M10: 强类型 JSON 解析 + 锚点版本正则 + Release 正文 sha256 第二道完整性校验
/// </summary>
public static class UpdateManager
{
    // === 常量 ===
    public const string RegistryKeyPath = @"Software\ikun_tools";
    public const string AssetName = "ikun_installer.exe";

    /// <summary>远端 release 信息</summary>
    public sealed record RemoteRelease(Version Version, string DownloadUrl, long Size, string? Sha256);

    // === 版本 ===
    // 版本解析/比较/哈希提取纯逻辑集中在 Versioning (M9: 可在 CI 容器测试);
    // 本类只保留与注册表/网络/进程相关的部分。

    // === 代理 ===

    /// <summary>读注册表代理: null=从未设置(调用方可给默认值); ""=用户显式清空(直连); 其他=代理地址</summary>
    public static string? ReadProxy()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath);
            if (key == null) return null;   // 从未设置
            var v = key.GetValue("proxy") as string;
            return string.IsNullOrWhiteSpace(v) ? "" : v.Trim();  // 已设置: 空=显式直连
        }
        catch { return null; }
    }

    public static void SaveProxy(string? proxy)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RegistryKeyPath);
            key.SetValue("proxy", proxy ?? "");
        }
        catch { }
    }

    /// <summary>规范化代理为可用的 http://host:port (混合端口以 http 代理协议访问)</summary>
    public static string? NormalizeProxy(string? proxy)
    {
        if (string.IsNullOrWhiteSpace(proxy)) return null;
        var p = proxy.Trim();
        // 只允许 host:port 或 scheme://host:port; 拒绝路径/用户信息等
        if (!Regex.IsMatch(p, @"^(?:(?:https?)://)?[0-9A-Za-z_.\-]+:\d+$"))
            return null;
        return p.Contains("://") ? p : "http://" + p;
    }

    // === 网络 ===

    /// <summary>创建带代理(可空)的 HttpClient</summary>
    public static HttpClient CreateClient(string? proxy)
    {
        var handler = new HttpClientHandler
        {
            UseProxy = false,
            AutomaticDecompression = System.Net.DecompressionMethods.GZip | System.Net.DecompressionMethods.Deflate
        };
        var norm = NormalizeProxy(proxy);
        if (norm != null)
        {
            try
            {
                handler.Proxy = new WebProxy(new Uri(norm));
                handler.UseProxy = true;
            }
            catch { handler.UseProxy = false; }
        }
        var c = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(30) };
        c.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("ikun_installer", "1.0"));
        return c;
    }

    // === Gitea 响应强类型 DTO (M9: 替代脆弱正则 JSON 解析) ===

    private sealed class GiteaReleaseDto
    {
        public string? Name { get; set; }
        public string? Body { get; set; }
        public List<GiteaAssetDto>? Assets { get; set; }
    }

    private sealed class GiteaAssetDto
    {
        public string? Name { get; set; }
        public long Size { get; set; }
        public string? BrowserDownloadUrl { get; set; }
    }

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };

    // === 检查 ===

    /// <summary>
    ///  查询 Gitea latest release 并解析版本/附件地址/正文 sha256。
    ///  返回 null 表示: 网络失败 / 解析失败 / 无附件(视为"无法检查", 不误报有更新)。
    /// </summary>
    public static async Task<RemoteRelease?> FetchRemoteAsync(string? proxy, CancellationToken ct = default)
    {
        try
        {
            using var client = CreateClient(proxy);
            using var resp = await client.GetAsync(AppConfig.GiteaLatestApi, ct);
            if (!resp.IsSuccessStatusCode) return null;
            var json = await resp.Content.ReadAsStringAsync(ct);

            var rel = JsonSerializer.Deserialize<GiteaReleaseDto>(json, JsonOpts);
            if (rel?.Name == null) return null;
            var asset = rel.Assets?.FirstOrDefault(a =>
                string.Equals(a.Name, AssetName, StringComparison.OrdinalIgnoreCase));
            if (asset == null || string.IsNullOrEmpty(asset.BrowserDownloadUrl)) return null;

            var ver = Versioning.ParseRemoteVersion(rel.Name);
            if (ver == null) return null;
            // 下载地址必须 https, 防 Gitea 响应被控后指向明文 http + MITM (security MEDIUM)
            if (!asset.BrowserDownloadUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) return null;
            return new RemoteRelease(ver, asset.BrowserDownloadUrl, asset.Size, Versioning.ExtractSha256(rel.Body));
        }
        catch { return null; }
    }

    /// <summary>下载大小硬上限 (防御恶意服务器填满磁盘; 单文件安装器约 110MB)</summary>
    private const long MaxDownloadBytes = 200L * 1024 * 1024;

    // === Authenticode 校验 (经 PowerShell Get-AuthenticodeSignature, 系统级签名验证) ===
    // 说明: 直接 P/Invoke WinVerifyTrust 在本机环境对任何文件都返回 0x800B0001
    // (trust provider 不识别主题, 连有签名的 notepad 也如此), 故改用系统已验证的
    // PowerShell 校验器。exit: 0=签名有效, 1=无签名, 2=有签名但无效/校验失败。

    /// <summary>
    ///  Authenticode 校验: 有签名则必须有效; 无签名返回 false(企业内部构建放行)。
    ///  返回 null 表示校验失败(校验器不可用/超时/路径异常 → fail-closed 拒绝下载)。
    /// </summary>
    private static bool? VerifyAuthenticode(string path)
    {
        try
        {
            // path 由本程序生成, 但 GetTempPath 来自 TMP 环境变量, 可能含单引号/引号/换行 → 拒绝(fail-closed)
            if (path.IndexOfAny(new[] { '\'', '"', '\n', '\r' }) >= 0)
                return null;
            // powershell 用绝对路径, 防应用目录/CWD 的恶意同名 exe 劫持 (security HIGH)
            var psExe = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(psExe)) return null;
            var ps = $"-NoProfile -NonInteractive -WindowStyle Hidden -Command \"& {{$s=Get-AuthenticodeSignature -LiteralPath '{path}'; switch($s.Status){{'Valid'{{exit 0}}'NotSigned'{{exit 1}}default{{exit 2}}}}}}\"";
            using var p = Process.Start(new ProcessStartInfo(psExe, ps)
            {
                CreateNoWindow = true,
                UseShellExecute = false
            });
            if (p == null) return null;
            if (!p.WaitForExit(30000))
            {
                try { p.Kill(); } catch { }
                return null;
            }
            return p.ExitCode switch
            {
                0 => true,  // 签名有效
                1 => false, // 无签名
                _ => null   // 有签名但无效 → 拒绝
            };
        }
        catch { return null; }
    }

    /// <summary>
    ///  下载后信任校验: ①size 已比对 ②FileVersion 必须等于远端版本(防损坏/错文件)
    ///  ③有 Authenticode 签名则必须有效 ④Release 正文 sha256 存在则必须匹配 (M10)。
    ///  信任链权衡(对抗性审查记录): 无签名的企业内部构建放行 + FileVersion 由 Gitea
    ///  响应提供 → 实际信任边界为「Gitea 服务器 + TLS」; 若 CI token/服务器被攻破即可
    ///  分发任意代码经 runas 以管理员执行, 属内部构建已知风险; M13(代码签名)落地前
    ///  保持现状, 落地时切换为 fail-closed。
    /// </summary>
    public static bool VerifyDownloadedInstaller(string path, Version expected, string? sha256 = null)
    {
        try
        {
            var fv = FileVersionInfo.GetVersionInfo(path).FileVersion;
            if (string.IsNullOrEmpty(fv) || !Version.TryParse(fv, out var v) || v != expected)
                return false;
            var sig = VerifyAuthenticode(path);
            if (sig == null) return false;           // 校验器不可用 → fail-closed
            if (sig == false && sha256 == null) return true;  // 无签名且无 sha256: 过渡期放行(见上注释)
            if (sha256 != null)
            {
                var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
                if (!string.Equals(hash, sha256, StringComparison.OrdinalIgnoreCase))
                    return false;
            }
            return sig != false;                     // 有签名必须有效; 无签名但有 sha256 也放行
        }
        catch { return false; }
    }

    /// <summary>有更新且可下载时返回 RemoteRelease, 否则 null。
    ///  注意: 网络失败/解析失败与无更新均返回 null, 调用方需要区分时请用 FetchRemoteAsync + IsNewer。</summary>
    public static async Task<RemoteRelease?> CheckForUpdateAsync(string? proxy, Version? local = null, CancellationToken ct = default)
    {
        var cur = local ?? Versioning.GetLocalVersion();
        var remote = await FetchRemoteAsync(proxy, ct);
        if (remote == null) return null;
        return Versioning.IsNewer(remote.Version, cur) ? remote : null;
    }

    // === 下载 ===

    /// <summary>
    ///  下载 release 附件到 %TEMP%\ikun_installer_&lt;ver&gt;_&lt;rand&gt;.exe。
    ///  返回下载文件完整路径(已通过 size/FileVersion/Authenticode 信任校验); 失败返回 null。
    /// </summary>
    public static async Task<string?> DownloadAsync(RemoteRelease remote, string? proxy,
        IProgress<double>? progress = null, CancellationToken ct = default)
    {
        try
        {
            using var client = CreateClient(proxy);
            using var resp = await client.GetAsync(remote.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!resp.IsSuccessStatusCode) return null;

            // 强制 size>0 且不超过硬上限, 防御恶意服务器填满磁盘
            var expected = remote.Size > 0 ? remote.Size : resp.Content.Headers.ContentLength ?? 0;
            if (expected <= 0 || expected > MaxDownloadBytes) return null;
            var temp = Path.Combine(Path.GetTempPath(),
                $"{Path.GetFileNameWithoutExtension(AssetName)}_{remote.Version}_{Guid.NewGuid():N}.exe");

            await using var fs = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 64 * 1024, useAsync: true);
            await using var src = await resp.Content.ReadAsStreamAsync(ct);

            var buf = new byte[64 * 1024];
            long total = 0;
            while (true)
            {
                var n = await src.ReadAsync(buf, ct);
                if (n <= 0) break;
                if (total + n > MaxDownloadBytes) { total = -1; break; } // 超上限中止
                await fs.WriteAsync(buf.AsMemory(0, n), ct);
                total += n;
                if (progress != null)
                    progress.Report(Math.Min(1.0, (double)total / expected));
            }
            await fs.FlushAsync(ct);
            await fs.DisposeAsync();  // 必须先释放文件句柄(FileShare.None), 否则后续校验/删除打开会冲突

            if (total != expected)
            {
                try { File.Delete(temp); } catch { }
                return null;
            }
            // 信任链校验: FileVersion 必须等于远端版本; 有 Authenticode 签名则必须有效; sha256 存在则必须匹配
            if (!VerifyDownloadedInstaller(temp, remote.Version, remote.Sha256))
            {
                try { File.Delete(temp); } catch { }
                return null;
            }
            return temp;
        }
        catch { return null; }
    }

    /// <summary>
    ///  启动下载好的新安装器(更新安装对话框, 请求管理员以写 ikun tools 目录)。
    ///  TOCTOU 防护: runas 确认框显示期间同 TMP 用户可能替换已校验的 exe, 故启动前重校验。
    ///  返回 false 表示校验未通过或启动失败。
    /// </summary>
    public static bool LaunchInstaller(string exePath, Version expected, string? sha256 = null)
    {
        try
        {
            if (!VerifyDownloadedInstaller(exePath, expected, sha256)) return false;
            // Verb=runas 触发 UAC 提权: 安装器需写安装目录(见 AppConfig.InstallDir)
            Process.Start(new ProcessStartInfo(exePath) { UseShellExecute = true, Verb = "runas" });
            return true;
        }
        catch { return false; }
    }

    /// <summary>安装成功后把安装器自身复制到 ikun tools 目录, 供 NX 侧按钮调用</summary>
    public static bool SelfCopyToToolsDir(string toolsDir)
    {
        try
        {
            var self = Environment.ProcessPath;
            if (string.IsNullOrEmpty(self)) return false;
            var target = Path.Combine(toolsDir, AssetName);
            if (string.Equals(self, target, StringComparison.OrdinalIgnoreCase)) return true;
            Directory.CreateDirectory(toolsDir);
            File.Copy(self, target, overwrite: true);
            return File.Exists(target) && new FileInfo(target).Length == new FileInfo(self).Length;
        }
        catch { return false; /* 非致命: 插件部署与安装器自更新彼此隔离 */ }
    }
}
