#!/usr/bin/env bash
# ============================================================
#  gates.sh — CI 制品/结构闸门 G2/G3/G6/G8 (规范 §7.3)
#  运行环境: pack.yml (ubuntu-latest, 已安装 binutils/libxml2-utils/python3)
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
# 判据: PE 导出名表以 ASCII+null 明文存储, python 字节级判定。
# 不用 strings/grep: GNU strings 在容器(arm64 binutils 2.40)输出不稳定 (CI 两次实证误报)。
shopt -s nullglob
for f in "$APP"/*.dll; do
  if ! python3 -c 'import sys; d=open(sys.argv[1],"rb").read(); sys.exit(0 if (b"ufusr\x00" in d and b"ufusr_ask_unload\x00" in d) else 1)' "$f"; then
    err "G3: $f 缺少 ufusr/ufusr_ask_unload 导出"
  fi
done
shopt -u nullglob

echo "== G6: 禁止入库物 + secret 扫描 =="
cd "$ROOT"
# 规范 §7.4 全清单: 文件类 (*.obj *.exp *.lib *.ilk *.pdb *.pch *.sdf *.suo *.user *.aps *.winmd *.winmdpdb)
# + 目录/凭证类 (bin/ obj/ publish/ ref/ refint/ .env *.token secrets/) (红队批1 P1-4)
forbidden=$(git ls-files | grep -E '\.(obj|exp|lib|ilk|pdb|pch|sdf|suo|user|aps|winmd|winmdpdb)$|(^|/)(bin|obj|publish|ref|refint)/|(^|/)\.env$|\.token$|(^|/)secrets/' || true)
[ -z "$forbidden" ] || { err "G6: 仓库树存在禁止入库物: $forbidden"; }
# 扫描最近一次提交的 diff 中的疑似 secret (pack.yml 已 unshallow, 取父提交)
base_sha=$(git rev-parse HEAD~1 2>/dev/null || echo "")
if [ -n "$base_sha" ]; then
  hits=$(git diff "$base_sha"..HEAD -- . 2>/dev/null | grep -aoE '(ghp_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|Authorization: token [0-9a-f]{20,}|[0-9a-f]{40})' || true)
  [ -z "$hits" ] || { err "G6: 提交 diff 含疑似 secret 字面值"; }
else
  warn "G6: 无父提交可对比, secret 扫描跳过 (depth-1 克隆时发生)"
fi

echo "== G8(阶段一): ikun_updater.dll 与安装器仓 HEAD 绑定检查 =="
updater="$ROOT/nxplugin/ikun_updater.dll"
if [ -f "$updater" ]; then
  head_short=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || true)
  if ! python3 -c "import sys; d=open(sys.argv[1],'rb').read(); sys.exit(0 if sys.argv[2].encode() in d else 1)" "$updater" "$head_short"; then
    warn "G8(阶段一): nxplugin/ikun_updater.dll 未内嵌构建 SHA ${head_short} (规范 M14; 需开发机重编)"
  fi
fi

echo "== G 闸门结果: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL) =="
exit "$fail"
