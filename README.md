# 爱坤工具箱安装器 ikun_installer

NX 插件标准化发布安装器：打包、部署和安装 AiKun Toolbox 集合中的所有 NX 插件。

## What — 做什么

- 打包所有子项目的 DLL/DLX 文件
- 部署到 NX 启动目录（菜单/工具栏/图标）
- 生成自包含的单文件 Windows Forms 安装器
- 支持 NX 菜单（custom.men）和工具栏（custom.tbr）自定义
- 支持 NX 运行期间安装：每次写入独立部署槽，当前会话继续使用旧插件，下次启动自动切换
- 一键发布到分发位置

## Why — 为什么

多个 NX 插件需要统一发布和管理，此安装器自动化打包、部署、菜单配置和版本管理流程。

## Run — 如何运行

1. 确保所有子项目已标记 `.ready`
2. 在 build.ps1 的 `$subIcon` 映射中添加新插件图标文字
3. 注册菜单和工具栏到 `DeployResources/startup/`
4. 运行 `build.ps1` 发布

## Build — 如何编译

```powershell
pwsh -ExecutionPolicy Bypass -File .\build.ps1
```

## Test — 测试

- 发布说明增量提取：`bash ci/test-release-notes.sh`
- 编译后在 NX 1847 中加载安装器
- 验证插件 DLL/DLX 是否正确部署
- 检查 NX 菜单和工具栏是否正常显示

## File Structure

| 文件 | 说明 |
|------|------|
| `Form1.cs` | 安装器 UI 窗体 |
| `Program.cs` | 应用程序入口 |
| `ikun_installer.csproj` | .NET 9.0 SDK 项目文件 |
| `build.ps1` | 本机发布脚本（5 步自动化，刷共享盘） |
| `plugins.json` | 自动打包的子项目清单（仓库+图标） |
| `ci/assemble.sh` | CI：收集各子项目部署资源 |
| `ci/release-notes.sh` | CI：按上次 Release 基线提取子插件增量更新 |
| `ci/publish-release.sh` | CI：创建/更新 Gitea Release |
| `.gitea/workflows/pack.yml` | CI：打包工作流 |
| `DeployResources/` | 部署资源（菜单/工具栏/图标） |

## 自动打包（rock5t CI）

子项目更新后**自动**在 Gitea 主机 rock5t 上打包并更新 Release，无需本机操作。

**触发链**：改插件源码 → push 子项目（dll/dlx/dat 变更）→ 子项目 `notify-installer.yml` 调 API 触发本仓库 `pack.yml` → rock5t 的 act_runner 在 `dotnet/sdk:9.0` 容器里：读 `plugins.json` → clone 各子项目收集资源 → 交叉编译 win-x64 单文件 exe（`EnableWindowsTargeting=true`）→ 更新 Release `latest`（只放 exe）。

**取用**：从本仓库 **Releases → latest** 下载 `ikun_installer.exe` 运行安装。

**加新插件**：
1. `plugins.json` 登记（repo + icon）；
2. `DeployResources/startup/` 加菜单/图标（GBK 编码，见 `custom.men`/`ikun.rtb`）；
3. 新插件仓库放 `.gitea/workflows/notify-installer.yml`（复制现有子项目的即可）。

**额外资源**（不止 dll/dlx）：在子项目根放 `ikun-deploy.txt`，每行一个 glob（如 `*.dll`/`*.dlx`/`*.dat`/`*.cfg`）；缺省为 `*.dll *.dlx *.dat`。文件扁平部署到 `application/`。

**更新记录**：Release 正文内嵌上次实际打包的子项目提交清单。下次构建只展示清单之后新增的 `CHANGELOG.md` 条目（包括 `Unreleased`）；未维护 CHANGELOG 时回退到提交标题。每个插件最多展示 8 条，未变化的插件不重复列出。

**手动触发**：本仓库 Actions 页运行 `pack-installer`，或 `POST /api/v1/repos/zhaoshen/ikun_installer/actions/workflows/pack.yml/dispatches`。

> 自动链路走 Gitea Release；`build.ps1` 刷公司共享盘（Y:/X:）的旧方式保留作可选（rock5t 够不到 NAS）。
