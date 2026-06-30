using System.Text;
using Microsoft.Win32;

namespace ikun_installer;

public partial class Form1 : Form
{
    // === UI 控件 ===
    private Label lblTitle = null!;
    private Label lblNxPath = null!;
    private TextBox txtNxPath = null!;
    private Button btnBrowse = null!;
    private Button btnInstall = null!;
    private ProgressBar progressBar = null!;
    private RichTextBox txtLog = null!;

    // === 部署资源根命名空间 ===
    private const string ResourceRoot = "ikun_installer.DeployResources";
    private const string IkToolDir = @"D:\Program Files\ikun tools";

    public Form1()
    {
        InitializeComponent();
        AutoDetectNx();
    }

    private void InitializeComponent()
    {
        this.Text = "爱坤工具箱 NX 安装器 v2.0";
        this.Size = new Size(600, 500);
        this.StartPosition = FormStartPosition.CenterScreen;
        this.FormBorderStyle = FormBorderStyle.FixedDialog;
        this.MaximizeBox = false;
        this.BackColor = Color.FromArgb(240, 240, 240);

        int y = 10;

        // 标题
        lblTitle = new Label
        {
            Text = "爱坤工具箱 NX 1847 安装器",
            Font = new Font("Microsoft YaHei", 14, FontStyle.Bold),
            ForeColor = Color.FromArgb(255, 160, 0),
            AutoSize = true,
            Location = new Point(20, y)
        };
        y += 40;

        // NX 路径
        lblNxPath = new Label
        {
            Text = "NX 1847 安装路径:",
            Font = new Font("Microsoft YaHei", 9),
            AutoSize = true,
            Location = new Point(20, y)
        };
        y += 24;

        txtNxPath = new TextBox
        {
            Font = new Font("Consolas", 9),
            Location = new Point(20, y),
            Size = new Size(460, 24),
            Text = @"C:\Program Files\Siemens\NX 1847"
        };
        btnBrowse = new Button
        {
            Text = "浏览...",
            Font = new Font("Microsoft YaHei", 8),
            Location = new Point(490, y - 1),
            Size = new Size(80, 26)
        };
        btnBrowse.Click += BtnBrowse_Click;
        y += 36;

        // 安装按钮
        btnInstall = new Button
        {
            Text = "安  装",
            Font = new Font("Microsoft YaHei", 12, FontStyle.Bold),
            Location = new Point(20, y),
            Size = new Size(550, 40),
            BackColor = Color.FromArgb(255, 160, 0),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat
        };
        btnInstall.FlatAppearance.BorderSize = 0;
        btnInstall.Click += BtnInstall_Click;
        y += 50;

        // 进度条
        progressBar = new ProgressBar
        {
            Location = new Point(20, y),
            Size = new Size(550, 22),
            Style = ProgressBarStyle.Blocks
        };
        y += 32;

        // 日志框
        txtLog = new RichTextBox
        {
            Font = new Font("Consolas", 9),
            Location = new Point(20, y),
            Size = new Size(550, 180),
            ReadOnly = true,
            BackColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle,
            ScrollBars = RichTextBoxScrollBars.Vertical
        };

        // 添加控件
        this.Controls.Add(lblTitle);
        this.Controls.Add(lblNxPath);
        this.Controls.Add(txtNxPath);
        this.Controls.Add(btnBrowse);
        this.Controls.Add(btnInstall);
        this.Controls.Add(progressBar);
        this.Controls.Add(txtLog);
    }

    private void BtnBrowse_Click(object? sender, EventArgs e)
    {
        using var dlg = new FolderBrowserDialog
        {
            Description = "选择 NX 1847 安装根目录 (包含 UGII 子目录的文件夹)",
            InitialDirectory = txtNxPath.Text
        };
        if (dlg.ShowDialog() == DialogResult.OK)
        {
            txtNxPath.Text = dlg.SelectedPath;
        }
    }

