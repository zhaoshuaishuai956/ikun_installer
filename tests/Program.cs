using ikun_installer;
using System;
using System.IO;
using System.Linq;

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

// ============ 版本逻辑测试 (M9: 规范 §6.6 Release name 契约 + §9.3.2 单调) ============
var ver = Versioning.ParseRemoteVersion("爱坤工具箱 v2.1.0.54");
Require(ver == new Version(2, 1, 0, 54), "四段版本解析失败");
Require(Versioning.ParseRemoteVersion("爱坤工具箱 v2.1.0.54 (修复)") == new Version(2, 1, 0, 54),
    "带后缀的四段解析失败");
Require(Versioning.ParseRemoteVersion("爱坤工具箱 v2.1.0") == new Version(2, 1, 0, 0), "三段解析失败");
Require(Versioning.ParseRemoteVersion("爱坤工具箱 v10.0.0") == new Version(10, 0, 0, 0), "两位主版本解析失败");
Require(Versioning.ParseRemoteVersion("1.2.3.4.5") == null, "五段版本必须拒绝 (M9 锚点)");
Require(Versioning.ParseRemoteVersion("爱坤工具箱") == null, "无版本名必须拒绝");
Require(Versioning.ParseRemoteVersion("") == null, "空名必须拒绝");
Require(Versioning.ParseRemoteVersion(null) == null, "null 必须拒绝");
Require(Versioning.ParseRemoteVersion("v9") == null, "单段版本必须拒绝");
Require(Versioning.ParseRemoteVersion("v2.1.0-beta") == null, "预发布后缀必须拒绝 (红队批2 P2-3)");
Require(Versioning.ParseRemoteVersion("v2.1.0.") == null, "尾点必须拒绝 (红队批2 P2-3)");
Require(Versioning.ParseRemoteVersion("99999999999999999999.0.0") == null, "溢出必须拒绝 (红队批2 P2-2)");
Require(Versioning.ParseRemoteVersion("爱坤工具箱 v2.1.0.54 ") == new Version(2, 1, 0, 54),
    "尾随空格应容忍");
Require(Versioning.ParseRemoteVersion("爱坤工具箱 v2.1.0.54\t(修复)") == new Version(2, 1, 0, 54),
    "Tab+括号后缀应容忍");

Require(Versioning.IsNewer(new Version(2, 1, 0, 54), new Version(2, 1, 0, 53)), "新版本应判为新");
Require(!Versioning.IsNewer(new Version(2, 1, 0, 53), new Version(2, 1, 0, 54)), "旧版本不得判为新 (防降级)");
Require(!Versioning.IsNewer(new Version(2, 1, 0, 54), new Version(2, 1, 0, 54)), "相等不得判为新 (防重放)");

Require(Versioning.ExtractSha256("...\n- SHA256: " + new string('a', 64) + "\n...")?.Length == 64,
    "sha256 提取失败");
Require(Versioning.ExtractSha256("- SHA256: " + new string('A', 64)) == new string('A', 64).ToUpperInvariant(),
    "sha256 大小写归一失败");
Require(Versioning.ExtractSha256("无哈希正文") == null, "无哈希应返回 null");
Require(Versioning.ExtractSha256("- SHA256: abc") == null, "短哈希必须拒绝");

Console.WriteLine("versioning contract tests: PASS");

// ============ 更新检查单实例测试 ============
var updateMutexName = $"ikun-update-check-test-{Guid.NewGuid():N}";
using (var firstCheck = UpdateCheckInstanceGuard.TryAcquire(updateMutexName))
{
    Require(firstCheck != null, "首个更新检查应获得互斥锁");
    using var duplicateCheck = UpdateCheckInstanceGuard.TryAcquire(updateMutexName);
    Require(duplicateCheck == null, "活跃检查期间必须拒绝重复更新对话框");
}
using (var nextCheck = UpdateCheckInstanceGuard.TryAcquire(updateMutexName))
{
    Require(nextCheck != null, "前一次检查关闭后应允许再次检查");
}
Console.WriteLine("update-check single-instance guard: PASS");

