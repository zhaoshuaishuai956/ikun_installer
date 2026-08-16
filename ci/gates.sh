#!/usr/bin/env bash
# ============================================================
#  gates.sh — CI 制品/结构闸门 G2/G3/G6/G8 (规范 §7.3)
#  运行环境: pack.yml (dotnet/sdk:9.0 容器, 已安装 binutils/libxml2-utils/python3)
#  失败退出非 0 → pack 失败。G4 在 assemble.sh 内, G1 在 assemble.sh 内,
#  G5/G7 由 check_consistency.py 承担。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$ROOT/DeployResources/application"
STARTUP="$ROOT/DeployResources/startup"
fail=0
err() { echo "[G] 失败: $*"; fail=1; }
warn() { echo "[G] 警告: $*"; }

echo "== 闸门工具检查 =="
for t in objdump xmllint python3 iconv strings; do
  command -v "$t" >/dev/null || { err "缺少工具 $t"; }
done

echo "== G2: dlx 必须为合法 XML =="
shopt -s nullglob
for f in "$APP"/*.dlx; do
  if ! xmllint --noout "$f" 2>/dev/null; then err "G2: $f 不是合法 XML"; fi
done
shopt -u nullglob

echo "== G3: dll 必须导出 ufusr + ufusr_ask_unload =="
shopt -s nullglob
for f in "$APP"/*.dll; do
  exports=$(objdump -p "$f" 2>/dev/null || true)
  echo "$exports" | grep -qw 'ufusr' || { err "G3: $f 缺少 ufusr 导出"; continue; }
  echo "$exports" | grep -qw 'ufusr_ask_unload' || { err "G3: $f 缺少 ufusr_ask_unload 导出"; }
done
shopt -u nullglob

echo "== G6: 禁止入库物 + secret 扫描 =="
cd "$ROOT"
forbidden=$(git ls-files | grep -E '\.(obj|exp|lib|ilk|pdb|pch|sdf|suo|aps|winmd|winmdpdb)$' || true)
[ -z "$forbidden" ] || { err "G6: 仓库树存在禁止入库物: $forbidden"; }
# 扫描最近提交的 diff (相对 origin/master) 中的疑似 secret
base_sha=$(git rev-parse origin/master 2>/dev/null || echo "")
if [ -n "$base_sha" ]; then
  hits=$(git diff "$base_sha"..HEAD -- . 2>/dev/null | grep -aoE '(ghp_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|Authorization: token [0-9a-f]{20,}|[0-9a-f]{40})' || true)
  [ -z "$hits" ] || { err "G6: 提交 diff 含疑似 secret 字面值"; }
fi

echo "== G 闸门结果: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL) =="
exit "$fail"
