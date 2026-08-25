# 视觉 MCP 服务器（给没有原生视觉的 agent 外挂"眼睛"）

给**纯文本、看不了图的 agent**（如 reasonix 里的 DeepSeek）装一只"眼睛"：agent 需要看图时调用 `analyze_image` 工具，本服务器用**智谱 GLM-4V-Flash（免费）**看图并返回文字结论。

> **自带视觉的 agent（Claude Code、Cursor 等绝大多数）不需要本服务器**——需要看图时直接把截图贴/拖给它即可。本服务器只为给纯文本模型补上看图能力而存在。

**原理**：不去改一个可能不存在的"默认视觉模型"开关，而是用几乎所有 agent 都支持的 **MCP** 外挂一个工具。图片只经过本进程，agent 只处理文字 + 工具调用——两者都是标准 MCP 能力。（这也正是 reasonix 这类不把图片喂给第三方视觉模型的 agent 的通用绕法，参见 [issue #3584](https://github.com/esengine/DeepSeek-Reasonix/issues/3584)。）换任何 OpenAI 兼容视觉后端，只改环境变量、`analyze_image` 接口不变。

## 安装

```powershell
# 需要 Python 3.10+
pip install -r requirements.txt      # 只装一个库：mcp
```

## 接到你的 agent（MCP 配置）

这是个标准 **stdio MCP 服务器**：命令 `python <vision_server.py 的绝对路径>`，靠环境变量 `ZHIPU_API_KEY` 拿密钥。按你 agent 的 MCP 配置方式接入即可。几个常见示例（把路径换成你克隆得到的真实绝对路径、用正斜杠）：

### Claude Code

```powershell
claude mcp add vision -e ZHIPU_API_KEY=你的智谱密钥 -- python C:/绝对路径/templates/vision-mcp/vision_server.py
```

或写进项目 `.mcp.json`：

```json
{
  "mcpServers": {
    "vision": {
      "command": "python",
      "args": ["C:/绝对路径/templates/vision-mcp/vision_server.py"],
      "env": { "ZHIPU_API_KEY": "你的智谱密钥" }
    }
  }
}
```

### reasonix（`%AppData%\reasonix\config.toml` 或项目 `reasonix.toml`）

```toml
[[plugins]]
name    = "vision"
command = "python"                                  # 若报找不到 python，改用 "py" 或 python 绝对路径
args    = ["C:/绝对路径/templates/vision-mcp/vision_server.py"]
env     = { ZHIPU_API_KEY = "${ZHIPU_API_KEY}" }    # 从 reasonix 全局 .env 展开，不写明文
trusted_read_only_tools = ["analyze_image"]
```

密钥放 reasonix 全局 `.env`（`%AppData%\reasonix\.env`）里：`ZHIPU_API_KEY=你的智谱密钥`。

### 其它 agent（Cursor / Cline / Windsurf …）

它们的 MCP 配置和上面 `.mcp.json` 的结构基本一致（`command` + `args` + `env`），照填即可；密钥统一放各自的环境变量/密钥配置里，别写进会提交进 git 的文件。

## 验证

重启 / 重载 agent，在其 **MCP / 工具面板**应看到 `vision` → `analyze_image`（对模型暴露为 `mcp__vision__analyze_image`）。
若没出现：确认上面那段配置无语法错；`python vision_server.py` 手动跑不报错（能启动就 Ctrl+C 退出）。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `ZHIPU_API_KEY` | （必需） | 智谱开放平台密钥；放 agent 的环境变量/密钥配置里 |
| `VISION_MODEL` | `glm-4v-flash` | 视觉模型 id |
| `VISION_BASE_URL` | `https://open.bigmodel.cn/api/paas/v4` | OpenAI 兼容接口地址 |
| `VISION_BACKEND` | `zhipu` | 预留，便于换后端 |

换别的 OpenAI 兼容视觉后端：改 `VISION_BASE_URL` / `VISION_MODEL` / 对应密钥即可，`analyze_image` 接口不变。
