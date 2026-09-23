#!/usr/bin/env bash
# ============================================================
#  gen-icons.sh — 为缺失工具栏图标的插件自动生成 24x24 BMP
#  (对齐旧 build.ps1 的 PIL 生成逻辑, 橙色文字+灰边框)
#  运行环境: GitHub Actions ubuntu-latest; 需要时才 apt 装 imagemagick + 中文字体
#
#  说明: 只生成 startup/ikun_<dll基名>.bmp 位图文件本身。
#        插件要在 NX 里显示, 仍需在 custom.men / custom.tbr / ikun.rtb
#        里引用该 BITMAP 并加 BUTTON(GBK 编码, 目前手工维护)。
# ============================================================
set -euo pipefail

STARTUP="DeployResources/startup"
APP="DeployResources/application"
mkdir -p "$STARTUP"

missing=()
META_TSV="ci/_plugin_meta.tsv"
[ -f "$META_TSV" ] || { echo "错误: 缺少 $META_TSV (须先运行 assemble.sh, 规范 M4)"; exit 1; }
# M4: 图标文字来自各仓 plugin.meta 的 icon_cn (assemble.sh 导出的 meta 摘要), 不再读 plugins.json
while IFS='|' read -r repo name icon category inikun; do
  [ -z "$repo" ] && continue
  # 白名单校验 (规范 §4.2/§11.3): 1-2 汉字或 1-3 大写字母, 防 ImageMagick @/% 注入
  if ! printf '%s' "$icon" | python3 -c 'import re,sys; s=sys.stdin.read().strip(); sys.exit(0 if re.fullmatch(r"[\u4e00-\u9fff]{1,2}|[A-Z]{1,3}", s) else 1)'; then
    echo "  !! 拒绝非法 icon_cn [$icon] (白名单: 1-2 汉字或 1-3 大写字母, 规范 §4.2/§11.3)"
    icon="?"
  fi
  # 找该插件的 dll 基名: 优先 <repo>.dll, 否则取以 repo 开头的第一个 dll
  dll=""
  if [ -f "$APP/$repo.dll" ]; then
    dll="$repo"
  else
    for f in "$APP/$repo"*.dll; do [ -f "$f" ] && { dll="$(basename "$f" .dll)"; break; }; done
  fi
  [ -z "$dll" ] && { echo "  跳过 $repo (application 里无对应 dll)"; continue; }
  bmp="$STARTUP/ikun_${dll}.bmp"
  [ -f "$bmp" ] || missing+=("${bmp}|${icon}")
done < "$META_TSV"

if [ ${#missing[@]} -eq 0 ]; then
  echo "工具栏图标齐全, 无需生成"
  exit 0
fi

echo "需生成 ${#missing[@]} 个图标, 安装 imagemagick + 中文字体..."
apt-get update -qq && apt-get install -y -qq imagemagick fonts-wqy-zenhei >/dev/null
FONT=/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc

for m in "${missing[@]}"; do
  bmp="${m%%|*}"
  txt="${m#*|}"
  [ -z "$txt" ] && txt="?"
  echo "  生成 $(basename "$bmp") 文字[$txt]"
  convert -size 24x24 xc:white \
    -font "$FONT" -pointsize 11 -fill '#FF8C00' -gravity center -annotate +0+0 "$txt" \
    -fill none -stroke '#C8C8C8' -draw 'rectangle 1,1 22,22' \
    "BMP3:${bmp}"
done
echo "图标生成完成 (提醒: 新插件仍需在 custom.men/ikun.rtb 里引用图标+加 BUTTON 才会在 NX 显示)"
