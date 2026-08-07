#!/usr/bin/env bash
# ============================================================
#  publish-release.sh — 创建/更新 Gitea Release, 只上传 ikun_installer.exe
#  用法: publish-release.sh <exe路径>
#  依赖环境变量: PAT; 可选: GITEA_HOST/OWNER/REPO, RELEASE_TAG, BUILD_TIME
#  策略: 滚动 tag(默认 latest), 每次删旧 release+标签后在【当前最新提交】重建,
#        使标签始终指向最新提交(页面不再停在旧提交); 版本号随 run_number 递增。
# ============================================================
set -euo pipefail

EXE="${1:?用法: publish-release.sh <exe路径>}"
HOST="${GITEA_HOST:-gt.h.zss.fan:2233}"
OWNER="${GITEA_OWNER:-zhaoshen}"
REPO="${GITEA_REPO:-ikun_installer}"
TAG="${RELEASE_TAG:-latest}"
NAME="ikun_installer.exe"
: "${PAT:?需要 PAT}"
BUILD_TIME="${BUILD_TIME:-auto}"
VERSION="${VERSION:-0.0.0}"
PLUGIN_COUNT="${PLUGIN_COUNT:-?}"
API="https://${HOST}/api/v1/repos/${OWNER}/${REPO}"
AUTH="Authorization: token ${PAT}"

[ -f "$EXE" ] || { echo "错误: 找不到 $EXE"; exit 1; }

title="爱坤工具箱 v${VERSION}"

# 读取子项目更新说明 (assemble.sh 生成); 缺失/为空时回退提示语
CHANGES_FILE="$(dirname "$0")/_plugin_changes.md"
if [ -f "$CHANGES_FILE" ] && [ -s "$CHANGES_FILE" ]; then
  PLUGIN_CHANGES=$(cat "$CHANGES_FILE")
else
  PLUGIN_CHANGES="（本次无子项目变更详情）"
fi

body="$(cat <<EOF
爱坤工具箱 NX 安装器 v${VERSION}

- 自动构建于 ${BUILD_TIME}
- 包含 ${PLUGIN_COUNT} 个插件, 从各子项目最新提交打包
- 下载 ikun_installer.exe 运行即可 (自包含单文件, 无需 .NET)

## 子项目更新内容

${PLUGIN_CHANGES}
EOF
)"

# 让 latest 标签跟到最新提交: 删旧 release + 旧标签, 再在当前提交处重建 release
SHA="$(git rev-parse HEAD 2>/dev/null || true)"
old=$(curl -sS -H "$AUTH" "${API}/releases/tags/${TAG}" | jq -r '.id // empty')
if [ -n "$old" ]; then
  echo "删除旧 release id=${old} (标签将重指向 ${SHA:0:8})"
  curl -sS -X DELETE -H "$AUTH" "${API}/releases/${old}" >/dev/null
fi
# 删可能残留的旧标签(删 release 未必删除 git tag; 不先删则新建 release 会沿用旧 tag 的提交)
curl -sS -o /dev/null -X DELETE -H "$AUTH" "${API}/tags/${TAG}" || true
echo "创建 release ${TAG} @ ${SHA:0:8} (${title})"
rid=$(curl -sS -X POST -H "$AUTH" -H "Content-Type: application/json" \
  -d "$(jq -n --arg t "$TAG" --arg c "$SHA" --arg n "$title" --arg b "$body" \
        '{tag_name:$t, target_commitish:$c, name:$n, body:$b}')" \
  "${API}/releases" | jq -r '.id // empty')

[ -z "$rid" ] && { echo "错误: 无法创建 release"; exit 1; }

echo "上传 ${NAME} ($(du -h "$EXE" | cut -f1))"
url=$(curl -sS -X POST -H "$AUTH" \
  -F "attachment=@${EXE};filename=${NAME}" \
  "${API}/releases/${rid}/assets?name=${NAME}" | jq -r '.browser_download_url // empty')
[ -z "$url" ] && { echo "错误: 附件上传失败"; exit 1; }
echo "完成: ${url}"
