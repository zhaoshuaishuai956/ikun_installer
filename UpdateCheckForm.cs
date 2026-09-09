namespace ikun_installer;

/// <summary>
///  --check-update 静默检查窗体: NX 侧按钮/启动自动检测调起。
///  流程: 先按资源清单增量热更新；只有用户选择完整更新安装器时才下载 exe。
/// </summary>
public sealed class UpdateCheckForm : Form
{
    private readonly string? _proxyArg;
    private readonly bool _elevated;
    private readonly Label _lblStatus = null!;
    private readonly ProgressBar _progress = null!;
    private readonly Button _btnClose = null!;
    private System.Windows.Forms.Timer? _autoClose;

    public UpdateCheckForm(string? proxyArg, bool elevated = false)
    {
        _proxyArg = proxyArg;
        _elevated = elevated;
        Text = "爱坤工具箱 - 检查更新";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(380, 130);

        _lblStatus = new Label
        {
            Text = "正在检查更新...",
            Font = new Font("Microsoft YaHei", 10),
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(15, 15),
            Size = new Size(350, 40)
        };
        _progress = new ProgressBar
        {
            Location = new Point(15, 62),
            Size = new Size(350, 20),
            Style = ProgressBarStyle.Continuous
        };
        _btnClose = new Button
        {
            Text = "关闭",
            Location = new Point(150, 92),
            Size = new Size(80, 28),
            Enabled = false
        };
        _btnClose.Click += (_, _) => Close();

        Controls.Add(_lblStatus);
        Controls.Add(_progress);
        Controls.Add(_btnClose);

        // 外层 try/catch: 下载中关窗等竞态可能抛 ObjectDisposedException, 静默兜底
        Shown += async (_, _) => { try { await RunCheckAsync(); } catch { } };
    }

    private async Task RunCheckAsync()
    {
        // 代理: 命令行 --proxy 优先, 否则注册表; 从未设置才用默认(显式清空=直连)
        var proxy = _proxyArg ?? UpdateManager.ReadProxy() ?? AppConfig.DefaultProxy;
        var local = Versioning.GetLocalVersion();
        UpdateManager.RemoteRelease? remote;
        try
        {
            remote = await UpdateManager.FetchRemoteAsync(proxy);
        }
        catch { remote = null; }

        if (remote == null)
        {
            TelemetryClient.QueueEvent("update_check", "first_plugin_use", "failed");
            _lblStatus.Text = "检查失败: 无法连接 Gitea 或解析版本信息";
            _btnClose.Enabled = true;
            return;
        }
        var resourceChanged = false;
        if (remote.Resources is not null)
        {
            _lblStatus.Text = "正在检查插件资源差异...";
            var resourceProgress = new Progress<double>(p =>
                _lblStatus.Text = $"正在更新插件资源... {(int)(p * 100)}%" );
            var resourceResult = await UpdateManager.UpdateResourcesAsync(remote, proxy, resourceProgress);
            if (!resourceResult.Succeeded)
            {
                if (resourceResult.Error == "找不到已安装的插件部署目录")
                {
                    _lblStatus.Text = "未找到现有插件目录，将提供完整安装器更新...";
                }
                else
                {
                if (resourceResult.RequiresElevation && !_elevated && UpdateManager.LaunchElevatedResourceCheck(proxy))
                {
                    _lblStatus.Text = "正在请求管理员权限完成插件更新...";
                    Close();
                    return;
                }
                _lblStatus.Text = $"插件资源更新未完成: {resourceResult.Error}";
                _btnClose.Enabled = true;
                return;
                }
            }
            resourceChanged = resourceResult.Succeeded && resourceResult.Changed > 0;
            if (resourceChanged)
            {
                TelemetryClient.QueueEvent("download_completed", "first_plugin_use", "completed", remote.Version);
                _lblStatus.Text = $"已原子更新 {resourceResult.Changed} 项插件资源";
                if (resourceResult.NewPlugin)
                    MessageBox.Show(this, "已有插件已热更新，可直接使用。\n检测到新增插件，需重启 NX 后载入菜单。",
                        "插件资源更新完成", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        if (!Versioning.IsNewer(remote.Version, local))
        {
            TelemetryClient.QueueEvent("update_check", "first_plugin_use", "up_to_date", remote.Version);
            _lblStatus.Text = resourceChanged ? "插件资源已更新" : $"已是最新版本 (v{local})";
            _btnClose.Enabled = true;
            _autoClose = new System.Windows.Forms.Timer { Interval = 3000 };
            _autoClose.Tick += (_, _) => Close();
            _autoClose.Start();
            return;
        }

        // 拷贝非空引用: lambda 捕获与 await 会使 nullable 流分析失效, 统一用非空变量
        UpdateManager.RemoteRelease r = remote!;
        var verText = $"v{r.Version}";

        var ask = MessageBox.Show(
            this,
            resourceChanged
                ? $"插件资源已更新。安装器本体也有新版本 {verText}（当前 v{local}）。\n\n是否同时下载完整安装器？"
                : $"发现新版本 {verText} (当前 v{local})\n\n是否立即下载完整安装器?",
            resourceChanged ? "安装器完整更新" : "发现新版本",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Information);
        if (ask != DialogResult.Yes) { TelemetryClient.QueueEvent("update_offer_closed", "first_plugin_use", "closed", r.Version); Close(); return; }

        _lblStatus.Text = $"正在下载 {verText} ...";
        var progress = new Progress<double>(p =>
        {
            _progress.Value = (int)(p * 100);
            _lblStatus.Text = $"正在下载 {verText} ... {_progress.Value}%";
        });
        var path = await UpdateManager.DownloadAsync(r, proxy, progress);
        TelemetryClient.QueueEvent(path is null ? "download_failed" : "download_completed", "first_plugin_use", path is null ? "failed" : "completed", r.Version);
        if (path == null)
        {
            _lblStatus.Text = "下载失败, 请检查代理与网络";
            _btnClose.Enabled = true;
            return;
        }

        var ok = MessageBox.Show(
            this,
            $"新版本 {verText} 已下载完成.\n\n是否立即启动更新安装?",
            "下载完成",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question);
        if (ok == DialogResult.Yes)
        {
            if (!UpdateManager.LaunchInstaller(path, r.Version, r.Sha256))
            {
                _lblStatus.Text = "启动更新安装失败(校验未通过或已被替换), 请重新下载";
                _btnClose.Enabled = true;
                return;
            }
            Close();
            return;
        }
        _lblStatus.Text = $"已下载: {path}";
        _btnClose.Enabled = true;
    }
}