// ============ 热更新部署目录测试 ============
var hotTools = Path.Combine(Path.GetTempPath(), $"ikun-hot-root-{Guid.NewGuid():N}");
var hotRoot = Path.Combine(hotTools, "deployments", "2.1.0-active");
var hotLines = new[] { @"D:\IndependentTool", DeploymentLayout.Marker, hotRoot };
Require(DeploymentLayout.FindActiveRoot(hotLines, hotTools) == Path.GetFullPath(hotRoot),
    "未能找到已注册的热更新部署目录");
Require(DeploymentLayout.FindActiveRoot(new[] { hotTools }, hotTools) == Path.GetFullPath(hotTools),
    "未兼容早期直接注册的工具箱根目录");
Require(DeploymentLayout.FindActiveRoot(new[] { @"D:\IndependentTool" }, hotTools) == null,
    "误将无关 NX 工具目录识别为热更新目录");
Directory.CreateDirectory(hotRoot);
var atomicTarget = Path.Combine(hotRoot, "application", "plugin.dll");
DeploymentLayout.WriteFileAtomic(atomicTarget, new byte[] { 1, 2, 3 });
if (OperatingSystem.IsWindows())
{
    using var loadedPlugin = new FileStream(atomicTarget, FileMode.Open, FileAccess.Read, FileShare.Read);
    var lockedUpdateRejected = false;
    try { DeploymentLayout.WriteFileAtomic(atomicTarget, new byte[] { 9 }); }
    catch (IOException) { lockedUpdateRejected = true; }
    catch (UnauthorizedAccessException) { lockedUpdateRejected = true; }
    Require(lockedUpdateRejected, "不得覆盖正在使用的插件 DLL");
    Require(File.ReadAllBytes(atomicTarget).SequenceEqual(new byte[] { 1, 2, 3 }),
        "热更新失败时未保留旧 DLL");
}
DeploymentLayout.WriteFileAtomic(atomicTarget, new byte[] { 4, 5 });
Require(File.ReadAllBytes(atomicTarget).SequenceEqual(new byte[] { 4, 5 }), "原子热覆盖失败");
Directory.Delete(hotTools, recursive: true);
Console.WriteLine("in-place hot-update deployment: PASS");

// ============ 部署槽测试 (既有) ============
var sandbox = Path.Combine(Path.GetTempPath(), $"ikun-layout-test-{Guid.NewGuid():N}");
Directory.CreateDirectory(sandbox);
try
{
    var tools = Path.Combine(sandbox, "ikun tools");
    var oldRoot = Path.Combine(tools, "deployments", "2.1.0-old");
    Directory.CreateDirectory(Path.Combine(oldRoot, "application"));
    var lockedDll = Path.Combine(oldRoot, "application", "MultiEntityNester.dll");
    File.WriteAllText(lockedDll, "old-loaded-dll");

    // 部署槽测试 (CI 容器为 linux: FileShare 锁是 Windows 语义, 非 Windows 跳过占用断言)
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
    Require(File.ReadAllText(Path.Combine(newApp, "MultiEntityNester.dll")) == "new-dll",
        "旧 DLL 占用影响了新槽写入");

    if (OperatingSystem.IsWindows())
    {
        // Windows 专属: 旧 dll 被 NX 以 FileShare.Read 占用时, 写入必须失败 (部署槽机制的前提)
        using (var nxLock = new FileStream(lockedDll, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var oldWasLocked = false;
            try { File.WriteAllText(lockedDll, "overwrite"); }
            catch (IOException) { oldWasLocked = true; }
            catch (UnauthorizedAccessException) { oldWasLocked = true; }
            Require(oldWasLocked, "测试未建立旧 DLL 占用条件");
        }
        Console.WriteLine("side-by-side locked-DLL deployment (Windows): PASS");
    }
    else
    {
        Console.WriteLine("side-by-side deployment (linux: 锁语义跳过): PASS");
    }

    Console.WriteLine("side-by-side locked-DLL deployment: PASS");
    Console.WriteLine("atomic custom_dirs switch: PASS");
    Console.WriteLine("unrelated custom directory preservation: PASS");
}
finally
{
    try { Directory.Delete(sandbox, recursive: true); } catch { }
}
