#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:?用法: make-resource-manifest.sh <DeployResources> <输出目录> [资源版本] [安装器版本] [更新类型]}"
OUT="${2:?用法: make-resource-manifest.sh <DeployResources> <输出目录> [资源版本] [安装器版本] [更新类型]}"
VERSION="${3:-0.0.0}"
INSTALLER_VERSION="${4:-$VERSION}"
UPDATE_KIND="${5:-installer}"
mkdir -p "$OUT"
manifest="$OUT/ikun_resources.json"
tmp="$manifest.tmp"

python3 - "$ROOT" "$OUT" "$VERSION" "$INSTALLER_VERSION" "$UPDATE_KIND" "$tmp" <<'PY'
import hashlib, json, os, sys
root, out, version, installer_version, update_kind, target = sys.argv[1:]
if update_kind not in ('plugins', 'installer'):
    raise SystemExit('更新类型必须是 plugins 或 installer')
items = []
for base, _, files in os.walk(root):
    for name in sorted(files):
        full = os.path.join(base, name)
        rel = os.path.relpath(full, root).replace(os.sep, '/')
        if rel == 'application/.gitkeep' or not (rel.startswith('application/') or rel.startswith('startup/')):
            continue
        asset = 'ikun_resource_' + rel.replace('/', '__')
        staged = os.path.join(out, asset)
        with open(full, 'rb') as src, open(staged, 'wb') as dst:
            digest = hashlib.sha256()
            while True:
                chunk = src.read(1024 * 1024)
                if not chunk: break
                digest.update(chunk); dst.write(chunk)
        items.append({'relative_path': rel, 'asset': asset, 'size': os.path.getsize(full), 'sha256': digest.hexdigest()})
if not items:
    raise SystemExit('没有可发布的插件资源')
with open(target, 'w', encoding='utf-8') as f:
    json.dump({'schema': 1, 'release_version': version,
               'installer_version': installer_version,
               'update_kind': update_kind,
               'resources': items}, f, ensure_ascii=False, indent=2)
    f.write('\n')
os.replace(target, os.path.join(out, 'ikun_resources.json'))
PY
echo "生成资源清单: $manifest ($(jq '.resources | length' "$manifest") 项)"
