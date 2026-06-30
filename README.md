# 爱坤工具箱安装器 ikun_installer

NX 插件标准化发布安装器：打包、部署和安装 AiKun Toolbox 集合中的所有 NX 插件。

## What — 做什么

- 打包所有子项目的 DLL/DLX 文件
- 部署到 NX 启动目录（菜单/工具栏/图标）
- 生成自包含的单文件 Windows Forms 安装器
- 支持 NX 菜单（custom.men）和工具栏（custom.tbr）自定义
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

- 编译后在 NX 1847 中加载安装器
- 验证插件 DLL/DLX 是否正确部署
- 检查 NX 菜单和工具栏是否正常显示

## File Structure

| 文件 | 说明 |
|------|------|
| `Form1.cs` | 安装器 UI 窗体 |
| `Program.cs` | 应用程序入口 |
| `ikun_installer.csproj` | .NET 9.0 SDK 项目文件 |
| `build.ps1` | 发布脚本（5 步自动化） |
| `DeployResources/` | 部署资源（菜单/工具栏/图标） |
