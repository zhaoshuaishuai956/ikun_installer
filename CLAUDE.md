# Gitea Workflow — AI Agent 系统指令

本文件是通用 Markdown 格式的可执行系统指令，适用于所有主流 AI 编程助手。不含占位符，每个指令须被无条件执行。

---

## 0. Agent Compatibility

本文件同时提供 `CLAUDE.md` 和 `AGENTS.md` 两个版本，内容完全相同。
- **CLAUDE.md** — Claude Code 原生加载
- **AGENTS.md** — 30+ AI 工具的跨平台标准（Linux Foundation / Agentic AI Foundation 管理），包括 Cline、Copilot、Windsurf、Gemini CLI、Devin、Aider、Zed、OpenAI Codex 等

任选其一，或按需重命名为以下文件名：

| AI 工具 | 指令文件名 | 加载方式 |
|---------|-----------|----------|
| **AGENTS.md (跨平台标准)** | `AGENTS.md` | 项目根目录，30+ 工具自动加载 |
| **Claude Code** | `CLAUDE.md` | 项目根目录，自动加载。也可 `@AGENTS.md` 引入 |
| **Cursor** | `.cursorrules` | 项目根目录；或 `.cursor/rules/*.mdc`（推荐） |
| **GitHub Copilot** | `.github/copilot-instructions.md` | 项目 `.github/` 目录；也回退读取 `AGENTS.md` |
| **Aider** | `CONVENTIONS.md` | 项目根目录，`aider --conventions` 参数 |
| **Cline** (VS Code) | `.clinerules` | 项目根目录；也原生读取 `.cursorrules`、`AGENTS.md` |
| **Windsurf** | `AGENTS.md` 或 `.windsurfrules` | `AGENTS.md` 目录级自动作用域；`.windsurf/rules/*.md`（推荐） |

```bash
# 从本仓库复制到你的项目
cp AGENTS.md ~/your-project/AGENTS.md                  # 跨平台标准（推荐）
cp CLAUDE.md ~/your-project/CLAUDE.md                  # Claude Code
cp AGENTS.md ~/your-project/.cursorrules                # Cursor
cp AGENTS.md ~/your-project/.github/copilot-instructions.md  # GitHub Copilot
```

### Agent 身份自动检测

在执行 commit 时，按以下优先级确定 `Co-Authored-By` 签名：

1. 环境变量 `GITEA_COAUTHOR` 已设置 → 直接使用
2. `$CLAUDE_CODE_SESSION_ID` 存在 → `Claude Code <noreply@anthropic.com>`
3. `.cursorrules` 或 `.cursor/` 目录存在 → `Cursor AI <noreply@cursor.com>`
4. `.github/copilot-instructions.md` 存在 → `GitHub Copilot <noreply@github.com>`
5. `.clinerules` 存在 → `Cline AI <noreply@cline.bot>`
6. `.windsurfrules` 存在 → `Windsurf AI <noreply@windsurf.com>`
7. 均不匹配 → `AI Assistant <assistant@ai.tool>`

用户可通过 `export GITEA_COAUTHOR="My Tool <tool@example.com>"` 覆盖。

### 设备名检测

提交时自动获取设备名，写入 `Device:` trailer：

```bash
# Linux / macOS / Git Bash
hostname

# PowerShell / Windows
$env:COMPUTERNAME
```

若无法获取，默认为 `unknown-device`。用户可通过 `export GITEA_DEVICE="my-machine"` 手动设置。

---

## 1. Configuration

从以下来源读取 Gitea 凭证（优先级从高到低）：
1. 环境变量：`GITEA_HOST`、`GITEA_TOKEN`、`GITEA_USER`
2. Agent 持久化存储（Claude Code: memory 系统；Cursor: Cursor Settings；Copilot: VS Code settings；其他: 环境变量或 `.env`）
3. 项目 `.env` 文件（如存在且不在 git 追踪中）

`GITEA_HOST` 格式约定：
- API 调用用完整 URL：`https://git.example.com`（含协议）
- Git remote URL 只用 host:port：`git.example.com`（不含协议）
- 若 `GITEA_HOST` 含协议前缀，构造 git URL 时须剥离。

### Bootstrap：当 GITEA_TOKEN 未设置

执行以下检测序列：
```bash
echo $GITEA_TOKEN
```
- 若为空：**停止**。提示用户提供 Gitea 访问令牌，告知生成路径：`https://${GITEA_HOST}/user/settings/applications`
- 将用户提供的 Token 存入当前 Agent 的持久化存储（不要写入任何文件）。若 Agent 无持久化存储能力，引导用户设置环境变量。
- 验证 Token 有效性后继续

### Token 验证（每次会话开始时执行一次）

