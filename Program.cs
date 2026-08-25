namespace ikun_installer;

static class Program
{
    /// <summary>
    ///  The main entry point for the application.
    ///  --check-update [--proxy host:port] : 静默检查更新(NX 侧按钮/启动自动检测调起)
    ///  --proxy host:port                 : 指定更新代理(可与 GUI 模式混用, 覆盖注册表)
    /// </summary>
    [STAThread]
    static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        _ = TelemetryClient.InitializeAsync();

        // M6: 运行时可配置项注入 (规范 §11.4; 注册表>环境变量>默认值)
        DeploymentLayout.LegacyDeployDir = AppConfig.GetString(
            "legacy_nx_deploy_dir", @"E:\NX二次开发\项目\nx_tools_deploy");

        var proxyArg = ExtractProxyArg(args);
        if (args.Contains("--check-update"))
        {
            // The NX DLL can request a manual check while its delayed startup check is still
            // pending. Keep this mutex for the entire dialog lifetime so only one process can
            // display update prompts, including requests from another NX session.
            using var instanceGuard = UpdateCheckInstanceGuard.TryAcquire();
            if (instanceGuard == null) return;

            Application.Run(new UpdateCheckForm(proxyArg));
            return;
        }

        Application.Run(new Form1(proxyArg, args.Contains("--install")));
    }

    /// <summary>从参数里取 --proxy 的下一段; 无则 null</summary>
    private static string? ExtractProxyArg(string[] args)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--proxy" && !string.IsNullOrWhiteSpace(args[i + 1]))
                return args[i + 1].Trim();
        }
        return null;
    }
}
