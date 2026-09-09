#!/usr/bin/env bash
# ============================================================
#  publish-release.sh — 创建/更新 Gitea Release, 上传安装器和插件资源
#  用法: publish-release.sh <exe路径> <资源清单> <资源目录>
#  依赖环境变量: PAT; 可选: GITEA_HOST/OWNER/REPO, RELEASE_TAG, BUILD_TIME
#  策略: 滚动 tag(默认 latest), 每次删旧 release+标签后在【当前最新提交】重建,
#        使标签始终指向最新提交(页面不再停在旧提交); 版本号随 run_number 递增。
# ============================================================
set -euo pipefail

EXE="${1:?用法: publish-release.sh <exe路径>}"
MANIFEST="${2:?用法: publish-release.sh <exe路径> <资源清单> <资源目录>}"
RESOURCE_DIR="${3:?用法: publish-release.sh <exe路径> <资源清单> <资源目录>}"
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
[ -f "$MANIFEST" ] || { echo "错误: 找不到资源清单 $MANIFEST"; exit 1; }
[ -d "$RESOURCE_DIR" ] || { echo "错误: 找不到资源目录 $RESOURCE_DIR"; exit 1; }

title="爱坤工具箱 v${VERSION}"

# 读取子项目更新说明 (assemble.sh 生成); 缺失/为空时回退提示语
CHANGES_FILE="$(dirname "$0")/_plugin_changes.md"
REVISIONS_FILE="$(dirname "$0")/_plugin_revisions.json"
if [ -f "$CHANGES_FILE" ] && [ -s "$CHANGES_FILE" ]; then
  PLUGIN_CHANGES=$(cat "$CHANGES_FILE")
else
  PLUGIN_CHANGES="（本次无子项目变更详情）"
fi

# 版本清单是下一次构建计算增量的唯一可靠基线。缺失时拒绝发布，避免一次坏构建
# 让后续 Release 永久失去子插件变更范围。base64 后放入 HTML 注释，不干扰人类阅读。
if [ ! -f "$REVISIONS_FILE" ] ||
    ! jq -e '.schema == 1 and (.plugins | type == "object") and (.plugins | length > 0)' \
      "$REVISIONS_FILE" >/dev/null 2>&1; then
  echo "错误: 子项目版本清单缺失或无效，拒绝发布"
  exit 1
fi
REVISION_DATA=$(base64 < "$REVISIONS_FILE" | tr -d '\r\n')
REVISION_MARKER="<!-- ikun-plugin-revisions:${REVISION_DATA} -->"

# 安装器自身更新内容 (规范 M3 §6.5): 从本仓 CHANGELOG.md 最新段提取 (复用 release-notes.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-notes.sh
source "$SCRIPT_DIR/release-notes.sh"
INSTALLER_CHANGES=$(collect_current_changelog "$(pwd)" 2>/dev/null || true)
[ -z "$INSTALLER_CHANGES" ] && INSTALLER_CHANGES="（无安装器变更说明）"

# M10: 发布物完整性第二道校验 (规范 §9.3.6) — 更新器下载后与正文 sha256 比对
# sha256sum 缺失即失败 (红队批2 P2-4: 空哈希会让 M10 静默失效)
SHA256=$(sha256sum "$EXE" | cut -d' ' -f1)

body="$(cat <<EOF
爱坤工具箱 NX 安装器 v${VERSION}

- 自动构建于 ${BUILD_TIME}
- 包含 ${PLUGIN_COUNT} 个插件, 从各子项目最新提交打包
- 下载 ikun_installer.exe 运行即可 (自包含单文件, 无需 .NET)
- 插件资源清单: ${RESOURCE_MANIFEST_NAME:-ikun_resources.json}（支持逐项原子热更新）
- SHA256: ${SHA256}

## 安装器更新内容

${INSTALLER_CHANGES}

## 子项目更新内容

${PLUGIN_CHANGES}

${REVISION_MARKER}
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

upload_asset() {
  local file="$1" name="$2"
  echo "上传资源 ${name} ($(du -h "$file" | cut -f1))"
  curl -sS -X POST -H "$AUTH" -F "attachment=@${file};filename=${name}" \
    "${API}/releases/${rid}/assets?name=${name}" | jq -e '.browser_download_url != null' >/dev/null
}

upload_asset "$MANIFEST" "ikun_resources.json"
while IFS= read -r file; do
  [ -f "$file" ] || continue
  name="$(basename "$file")"
  [ "$name" = "ikun_resources.json" ] && continue
  upload_asset "$file" "$name"
done < <(find "$RESOURCE_DIR" -maxdepth 1 -type f -printf '%p\n' | sort)