```bash
curl -sS -o /dev/null -w "%{http_code}" \
  "https://${GITEA_HOST}/api/v1/user" \
  -H "Authorization: token ${GITEA_TOKEN}"
```
- 200 → 有效，继续
- 401 → Token 过期/无效，提示用户重新生成
- 其他 → 检查网络和 `GITEA_HOST`

---

## 2. 项目检测

每个项目开始时：
```bash
git remote -v
```
- 无 remote → 执行「新项目」流程
- 有 remote 且指向 Gitea → 执行「已有项目」流程
- 有 remote 但指向其他平台 → 询问用户是否迁移

---

## 3. 新项目：创建远程仓库

### 3.1 前置检查
```bash
# 1. 是否已是 git 仓库？
git status 2>&1
# 若非仓库 → git init

# 2. Token 是否有效？（见 Section 1）

# 3. 仓库是否已存在？
curl -sS -o /dev/null -w "%{http_code}" \
  "https://${GITEA_HOST}/api/v1/repos/${GITEA_USER}/${REPO_NAME}" \
  -H "Authorization: token ${GITEA_TOKEN}"
# 404 → 不存在，可以创建
# 200 → 已存在，直接设置 remote 即可
```

### 3.2 创建仓库
```bash
curl -sS -X POST "https://${GITEA_HOST}/api/v1/user/repos" \
  -H "Authorization: token ${GITEA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"<repo>","description":"<desc>","private":true,"has_issues":true,"has_wiki":false,"has_projects":true,"has_pull_requests":true,"default_branch":"master"}'

# 验证：检查返回的 HTTP 状态码必须为 201
```

### 3.3 创建 .gitignore
在 `git add` 之前，确保 `.gitignore` 存在并覆盖：
- 构建产物：`*.pyc`、`__pycache__/`、`node_modules/`、`dist/`、`*.bin`
- IDE：`.vscode/`、`.idea/`
- 密钥：`.env`、`*.token`、`secrets/`
- OS：`.DS_Store`、`Thumbs.db`

若 `.gitignore` 不存在，必须**先创建它**再继续。

### 3.4 初始化 Git LFS（大文件项目）

如果项目包含以下类型的大文件（>1MB），必须初始化 Git LFS：
- 二进制文件：`*.dll`、`*.so`、`*.exe`、`*.bin`、`*.wasm`
- 模型文件：`*.pt`、`*.onnx`、`*.pth`、`*.h5`、`*.safetensors`
- 媒体文件：`*.png`、`*.jpg`、`*.mp3`、`*.mp4`、`*.wav`、`*.glb`
- 数据集：`*.csv`、`*.jsonl`、`*.parquet`（单文件 >1MB）
- 固件：`*.hex`、`*.elf`、`*.uf2`
- 设计文件：`*.psd`、`*.blend`、`*.fcstd`

```bash
# 初始化 LFS
git lfs install

# 按项目需求追踪文件类型
git lfs track "*.bin" "*.pt" "*.onnx" "*.wasm" "*.glb" "*.png"

# .gitattributes 会被自动创建/更新，须提交
git add .gitattributes
git commit -m "chore(lfs): configure Git LFS tracking"
```

**注意**：Gitea 实例必须启用 Git LFS（默认启用）。若服务器不支持，将大文件排除在 `.gitignore` 中。

### 3.5 设置 Remote 并推送
```bash
# GITEA_HOST_NO_PROTO = GITEA_HOST 去掉 https:// 前缀
git remote add origin "https://${GITEA_USER}:${GITEA_TOKEN}@${GITEA_HOST_NO_PROTO}/${GITEA_USER}/${REPO_NAME}.git"
git push -u origin $(git symbolic-ref --short HEAD)

# 验证推送成功
git ls-remote --heads origin | grep $(git branch --show-current)
# 必须返回包含当前分支名的一行
```

---

## 4. 提交规范

### 4.1 何时提交

**必须提交**（满足任一条件）：
- 完成了一个完整的功能或模块
- 修复了一个 bug
- 用户明确要求提交
- 跨越了一个逻辑里程碑

**不要提交**：
- 代码无法编译/运行
- 单行 typo 修复（累积 ≥3 个或伴随其他变更时一起提交）
- 临时调试代码

### 4.2 提交前安全检查（MANDATORY）

**以下 5 项全部通过才能 `git commit`，任一项失败则中止：**

```
[ ] .gitignore 存在且覆盖了 .env、构建产物、IDE 目录
[ ] git diff --cached 不包含 TOKEN、KEY、SECRET、PASSWORD（大小写不敏感）
[ ] git diff --cached 不包含 API 密钥或 Access Token 字面值
[ ] Commit 消息符合 format（见 4.3），含 Agent: 和 Device: trailers
[ ] 未使用 --no-verify、--no-gpg-sign、--force 标志
```

