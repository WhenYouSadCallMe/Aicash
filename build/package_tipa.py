# -*- coding: utf-8 -*-
"""把装配好的 Payload/ 目录打包成与原包布局一致的 .tipa（zip）。

与原包一致性要点：
  * 条目顺序：完全按 build/bundle_manifest.json（= 原包 zip 实测顺序）
  * 权限位：zip external_attr 高 16 位写入 manifest 中的 mode（0o755 / 0o644）
  * 符号链接：以 S_IFLNK 标记 + 链接目标为内容写入（不跟随）
  * 目录条目：保留（原包存在 Payload/、CodexApp.app/ 等目录条目）
"""
import argparse, json, os, stat, sys, zipfile


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", required=True, help="Payload 目录（包含 CodexApp.app）")
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--app-name", default="CodexApp.app")
    args = ap.parse_args()

    manifest = json.load(open(args.manifest, encoding="utf-8"))
    payload = os.path.abspath(args.bundle)
    app = os.path.join(payload, args.app_name)
    if not os.path.isdir(app):
        sys.exit("app bundle not found: %s" % app)

    prefix = "Payload/%s/" % args.app_name
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    written = missing = 0

    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        # 1) 目录条目：Payload/ 与 Payload/CodexApp.app/
        for dirpath in ("Payload/", "Payload/%s/" % args.app_name):
            info = zipfile.ZipInfo(dirpath)
            info.external_attr = (stat.S_IFDIR | 0o755) << 16 | 0x10
            zf.writestr(info, b"")
        # 2) 按原包顺序写入每个条目（符号链接以 manifest 为准，保证跨平台确定性）
        for entry in manifest["entries"]:
            rel, kind, mode = entry["path"], entry["kind"], int(entry["mode"], 8)
            if rel.startswith("../") or rel in ("", "/"):
                continue
            arcname = prefix + rel
            host = os.path.join(app, rel.rstrip("/"))

            if kind == "dir":
                info = zipfile.ZipInfo(arcname)
                info.external_attr = (stat.S_IFDIR | (mode or 0o755)) << 16 | 0x10
                zf.writestr(info, b"")
                written += 1
                continue

            if kind == "symlink":
                target = entry.get("symlink_target")
                if not target and os.path.islink(host):
                    target = os.readlink(host)
                if not target:
                    missing += 1
                    continue
                info = zipfile.ZipInfo(arcname)
                info.external_attr = (stat.S_IFLNK | (mode or 0o755)) << 16
                info.compress_type = zipfile.ZIP_STORED
                zf.writestr(info, target.encode())
                written += 1
                continue

            # file
            if not os.path.exists(host):
                missing += 1
                continue
            with open(host, "rb") as fh:
                data = fh.read()
            info = zipfile.ZipInfo(arcname)
            info.external_attr = (stat.S_IFREG | (mode or 0o644)) << 16
            zf.writestr(info, data)
            written += 1

        # 3) 追加 bundle 中存在但清单没有的文件（如 CI 拉取的 Helpers/codex 内核）
        known = set()
        for entry in manifest["entries"]:
            rel = entry["path"]
            if rel.startswith("../") or rel in ("", "/"):
                continue
            known.add(rel.rstrip("/"))
        for dirpath, dirnames, filenames in os.walk(app):
            for fn in filenames:
                host = os.path.join(dirpath, fn)
                rel = os.path.relpath(host, app).replace(os.sep, "/")
                if rel in known or os.path.islink(host):
                    continue
                with open(host, "rb") as fh:
                    data = fh.read()
                info = zipfile.ZipInfo(prefix + rel)
                info.external_attr = (stat.S_IFREG | 0o755) << 16
                zf.writestr(info, data)
                written += 1

    size = os.path.getsize(args.output)
    print("生成 %s (%d 字节)，写入条目 %d，缺失 %d" % (args.output, size, written, missing))


if __name__ == "__main__":
    main()
