/* ============================================================
 *  ikun_updater.cpp - 爱坤工具箱「检查更新」NX 插件 (NX 1847)
 *  入口:
 *   - ufusr: 菜单/Ribbon「检查更新」按钮 (ACTIONS ikun_updater.dll)
 *  功能: 读注册表 HKCU\Software\ikun_tools\proxy (代理配置, 由安装器维护),
 *        启动 ikun_installer.exe --check-update [--proxy ...]
 *        版本对比/下载/更新安装对话框全部由安装器完成。
 * ============================================================ */
#include <windows.h>
#ifdef CreateDialog
#undef CreateDialog   /* 避免与 NXOpen::UI::CreateDialog 冲突 (UI.hxx 明确要求) */
#endif
#ifdef max
#undef max
#endif
#include <uf.h>
#include <uf_ui.h>
#include <NXOpen/UI.hxx>
#include <NXOpen/NXMessageBox.hxx>
#include <NXOpen/NXString.hxx>
#include <cstdio>
#include <cstring>
#include <string>

using namespace NXOpen;

// M6 (规范 §11.4): 安装器路径不再硬编码 — 安装器安装时把目录写入注册表 install_dir,
// 本 dll 优先读注册表/环境变量 IKUN_INSTALL_DIR, 回退到默认值。
// 注意: 本文件改动需在开发机用 nxplugin/build.ps1 重编 ikun_updater.dll (NX SDK)。
static const char* IKUN_EXE_DEFAULT = "D:\\Program Files\\ikun tools\\ikun_installer.exe";
static const char* REG_KEY  = "Software\\ikun_tools";
static const char* REG_VAL_PROXY = "proxy";
static const char* REG_VAL_INSTALL_DIR = "install_dir";

// 读注册表字符串(空=未设置)
static std::string ReadRegString(const char* valueName)
{
    char buf[1024] = "";
    HKEY hk = nullptr;
    if (RegOpenKeyExA(HKEY_CURRENT_USER, REG_KEY, 0, KEY_READ, &hk) == ERROR_SUCCESS)
    {
        DWORD type = 0, sz = sizeof(buf);
        if (RegQueryValueExA(hk, valueName, nullptr, &type, (LPBYTE)buf, &sz) == ERROR_SUCCESS
            && type == REG_SZ && sz > 0 && buf[0] != '\0')
        {
            RegCloseKey(hk);
            return std::string(buf);
        }
        RegCloseKey(hk);
    }
    return "";
}

// 安装器完整路径: 注册表 install_dir > 环境变量 IKUN_INSTALL_DIR > 默认值
// 红队批2 P2-7: 目录必须过白名单(字母/数字/空格/:\-_.), 防 CreateProcessA 命令行注入
static std::string GetInstallerExePath()
{
    std::string dir = ReadRegString(REG_VAL_INSTALL_DIR);
    if (dir.empty())
    {
        const char* env = getenv("IKUN_INSTALL_DIR");
        if (env != nullptr && *env != '\0') dir = env;
    }
    if (dir.empty()) dir = IKUN_EXE_DEFAULT;
    bool ok = true;
    for (char c : dir)
    {
        bool valid = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                  || c == ' ' || c == ':' || c == '\\' || c == '/' || c == '-' || c == '_' || c == '.';
        if (!valid) { ok = false; break; }
    }
    if (!ok) dir = IKUN_EXE_DEFAULT;   // 非法配置回退默认值, 不执行
    if (!dir.empty() && dir.back() != '\\' && dir.back() != '/') dir += '\\';
    return dir + "ikun_installer.exe";
}

// 显示 NX 消息框: 用 NXMessageBox(按 UTF-8 显示), 不能用 uc1601(UF 层期望 ANSI/GBK,
// UTF-8 字符串会乱码——踩坑总结「中文编码」)。NX 会话异常时静默。
static void ShowNxMsg(const char* title, const char* msg)
{
    try
    {
        UI::GetUI()->NXMessageBox()->Show(title, NXMessageBox::DialogTypeInformation, msg);
    }
    catch (...) { }
}

// 读注册表代理(空=直连); 结果只保留白名单字符, 防 CreateProcess 参数注入
static std::string ReadProxyConfig()
{
    char buf[256] = "";
    HKEY hk = nullptr;
    if (RegOpenKeyExA(HKEY_CURRENT_USER, REG_KEY, 0, KEY_READ, &hk) == ERROR_SUCCESS)
    {
        DWORD type = 0, sz = sizeof(buf);
        if (RegQueryValueExA(hk, REG_VAL_PROXY, nullptr, &type, (LPBYTE)buf, &sz) == ERROR_SUCCESS
            && type == REG_SZ && sz > 0 && buf[0] != '\0')
        {
            for (const char* p = buf; *p; ++p)
            {
                char c = *p;
                bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                       || c == '.' || c == ':' || c == '/' || c == '-' || c == '_';
                if (!ok) { buf[0] = '\0'; break; }
            }
        }
        else { buf[0] = '\0'; }
        RegCloseKey(hk);
    }
    return std::string(buf);
}

// 启动安装器检查更新 (CreateProcessA 不经 cmd.exe, 无 shell 注入面)
static void LaunchUpdateCheck()
{
    std::string cmd = std::string("\"") + GetInstallerExePath() + "\" --check-update";
    std::string proxy = ReadProxyConfig();
    if (!proxy.empty())
        cmd += " --proxy " + proxy;

    STARTUPINFOA si = {};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = {};
    char cmdline[1024] = {};
    strncpy_s(cmdline, cmd.c_str(), _TRUNCATE);

    if (CreateProcessA(nullptr, cmdline, nullptr, nullptr, FALSE,
                       CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi))
    {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
}

// 启动自动检测/按钮检查的公共入口: 取命名互斥(多会话只允许一个检查)
// WAIT_ABANDONED(持互斥的会话崩溃)也视为已获取并释放, 防检查永久静默失效
static bool LaunchUpdateCheckOnce()
{
    HANDLE mtx = CreateMutexA(nullptr, FALSE, "ikun_update_check");
    DWORD wait = mtx ? WaitForSingleObject(mtx, 0) : WAIT_FAILED;
    bool acquired = (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED);
    if (acquired)
    {
        LaunchUpdateCheck();
        ReleaseMutex(mtx);
    }
    if (mtx) CloseHandle(mtx);
    return acquired;
}

extern "C" __declspec(dllexport) void ufusr(char* param, int* retcod, int parm_len)
{
    int err = UF_initialize();
    if (err != 0) return;
    try
    {
        if (GetFileAttributesA(GetInstallerExePath().c_str()) == INVALID_FILE_ATTRIBUTES)
        {
            char msg[512] = {};
            snprintf(msg, sizeof(msg),
                "未找到安装器:\n%s\n\n请先运行爱坤工具箱安装器 (ikun_installer.exe) 完成安装。", GetInstallerExePath().c_str());
            ShowNxMsg("爱坤工具箱", msg);
        }
        else if (!LaunchUpdateCheckOnce())
        {
            ShowNxMsg("爱坤工具箱", "已有更新检查正在进行，请稍候。");
        }
        // else: 已成功启动更新检查——不弹「已启动」提示, 由安装器 UpdateCheckForm 自行反馈
        //       (有更新弹确认框 / 无更新 3 秒自动关闭)
    }
    catch (...) { }
    UF_terminate();
}

extern "C" __declspec(dllexport) int ufusr_ask_unload(void) { return UF_UNLOAD_IMMEDIATELY; }
