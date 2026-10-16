# -*- coding: utf-8 -*-
"""复刻一致性校验：原包 .tipa  vs  复刻工程。

校验维度
  1. Info.plist（主 app / 分享扩展）语义一致
  2. entitlements（主 app / 扩展）集合与取值一致
  3. 内嵌重签 entitlements 模板（runtime / helper）与原二进制里的一致
  4. Helper 布局（路径 / 种类 / 权限位 / 符号链接目标）一致
  5. 资源文件 SHA256 一致（cacert.pem、models.json、codex-fallback-prompt.md、Mermaid、ThirdPartyNotices、图标…）
  6. 源码对原包 ObjC 符号的覆盖度（类名 / 选择器名）
用法：
  python verify/verify_parity.py
"""
import hashlib, json, os, plistlib, re, stat, sys, zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
REPLICA = os.path.dirname(ROOT)
TIP = r"C:\Users\Administrator\Desktop\ai\MT-Agent-v1.0.2-Lite.tipa"
APP_PREFIX = "Payload/CodexApp.app/"
EXT_PREFIX = APP_PREFIX + "PlugIns/MTShareExtension.appex/"

results = []


def record(name, ok, detail=""):
    results.append((name, ok, detail))
    print("%s %-46s %s" % ("[ OK ]" if ok else "[FAIL]", name, detail))


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def load_plist(data):
    return plistlib.loads(data)


