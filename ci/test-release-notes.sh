#!/usr/bin/env bash
# release-notes.sh 回归测试：覆盖曾导致子插件更新丢失的 Unreleased 与增量聚合路径。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-notes.sh
source "$SCRIPT_DIR/release-notes.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/plugin"
mkdir -p "$REPO"
git -C "$REPO" init --quiet
git -C "$REPO" config user.name "CI Test"
git -C "$REPO" config user.email "ci-test@example.invalid"

cat > "$REPO/CHANGELOG.md" <<'EOF'
# 变更日志

## Unreleased

- **UI**: 新增实时四算法预览
- 修复 [尺寸标注](https://invalid.example/path) 被截断

## v1.0.0

- 旧版本内容，不应代替 Unreleased
EOF
git -C "$REPO" add CHANGELOG.md
git -C "$REPO" commit --quiet -m "initial changelog"
BASE="$(git -C "$REPO" rev-parse HEAD)"

initial="$(collect_current_changelog "$REPO")"
[[ "$initial" == *"新增实时四算法预览"* ]]
[[ "$initial" == *"修复 尺寸标注 被截断"* ]]
[[ "$initial" != *"旧版本内容"* ]]
[[ "$initial" != *"https://"* ]]

cat > "$REPO/CHANGELOG.md" <<'EOF'
# 变更日志

## Unreleased

- **性能**: 多核计算提速
- **UI**: 新增实时四算法预览
- 修复 [尺寸标注](https://invalid.example/path) 被截断

## v1.0.0

- 旧版本内容，不应代替 Unreleased
EOF
git -C "$REPO" add CHANGELOG.md
git -C "$REPO" commit --quiet -m "feat: speed up nesting"

delta="$(collect_changelog_delta "$REPO" "$BASE")"
[[ "$delta" == *"性能: 多核计算提速"* ]]
[[ "$delta" != *"旧版本内容"* ]]
[[ "$delta" != *"新增实时四算法预览"* ]]

commit_delta="$(collect_commit_delta "$REPO" "$BASE")"
[[ "$commit_delta" == *"feat: speed up nesting"* ]]

# Release 正文中的隐藏基线必须可无损恢复；换行 base64 会破坏单行 HTML 标记。
MANIFEST="$WORK/revisions.json"
RESTORED="$WORK/restored.json"
printf '{"schema":1,"plugins":{"demo":{"ref":"master","sha":"0123456789abcdef"}}}\n' > "$MANIFEST"
encoded="$(base64 < "$MANIFEST" | tr -d '\r\n')"
marker="<!-- ikun-plugin-revisions:${encoded} -->"
payload="${marker#<!-- ikun-plugin-revisions:}"
payload="${payload% -->}"
printf '%s' "$payload" | base64 -d > "$RESTORED"
cmp -s "$MANIFEST" "$RESTORED"

echo "release notes regression tests: PASS"
