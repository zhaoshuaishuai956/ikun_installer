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
///   - 资源版本 = Gitea 滚动 release(latest tag) 的 name 中提取的 x.y.z(.w)
///   - 安装器版本 = 资源清单 installer_version；旧清单缺失时回退资源版本
///   - 本地版本 = 程序集 FileVersion(CI 以 -p:Version 注入)
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
    public sealed record RemoteRelease(Version Version, string DownloadUrl, long Size, string? Sha256,
        ResourceManifest? Resources = null, Version? InstallerVersion = null);

    public const string ResourceManifestAssetName = "ikun_resources.json";

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
            ResourceManifest? manifest = null;
            var manifestAsset = rel.Assets?.FirstOrDefault(a =>
                string.Equals(a.Name, ResourceManifestAssetName, StringComparison.OrdinalIgnoreCase));
            if (manifestAsset?.BrowserDownloadUrl is { Length: > 0 } manifestUrl &&
                manifestUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                using var manifestResponse = await client.GetAsync(manifestUrl, ct);
                if (manifestResponse.IsSuccessStatusCode && (manifestResponse.Content.Headers.ContentLength ?? 0) <= 10 * 1024 * 1024)
                {
                    var parsed = ResourceManifest.Parse(await manifestResponse.Content.ReadAsByteArrayAsync(ct));
                    if (parsed is not null && Version.TryParse(parsed.ReleaseVersion, out var manifestVersion) && manifestVersion == ver)
                    {
                        var assetsByName = (rel.Assets ?? []).Where(a => !string.IsNullOrWhiteSpace(a.Name) &&
                            !string.IsNullOrWhiteSpace(a.BrowserDownloadUrl)).ToDictionary(a => a.Name!, StringComparer.OrdinalIgnoreCase);
                        var resolved = parsed.Resources.Select(entry =>
                        {
                            if (!assetsByName.TryGetValue(entry.Asset, out var resourceAsset) ||
                                resourceAsset.BrowserDownloadUrl is not { Length: > 0 } url ||
                                !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) return null;
                            return entry with { Asset = url };
                        }).ToList();
                        if (resolved.All(x => x is not null))
                            manifest = parsed with { Resources = resolved! };
                    }
                }
            }
            Version? installerVersion = null;
            if (manifest?.InstallerVersion is { } installerText && Version.TryParse(installerText, out var parsedInstallerVersion))
                installerVersion = parsedInstallerVersion;
            return new RemoteRelease(ver, asset.BrowserDownloadUrl, asset.Size, Versioning.ExtractSha256(rel.Body), manifest, installerVersion);
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
    ///  ③sha256 存在则必须匹配 (M10) ④有 Authenticode 签名则必须有效。
    ///  信任链权衡(对抗性审查记录):
    ///   - 过渡期 (M13 代码签名落地前): 无签名构建放行 — 信任边界为「Gitea 服务器 + TLS」,
    ///     sha256 为 TLS 之外的第二道完整性校验 (红队批2 P0-1: 无签名+sha256 匹配必须放行,
    ///     否则更新链自我中断; 注释曾与实现相反已修复)。
    ///   - M13 落地时**同一版本原子切换**: 本函数末尾改为 `return sig == true` (签名缺失即拒绝),
    ///     与首个已签名 exe 一起发布 (规范 §9.3.3/M13)。
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
            if (sha256 != null)
            {
                var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
                if (!string.Equals(hash, sha256, StringComparison.OrdinalIgnoreCase))
                    return false;
            }
            // 过渡期: 有签名必须有效, 无签名放行 — M13 落地时改为 return sig == true (红队批2 P0-1)
            return true;
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
        return IsInstallerUpdateAvailable(remote, cur) ? remote : null;
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
            // M6/红队批2 P1-3: 下载落用户级受保护目录 (%LOCALAPPDATA%), 禁止 %TEMP% 共享目录
            // (防同机低权限用户 TOCTOU 换文件; 规范 §9.3.3)
            var dlDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "ikun_tools", "downloads");
            Directory.CreateDirectory(dlDir);
            var temp = Path.Combine(dlDir,
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
    /// 只判断安装器本体是否需要下载。插件资源版本递增不再隐式触发完整安装器更新。
    /// 没有新版清单时回退旧行为，兼容历史 Release。
    /// </summary>
    public static bool IsInstallerUpdateAvailable(RemoteRelease remote, Version local)
        => Versioning.IsNewer(remote.InstallerVersion ?? remote.Version, local);

    /// <summary>
    /// 下载并原子替换 Release 清单中发生变化的插件资源，不下载完整安装器。
    /// 所有资源先落到用户临时目录并校验，之后逐项替换；失败时回滚已替换文件。
    /// </summary>
    public static async Task<ResourceUpdateResult> UpdateResourcesAsync(RemoteRelease remote, string? proxy,
        IProgress<double>? progress = null, CancellationToken ct = default)
    {
        if (remote.Resources is null) return new(0, 0, false, "远端没有插件资源清单");
        var root = ResolveActiveDeploymentRoot();
        if (root is null) return new(0, 0, false, "找不到已安装的插件部署目录");
        var resources = remote.Resources.Resources;
        var staged = new List<(ResourceEntry Entry, string TempPath, string TargetPath, bool IsNew)>();
        var changed = 0;
        var skipped = 0;
        var newPlugin = false;
        var details = new List<ResourceUpdateDetail>();
        var stageRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ikun_tools", "resource-updates", Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(stageRoot);
            using var client = CreateClient(proxy);
            for (var i = 0; i < resources.Count; i++)
            {
                ct.ThrowIfCancellationRequested();
                var entry = resources[i];
                var target = Path.Combine(root, entry.RelativePath.Replace('/', Path.DirectorySeparatorChar));
                if (!IsUnderRoot(root, target)) return new(0, skipped, false, "资源路径越界");
                if (File.Exists(target) && await HashMatchesAsync(target, entry.Sha256, ct)) { skipped++; continue; }
                var temp = Path.Combine(stageRoot, $"{i:D4}.tmp");
                using var response = await client.GetAsync(entry.Asset, HttpCompletionOption.ResponseHeadersRead, ct);
                if (!response.IsSuccessStatusCode) return new(0, skipped, false, $"资源下载失败: {entry.RelativePath}");
                var length = response.Content.Headers.ContentLength;
                if (length is not null && length.Value != entry.Size) return new(0, skipped, false, $"资源大小校验失败: {entry.RelativePath}");
                await using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 64 * 1024, true))
                await using (var input = await response.Content.ReadAsStreamAsync(ct))
                {
                    await input.CopyToAsync(output, ct);
                }
                if (new FileInfo(temp).Length != entry.Size || !await HashMatchesAsync(temp, entry.Sha256, ct))
                    return new(0, skipped, false, $"资源完整性校验失败: {entry.RelativePath}");
                var isNew = entry.RelativePath.StartsWith("application/", StringComparison.OrdinalIgnoreCase) && !File.Exists(target) &&
                    !string.Equals(Path.GetFileName(entry.RelativePath), "ikun_updater.dll", StringComparison.OrdinalIgnoreCase);
                newPlugin |= isNew;
                staged.Add((entry, temp, target, isNew));
                var pluginId = string.IsNullOrWhiteSpace(entry.PluginId)
                    ? Path.GetFileNameWithoutExtension(entry.RelativePath)
                    : entry.PluginId;
                var pluginName = string.IsNullOrWhiteSpace(entry.PluginName) ? pluginId : entry.PluginName;
                var description = string.IsNullOrWhiteSpace(entry.Description) ? "部署资源更新" : entry.Description;
                details.Add(new ResourceUpdateDetail(pluginId!, pluginName!, entry.RelativePath, description!, isNew));
                changed++;
                progress?.Report((double)(i + 1) / resources.Count);
            }

            var backups = new List<(string Target, byte[]? Old, bool Existed)>();
            try
            {
                foreach (var item in staged)
                {
                    var existed = File.Exists(item.TargetPath);
                    backups.Add((item.TargetPath, existed ? await File.ReadAllBytesAsync(item.TargetPath, ct) : null, existed));
                    DeploymentLayout.WriteFileAtomic(item.TargetPath, await File.ReadAllBytesAsync(item.TempPath, ct));
                }
            }
            catch (UnauthorizedAccessException)
            {
                return new(0, skipped, false, "需要管理员权限写入插件部署目录", true);
            }
            catch (Exception ex)
            {
                foreach (var backup in backups.AsEnumerable().Reverse())
                {
                    try
                    {
                        if (backup.Existed && backup.Old is not null) DeploymentLayout.WriteFileAtomic(backup.Target, backup.Old);
                        else if (File.Exists(backup.Target)) File.Delete(backup.Target);
                    }
                    catch { }
                }
                return new(0, skipped, false, $"资源替换失败，已回滚: {ex.Message}");
            }
            return new(changed, skipped, newPlugin, null, false, details);
        }
        catch (OperationCanceledException) { return new(0, skipped, false, "更新已取消"); }
        catch (Exception ex) { return new(0, skipped, false, ex.Message); }
        finally
        {
            try { if (Directory.Exists(stageRoot)) Directory.Delete(stageRoot, true); } catch { }
        }
    }

    private static async Task<bool> HashMatchesAsync(string path, string expected, CancellationToken ct)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 64 * 1024, true);
        var hash = await SHA256.HashDataAsync(stream, ct);
        return Convert.ToHexString(hash).Equals(expected, StringComparison.OrdinalIgnoreCase);
    }

    private static string? ResolveActiveDeploymentRoot()
    {
        var configured = AppConfig.GetString("active_deploy_root", "");
        if (Directory.Exists(configured)) return Path.GetFullPath(configured);
        var deployments = Path.Combine(AppConfig.InstallDir, "deployments");
        return Directory.Exists(deployments)
            ? Directory.EnumerateDirectories(deployments).OrderByDescending(Directory.GetLastWriteTimeUtc).FirstOrDefault()
            : null;
    }

    private static bool IsUnderRoot(string root, string candidate)
    {
        var normalizedRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        return Path.GetFullPath(candidate).StartsWith(normalizedRoot, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>仅在资源确实需要写入且当前进程权限不足时，以 UAC 重启一次检查流程。</summary>
    public static bool LaunchElevatedResourceCheck(string? proxy)
    {
        try
        {
            var self = Environment.ProcessPath;
            if (string.IsNullOrWhiteSpace(self) || !File.Exists(self)) return false;
            var args = "--check-update --elevated" + (string.IsNullOrWhiteSpace(proxy) ? "" : $" --proxy \"{proxy.Replace("\"", "") }\"");
            Process.Start(new ProcessStartInfo(self, args) { UseShellExecute = true, Verb = "runas" });
            return true;
        }
        catch { return false; }
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
