#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:?用法: make-resource-manifest.sh <DeployResources> <输出目录> [资源版本] [安装器版本] [更新类型]}"
OUT="${2:?用法: make-resource-manifest.sh <DeployResources> <输出目录> [资源版本] [安装器版本] [更新类型]}"
VERSION="${3:-0.0.0}"
INSTALLER_VERSION="${4:-$VERSION}"
UPDATE_KIND="${5:-installer}"
META_FILE="${6:-ci/_plugin_meta.tsv}"
CHANGES_FILE="${7:-ci/_plugin_changes.md}"
mkdir -p "$OUT"
manifest="$OUT/ikun_resources.json"
tmp="$manifest.tmp"

python3 - "$ROOT" "$OUT" "$VERSION" "$INSTALLER_VERSION" "$UPDATE_KIND" "$tmp" "$META_FILE" "$CHANGES_FILE" <<'PY'
import hashlib, json, os, re, sys
root, out, version, installer_version, update_kind, target, meta_path, changes_path = sys.argv[1:]
if update_kind not in ('plugins', 'installer'):
    raise SystemExit('更新类型必须是 plugins 或 installer')

plugin_names = {}
if os.path.isfile(meta_path):
    with open(meta_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            fields = line.rstrip('\r\n').split('|')
            if len(fields) >= 2 and fields[0].strip():
                plugin_names[fields[0].strip()] = fields[1].strip() or fields[0].strip()

plugin_changes = {}
current_plugin = None
if os.path.isfile(changes_path):
    with open(changes_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            heading = re.match(r'^-\s+\*\*([^*]+)\*\*', line)
            if heading:
                current_plugin = heading.group(1).strip()
                plugin_changes.setdefault(current_plugin, [])
                continue
            detail = re.match(r'^\s+-\s+(.+?)\s*$', line)
            if current_plugin and detail and len(plugin_changes[current_plugin]) < 3:
                text = ' '.join(detail.group(1).split())
                if text:
                    plugin_changes[current_plugin].append(text[:512])

plugin_ids = sorted(plugin_names, key=len, reverse=True)
def describe(rel):
    filename = os.path.basename(rel).lower()
    for plugin_id in plugin_ids:
        if filename.startswith(plugin_id.lower()) or filename.startswith('ikun_' + plugin_id.lower()):
            name = plugin_names[plugin_id]
            details = plugin_changes.get(plugin_id, [])
            return plugin_id, name, '；'.join(details) if details else '插件资源更新'
    return 'ikun_toolbox', '爱坤工具箱', '菜单与工具栏资源更新'

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
        plugin_id, plugin_name, description = describe(rel)
        items.append({'relative_path': rel, 'asset': asset, 'size': os.path.getsize(full),
                      'sha256': digest.hexdigest(), 'plugin_id': plugin_id,
                      'plugin_name': plugin_name, 'description': description})
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
