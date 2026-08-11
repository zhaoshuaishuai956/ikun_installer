namespace ikun_installer;

/// <summary>
///  --check-update 静默检查窗体: NX 侧按钮/启动自动检测调起, 有更新才弹窗。
///  流程: 检查 -> 无更新静默自动关闭; 有更新弹确认 -> 下载(进度) -> 启动新安装器 -> 关闭。
/// </summary>
public sealed class UpdateCheckForm : Form
{
    private readonly string? _proxyArg;
    private readonly Label _lblStatus = null!;
    private readonly ProgressBar _progress = null!;
    private readonly Button _btnClose = null!;
    private System.Windows.Forms.Timer? _autoClose;

    public UpdateCheckForm(string? proxyArg)
    {
        _proxyArg = proxyArg;
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

        Shown += async (_, _) => await RunCheckAsync();
    }

    private async Task RunCheckAsync()
    {
        // 代理: 命令行 --proxy 优先, 否则注册表; 无则默认(与 GUI 默认一致)
        var proxy = _proxyArg ?? UpdateManager.ReadProxy() ?? UpdateManager.DefaultProxy;
        var local = UpdateManager.GetLocalVersion();
        UpdateManager.RemoteRelease? remote;
        try
        {
            remote = await UpdateManager.CheckForUpdateAsync(proxy, local);
        }
        catch { remote = null; }

        if (remote == null)
        {
            _lblStatus.Text = $"已是最新版本 (v{local})";
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
            $"发现新版本 {verText} (当前 v{local})\n\n是否立即下载更新?",
            "发现新版本",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Information);
        if (ask != DialogResult.Yes) { Close(); return; }

        _lblStatus.Text = $"正在下载 {verText} ...";
        var progress = new Progress<double>(p =>
        {
            _progress.Value = (int)(p * 100);
            _lblStatus.Text = $"正在下载 {verText} ... {_progress.Value}%";
        });
        var path = await UpdateManager.DownloadAsync(r, proxy, progress);
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
            if (!UpdateManager.LaunchInstaller(path, r.Version))
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
