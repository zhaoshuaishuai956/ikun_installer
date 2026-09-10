#!/usr/bin/env bash
# classify-update.sh 的回归测试：插件/元数据变化不得要求完整安装器，运行时代码变化必须要求。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git -C "$WORK" init -q
git -C "$WORK" config user.email test@example.invalid
git -C "$WORK" config user.name classifier-test
printf '<Project>\n  <Version>2.1.0</Version>\n</Project>\n' > "$WORK/ikun_installer.csproj"
printf 'initial\n' > "$WORK/Form1.cs"
printf '{}\n' > "$WORK/plugins.json"
git -C "$WORK" add ikun_installer.csproj Form1.cs plugins.json
git -C "$WORK" commit -qm initial
base=$(git -C "$WORK" rev-parse HEAD)

printf '{"plugins":[]}\n' > "$WORK/plugins.json"
git -C "$WORK" add plugins.json
git -C "$WORK" commit -qm plugin-only
result=$(cd "$WORK" && bash "$SCRIPT_DIR/classify-update.sh" "$base" 2.1.0.2 2.1.0.1)
grep -qx 'UPDATE_KIND=plugins' <<< "$result"
grep -qx 'INSTALLER_CHANGED=false' <<< "$result"
grep -qx 'INSTALLER_VERSION=2.1.0.1' <<< "$result"

base=$(git -C "$WORK" rev-parse HEAD)
printf '<Project>\n  <!-- CI test -->\n  <Version>2.1.0.3</Version>\n</Project>\n' > "$WORK/ikun_installer.csproj"
git -C "$WORK" add ikun_installer.csproj
git -C "$WORK" commit -qm version-only
result=$(cd "$WORK" && bash "$SCRIPT_DIR/classify-update.sh" "$base" 2.1.0.3 2.1.0.1)
grep -qx 'UPDATE_KIND=plugins' <<< "$result"
grep -qx 'INSTALLER_CHANGED=false' <<< "$result"

base=$(git -C "$WORK" rev-parse HEAD)
printf 'runtime change\n' >> "$WORK/Form1.cs"
git -C "$WORK" add Form1.cs
git -C "$WORK" commit -qm installer-change
result=$(cd "$WORK" && bash "$SCRIPT_DIR/classify-update.sh" "$base" 2.1.0.3 2.1.0.1)
grep -qx 'UPDATE_KIND=installer' <<< "$result"
grep -qx 'INSTALLER_CHANGED=true' <<< "$result"
grep -qx 'INSTALLER_VERSION=2.1.0.3' <<< "$result"

echo "update classification tests: PASS"
