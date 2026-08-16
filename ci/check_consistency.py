#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""G5/G7 一致性闸门 (规范 §7.3) — 纯 stdlib, 无第三方依赖。

G5: plugins.json <-> registry/菜单/application 集合一致; BITMAP==ikun_<repo>.bmp;
    LABEL==plugin.meta.name_cn (字节比较, GBK 解码后); meta 字段白名单 (规范 §4.2/§11.3)
G7: 菜单文件 GBK 往返一致 + 无 U+FFFD + 结构合法 (BUTTON 块配对/ACTIONS/BITMAP/LABEL 齐备)

用法: python3 ci/check_consistency.py   (工作目录 = 仓库根)
退出码: 0=通过, 1=失败(任一 G5/G7 项失败)
"""
import json
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # Windows 控制台可读

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "DeployResources", "application")
STARTUP = os.path.join(ROOT, "DeployResources", "startup")
META_TSV = os.path.join(ROOT, "ci", "_plugin_meta.tsv")
fail = False


def err(msg):
    global fail
    fail = True
    print("[G] 失败: " + msg)


def warn(msg):
    print("[G] 警告: " + msg)


def read_gbk(path):
    with open(path, "rb") as f:
        raw = f.read()
    try:
        text = raw.decode("gbk")
    except UnicodeDecodeError:
        err("G7: %s 不是合法 GBK 编码" % path)
        return None, raw
    if "\ufffd" in text:
        err("G7: %s 解码含 U+FFFD (疑似被存成 UTF-8)" % path)
        return None, raw
    if text.encode("gbk") != raw:
        err("G7: %s GBK 往返不一致 (字节被改写)" % path)
        return None, raw
    return text, raw


def parse_menu(text):
    """解析 custom.men: 返回 [(button_id, {label, bitmap, actions}), ...]"""
    buttons = []
    cur = None
    for line in text.splitlines():
        s = line.strip()
        if not s:
            continue
        if s.upper().startswith("BUTTON "):
            if cur is not None:
                buttons.append(cur)
            cur = {"id": s.split(None, 1)[1], "label": None, "bitmap": None, "actions": None}
        elif cur is not None:
            up = s.upper()
            if up.startswith("LABEL "):
                cur["label"] = s.split(None, 1)[1]
            elif up.startswith("BITMAP "):
                cur["bitmap"] = s.split(None, 1)[1]
            elif up.startswith("ACTIONS "):
                cur["actions"] = s.split(None, 1)[1]
    if cur is not None:
        buttons.append(cur)
    return buttons


def main():
    global fail
    print("== G5: 注册/菜单/制品一致性 ==")
    with open(os.path.join(ROOT, "plugins.json"), encoding="utf-8") as f:
        plugins = json.load(f)["plugins"]
    repo_set = {p["repo"] for p in plugins}

    # meta 摘要 (assemble.sh 生成)
    meta = {}  # repo -> (name_cn, icon_cn, category, in_ikun)
    if os.path.exists(META_TSV):
        with open(META_TSV, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\r\n").split("|")   # rstrip 含 \r: Windows 生成的行尾
                if len(parts) >= 5:
                    meta[parts[0]] = tuple(parts[1:5])
    for repo in sorted(repo_set - set(meta)):
        err("G5: %s 无 plugin.meta (assemble 未收集到)" % repo)

    # 菜单 (custom.men)
    men_path = os.path.join(STARTUP, "custom.men")
    if not os.path.exists(men_path):
        err("G5: 缺少 custom.men")
        return 1
    text, _ = read_gbk(men_path)
    if text is None:
        return 1
    buttons = parse_menu(text)
    act2btn = {}
    for b in buttons:
        if b["actions"]:
            act2btn.setdefault(b["actions"].lower(), []).append(b)

    # G5a: ACTIONS 集合 == 在册 dll 集合 + ikun_updater.dll (大小写不敏感, M1 未完成前兼容)
    expected_actions = {r.lower() + ".dll" for r in repo_set} | {"ikun_updater.dll"}
    actual_actions = set(act2btn)
    for a in sorted(actual_actions - expected_actions):
        err("G5: 菜单 ACTIONS 出现未登记 dll: %s" % a)
    for a in sorted(expected_actions - actual_actions):
        err("G5: 菜单缺少 ACTIONS: %s" % a)

    # G5b: application/ 收集结果: dll 基名唯一且 == 仓库名
    if os.path.isdir(APP):
        app_dlls = sorted(f[:-4] for f in os.listdir(APP) if f.lower().endswith(".dll"))
        dup = [d for d in set(app_dlls) if app_dlls.count(d) > 1]
        for d in dup:
            err("G5: application/ 出现重复 dll 基名: %s (M1 改名期双收?)" % d)
        for base in app_dlls:
            if base not in repo_set and base != "ikun_updater":
                err("G5: application/ 存在未登记 dll: %s.dll" % base)
        for repo in sorted(repo_set):
            if repo not in app_dlls:
                err("G5: application/ 缺少 %s.dll" % repo)
    else:
        err("G5: application/ 目录不存在")

    # G5c: BITMAP == ikun_<repo>.bmp 且文件存在 (updater 例外: ikun_tools.bmp)
    for repo in sorted(repo_set):
        for b in act2btn.get(repo + ".dll", []):
            want = "ikun_%s.bmp" % repo
            if b["bitmap"] != want:
                err("G5: %s 的 BITMAP=%s, 应为 %s (规范 §4.1/M4 归一)" % (repo, b["bitmap"], want))
            elif not os.path.exists(os.path.join(STARTUP, want)):
                err("G5: %s 引用图标 %s 不存在 (CI 应已生成)" % (repo, want))
    for b in act2btn.get("ikun_updater.dll", []):
        if b["bitmap"] != "ikun_tools.bmp":
            err("G5: ikun_updater 的 BITMAP 应为 ikun_tools.bmp, 实为 %s" % b["bitmap"])

    # G5d: LABEL == plugin.meta.name_cn (字节比较)
    for repo in sorted(repo_set):
        for b in act2btn.get(repo + ".dll", []):
            m = meta.get(repo)
            if m is None:
                continue
            want_label = m[0]
            if b["label"] != want_label:
                err("G5: %s 菜单 LABEL=%s, 应为 meta.name_cn=%s (规范 §8.2/M8b)" % (repo, b["label"], want_label))

    # G5e: meta 字段白名单 (规范 §4.2/§11.3)
    for repo, (name_cn, icon_cn, category, in_ikun) in meta.items():
        if not re.fullmatch(r"[\u4e00-\u9fff]{1,2}|[A-Z]{1,3}", icon_cn or ""):
            err("G5e: %s icon_cn=%r 不合规 (须纯汉字 1-2 字或 1-3 大写字母, 防 ImageMagick 注入)" % (repo, icon_cn))
        cjk = len(re.findall(r"[\u4e00-\u9fff]", name_cn or ""))
        if not re.fullmatch(r"[\u4e00-\u9fffA-Za-z0-9]{1,12}", name_cn or "") or cjk > 8:
            err("G5e: %s name_cn=%r 不合规 (汉字≤8/总长≤12, 无控制字符)" % (repo, name_cn))
        if category not in ("建模", "CAM", "PMI", "制图", "装配", "钣金", "其它", ""):
            err("G5e: %s category=%r 不在枚举" % (repo, category))
        if in_ikun not in ("true", "false", ""):
            err("G5e: %s in_ikun=%r 非法" % (repo, in_ikun))

    print("== G7: 菜单编码与结构 ==")
    for fn in ("custom.men", "custom.tbr", "ikun.rtb"):
        p = os.path.join(STARTUP, fn)
        if not os.path.exists(p):
            warn("G7: %s 不存在 (可选文件, 跳过)" % fn)
            continue
        t, _ = read_gbk(p)
        if t is None:
            continue
        if not re.search(r"(?m)^VERSION\s+\d+", t):
            err("G7: %s 缺 VERSION 声明" % fn)
        if fn == "custom.men":
            if t.count("MENU ") != t.count("END_OF_MENU"):
                err("G7: %s MENU/END_OF_MENU 不配对" % fn)
            for b in buttons:
                if b["label"] is None:
                    err("G7: %s 的 BUTTON %s 缺 LABEL" % (fn, b["id"]))
                if b["bitmap"] is None:
                    err("G7: %s 的 BUTTON %s 缺 BITMAP" % (fn, b["id"]))
                if b["actions"] is None:
                    err("G7: %s 的 BUTTON %s 缺 ACTIONS" % (fn, b["id"]))

    print("== 一致性闸门结果: %s ==" % ("PASS" if not fail else "FAIL"))
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