    private void AutoDetectNx()
    {
        // 1. 注册表检测
        string[] regPaths = {
            @"SOFTWARE\Siemens\NX\1847",
            @"SOFTWARE\WOW6432Node\Siemens\NX\1847"
        };
        foreach (var regPath in regPaths)
        {
            try
            {
                using var key = Registry.LocalMachine.OpenSubKey(regPath);
                if (key != null)
                {
                    var dir = key.GetValue("INSTALLDIR") as string;
                    if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir))
                    {
                        txtNxPath.Text = dir.TrimEnd('\\');
                        Log($"注册表检测: {txtNxPath.Text}", Color.Green);
                        return;
                    }
                }
            }
            catch { }
        }

        // 2. 环境变量
        var ugii = Environment.GetEnvironmentVariable("UGII_ROOT_DIR");
        if (!string.IsNullOrEmpty(ugii) && Directory.Exists(ugii))
        {
            txtNxPath.Text = Directory.GetParent(ugii)!.FullName;
            Log($"UGII_ROOT_DIR 检测: {txtNxPath.Text}", Color.Green);
            return;
        }

        // 3. 多盘符遍历标准安装路径
        string[] nxDirs = {
            @"Program Files\Siemens\NX 1847",
            @"Program Files\Siemens\NX1847",
            @"Siemens\NX 1847",
            @"Siemens\NX1847"
        };
        string[] drives = { "C", "D", "E" };
        foreach (var drive in drives)
        {
            foreach (var nxDir in nxDirs)
            {
                var candidate = $@"{drive}:\{nxDir}";
                var ugiiPath = Path.Combine(candidate, "UGII");
                if (Directory.Exists(ugiiPath))
                {
                    txtNxPath.Text = candidate;
                    Log($"多盘符遍历检测: {candidate}", Color.Green);
                    return;
                }
            }
        }

        Log("未自动检测到 NX 1847, 请手动浏览指定路径", Color.DarkOrange);
    }

    private async void BtnInstall_Click(object? sender, EventArgs e)
    {
        btnInstall.Enabled = false;
        txtLog.Clear();
        progressBar.Value = 0;
        int totalSteps = 5;

        try
        {
            var nxRoot = txtNxPath.Text.Trim();
            var nxUgii = Path.Combine(nxRoot, "UGII");
            var nxMenus = Path.Combine(nxUgii, "menus");
            var datFile = Path.Combine(nxMenus, "custom_dirs.dat");
            var startupDir = Path.Combine(IkToolDir, "startup");
            var appDir = Path.Combine(IkToolDir, "application");

            // 步骤1: 验证 NX 目录
            Log("[1/5] 验证 NX 目录...", Color.Black);
            if (!Directory.Exists(nxUgii))
            {
                throw new Exception($"NX UGII 目录不存在: {nxUgii}\n请确认 NX 1847 安装路径正确");
            }
            Log($"  NX 路径验证通过: {nxUgii}", Color.Green);
            progressBar.Value = (int)(1.0 / totalSteps * 100);

            // 步骤2: 创建爱坤工具箱目录
            Log("\n[2/5] 创建爱坤工具箱目录...", Color.Black);
            Directory.CreateDirectory(startupDir);
            Directory.CreateDirectory(appDir);
            Log($"  {startupDir}", Color.Green);
            Log($"  {appDir}", Color.Green);
            progressBar.Value = (int)(2.0 / totalSteps * 100);

            // 步骤3: 释放部署文件
            Log("\n[3/5] 释放部署文件...", Color.Black);
            await Task.Run(() => ExtractResources(startupDir, appDir));
            progressBar.Value = (int)(3.0 / totalSteps * 100);

            // 步骤4: 注册到 NX
            Log("\n[4/5] 注册到 NX custom_dirs.dat...", Color.Black);
            Directory.CreateDirectory(nxMenus);
            await Task.Run(() => RegisterCustomDirs(datFile));
            progressBar.Value = (int)(4.0 / totalSteps * 100);

            // 步骤5: 逐个验证文件
            Log("\n[5/5] 验证安装...", Color.Black);
            var filesToCheck = new Dictionary<string, bool> {
                { Path.Combine(startupDir, "custom.men"), true },
                { Path.Combine(startupDir, "custom.tbr"), false },
                { Path.Combine(startupDir, "ikun_tools.bmp"), false },
                { Path.Combine(startupDir, "ikun_ejector.bmp"), false },
                { Path.Combine(startupDir, "ikun_pmi.bmp"), false },
                { Path.Combine(appDir, "ejector_layout.dll"), true },
                { Path.Combine(appDir, "ejector_layout.dlx"), false },
                { Path.Combine(appDir, "pmi_hole_dim.dll"), true },
                { Path.Combine(appDir, "pmi_hole_dim.dlx"), false },
            };
            var missing = new List<string>();
            foreach (var kv in filesToCheck)
            {
                if (File.Exists(kv.Key))
                    Log($"  ✓ {Path.GetFileName(kv.Key)}", Color.Green);
                else
                {
                    missing.Add(kv.Key);
                    if (kv.Value) // 核心文件
                        Log($"  ✗ {Path.GetFileName(kv.Key)} [核心文件缺失!]", Color.Red);
                    else
                        Log($"  - {Path.GetFileName(kv.Key)} [未生成]", Color.DarkOrange);
                }
            }
            if (missing.Any(f => filesToCheck[f]))
                throw new Exception($"核心文件缺失!\n\n{string.Join("\n", missing.Where(f => filesToCheck[f]))}");
            if (missing.Count > 0)
                Log($"\n  警告: {missing.Count} 个非核心文件未生成, 功能可能受影响", Color.DarkOrange);
            progressBar.Value = 100;

            Log("\n========================================", Color.Green);
            Log("  爱坤工具箱 安装成功!", Color.Green);
            Log("========================================", Color.Green);
            Log("使用: 重启 NX 1847 -> Help 右侧 -> 爱坤工具箱", Color.Blue);

            MessageBox.Show(
                "安装成功!\n\n重启 NX 1847 后, 在菜单栏 Help 右侧\n点击「爱坤工具箱」即可使用。",
                "安装完成",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            Log($"\n✗ 安装失败: {ex.Message}", Color.Red);
            MessageBox.Show(
                $"安装失败:\n\n{ex.Message}",
                "安装失败",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        finally
        {
            btnInstall.Enabled = true;
        }
    }

    private void ExtractResources(string startupDir, string appDir)
    {
        var asm = System.Reflection.Assembly.GetExecutingAssembly();
        var resourceNames = asm.GetManifestResourceNames();

        // 诊断: 列出所有资源名
        Log($"  共找到 {resourceNames.Length} 个嵌入式资源:", Color.DarkGray);
        foreach (var rn in resourceNames)
            Log($"    {rn}", Color.DarkGray);

        int extracted = 0, skipped = 0;
        foreach (var fullName in resourceNames)
        {
            // 解析: ikun_installer.DeployResources.startup.custom.men -> startup\custom.men
            string relPath;
            string? subDir = null;
            if (fullName.StartsWith(ResourceRoot + ".startup."))
            {
                relPath = fullName.Substring((ResourceRoot + ".startup.").Length);
                subDir = startupDir;
            }
            else if (fullName.StartsWith(ResourceRoot + ".application."))
            {
                relPath = fullName.Substring((ResourceRoot + ".application.").Length);
                subDir = appDir;
            }
            else
            {
                skipped++;
                continue;
            }

            if (string.IsNullOrEmpty(relPath) || relPath.EndsWith(".bk", StringComparison.OrdinalIgnoreCase))
            { skipped++; continue; }

            var targetPath = Path.Combine(subDir!, relPath);
            Directory.CreateDirectory(Path.GetDirectoryName(targetPath)!);

            using var stream = asm.GetManifestResourceStream(fullName);
            if (stream == null)
            {
                Log($"  ✗ 无法读取流: {relPath}", Color.Red);
                continue;
            }
            using var fs = File.Create(targetPath);
            stream.CopyTo(fs);
            Log($"  ✓ {relPath}", Color.DarkGray);
            extracted++;
        }
        Log($"  已释放 {extracted} 个文件 (跳过 {skipped} 个)", Color.Green);
    }

    private void RegisterCustomDirs(string datFile)
    {
        var lines = new List<string>();
        if (File.Exists(datFile))
        {
            lines.AddRange(File.ReadAllLines(datFile, Encoding.UTF8)
                .Where(l => !string.IsNullOrWhiteSpace(l)));
        }

        // 清理旧注册
        var newLines = new List<string>();
        bool skip = false;
        foreach (var line in lines)
        {
            if (line == "# ikun_tools" || line == "# nx_tools_deploy" ||
                line == @"E:\NX二次开发\项目\nx_tools_deploy")
            {
                skip = true;
                continue;
            }
            if (skip && line.StartsWith(@"D:\") || skip && line.StartsWith(@"E:\"))
            {
                skip = false;
                if (line != IkToolDir) newLines.Add(line);
                continue;
            }
            if (!skip) newLines.Add(line);
        }

        newLines.Add("");
        newLines.Add("# ikun_tools");
        newLines.Add(IkToolDir);
        File.WriteAllLines(datFile, newLines, new UTF8Encoding(false));
        Log($"  已注册: {IkToolDir}", Color.Green);
    }

    private void Log(string msg, Color color)
    {
        if (txtLog.InvokeRequired)
        {
            txtLog.Invoke(() => Log(msg, color));
            return;
        }
        txtLog.SelectionStart = txtLog.TextLength;
        txtLog.SelectionColor = color;
        txtLog.AppendText(msg + "\n");
        txtLog.ScrollToCaret();
    }
}