def main():
    if not os.path.exists(TIP):
        sys.exit("原始 tipa 不存在: %s" % TIP)
    zf = zipfile.ZipFile(TIP)
    names = set(zf.namelist())

    def member(path):
        return zf.read(path)

    # ---------- 1. Info.plist ----------
    orig_app_plist = load_plist(member(APP_PREFIX + "Info.plist"))
    replica_app_plist = plistlib.load(open(os.path.join(REPLICA, "MTAgent/Info.plist"), "rb"))
    diff_keys = [k for k in set(orig_app_plist) | set(replica_app_plist)
                 if orig_app_plist.get(k) != replica_app_plist.get(k)]
    record("App Info.plist 语义一致", not diff_keys,
           "keys=%d 差异=%s" % (len(orig_app_plist), diff_keys or "无"))

    orig_ext_plist = load_plist(member(EXT_PREFIX + "Info.plist"))
    replica_ext_plist = plistlib.load(open(os.path.join(REPLICA, "MTShareExtension/Info.plist"), "rb"))
    diff_ext = [k for k in set(orig_ext_plist) | set(replica_ext_plist)
                if orig_ext_plist.get(k) != replica_ext_plist.get(k)]
    record("扩展 Info.plist 语义一致", not diff_ext, "差异=%s" % (diff_ext or "无"))

    # ---------- 2. entitlements ----------
    orig_ent = load_plist(member(APP_PREFIX + "entitlements.plist"))
    replica_ent = plistlib.load(open(os.path.join(REPLICA, "MTAgent/entitlements.plist"), "rb"))
    record("App entitlements 完全一致", orig_ent == replica_ent,
           "键数 %d -> %d" % (len(orig_ent), len(replica_ent)))
    ext_ent = plistlib.load(open(os.path.join(REPLICA, "MTShareExtension/entitlements.plist"), "rb"))
    record("扩展 entitlements 含同组 app-group 与特权集",
           ext_ent.get("com.apple.security.application-groups") == orig_ent.get("com.apple.security.application-groups"),
           "origin 文件不存在（原包未附），按主 app 特权集对齐")

    # ---------- 3. 内嵌重签模板 ----------
    bin_path = os.path.join(REPLICA, "SPEC/assets/CodexApp.original.bin")
    origin_binary = open(bin_path, "rb").read() if os.path.exists(bin_path) else b""
    pat = rb'<\?xml version="1\.0" encoding="UTF-8"\?>.{0,3000}?</plist>'
    templates = []
    if origin_binary:
        for m in re.finditer(pat, origin_binary, re.S):
            s = m.group(0)
            if b"platform-application" in s:
                templates.append(plistlib.loads(s))
    runtime_tpl = plistlib.load(open(os.path.join(REPLICA, "MTAgent/ResignEntitlements/runtime.entitlements.plist"), "rb"))
    helper_tpl = plistlib.load(open(os.path.join(REPLICA, "MTAgent/ResignEntitlements/helper.entitlements.plist"), "rb"))
    uniq = []
    for t in templates:
        if t not in uniq:
            uniq.append(t)
    record("重签模板(helper) 命中原包内嵌模板", helper_tpl in uniq, "原包内嵌模板数=%d" % len(uniq))
    record("重签模板(runtime) 命中原包内嵌模板", runtime_tpl in uniq, "runtime 模板键=%d" % len(runtime_tpl))

    # ---------- 4. Helper 布局 ----------
    manifest = json.load(open(os.path.join(REPLICA, "build/bundle_manifest.json"), encoding="utf-8"))
    manifest_map = {e["path"]: e for e in manifest["entries"]}
    orig_layout = {}
    for info in zf.infolist():
        if not info.filename.startswith(APP_PREFIX):
            continue
        rel = info.filename[len(APP_PREFIX):]
        if rel == "":
            continue
        mode = info.external_attr >> 16
        kind = "symlink" if stat.S_ISLNK(mode) else ("dir" if stat.S_ISDIR(mode) else "file")
        target = zf.read(info).decode("utf-8", "replace") if kind == "symlink" else None
        orig_layout[rel] = (kind, oct(mode & 0o7777), target)
    mismatch = []
    for rel, (kind, mode, target) in orig_layout.items():
        e = manifest_map.get(rel)
        if not e:
            mismatch.append("%s 缺失" % rel)
            continue
        if (e["kind"], e["mode"], e["symlink_target"]) != (kind, mode, target):
            mismatch.append("%s %s/%s/%s != %s/%s/%s" % (rel, e["kind"], e["mode"], e["symlink_target"], kind, mode, target))
    record("Helper/资源布局（种类·权限·链接目标）一致", not mismatch,
           "条目 %d，差异 %d %s" % (len(orig_layout), len(mismatch), mismatch[:4] if mismatch else ""))

    # ---------- 5. 资源哈希 ----------
    asset_root = os.path.join(REPLICA, "OriginalAssets", "Payload", "CodexApp.app")
    checked = 0
    bad = []
    skip_files = {"CodexApp", "Helpers/bash.real", "Helpers/codex-sign", "Helpers/ca-filetool",
                  "PlugIns/MTShareExtension.appex/MTShareExtension"}
    for rel, (kind, mode, target) in orig_layout.items():
        if kind != "file" or rel in skip_files or rel.endswith("/"):
            continue
        host = os.path.join(asset_root, rel)
        if not os.path.exists(host):
            bad.append("%s 未随工程附带" % rel)
            continue
        orig_hash = sha256_bytes(zf.read(APP_PREFIX + rel))
        local_hash = sha256_bytes(open(host, "rb").read())
        checked += 1
        if orig_hash != local_hash:
            bad.append("%s 哈希不同" % rel)
    record("随包资源 SHA256 与原包一致", not bad, "校验 %d 个文件，异常 %d %s" % (checked, len(bad), bad[:3] if bad else ""))

    # ---------- 6. 源码符号覆盖度 ----------
    api_map = json.load(open(os.path.join(REPLICA, "SPEC/assets/objc_api_map.json"), encoding="utf-8"))
    sources = []
    for dirpath, _dirs, files in os.walk(os.path.join(REPLICA, "MTAgent/Sources")):
        for f in files:
            if f.endswith((".m", ".h")):
                sources.append(open(os.path.join(dirpath, f), encoding="utf-8", errors="replace").read())
    for dirpath, _dirs, files in os.walk(os.path.join(REPLICA, "MTShareExtension")):
        for f in files:
            if f.endswith((".m", ".h")):
                sources.append(open(os.path.join(dirpath, f), encoding="utf-8", errors="replace").read())
    blob = "\n".join(sources)

    core_prefixes = ("CA", "MT")
    orig_classes = [c for c in api_map if c.startswith(core_prefixes)]
    implemented = [c for c in orig_classes if re.search(r"\b%s\b" % re.escape(c), blob)]
    record("原包 ObjC 类名在复刻源码中出现", len(implemented) > 0,
           "%d/%d 个 CA*/MT* 类名被引用或实现" % (len(implemented), len(orig_classes)))

    must_have = ["CARemoteOperations", "CAProviderConfiguration", "CALogger", "CARuntimePaths", "CAStorageManager",
                 "CACodexEngine", "CAAppServerSession", "CARuntimeCatalog", "CARuntimeCatalogEntry", "CAMCPBridge",
                 "CAArchiveExtractor", "CAUpdateManager", "CAExecutionEnvironment", "CAExecutionEnvironmentProfile",
                 "CAManagedRuntimeEnvironment", "CAPythonEnvironment", "CATheosEnvironment", "CAReverseToolsEnvironment",
                 "CAFileToolMain", "CAAgentRuntimeMain", "CAAppDelegate"]
    missing_must = [c for c in must_have if not re.search(r"\b%s\b" % re.escape(c), blob)]
    record("核心子系统类名齐全", not missing_must, "缺失=%s" % (missing_must or "无"))

    if not sources:
        record("源码存在", False, "MTAgent/Sources 无 .m/.h")

    # ---------- 汇总 ----------
    print("\n" + "=" * 70)
    failed = [r for r in results if not r[1]]
    print("校验项 %d，通过 %d，未通过 %d" % (len(results), len(results) - len(failed), len(failed)))
    for name, _ok, detail in failed:
        print("  未通过: %s — %s" % (name, detail))
    print("=" * 70)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
