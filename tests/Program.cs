using ikun_installer;
using System;
using System.IO;
using System.Linq;

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

var sandbox = Path.Combine(Path.GetTempPath(), $"ikun-layout-test-{Guid.NewGuid():N}");
Directory.CreateDirectory(sandbox);
try
{
    var tools = Path.Combine(sandbox, "ikun tools");
    var oldRoot = Path.Combine(tools, "deployments", "2.1.0-old");
    Directory.CreateDirectory(Path.Combine(oldRoot, "application"));
    var lockedDll = Path.Combine(oldRoot, "application", "MultiEntityNester.dll");
    File.WriteAllText(lockedDll, "old-loaded-dll");

    using (var nxLock = new FileStream(lockedDll, FileMode.Open, FileAccess.Read, FileShare.Read))
    {
        var newRoot = DeploymentLayout.CreateUniqueRoot(tools, "2.1.0.52",
            new DateTime(2026, 8, 11, 22, 0, 0), "abc12345");
        Require(!newRoot.Equals(oldRoot, StringComparison.OrdinalIgnoreCase), "新旧部署槽发生碰撞");
        var newApp = Path.Combine(newRoot, "application");
        Directory.CreateDirectory(newApp);
        File.WriteAllText(Path.Combine(newApp, "MultiEntityNester.dll"), "new-dll");

        var existing = new[] {
            @"C:\OtherNxTool",
            "# ikun_tools",
            oldRoot,
            @"D:\IndependentTool"
        };
        var updated = DeploymentLayout.BuildCustomDirs(existing, tools, newRoot);
        Require(updated.Contains(@"C:\OtherNxTool"), "误删其他 NX 工具路径");
        Require(updated.Contains(@"D:\IndependentTool"), "误删独立 D 盘工具路径");
        Require(!updated.Contains(oldRoot), "旧部署路径没有移除");
        Require(updated[updated.Count - 2] == DeploymentLayout.Marker && updated[updated.Count - 1] == newRoot,
            "新部署路径没有写在受管标记后");

        var dat = Path.Combine(sandbox, "NX", "UGII", "menus", "custom_dirs.dat");
        DeploymentLayout.WriteCustomDirsAtomic(dat, updated);
        var written = File.ReadAllLines(dat);
        Require(written[written.Length - 1] == newRoot, "custom_dirs.dat 原子切换失败");

        var oldWasLocked = false;
        try { File.WriteAllText(lockedDll, "overwrite"); }
        catch (IOException) { oldWasLocked = true; }
        catch (UnauthorizedAccessException) { oldWasLocked = true; }
        Require(oldWasLocked, "测试未建立旧 DLL 占用条件");
        Require(File.ReadAllText(Path.Combine(newApp, "MultiEntityNester.dll")) == "new-dll",
            "旧 DLL 占用影响了新槽写入");
    }

    Console.WriteLine("side-by-side locked-DLL deployment: PASS");
    Console.WriteLine("atomic custom_dirs switch: PASS");
    Console.WriteLine("unrelated custom directory preservation: PASS");
}
finally
{
    try { Directory.Delete(sandbox, recursive: true); } catch { }
}
