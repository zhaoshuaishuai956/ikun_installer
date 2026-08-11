#!/usr/bin/env bash
# 子插件 Release Note 提取函数。此文件只定义纯函数，可被 assemble.sh 与回归测试共同加载。

MAX_PLUGIN_CHANGE_ITEMS="${MAX_PLUGIN_CHANGE_ITEMS:-8}"

# 子仓库 CHANGELOG 与提交标题属于外部输入。移除可执行/跳转型 Markdown、HTML、URL、邮箱，
# 并限制单条长度，避免污染安装器公开 Release 正文。
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
    gsub(/[*_`#]/, "", s)
    gsub(/[[:cntrl:]]/, "", s)
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    if (length(s) > 240) s = substr(s, 1, 237) "..."
    print s
  }'
}

emit_sanitized_items() {
  local raw clean count=0
  while IFS= read -r raw; do
    clean=$(printf '%s\n' "$raw" | sanitize_summary)
    [ -z "$clean" ] && continue
    printf '%s\n' "$clean"
    count=$((count + 1))
    [ "$count" -ge "$MAX_PLUGIN_CHANGE_ITEMS" ] && break
  done
  return 0
}

# 没有历史基线时，读取 Unreleased/未发布/待发布；若不存在则读取第一个版本段。
# 与旧实现不同，这里保留该段的多条更新，而不是只取正式版本的第一条。
collect_current_changelog() {
  local repo_dir="${1:?repo dir required}"
  local changelog="$repo_dir/CHANGELOG.md"
  [ -f "$changelog" ] || return 0
  awk '
    /^##[[:space:]]+/ {
      if (active) exit
      heading = tolower($0)
      if (heading ~ /^##[[:space:]]*(unreleased|未发布|待发布)/ ||
          heading ~ /^##[[:space:]]*v?[0-9]/) active = 1
      next
    }
    active && /^[[:space:]]*[-*][[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*[-*][[:space:]]+/, "", line)
      print line
    }
  ' "$changelog" | emit_sanitized_items
}

# 提取 old_revision 到当前 HEAD 之间 CHANGELOG 新增的项目，包含 Unreleased 条目。
collect_changelog_delta() {
  local repo_dir="${1:?repo dir required}"
  local old_revision="${2:?old revision required}"
  [ -f "$repo_dir/CHANGELOG.md" ] || return 0
  git -C "$repo_dir" diff --unified=0 --no-color "$old_revision" HEAD -- CHANGELOG.md 2>/dev/null |
    awk '/^\+[^+]/ {
      line = substr($0, 2)
      if (line ~ /^[[:space:]]*[-*][[:space:]]+/) {
        sub(/^[[:space:]]*[-*][[:space:]]+/, "", line)
        print line
      }
    }' | emit_sanitized_items
}

# CHANGELOG 未维护或本次未新增条目时，以真实提交标题兜底。
collect_commit_delta() {
  local repo_dir="${1:?repo dir required}"
  local old_revision="${2:-}"
  if [ -n "$old_revision" ]; then
    git -C "$repo_dir" log --format='%s' "$old_revision..HEAD" 2>/dev/null | emit_sanitized_items
  else
    git -C "$repo_dir" log -1 --format='%s' 2>/dev/null | emit_sanitized_items
  fi
}
