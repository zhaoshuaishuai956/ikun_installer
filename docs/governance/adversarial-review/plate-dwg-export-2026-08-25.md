# 板面导出修复与更新接入对抗审查（2026-08-25）

范围：plate_dwg_export 默认 DWG 文件名修复、首次点击更新接入，以及安装器启动图标资源。

## P0

无。未发现会删除旧部署、改写 custom_dirs.dat、泄露凭证或使已注册按钮失效的变更。

## P1（已修复）

1. **NX 历史输入覆盖当前 PRT 名**
   - 反例：用户切换 PRT 后再次打开 Block Styler，NX 在 init_cb 后恢复历史字段，默认 DWG 名可能属于上一个部件。
   - 修复：在 AddDialogShownHandler 中读取当前显示部件，刷新输出目录和同名 .dwg 文件名；用户在本次对话框内手工修改后不会被再次覆盖。

2. **在册插件未触发统一更新检查**
   - 反例：安装器发布新版后，用户点击该插件不会启动安装器检查，无法得到更新提醒。
   - 修复：逐字复制权威 ikun_update_check.hpp，并在 ufusr 的 UF_initialize() 前调用 CheckOnceOnFirstPluginUse()。模板使用命名事件按 NX 进程去重；安装器缺失或启动失败静默放行业务并允许下次重试。

3. **菜单引用的图标资源缺失**
   - 反例：菜单按钮 IKUN_PLATEDWG / IKUN_TEXTLAYOUT 的 BITMAP 不存在，安装器一致性闸门失败，发布包资源不完整。
   - 修复：新增 ikun_plate_dwg_export.bmp 和 ikun_text_auto_layout.bmp，保留原有 GBK 菜单、BUTTON、LABEL、ACTIONS 与注册表不变。

## P2（未验证边界）

1. 未做 NX 1847 人工实机冒烟：当前没有可用于验证的已保存 PRT，因而未声称已验证对话框显示、导出结果或关闭窗口后的热加载。
2. 未触发远端 Release/安装器打包；该行为留给通知工作流，须在 CI 中验证带本次 DLL 的实际收集和发布。
3. DLL 被 NX 占用时的同目录替换已由 DeploymentLayoutTests 验证“拒绝覆盖且保留旧文件”；本次未在真实 NX 进程中重复该场景。

## 证据

- python ci/check_consistency.py：退出码 0。
- dotnet run --project tests/DeploymentLayoutTests.csproj -c Release --no-restore：退出码 0。
- plate_dwg_export/build.ps1：退出码 0；dumpbin /exports 同时含 ufusr 与 ufusr_ask_unload。
- DLL 二进制包含 UTF-16LE 标记 ikun_first_plugin_check_。
