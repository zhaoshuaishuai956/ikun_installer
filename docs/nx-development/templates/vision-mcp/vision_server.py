#!/usr/bin/env python3
"""
视觉 MCP 服务器 —— 给没有原生视觉的文本 agent 装一只“眼睛”。

有些 agent 的大脑是纯文本模型、看不了图（如 reasonix 里的 DeepSeek）。绕过办法：
把“看图”做成一个标准 MCP 工具 analyze_image。agent 判断需要看图时调用它 → 本服务器
读图、base64、调 GLM-4V-Flash → 把图片描述【文字】返回给 agent 继续推理。图片只经过
本进程、不进 agent 的模型管线。自带视觉的 agent（Claude Code / Cursor 等）无需本服务器。

接入（任意支持 MCP 的 agent；下例为 reasonix，Claude Code 等其它 agent 见 README.md）：
    [[plugins]]
    name    = "vision"
    command = "python"                        # Windows 上也可用 "py"
    args    = ["<本文件的绝对路径>"]
    env     = { ZHIPU_API_KEY = "${ZHIPU_API_KEY}" }
    trusted_read_only_tools = ["analyze_image"]

依赖：Python 3.10+，`pip install mcp`（仅此一个第三方库；HTTP 用标准库）。
环境变量：ZHIPU_API_KEY（必需）；可选 VISION_MODEL(默认 glm-4v-flash)、
         VISION_BASE_URL(默认智谱 v4)、VISION_BACKEND(默认 zhipu)。
"""
import base64
import json
import mimetypes
import os
import urllib.request
import urllib.error

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("vision")

BACKEND  = os.environ.get("VISION_BACKEND", "zhipu")
MODEL    = os.environ.get("VISION_MODEL", "glm-4v-flash")
BASE_URL = os.environ.get("VISION_BASE_URL", "https://open.bigmodel.cn/api/paas/v4")
API_KEY  = os.environ.get("ZHIPU_API_KEY", "")
TIMEOUT  = int(os.environ.get("VISION_TIMEOUT", "60"))


def _image_to_ref(path: str) -> str:
    """本地图片 → API 可接受的引用。
    智谱官方示例的 image_url.url 用【裸 base64】(无 data: 前缀)；
    其它 OpenAI 兼容后端普遍用 data URI —— 按 BACKEND 区分。"""
    with open(path, "rb") as f:
        raw = f.read()
    b64 = base64.b64encode(raw).decode("ascii")
    if BACKEND == "zhipu":
        return b64
    mime = mimetypes.guess_type(path)[0] or "image/png"
    return f"data:{mime};base64,{b64}"


@mcp.tool()
def analyze_image(image_path: str, question: str = "请详细、客观地描述这张图片的内容") -> str:
    """看一张图片并用文字回答关于它的问题（GLM-4V-Flash 视觉后端）。

    Args:
        image_path: 图片的本地绝对路径，或以 http(s):// 开头的图片 URL。
        question:   想让模型回答的问题；默认给出整体描述。适合让 agent 在需要
                    “看截图/看图纸/看报错弹窗”时调用，拿回文字结论再继续推理。
    """
    if not API_KEY:
        return "错误：未设置 ZHIPU_API_KEY。请在 agent 的环境变量/密钥配置里设 ZHIPU_API_KEY=你的智谱密钥。"

    # 本地路径 → data URI；http(s) URL 直接传给模型
    if image_path.startswith(("http://", "https://")):
        image_ref = image_path
    else:
        if not os.path.isfile(image_path):
            return f"错误：找不到图片文件：{image_path}（请用绝对路径）。"
        try:
            image_ref = _image_to_ref(image_path)
        except Exception as e:  # noqa: BLE001
            return f"错误：读取/编码图片失败：{e}"

    payload = {
        "model": MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": image_ref}},
                {"type": "text", "text": question},
            ],
        }],
    }
    req = urllib.request.Request(
        url=f"{BASE_URL.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"]
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        return f"错误：视觉后端({BACKEND}/{MODEL})返回 HTTP {e.code}：{body[:500]}"
    except (urllib.error.URLError, TimeoutError) as e:
        return f"错误：调用视觉后端网络失败：{e}"
    except (KeyError, IndexError, ValueError) as e:
        return f"错误：解析视觉后端返回失败：{e}"


if __name__ == "__main__":
    mcp.run()  # 默认 stdio 传输，与各家 agent 的本地 stdio MCP 约定一致
