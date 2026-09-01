# 在册插件紫色生产图标与远程打包对抗审查（2026-09-01）

范围：8 个在册业务插件的正式 32×32 图标、紫色技术图标设计方法、权威规范 §4.1 配色条款、
图标语义表与 G5g 防漂移检查，以及本次推送会实际运行的远程拉仓链路。

## P0（阻断）

无。

- 没有修改 `custom.men` 的 BUTTON、LABEL、ACTIONS 或 BITMAP 文件名，既有注册功能不受影响。
- 8 个生产 BMP 全部在完整生成并通过格式检查后才覆盖，不存在只替换部分图标的提交状态。
- 没有改 DLL/DLX、更新器、下载地址或安装布局。

## P1（已修复并复验）

1. **权威规范与紫色设计方法冲突。**
   原 §4.1 仍规定蓝橙配色，而设计文档为紫色提案，会形成两个事实源。现已由维护者确认后把紫色角色色值
   回写 §4.1，设计文档明确为下位细则，格式、命名和发布规则仍以权威规范为准。

2. **在册插件与设计资料可能漂移。**
   语义表以 `plugin-semantic:<repo>` 机器标记记录 8 个插件，G5g 对 `plugins.json` 做双向集合与重复项检查；
   菜单 BITMAP、部署 BMP 与插件清单继续由 G5b/G5c 校验。

3. **CI Token 进入 clone URL。**
   `.gitea/workflows/pack.yml` 的安装器自仓 clone 和 `ci/assemble.sh` 的 8 个子仓 clone 原先都把 PAT 放入
   URL，可能进入进程参数或失败日志。两处均改为无凭证 HTTPS URL，临时 `GIT_ASKPASS` 只从环境读取
   PAT；脚本退出时删除临时文件，Token 不进入仓库、URL、git config 或提交差异。

4. **本地远程组装中途失败会破坏旧部署目录。**
   `scripts/dev-assemble.ps1` 改为先在同卷暂存目录收齐全部插件并验证 DLL/DLX，再交换
   `DeployResources/application`；失败恢复旧目录并保留可恢复证据。远程 8 仓组装实测退出码 0。

5. **恶意 `plugin.meta`、`ikun-deploy.txt`、CHANGELOG 或文档诱导越权。**
   元数据只按白名单字段解析并由 G5 校验；部署 glob 拒绝路径分隔符和符号链接；CHANGELOG 只按文本提取，
   不执行其中内容。本次实现没有把仓库 README、注释、设计文档或外部页面当成用户授权。

## P2（已知边界）

1. **未做 NX 1847 实机 Ribbon/DPI 检查。**
   已做 32px 原尺寸接触表和格式检查，但 NX 100%/125%/150% DPI、浅色/深色主题观感仍需用户实机确认。
   图标和菜单资源在 NX 启动时加载；安装新版后需重启 NX 才能可靠看到新图标，业务 DLL 热更新边界不变。

2. **本机完整 `ci/gates.sh` 缺少 WSL `xmllint`。**
   本机命令因此退出 1，并把 8 个 DLX 误报为 XML 失败；Python `ElementTree` 等价解析 8/8 通过。
   远程工作流在闸门前明确安装 `libxml2-utils`，会执行真实 `xmllint`。G3 导出检查和 G6 安全检查本机未报错。

3. **不声称 NX 业务功能已实机回归。**
   本次不改业务 DLL/DLX；验证覆盖安装器测试、远程资源组装、图标格式/注册和安装器发布构建。

## 反例结论

- **攻击者/凭证泄露**：clone 命令和 remote URL 不含 Token；暂存区仍需在提交前再做 secret 扫描。
- **断网用户**：图标为安装包内本地 BMP，不依赖网络；断网不影响已安装图标显示。
- **NX 正在运行且 DLL 被占用**：本次不替换业务 DLL；图标随下次 NX 启动加载，不改变失败保旧热更新机制。
- **旧版安装布局**：沿用既有 `DeployResources/startup/ikun_<repo>.bmp` 文件名原位覆盖，不新增注册路径。
- **新增插件首次接入**：8 个插件均已在 `plugins.json` 与菜单登记，G5/G7 双向检查通过；不产生半接入。
- **更新中途失败**：安装器既有原子部署与失败保旧逻辑未修改；本地开发组装也改为收齐后交换。

## 验证证据

- 资源合同：8/8 SVG 可解析；PNG 为 32×32；BMP 为 `BM`、32×32、planes=1、24 位、3126 字节；
  `docs/design/assets/bmp32` 与 `DeployResources/startup` SHA-256 逐一相同。
- `python ci/check_consistency.py`：退出码 0，G5/G7 PASS。
- `bash ci/test-release-notes.sh`：退出码 0。
- `dotnet run --project tests -c Release`：退出码 0；版本、单实例、原位热更新、锁定 DLL 旁路、原子目录切换通过。
- `pwsh -File scripts/dev-assemble.ps1 -UseRemote`：退出码 0，8 个远程插件全部收集。
- Python DLX XML 解析：8/8 通过，退出码 0。
- `dotnet publish ikun_installer.csproj -c Release -p:EnableWindowsTargeting=true`：退出码 0，生成单文件 EXE。
- `git diff --check`：退出码 0；工作差异 secret 扫描 0 命中。
