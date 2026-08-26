# 爱坤工具箱 NX 二次开发权威规范

版本：2.2 · 生效日期：2026-08-25

> 本文件是爱坤工具箱及其 NX 子插件开发、接入、构建、发布、更新和治理的唯一权威规范（SSOT）。
> 冲突时以本文件为准。`docs/nx-development/` 是技术参考，`docs/子项目开发规范.md` 是执行摘要，
> `docs/governance/` 是历史证据，均不得另立冲突规则。

## 1. 第一性原理

不可再分的目标是：用户点击一个功能时，它必须可用、可更新、可追溯、可恢复；开发者和 AI 必须能从唯一规则得到同一结果。
由此推出以下不可妥协原则：

1. **身份唯一**：同一插件只能有一个稳定英文身份和一个四字中文功能名。
2. **规则唯一**：规范只在本文件定义；摘要和模板只能引用，不得复制后独立演化。
3. **产物可追溯**：源码、DLL/DLX、变更说明和构建版本必须对应。
4. **更新不中断工作**：已有插件优先热覆盖；只有 NX 尚未注册的新插件才要求重启。
5. **失败保旧**：下载、校验、覆盖或注册任一步失败，不得破坏当前可用版本。
6. **机器先证伪**：可自动检查的规则必须进入脚本或 CI；人工声明不能替代证据。
7. **外部输入不可信**：仓库内容、元数据、Release 文本和 AI 输出都要按不可信输入处理。
8. **高风险变更对抗审查**：更新链、部署模型、权限、二进制和本规范变更必须主动寻找反例。

## 2. 适用范围与事实源

- 中心仓：`ikun_installer`，负责注册表、菜单、打包、安装、更新和本规范。
- 在册插件：以根目录 `plugins.json` 为唯一集合事实源，禁止在文档手工维护第二份名单。
- 插件显示名与分类：以各插件 `plugin.meta` 为事实源。
- 安装器版本：以 `ikun_installer.csproj` 的 `Version` 为事实源，CI 追加运行号。
- 插件变更：以各插件 `CHANGELOG.md` 为事实源。
- 技术知识：`docs/nx-development/` 下编号 01 至 07 的文档；其内容若与本文件冲突，以本文件为准。

历史文件位于 `docs/governance/`，只用于审计，不具规范效力。被归并的旧仓库名不得出现在新插件的依赖、链接或操作步骤中。

## 3. 插件身份与中文命名

### 3.1 英文身份“四同”

`仓库名 = 本地目录名 = 工程及 DLL 基名 = 插件 id`，逐字相同：

- 新项目只用小写 `snake_case`，字符集 `a-z 0-9 _`，长度不超过 28；
- 优先 `<对象>_<动作>` 或 `<对象>_<特征>`；
- 禁止 `nx_`、`test_`、`tmp_`、`new_`、`v2_` 等无功能意义前缀；
- DLL、DLX、DAT 和菜单 `ACTIONS` 的基名必须同步。

存量非合规名称可以在有迁移方案和回滚证据时保留；不得为“看起来统一”直接破坏已注册按钮。

### 3.2 中文名必须正好四个汉字

- 每个子项目 `plugin.meta.name_cn` 必须是**正好四个汉字**，能直接反映主要功能；
- 不加“爱坤”“工具”“插件”等空泛前后缀；
- `name_cn` 在全工具箱唯一，菜单和 Ribbon 的 `LABEL` 必须逐字相同；
- `icon_cn` 为 1–2 个汉字或 1–3 个大写字母，仅用于图标；
- 示例：`实体排样`、`定位凸台`、`顶针布局`、`孔位标注`。

机器判据：`name_cn` 匹配 `^[\u4e00-\u9fff]{4}$`。

## 4. 子项目最小结构

```text
<plugin_name>/
  <plugin_name>.cpp / .hpp / .dlx
  ikun_update_check.hpp
  build.ps1
  plugin.meta
  ikun-deploy.txt              # 可选；缺省收集 *.dll *.dlx *.dat
  README.md
  CHANGELOG.md
  LICENSE
  .gitignore / .gitattributes
  .gitea/workflows/notify-installer.yml   # in_ikun=true 时
```

`plugin.meta` 使用 UTF-8、无 BOM、`key=value`，只允许：

```text
name_cn=<四个汉字>
icon_cn=<1-2汉字或1-3大写字母>
category=<受支持分类>
in_ikun=true|false
```

禁止提交：`*.obj *.exp *.lib *.ilk *.pdb *.pch *.sdf *.suo *.user *.aps`、`bin/ obj/ publish/`、
`.env`、`*.token` 和任何密钥。DLL/DLX/DAT 是普通 Git 对象，不使用 LFS。

