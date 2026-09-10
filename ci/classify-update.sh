#!/usr/bin/env bash
# ============================================================
# classify-update.sh — 区分“仅插件资源”与“安装器本体”变更
# 用法: classify-update.sh <previous-commit> <current-version> [previous-installer-version]
# 输出 UPDATE_KIND / INSTALLER_CHANGED / INSTALLER_VERSION，可直接追加到 GITHUB_ENV。
# ============================================================
set -euo pipefail

PREVIOUS_COMMIT="${1:-}"
CURRENT_VERSION="${2:?用法: classify-update.sh <previous-commit> <current-version> [previous-installer-version]}"
PREVIOUS_INSTALLER_VERSION="${3:-}"

version_ok() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; }

# 旧 Release 不含分类标记时，使用其 Release 版本作为一次性兼容基线。
if ! version_ok "$PREVIOUS_INSTALLER_VERSION"; then
  PREVIOUS_INSTALLER_VERSION="$CURRENT_VERSION"
fi

range=""
if [ -n "$PREVIOUS_COMMIT" ] && git cat-file -e "${PREVIOUS_COMMIT}^{commit}" 2>/dev/null; then
  range="${PREVIOUS_COMMIT}..HEAD"
elif git rev-parse HEAD^ >/dev/null 2>&1; then
  range="HEAD^..HEAD"
fi

installer_changed=false
if [ -n "$range" ]; then
  # 分类只看安装器运行时代码与内嵌安装器资源。插件 DLL/DLX、菜单、图标、插件清单、
  # 文档、测试和 CI 脚本属于资源发布，不应把完整安装器更新提示带给用户。
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      CHANGELOG.md|README.md|LICENSE|plugins.json|DeployResources/*|docs/*|tests/*|ci/*|scripts/*|.gitattributes|.gitignore)
        ;;
      ikun_installer.csproj)
        # CI 每次运行都会注入 Version；仅版本/注释变化不能算安装器代码变化。
        if git diff "$range" -- "$path" | grep -E '^[-+]' | grep -Ev '^(---|\+\+\+)' |
            grep -Ev '^[-+][[:space:]]*(<!--.*-->|<Version>[^<]+</Version>)[[:space:]]*$' >/dev/null; then
          installer_changed=true
        fi
        ;;
      *)
        installer_changed=true
        ;;
    esac
    [ "$installer_changed" = true ] && break
  done < <(git diff --name-only "$range")
fi

if [ "$installer_changed" = true ]; then
  UPDATE_KIND=installer
  INSTALLER_VERSION="$CURRENT_VERSION"
else
  UPDATE_KIND=plugins
  INSTALLER_VERSION="$PREVIOUS_INSTALLER_VERSION"
fi

printf 'UPDATE_KIND=%s\n' "$UPDATE_KIND"
printf 'INSTALLER_CHANGED=%s\n' "$installer_changed"
printf 'INSTALLER_VERSION=%s\n' "$INSTALLER_VERSION"