检查命令：
```bash
git diff --cached | grep -qi 'token\|key\|secret\|password\|ghp_\|glpat-' && echo "FAIL: secrets detected" || echo "PASS"
```

### 4.3 Commit 格式

```
<type>(<scope>): <简短描述>

<详细说明 — 每行 ≤ 100 字符，多段落以空行分隔>

Co-Authored-By: <按 Section 0 的检测逻辑确定>
Agent: <按 Section 0 的检测逻辑确定>
Device: <设备主机名>
```

**规则**：
- 简短描述 ≤ 72 字符，英文小写
- 描述与正文之间空一行
- `Co-Authored-By`、`Agent`、`Device` 作为 git trailers 放在最后
- 签名按 Section 0 "Agent 身份自动检测" 确定
- 设备名自动检测：`hostname`（Linux/macOS）或 `$env:COMPUTERNAME`（Windows）或 `hostname` 命令

### 4.4 Type 速查（5 类）

| Type | 用途 | semver 影响 |
|------|------|------------|
| `feat` | 新功能 | MINOR |
| `fix` | Bug 修复 | PATCH |
| `refactor` | 重构（无功能变更） | PATCH |
| `docs` | 文档变更 | — |
| `chore` | 构建、依赖、工具、样式、测试、CI | — |

若变更本质是 `chore` 但想更具体，可用 `test`、`ci`、`style`。不确定时用 `chore`。

### 4.5 Scope

按模块/层级命名，不用文件名：
- `feat(clock): add battery display`
- `fix(api): correct JSON field casing`
- `refactor(ui): extract drawProgressBar`

多文件跨模块时可省略 scope。

### 4.6 跨平台 Commit 语法

所有平台均可用 `-m "subject" -m "body"` 形式：

Bash：
```bash
git commit -m "feat(auth): add login" -m "Implement session-based auth."
```

PowerShell：
```powershell
git commit -m "feat(auth): add login" -m "Implement session-based auth."
```

---

## 5. 推送与验证

### 5.1 推送
每次 commit 后立即推送：
```bash
git push
```

### 5.2 推送后验证
```bash
# 确认远程已收到最新 commit
git log --oneline -3
git ls-remote --heads origin | grep $(git branch --show-current)
```

---

## 6. 错误恢复决策树

```
PUSH FAILED
├── "fatal: Authentication failed" / HTTP 401
│   → Token 无效或过期
│   → curl -sS "https://${GITEA_HOST}/api/v1/user" -H "Authorization: token ${GITEA_TOKEN}"
│   → 若 401：提示用户到 ${GITEA_HOST}/user/settings/applications 重新生成
│   → 不要用相同凭证重试
│
├── "remote: Not Found" / HTTP 404
│   → 仓库不存在（可能被删除或改名）
│   → 执行 Section 3.2 重建仓库
│   → git remote set-url origin <新 URL> && git push
│
├── "non-fast-forward" / "fetch first"
│   → git pull --rebase
│   → 有冲突？→ 列出冲突文件，让用户手动解决
│   → 无冲突？→ git push
│
├── "Connection timed out" / "Could not resolve host"
│   → curl -sS --max-time 10 "https://${GITEA_HOST}/api/v1/version"
│   → 若超时：检查 VPN、防火墙；等待 5s 重试
│   → 3 次重试后仍失败 → 报告用户，附诊断信息
│
├── "RPC failed; HTTP 413" / "larger than allowed"
│   → 文件超过 Gitea 允许大小
│   → 确认文件类型是否适合 Git LFS（见 Section 3.4）
│   → 适合 LFS：git lfs install && git lfs track "<pattern>" && git add .gitattributes
│   → 不适合 LFS（代码文件异常大）：检查是否误提交了构建产物或数据集
│   → git config http.postBuffer 524288000 && git push（临时方案）
│   → 仍失败 → 建议将大文件拆分或使用 Git LFS 重做
│
└── "SSL certificate problem"
   → 自签名证书
   → 临时：git -c http.sslVerify=false push（不安全，仅测试用）
   → 永久：安装 Let's Encrypt 证书或添加自签名证书到信任链
```

---

## 7. 分支策略

- **默认**：直接在 `master`/`main` 上工作
- **较大功能**（预计 ≥3 commits）：`git checkout -b feat/<name>`
- **完成合并**：
  ```bash
  git checkout master
  git merge feat/<name>
  git push
  git branch -d feat/<name>
  git push origin --delete feat/<name>
  ```
- **切换分支前**：确保 `git status --porcelain` 为空（无未提交变更）