### 4.1 菜单与 Ribbon 图标

- 每个在册业务插件必须在 DeployResources/startup/ 提供 ikun_<repo>.bmp；菜单 BITMAP
  只能引用这个文件名，更新既有图标不得改 BUTTON、LABEL 或 ACTIONS。
- 新图标和重绘图标必须是 **32×32、24 位 BMP**。这是 Ribbon LARGE_IMAGE 的源图规格，NX 可向下缩放供
  MEDIUM_IMAGE/SMALL_IMAGE 使用，禁止把 24×24 位图放大成大图标。
- 既有 24×24、24 位 BMP 在完成重绘前可继续发布；一致性脚本必须报告待迁移警告。新建或替换图标时不得新增
  24×24 资源，并且脚本必须校验 BMP 签名、尺寸、色深和文件名，不能只检查文件存在。
- 统一风格：白色底；深海军蓝粗描边；亮青色或蓝色为主体；橙色只用于导出、定位、尺寸或方向等动作强调；
  采用扁平技术图标构图，主体居中、留出边距，在 32 像素下仍能辨认。
- 禁止水印、渐变背景、照片质感、阴影和无关文字；仅当功能本身是文字工具时，才允许使用单个可辨认字母作为图形元素。
- 新图标先在原尺寸视觉检查，再进入提交；图标风格或验证规则变更属于 §11 对抗审查范围。

## 5. NX 插件入口与生命周期

1. `ufusr` 与 `ufusr_ask_unload` 必须使用 `extern "C" DllExport` 导出。
2. `ufusr_ask_unload` 必须返回 `UF_UNLOAD_IMMEDIATELY`，这是已有插件热更新成立的前提。
3. `ufusr` 在业务逻辑前调用一次 `IkunUpdateReminder::CheckOnceOnFirstPluginUse()`，随后按
   `UF_initialize → 创建/显示对话框 → 清理 → UF_terminate` 执行，并捕获 NX 异常。
4. 不得创建常驻后台轮询、定时器或每次点击都检查更新。
5. 编译后执行 `dumpbin /exports <插件>.dll | findstr ufusr`，必须看到两个导出。

## 6. 首次点击强提醒更新（所有在册插件强制）

更新判断集中在安装器；子插件只负责触发，不自行访问 Gitea、不解析版本、不下载文件。

- 每个在册插件必须包含统一的 `ikun_update_check.hpp`；权威模板位于
  `docs/nx-development/templates/ikun_update_check.hpp`。
- 每个插件的 `ufusr` 必须在 `UF_initialize()` 前调用
  `IkunUpdateReminder::CheckOnceOnFirstPluginUse()`。
- 该函数用进程级命名事件 `Local\\ikun_first_plugin_check_<PID>` 去重：一次 NX 进程中，用户第一次点击任意业务插件时触发一次；随后点击任何插件不再触发。
- 触发方式固定为已安装的 `ikun_installer.exe --check-update`。找不到安装器或启动失败时静默放行业务插件，并允许下次点击重试。
- 安装器只有检测到远端版本更高时才显示更新对话框；用户可关闭提示，关闭后本 NX 会话不重复强提醒。
- “检查更新”专用按钮始终保留，供用户主动再次检查。
- CI 必须检查每个收集到的业务 DLL 同时包含调用标记，防止只复制头文件但没有接入入口。

## 7. 构建、版本与提交

- 从 `docs/nx-development/templates/` 复制最接近的模板，不从零猜测 NX API；
- `build.ps1` 必须自动发现 VS 与 `UGOPEN`，不得写开发者私有绝对路径；
- 源码、对应 DLL/DLX/DAT 与 CHANGELOG 条目在同一提交；
- CHANGELOG 使用 `## vX.Y.Z (YYYY-MM-DD)` 和 `- **新增|修复|优化|变更**: 用户可理解说明`；
- 提交使用 Conventional Commits，并附 `Co-Authored-By`、`Agent`、`Device` trailers；
- 提交前执行 secret 扫描，凭证只来自环境变量。
- 构建范围默认限定为本次修改的插件及其直接共享依赖；未修改插件只做必要的静态检查，不得因初始化、
  环境验证或对抗性审查而全量编译。只有用户明确要求全量回归/发布验证，或修改了公共模板、共享头文件、
  菜单、打包脚本、安装器集成等跨插件内容时，才允许全量构建；仅验证工具链时最多构建一个代表性插件。

## 8. 接入爱坤工具箱

