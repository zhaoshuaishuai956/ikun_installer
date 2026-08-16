#!/usr/bin/env bash
# ============================================================
#  assemble.sh — 从 plugins.json 列出的子项目仓库收集部署资源
#  运行环境: mcr.microsoft.com/dotnet/sdk:9.0 容器 (git/curl/jq 可用)
#  依赖环境变量: PAT (克隆私有子仓库用的 token)
#  产物: 重建 DeployResources/application/ (扁平放置各插件的部署文件)
#        + 生成 ci/_plugin_changes.md (相对上次 Release 的子项目增量摘要)
#        + 生成 ci/_plugin_revisions.json (本次实际打包的子项目提交基线)
#
#  通用打包规则:
#   - 子项目根目录若有 ikun-deploy.txt, 按其中每行一个 glob 收集(可含注释#)
#   - 否则默认收集 *.dll *.dlx *.dat
#   - 文件一律扁平复制到 application/ (与安装器 ExtractResources 的扁平模型一致)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-notes.sh
source "$SCRIPT_DIR/release-notes.sh"

HOST="${GITEA_HOST:-gt.h.zss.fan:2233}"
OWNER="${GITEA_OWNER:-zhaoshen}"
INSTALLER_REPO="${GITEA_REPO:-ikun_installer}"
RELEASE_TAG="${RELEASE_TAG:-latest}"
APP_DIR="DeployResources/application"
CHANGES_FILE="$SCRIPT_DIR/_plugin_changes.md"
REVISIONS_FILE="$SCRIPT_DIR/_plugin_revisions.json"
META_TSV="$SCRIPT_DIR/_plugin_meta.tsv"   # M4/M7b: 供 G5 校验与 gen-icons 消费 (pack.yml 步骤间 handoff)
API="https://${HOST}/api/v1/repos/${OWNER}/${INSTALLER_REPO}"

: "${PAT:?需要 PAT 环境变量(克隆子仓库)}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PREVIOUS_REVISIONS="$WORK/previous_plugin_revisions.json"
printf '{"schema":1,"plugins":{}}\n' > "$PREVIOUS_REVISIONS"

# WHY: 滚动 Release 的 tag 每次都会重建，仓库自身不能表示上次安装包包含了哪些子项目提交。
# 因此发布脚本把提交清单作为不可见元数据写入 Release 正文；下一次打包先读取它再做增量比较。
echo "== 读取上次 Release 的子项目版本基线 =="
if release_json=$(curl --fail --silent --show-error --max-time 20 -H "Authorization: token ${PAT}" \
    "${API}/releases/tags/${RELEASE_TAG}" 2>/dev/null); then
  marker=$(printf '%s' "$release_json" | jq -r '.body // ""' |
    grep -oE '<!-- ikun-plugin-revisions:[A-Za-z0-9+/=]+ -->' | tail -1 || true)
  encoded="${marker#<!-- ikun-plugin-revisions:}"
  encoded="${encoded% -->}"
  candidate="$WORK/previous_candidate.json"
  if [ -n "$marker" ] && printf '%s' "$encoded" | base64 -d > "$candidate" 2>/dev/null &&
      jq -e '.schema == 1 and (.plugins | type == "object")' "$candidate" >/dev/null 2>&1; then
    cp "$candidate" "$PREVIOUS_REVISIONS"
    echo "  已恢复 $(jq '.plugins | length' "$PREVIOUS_REVISIONS") 个子项目基线"
  else
    echo "  旧 Release 尚无版本清单，本次将建立初始基线"
  fi
else
  echo "  未找到旧 Release，本次将建立初始基线"
fi

printf '{"schema":1,"plugins":{}}\n' > "$REVISIONS_FILE"

echo "== 重建 $APP_DIR =="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
: > "$CHANGES_FILE"   # 清空子项目变更摘要
: > "$META_TSV"       # 清空 meta 摘要 (M4/M7b)

