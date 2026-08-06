#!/usr/bin/env bash
# ============================================================
#  assemble.sh — 从 plugins.json 列出的子项目仓库收集部署资源
#  运行环境: mcr.microsoft.com/dotnet/sdk:9.0 容器 (git/curl/jq 可用)
#  依赖环境变量: PAT (克隆私有子仓库用的 token)
#  产物: 重建 DeployResources/application/ (扁平放置各插件的部署文件)
#
#  通用打包规则:
#   - 子项目根目录若有 ikun-deploy.txt, 按其中每行一个 glob 收集(可含注释#)
#   - 否则默认收集 *.dll *.dlx *.dat
#   - 文件一律扁平复制到 application/ (与安装器 ExtractResources 的扁平模型一致)
# ============================================================
set -euo pipefail

HOST="${GITEA_HOST:-gt.h.zss.fan:2233}"
OWNER="${GITEA_OWNER:-zhaoshen}"
APP_DIR="DeployResources/application"
: "${PAT:?需要 PAT 环境变量(克隆子仓库)}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== 重建 $APP_DIR =="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

total=0
while IFS='|' read -r repo ref; do
  [ -z "$repo" ] && continue
  ref="${ref:-master}"
  echo "== 收集 $repo @ $ref =="
  dest="$WORK/$repo"
  # dll/dlx/dat 都是普通 git 对象(非 LFS); 跳过 LFS 平滑, 避免容器无 git-lfs 报错
  GIT_LFS_SKIP_SMUDGE=1 git clone --quiet --depth 1 --branch "$ref" \
    "https://${PAT}@${HOST}/${OWNER}/${repo}.git" "$dest"

  globs=()
  if [ -f "$dest/ikun-deploy.txt" ]; then
    while IFS= read -r g; do
      g="${g%%#*}"
      g="$(echo -n "$g" | tr -d '[:space:]')"
      # 安全: 拒绝含 / 的 glob(路径穿越/绝对路径), 只允许文件名模式 (security_review HIGH)
      case "$g" in
        */*) echo "  跳过不安全 glob: $g (禁止含 /)"; continue ;;
      esac
      [ -n "$g" ] && globs+=("$g")
    done < "$dest/ikun-deploy.txt"
    echo "  部署清单(ikun-deploy.txt): ${globs[*]:-<空>}"
  fi
  [ ${#globs[@]} -eq 0 ] && globs=("*.dll" "*.dlx" "*.dat")

  n=0
  shopt -s nullglob
  for g in "${globs[@]}"; do
    for f in "$dest"/$g; do
      if [ -f "$f" ]; then
        cp -f "$f" "$APP_DIR/"
        echo "  + $(basename "$f")"
        n=$((n + 1)); total=$((total + 1))
      fi
    done
  done
  shopt -u nullglob
  [ "$n" -eq 0 ] && echo "  !! 警告: $repo 未匹配到任何部署文件"
done < <(jq -r '.plugins[] | "\(.repo)|\(.ref // "master")"' plugins.json)

echo "== 收集完成, 共 $total 个文件 =="
ls -la "$APP_DIR"
[ "$total" -eq 0 ] && { echo "错误: 未收集到任何资源, 中止"; exit 1; }
exit 0
