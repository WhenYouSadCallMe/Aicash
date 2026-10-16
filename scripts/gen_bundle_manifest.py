# -*- coding: utf-8 -*-
"""从原 .tipa 的 zip 布局生成复刻包的装配清单（顺序 / 权限 / 符号链接目标 完全一致）。"""
import json, os

SRC = r"C:\Users\Administrator\Desktop\ai\MTAgent-Replica\SPEC\assets\zip_entry_modes.json"
OUT = r"C:\Users\Administrator\Desktop\ai\MTAgent-Replica\build\bundle_manifest.json"

entries = json.load(open(SRC, encoding='utf-8'))
app_prefix = "Payload/CodexApp.app/"
manifest = {"source_archive": "MT-Agent-v1.0.2-Lite.tipa", "app_root": "CodexApp.app", "entries": []}
for filename, kind, mode, size, target in entries:
    if filename.startswith(app_prefix):
        rel = filename[len(app_prefix):]
    elif filename.startswith("Payload/"):
        rel = "../" + filename[len("Payload/"):]
    else:
        continue
    manifest["entries"].append({
        "path": rel,
        "kind": kind,
        "mode": mode,
        "size": size,
        "symlink_target": target,
    })

os.makedirs(os.path.dirname(OUT), exist_ok=True)
json.dump(manifest, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print("entries:", len(manifest["entries"]))
for e in manifest["entries"]:
    if e["kind"] == "symlink" or e["path"].startswith("Helpers"):
        print("  %-42s %-8s %-6s %s" % (e["path"], e["kind"], e["mode"], e["symlink_target"] or ""))
