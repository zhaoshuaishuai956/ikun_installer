#pragma once

#include <windows.h>
#include <cwchar>
#include <string>

namespace IkunUpdateReminder
{
inline std::wstring ParentPath(const std::wstring& path)
{
    const auto slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

inline std::wstring FindInstallerPath()
{
    wchar_t modulePath[32768] = {};
    HMODULE module = nullptr;
    if (GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            (LPCWSTR)&FindInstallerPath, &module) &&
        GetModuleFileNameW(module, modulePath, static_cast<DWORD>(_countof(modulePath))) > 0)
    {
        // Current layout: <tools>\deployments\<active>\application\plugin.dll.
        // Legacy layout:  <tools>\application\plugin.dll.
        auto root = ParentPath(ParentPath(ParentPath(ParentPath(modulePath))));
        if (!root.empty() && GetFileAttributesW((root + L"\\ikun_installer.exe").c_str()) != INVALID_FILE_ATTRIBUTES)
            return root + L"\\ikun_installer.exe";

        root = ParentPath(ParentPath(modulePath));
        if (!root.empty() && GetFileAttributesW((root + L"\\ikun_installer.exe").c_str()) != INVALID_FILE_ATTRIBUTES)
            return root + L"\\ikun_installer.exe";
    }

    wchar_t envDir[32768] = {};
    const DWORD envLength = GetEnvironmentVariableW(
        L"IKUN_INSTALL_DIR", envDir, static_cast<DWORD>(_countof(envDir)));
    if (envLength > 0 && envLength < _countof(envDir))
    {
        std::wstring root(envDir, envLength);
        while (!root.empty() && (root.back() == L'\\' || root.back() == L'/')) root.pop_back();
        return root + L"\\ikun_installer.exe";
    }
    // Compatibility default for existing installations; prefer discovered layout or IKUN_INSTALL_DIR.
    return L"D:\\Program Files\\ikun tools\\ikun_installer.exe";
}

/// Launches one update check on the first business-plugin invocation in this NX process.
/// The event handle is intentionally kept open; Windows releases it when NX exits.
inline void CheckOnceOnFirstPluginUse()
{
    const std::wstring installer = FindInstallerPath();
    if (GetFileAttributesW(installer.c_str()) == INVALID_FILE_ATTRIBUTES) return;

    wchar_t eventName[128] = {};
    swprintf_s(eventName, L"Local\\ikun_first_plugin_check_%lu", GetCurrentProcessId());
    SetLastError(ERROR_SUCCESS);
    HANDLE sessionMarker = CreateEventW(nullptr, TRUE, TRUE, eventName);
    if (!sessionMarker) return;
    if (GetLastError() == ERROR_ALREADY_EXISTS)
    {
        CloseHandle(sessionMarker);
        return;
    }

    wchar_t commandLine[32768] = {};
    swprintf_s(commandLine, L"\"%s\" --check-update", installer.c_str());
    STARTUPINFOW startup = {};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process = {};
    if (CreateProcessW(installer.c_str(), commandLine, nullptr, nullptr, FALSE,
                       CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process))
    {
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        return;
    }

    // Launch failed: remove the marker so the next plugin click can retry.
    CloseHandle(sessionMarker);
}
}