---

## 8. 安全红线

违反以下任一条即为**硬错误**，必须中止操作：

| 禁止行为 | 后果 |
|----------|------|
| 将 GITEA_TOKEN 写入任何文件 | Token 泄露到 git 历史 |
| `git push --force` 未经用户明确批准 | 覆盖远程提交，数据丢失 |
| `git add -A` 未先验证 .gitignore | 可能暂存密钥文件 |
| `git commit --no-verify` 跳过检查 | 绕过 pre-commit hooks |
| 自动解决 merge 冲突 | 可能引入逻辑错误 |
| 提交 `.env`、`.token`、`credentials.*` 文件 | 凭证泄露 |

---

## 9. Issue / PR 操作

```bash
# 创建 Issue
curl -sS -X POST "https://${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues" \
  -H "Authorization: token ${GITEA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"title":"<title>","body":"<markdown body>"}'

# 创建 PR
curl -sS -X POST "https://${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls" \
  -H "Authorization: token ${GITEA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"title":"<title>","body":"<body>","head":"<source_branch>","base":"<target_branch>"}'
```

---

## 10. 通用开发规范

除了 Gitea 工作流，本指令文件要求遵循 AI Agent 通用开发规范。
完整规范见 `docs/dev-standards.md`，以下为强制要点：

### 10.1 项目结构与命名
- 根目录整洁：README.md、src/、docs/、tests/、scripts/ + 语言入口文件
- 最深层目录 ≤4；按领域分包（`src/auth/`），不按类型分包（`src/models/`）
- 禁止 `utils/`、`helpers/`、`common/` 万能文件 — 按职责命名
- 文件名揭示职责，不揭示类型；无空格；≤40 字符；单文件 ≤500 行
- 文件命名遵循语言惯例：Python `snake_case`，JS `camelCase`，React `PascalCase`，配置 `kebab-case`
- 禁止 `new_`/`old_`/`temp_`/`backup_` 前缀；禁止大小写变体共存；禁止纯编号命名

### 10.2 项目骨架
- 任何新项目必须创建：README.md（What/Why/Run/Test）、.gitignore（密钥+构建产物+IDE+OS）、LICENSE
- 必须提供 `.env.example`（不含真实值）

### 10.3 代码质量
- Public API 必须有 docstring（contract：输入/输出/副作用）
- 复杂逻辑（>10 行）前必须有 WHY 注释
- Magic number → 命名常量
- 代码交付前执行：Lint → 类型检查 → 修复 → 再检查 → 通过后交付

### 10.4 错误处理
- 禁止空 catch 块、禁止只 log 不处理
- 每个 error path：处理 | 传播+上下文 | 显式注释忽略原因
- 异步操作必须有超时（网络 ≤30s，计算 ≤5min）
- 禁止向用户暴露 stack trace

### 10.5 配置
- 禁止硬编码 URL/端口/密钥/路径 → 用环境变量
- 配置优先级：CLI > 环境变量 > 配置文件 > 默认值
- 禁止同一配置在多个来源重复定义

### 10.6 依赖
- Lock 文件必须提交到 git
- 能 stdlib 实现的不用第三方库
- 不引入 >1 年无维护的包
- 不因为单个函数引入巨型库
- 大文件（>1MB 的二进制/模型/媒体/数据集）用 Git LFS 管理，不直接提交

### 10.7 测试
- 至少一个 smoke test 验证核心流程
- Bug fix 必须包含 regression test（先写复现测试）
- 测试命令写入 README，可一键运行

### 10.8 安全
- 所有外部输入校验（类型/范围/长度）
- 禁止 eval/exec/Function() 处理用户输入
- SQL 必须参数化查询（禁止字符串拼接）
- 日志不记录密码/Token/身份证号/信用卡号
- 不信任客户端传来的 user_id/role/is_admin

### 10.9 遵守优先级
1. 项目已有规范（`.eslintrc`、`pyproject.toml`、现有代码风格）— 最高优先
2. `docs/dev-standards.md` 详细规则
3. 本 Section 的强制要点
4. 语言社区惯例（PEP 8、StandardJS、Effective Go 等）

---

## 11. 参考文档

本文件是权威行为规则。详细文档按规范 §2.2 分层存放于各权威源：
- L3 整体规范（最高优先）：`ikun_dev_standard` 仓库 `ikun-整体开发规范-v1.0.md`
- L1 工作流：`gitea-for-ai` 仓库 `docs/`（dev-standards.md / commit-guide.md / api-cheatsheet.md / troubleshooting.md / setup.md）
- L2 知识库：`nx_dev_skill`（私有权威）/ `nx_dev_handbook`（公开镜像）

