# 爱坤工具箱安装器 — 开发文档

> 本文档面向维护者（打包、部署、CI）。插件使用方法见根目录 [README.md](../README.md)。

NX 插件标准化发布安装器：打包、部署和安装 AiKun Toolbox 集合中的所有 NX 插件。

## What — 做什么

- 打包所有子项目的 DLL/DLX 文件
- 部署到 NX 启动目录（菜单/工具栏/图标）
- 生成自包含的单文件 Windows Forms 安装器
- 支持 NX 菜单（custom.men）和工具栏（custom.tbr）自定义
- 支持 NX 运行期间热更新：原子覆盖已有 DLL/DLX，bar 上已有功能下次点击即使用新版
- 每个 NX 会话首次点击任意业务插件时自动检查更新；新增插件仍需重启 NX 以载入菜单
- 一键发布到分发位置
- 可选受管遥测：通过一次性注册码登记设备，后台上报更新事件及加密设备快照；未配置注册码时完全停用，不影响主流程
- 遥测后台：动森风格只读监看页 `https://td.h.zss.fan:2233`，独立服务端口

## Why — 为什么

多个 NX 插件需要统一发布和管理，此安装器自动化打包、部署、菜单配置和版本管理流程。

## 开发规范

- 唯一权威规范：`docs/NX二次开发权威规范.md`
- AI 开发提示词：`docs/AI-NX二次开发提示词.md`
- 子项目执行摘要：`docs/子项目开发规范.md`
- NX 技术知识、流程、踩坑和模板：`docs/nx-development/`
- 历史规范与对抗审查证据：`docs/governance/`（不具现行规范效力）

## Run — 如何运行

1. 从本仓库 **Releases → latest** 下载 `ikun_installer.exe` 运行安装（日常唯一通道，见「自动打包」节）
   NX 内“检查更新”会先读取资源清单，只下载变化的 DLL/DLX/DAT、菜单和图标并逐项原子替换；Release 同时携带“更新分类”和独立的安装器本体版本，只有安装器运行时代码变化才提示下载完整安装器。
2. 本地调试安装器：先 `pwsh scripts/dev-assemble.ps1 -ReposRoot <插件克隆根目录>` 重建部署资源，再
   `dotnet run --project ikun_installer.csproj`（出真包用 CI；旧 `build.ps1`/`update.ps1` 已按规范 M6 移除）

## Build — 如何编译

```powershell
# 本地调试编译 (WinForms 需 Windows):
dotnet build ikun_installer.csproj -c Release
# 真包由 CI 在 GitHub Actions (ubuntu-latest) 交叉编译 (自包含单文件 win-x64), 见 .github/workflows/pack.yml
```

## Test — 测试

- 发布说明增量提取回归：`bash ci/test-release-notes.sh`
- 纯逻辑测试（版本契约/部署槽，可在 CI 容器跑）：`dotnet run --project tests`
- 闸门自检：`bash ci/gates.sh`（G2/G3/G6）+ `python3 ci/check_consistency.py`（G5/G7）
- 编译后在 NX 1847 中加载安装器
- 验证插件 DLL/DLX 是否正确部署
- 检查 NX 菜单和工具栏是否正常显示

## File Structure

| 文件 | 说明 |
|------|------|
| `Form1.cs` | 安装器 UI 窗体 |
| `Program.cs` | 应用程序入口 |
| `ikun_installer.csproj` | .NET 9.0 SDK 项目文件 |
| `AppConfig.cs` / `Versioning.cs` | 运行时可配置项 / 版本纯逻辑（规范 M6/M9） |
| `plugins.json` | 自动打包的子项目清单（repo+ref；图标取自各仓 plugin.meta） |
| `scripts/dev-assemble.ps1` | 本地重建 `DeployResources/application`（规范 M5） |
| `ci/assemble.sh` | CI：收集各子项目部署资源 + meta 摘要 + G1/G4/G8 |
| `ci/classify-update.sh` | CI：按上次 Release 提交范围区分插件资源更新与安装器本体更新 |
| `ci/gates.sh` | CI：闸门 G2/G3/G6 |
| `ci/check_consistency.py` | CI：闸门 G5/G7 一致性校验 |
| `ci/release-notes.sh` | CI：按上次 Release 基线提取子插件增量更新 |
| `ci/publish-release.sh` | CI：创建/更新 GitHub Release（含安装器更新段 + sha256） |
| `.github/workflows/pack.yml` | CI：打包工作流（含全部闸门） |
| `DeployResources/startup/` | 部署资源（菜单/工具栏/图标，GBK 编码） |

## 自动打包（GitHub Actions CI）

子项目更新后**自动**在 GitHub Actions 上打包并更新 Release，无需本机操作。

**触发链**：改插件源码 → push 子项目（dll/dlx/dat 变更）→ 子项目 `notify-installer.yml`（权威模板见 `docs/templates/`）调 API 触发本仓库 `pack.yml` → GitHub Actions 在 `ubuntu-latest` 上用 `actions/setup-dotnet` 装 9.0 SDK：读 `plugins.json` → clone 各子项目收集资源 → 闸门 G1–G8（规范 §7.3）→ 交叉编译 win-x64 单文件 exe（`EnableWindowsTargeting=true`）→ 更新 Release `latest`（包含完整安装器 exe、资源清单和逐项插件资源）。

**取用**：从本仓库 **Releases → latest** 下载 `ikun_installer.exe` 运行安装。

**加新插件**（规范 §8.2 三步接入，同一提交完成）：
1. `plugins.json` 登记（repo + ref）；
2. `DeployResources/startup/` 追加菜单/图标（GBK 编码，LABEL=该仓 `plugin.meta` 的 `name_cn`，见 `custom.men`/`ikun.rtb`）；
3. 新插件仓库放 `.github/workflows/notify-installer.yml`（从权威模板复制，仅允许定制 paths）。
4. 中文 `name_cn` 必须正好四个汉字；复制 `docs/nx-development/templates/ikun_update_check.hpp`，
   在 `ufusr` 的 `UF_initialize()` 前调用 `CheckOnceOnFirstPluginUse()`，并保持 `UF_UNLOAD_IMMEDIATELY` 以支持热更新。

**额外资源**（不止 dll/dlx）：在子项目根放 `ikun-deploy.txt`，每行一个 glob（如 `*.dll`/`*.dlx`/`*.dat`/`*.cfg`）；缺省为 `*.dll *.dlx *.dat`。文件扁平部署到 `application/`。

**更新记录**：Release 正文内嵌上次实际打包的子项目提交清单；资源清单还会记录每个资源对应的插件中文名和功能说明。下次构建只展示清单之后新增的 `CHANGELOG.md` 条目（包括 `Unreleased`）；未维护 CHANGELOG 时回退到提交标题。每个插件最多展示 8 条，未变化的插件不重复列出。NX 原子更新完成后会按插件分组显示具体更新内容。

**手动触发**：本仓库 Actions 页运行 `pack-installer`，或 `POST /repos/zhaoshuaishuai956/ikun_installer/actions/workflows/pack.yml/dispatches`。

> 自动链路走 GitHub Release；`build.ps1` 刷公司共享盘（Y:/X:）的旧方式保留作可选（CI 环境够不到公司 NAS）。