total=0
no_files_repos=()   # G1: 收集不到部署文件的在册插件 (规范 §7.3)
while IFS='|' read -r repo ref; do
  [ -z "$repo" ] && continue
  ref="${ref:-master}"
  echo "== 收集 $repo @ $ref =="
  dest="$WORK/$repo"
  # dll/dlx/dat 都是普通 git 对象(非 LFS); 跳过 LFS 平滑, 避免容器无 git-lfs 报错
  GIT_LFS_SKIP_SMUDGE=1 git clone --quiet --depth 100 --branch "$ref" \
    "https://${PAT}@${HOST}/${OWNER}/${repo}.git" "$dest"

  current_sha=$(git -C "$dest" rev-parse HEAD)
  old_sha=$(jq -r --arg repo "$repo" '.plugins[$repo].sha // empty' "$PREVIOUS_REVISIONS")
  # 通常 100 层浅历史足够；长时间未发布或分支重写时再按需补全，兼顾速度与正确性。
  if [[ "$old_sha" =~ ^[0-9a-fA-F]{7,64}$ ]] &&
      ! git -C "$dest" cat-file -e "${old_sha}^{commit}" 2>/dev/null; then
    if [ "$(git -C "$dest" rev-parse --is-shallow-repository)" = "true" ]; then
      git -C "$dest" fetch --quiet --unshallow origin "$ref" || true
    fi
    git -C "$dest" fetch --quiet origin "$old_sha" || true
  fi
  revision_tmp="$REVISIONS_FILE.tmp"
  jq --arg repo "$repo" --arg ref "$ref" --arg sha "$current_sha" \
    '.plugins[$repo] = {ref:$ref, sha:$sha}' "$REVISIONS_FILE" > "$revision_tmp"
  mv "$revision_tmp" "$REVISIONS_FILE"

  # M4/M7b: 导出 meta 摘要 (repo|name_cn|icon_cn|category|in_ikun) 供 G5 一致性校验与 gen-icons 消费
  meta_line=""
  if [ -f "$dest/plugin.meta" ]; then
    meta_name=$(grep -E '^name_cn=' "$dest/plugin.meta" | head -1 | cut -d= -f2- | tr -d '\r')
    meta_icon=$(grep -E '^icon_cn=' "$dest/plugin.meta" | head -1 | cut -d= -f2- | tr -d '\r')
    meta_cat=$(grep -E '^category=' "$dest/plugin.meta" | head -1 | cut -d= -f2- | tr -d '\r')
    meta_in=$(grep -E '^in_ikun=' "$dest/plugin.meta" | head -1 | cut -d= -f2- | tr -d '\r')
    meta_line="${repo}|${meta_name:-}|${meta_icon:-}|${meta_cat:-}|${meta_in:-}"
  else
    meta_line="${repo}||||"
  fi
  printf '%s\n' "$meta_line" >> "$META_TSV"

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
  if [ "$n" -eq 0 ]; then
    echo "  !! 警告: $repo 未匹配到任何部署文件"
    no_files_repos+=("$repo")   # G1 升级: 在册插件收集不到文件 → 打包失败 (规范 §7.3)
  else
    # G8 阶段一 (规范 M14): 制品内嵌插件仓构建 SHA 与 HEAD 比对 (仅警告, 存量宽限一个周期)
    if [ -n "$current_sha" ]; then
      sha_short="${current_sha:0:7}"
      for f in "$APP_DIR"/"$repo"*.dll; do
        [ -f "$f" ] || continue
        if ! strings "$f" 2>/dev/null | grep -qF "$sha_short"; then
          echo "  !! G8(阶段一): $(basename "$f") 未内嵌构建 SHA $sha_short (规范 M14; 新模板自动内嵌)"
        fi
      done
    fi
  fi

  # ---- 记录相对上次安装包的真实增量，而不是反复显示最新正式版本的第一条 ----
  if [ "$old_sha" = "$current_sha" ]; then
    echo "  = 自上次 Release 无代码变化"
    continue
  fi

  old_available=false
  if [[ "$old_sha" =~ ^[0-9a-fA-F]{7,64}$ ]] &&
      git -C "$dest" cat-file -e "${old_sha}^{commit}" 2>/dev/null; then
    old_available=true
  fi

  summaries=()
  used_fallback=false   # G4 阶段一: 制品更新但 CHANGELOG 无新增条目 → 标红+开 Issue (规范 §6.4)
  # 判据精化: 仅当部署制品真正变化才触发 G4, 文档类提交不误报;
  # 制品扩展名从 ikun-deploy.txt globs 派生 (红队批1 P2-8: 含 .def 等定制)
  artifact_changed=false
  if [ "$old_available" = true ]; then
    changed_artifacts=$(git -C "$dest" diff --name-only "$old_sha" HEAD -- "${globs[@]}" 2>/dev/null || true)
    [ -n "$changed_artifacts" ] && artifact_changed=true
  else
    artifact_changed=true   # 首次记录基线: 视为制品更新
  fi
  if [ "$old_available" = true ]; then
    mapfile -t summaries < <(collect_changelog_delta "$dest" "$old_sha")
    if [ ${#summaries[@]} -eq 0 ]; then
      used_fallback=true
      mapfile -t summaries < <(collect_commit_delta "$dest" "$old_sha")
    fi
    echo "- **${repo}** (\`${old_sha:0:8}\` → \`${current_sha:0:8}\`):" >> "$CHANGES_FILE"
  else
    mapfile -t summaries < <(collect_current_changelog "$dest")
    if [ ${#summaries[@]} -eq 0 ]; then
      used_fallback=true
      mapfile -t summaries < <(collect_commit_delta "$dest" "")
    fi
    echo "- **${repo}** (首次记录基线 \`${current_sha:0:8}\`):" >> "$CHANGES_FILE"
  fi
  if [ "$used_fallback" = true ] && [ "$artifact_changed" = true ]; then
    # G4 阶段一 (规范 §6.4): 制品已更新但 CHANGELOG 无新条目 → 发布说明标红 + 开 Issue (去重)
    echo "  - ⚠ **${repo}** 制品已更新但无 CHANGELOG 文字说明（违反规范 §6.2，gate G4 阶段一）" >> "$CHANGES_FILE"
    # 开 Issue 一律开在安装器仓 (规范 G4: 避免 CI token 需要各插件仓写权限, 与 M11 最小权限一致)
    issue_title="[G4] ${repo} 制品更新缺 CHANGELOG 条目"
    if ! curl --fail --silent --show-error --max-time 20 -H "Authorization: token ${PAT}" \
        "${API}/issues?state=open&limit=50" 2>/dev/null | grep -qF "$issue_title"; then
      curl --fail --silent --show-error --max-time 20 -X POST -H "Authorization: token ${PAT}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg t "$issue_title" --arg b "打包时发现 ${repo} 制品(dll/dlx/dat)已更新但 CHANGELOG.md 无新增条目（规范 §6.4 gate G4 阶段一）。请在变更提交中补充用户可感知的变更说明，否则阶段二将打包失败。" '{title:$t, body:$b}')" \
        "${API}/issues" >/dev/null 2>&1 && echo "  已开 Issue: $issue_title" || echo "  (开 Issue 失败, 不影响打包)"
    fi
  fi
  if [ ${#summaries[@]} -eq 0 ]; then
    summaries=("已更新部署文件，子项目未提供文字说明")
  fi
  for summary in "${summaries[@]}"; do
    echo "  - ${summary}" >> "$CHANGES_FILE"
  done
done < <(jq -r '.plugins[] | "\(.repo)|\(.ref // "master")"' plugins.json)

[ -s "$CHANGES_FILE" ] || echo "（子项目提交未发生变化；本次仅更新安装器）" > "$CHANGES_FILE"
jq -e '.schema == 1 and (.plugins | length > 0)' "$REVISIONS_FILE" >/dev/null || {
  echo "错误: 未生成有效的子项目版本清单"; exit 1;
}

echo "== 收集完成, 共 $total 个文件 =="
ls -la "$APP_DIR"
[ "$total" -eq 0 ] && { echo "错误: 未收集到任何资源, 中止"; exit 1; }
if [ ${#no_files_repos[@]} -gt 0 ]; then
  echo "错误: 以下在册插件未匹配到任何部署文件 (gate G1): ${no_files_repos[*]}"
  exit 1
fi
exit 0
