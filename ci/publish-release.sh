#!/usr/bin/env bash
# ============================================================
#  publish-release.sh — 创建/更新 Gitea Release, 只上传 ikun_installer.exe
#  用法: publish-release.sh <exe路径>
#  依赖环境变量: PAT; 可选: GITEA_HOST/OWNER/REPO, RELEASE_TAG, BUILD_TIME
#  策略: 固定 tag(默认 latest), 已存在则更新说明并替换同名附件
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
API="https://${HOST}/api/v1/repos/${OWNER}/${REPO}"
AUTH="Authorization: token ${PAT}"

[ -f "$EXE" ] || { echo "错误: 找不到 $EXE"; exit 1; }

body="爱坤工具箱 NX 安装器 — 自动构建于 ${BUILD_TIME}。从各插件子项目最新提交自动打包, 下载 ikun_installer.exe 运行即可。"

rid=$(curl -sS -H "$AUTH" "${API}/releases/tags/${TAG}" | jq -r '.id // empty')
if [ -z "$rid" ]; then
  echo "创建 release ${TAG}"
  rid=$(curl -sS -X POST -H "$AUTH" -H "Content-Type: application/json" \
    -d "$(jq -n --arg t "$TAG" --arg b "$body" '{tag_name:$t, name:"爱坤工具箱 (最新自动构建)", body:$b}')" \
    "${API}/releases" | jq -r '.id // empty')
else
  echo "更新 release ${TAG} (id=${rid})"
  curl -sS -X PATCH -H "$AUTH" -H "Content-Type: application/json" \
    -d "$(jq -n --arg b "$body" '{name:"爱坤工具箱 (最新自动构建)", body:$b}')" \
    "${API}/releases/${rid}" >/dev/null
  aid=$(curl -sS -H "$AUTH" "${API}/releases/${rid}/assets" | jq -r ".[] | select(.name==\"${NAME}\") | .id")
  if [ -n "$aid" ]; then
    echo "删除旧附件 id=${aid}"
    curl -sS -X DELETE -H "$AUTH" "${API}/releases/${rid}/assets/${aid}" >/dev/null
  fi
fi

[ -z "$rid" ] && { echo "错误: 无法获取 release id"; exit 1; }

echo "上传 ${NAME} ($(du -h "$EXE" | cut -f1))"
url=$(curl -sS -X POST -H "$AUTH" \
  -F "attachment=@${EXE};filename=${NAME}" \
  "${API}/releases/${rid}/assets?name=${NAME}" | jq -r '.browser_download_url // empty')
[ -z "$url" ] && { echo "错误: 附件上传失败"; exit 1; }
echo "完成: ${url}"
