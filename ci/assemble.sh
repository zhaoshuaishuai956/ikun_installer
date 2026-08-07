#!/usr/bin/env bash
# ============================================================
#  assemble.sh — 从 plugins.json 列出的子项目仓库收集部署资源
#  运行环境: mcr.microsoft.com/dotnet/sdk:9.0 容器 (git/curl/jq 可用)
#  依赖环境变量: PAT (克隆私有子仓库用的 token)
#  产物: 重建 DeployResources/application/ (扁平放置各插件的部署文件)
#        + 生成 ci/_plugin_changes.md (各子项目 CHANGELOG.md 最新版本摘要,
#          供 publish-release.sh 写入 Release 发布说明)
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
# 子项目变更摘要输出(相对本脚本定位, 与 publish-release.sh 共用)
CHANGES_FILE="$(dirname "$0")/_plugin_changes.md"

# 净化外部输入摘要: 剥 markdown 链接/图片/HTML/裸 URL(含 www.), 只留纯文本
# (security_review MEDIUM: CHANGELOG 与 commit 标题均属子仓库外部输入, 会进公开 Release 正文)
sanitize_summary() {
  awk '{
    s = $0
    while (match(s, /!?\[[^]]*\]\([^)]*\)/)) {
      t = substr(s, RSTART, RLENGTH)
      b = index(t, "[")
      inner = substr(t, b + 1, index(t, "](") - b - 1)
      s = substr(s, 1, RSTART - 1) inner substr(s, RSTART + RLENGTH)
    }
    gsub(/[Hh][Tt][Tt][Pp][Ss]?:\/\/[^[:space:])]+|[Ff][Tt][Pp]:\/\/[^[:space:])]+|[Ww][Ww][Ww]\.[^[:space:])]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, "", s)
    gsub(/<[^>]*>/, "", s)
    sub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    print s
  }'
}

: "${PAT:?需要 PAT 环境变量(克隆子仓库)}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== 重建 $APP_DIR =="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
: > "$CHANGES_FILE"   # 清空子项目变更摘要

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
      if [ -f "$f" ] && [ ! -L "$f" ]; then   # 拒绝 symlink: 防 evil.dll -> /proc/1/environ (security_review)
        cp -f "$f" "$APP_DIR/"
        echo "  + $(basename "$f")"
        n=$((n + 1)); total=$((total + 1))
      fi
    done
  done
  shopt -u nullglob
  [ "$n" -eq 0 ] && echo "  !! 警告: $repo 未匹配到任何部署文件"

  # ---- 记录子项目更新说明 (供 Release 发布正文使用) ----
  # 优先取 CHANGELOG.md 最新版本段的标题+首条变更; 缺失时回退最新 commit 标题
  if [ -f "$dest/CHANGELOG.md" ]; then
    chg_ver=; chg_summary=   # 先初始化: read EOF 零数据时不赋值, set -u 下避免 unbound 中止 (security_review)
    read -r chg_ver chg_summary < <(awk '
      /^##[[:space:]]*v?[0-9]/ {
        if (inblock) exit
        inblock = 1
        v = $0
        sub(/^##[[:space:]]*v?/, "", v)
        sub(/[[:space:]].*$/, "", v)
        next
      }
      inblock && /^[[:space:]]*-/ {
        s = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", s)
        sub(/^\*\*/, "", s)
        sub(/\*\*/, "", s)
        sub(/[[:space:]]+$/, "", s)
        print v, s
        exit
      }
    ' "$dest/CHANGELOG.md" 2>/dev/null) || true
    # 版本号严格三段式校验, 防畸形版本行携带 markdown 注入 (security_review)
    if [[ "$chg_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      chg_summary=$(printf '%s\n' "${chg_summary:-更新}" | sanitize_summary)
      echo "- **${repo}** (${chg_ver}): ${chg_summary}" >> "$CHANGES_FILE"
    else
      echo "- **${repo}**: 无 CHANGELOG 版本记录" >> "$CHANGES_FILE"
    fi
  else
    cmsg=$(git -C "$dest" log -1 --pretty='%s' 2>/dev/null || true)
    cmsg=$(printf '%s\n' "${cmsg:-更新}" | sanitize_summary)
    echo "- **${repo}**: ${cmsg}" >> "$CHANGES_FILE"
  fi
done < <(jq -r '.plugins[] | "\(.repo)|\(.ref // "master")"' plugins.json)

echo "== 收集完成, 共 $total 个文件 =="
ls -la "$APP_DIR"
[ "$total" -eq 0 ] && { echo "错误: 未收集到任何资源, 中止"; exit 1; }
exit 0