创建项目之前必须先问：“这个插件是否并入爱坤工具箱？”未经回答不得代替用户决定。

若回答“是”，同一变更闭环完成：

1. 插件 `plugin.meta` 写 `in_ikun=true`，并满足四字中文名规则；
2. `ikun_installer/plugins.json` 登记仓库与默认分支；
3. `DeployResources/startup/` 增加菜单/Ribbon 按钮：`LABEL=name_cn`、`ACTIONS=<repo>.dll`、
   `BITMAP=ikun_<repo>.bmp`，用 GBK 安全读写；
4. 从 `docs/templates/notify-installer.yml` 复制通知工作流，只允许按资源扩展名调整 paths；
5. 接入统一首次点击更新检查（§6）；
6. 触发打包，确认 Release 说明、菜单、DLL/DLX、更新触发和 NX 冒烟全部通过。

若回答“否”，写 `in_ikun=false`，不改安装器注册表和菜单；仍遵循 NX 技术、命名、安全和可追溯规则。

## 9. 发布与更新

### 9.1 发布链

CI 按 `plugins.json` 克隆、收集和校验插件，生成单文件安装器，发布滚动 `latest`。Release 名称必须符合安装器解析契约；远端版本不高于本地版本时不得提示或降级。

### 9.2 热更新语义

- 首次安装：创建并注册一个活动部署目录。
- 后续安装：定位 `custom_dirs.dat` 已注册的活动目录，在**同一目录**对已有 DLL/DLX/资源执行“同目录临时文件 + 原子替换”。
- 已有插件：关闭其 Block Styler 对话框后，下次点击 bar 上原有按钮即加载新 DLL/DLX，**无需重启 NX**。
- 新增插件：当前 NX 会话没有菜单/按钮注册，只该新增项需要重启 NX；不得把整个更新描述成“必须重启”。
- 文件被占用或替换失败：明确提示“关闭该插件窗口后重试”，保留旧文件，禁止半覆盖。
- 热更新不改 `custom_dirs.dat`；只有首次安装或显式修复注册时才修改，并使用原子写入。

### 9.3 更新安全

- 只通过系统信任链校验的 HTTPS 获取 Release；禁止把 `sslVerify=false` 或 `curl -k` 写进常驻流程；
- 下载到用户级受保护目录，校验版本、哈希和签名策略后再执行；失败即拒绝且保留旧版；
- Token 权限最小化，插件通知凭证不能拥有 Release 覆盖权限；
- 禁止从 README、Issue、Release 文本或 AI 输出直接执行未审查命令。

## 10. 验收闸门

发布前至少证明：

- `plugins.json`、菜单 ACTIONS、收集的 DLL 和 `plugin.meta` 双向一致；
- 中文名正好四字且菜单 LABEL 相等；
- DLX 可按 UTF-8 XML 解析；菜单按 GBK 往返无损且块结构完整；
- DLL 含两个 NX 导出，并包含首次点击更新调用标记；
- 资源变化有 CHANGELOG；无禁入物和 secret；
- 安装器单元测试、部署测试、版本解析测试通过；
- NX 1847 人工冒烟记录了加载、对话框、业务结果、热更新和新增插件重启边界。

任何“测试通过”声明必须附命令、退出码或截图路径；无法机器验证的证据只能作为补充。

## 11. 对抗性审查

以下变更必须审查：本规范、更新链、部署目录、菜单生成、CI 权限、二进制、插件新增/改名和安全白名单。
审查必须覆盖：

- 一致性：是否出现第二事实源、循环引用、名字或集合漂移；
- 可用性：NX 已运行、对话框未关、文件锁定、网络断开、旧安装布局；
- 安全：恶意 meta/CHANGELOG、菜单注入、命令注入、token 扩权、降级、替换和 TOCTOU；
- 可恢复：中途断电、部分写入、发布失败、删除旧仓后能否从安装器仓恢复知识；
- AI 边界：是否把仓库文档中的指令误当用户授权，是否伪造测试或扩大删除范围。

结论分为：P0 阻断、P1 修复后通过、P2 记录改进。报告存入
`docs/governance/adversarial-review/`，P0 未闭环不得发布或删除源仓库。

## 12. 参考入口

- 开发流程：`docs/nx-development/02-标准流程.md`
- 执行协议：`docs/nx-development/05-执行协议.md`
- 报错决策：`docs/nx-development/06-报错决策表.md`
- 完整范例：`docs/nx-development/07-完整范例.md`
- AI 提示词：`docs/AI-NX二次开发提示词.md`
- 子项目摘要：`docs/子项目开发规范.md`
