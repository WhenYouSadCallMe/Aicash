# -*- coding: utf-8 -*-
"""选择器级等价度：原包 CA*/MT* 类的方法在复刻源码中的命中情况（已用直驱逻辑验证）。

数据源：SPEC/method_types.json（163 类 / 5180 选择器的原型，IDA 全量导出）
        SPEC/assets/objc_api_map.json（补充 ivars；method_types 缺失时回退其中的 methods）
扫描：MTAgent/Sources + MTShareExtension/Sources（递归）

用法：python verify/verify_method_coverage.py [--min 0.05] [--class CAFoo]
"""
import argparse, json, os, re, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["MTAgent/Sources", "MTShareExtension/Sources"]
TYPES = os.path.join(ROOT, "SPEC", "method_types.json")
API = os.path.join(ROOT, "SPEC", "assets", "objc_api_map.json")


def collect_sources():
    blobs = []
    for sub in DIRS:
        base = os.path.join(ROOT, sub)
        if not os.path.isdir(base):
            continue
        for root_dir, _dirs, names in os.walk(base):
            for f in sorted(names):
                if f.endswith((".m", ".h")):
                    blobs.append(open(os.path.join(root_dir, f), encoding="utf-8", errors="replace").read())
    return "\n".join(blobs)


def hit(sel, blob):
    """选择器是否在复刻源码里有对应声明/实现。"""
    if sel in blob:
        return True
    if ":" in sel and (sel.split(":")[0] + ":") in blob:   # 多段选择器：源码里是 “段:(类型)参数”
        return True
    bare = sel.replace(":", "")
    if bare and bare in blob:
        return True
    m = re.fullmatch(r"set([A-Z][A-Za-z0-9_]*):", sel)      # setter → 属性名即可
    if m:
        tail = m.group(1)
        for cand in {tail, tail[0].lower() + tail[1:], "_" + tail[0].lower() + tail[1:] if tail else tail}:
            if cand and re.search(r"\b%s\b" % re.escape(cand), blob):
                return True
    m = re.fullmatch(r"is([A-Z][A-Za-z0-9_]*)", sel)        # isXxx → xxx 属性
    if m:
        tail = m.group(1)
        for cand in {tail, tail[0].lower() + tail[1:] if tail else tail}:
            if cand and re.search(r"\b%s\b" % re.escape(cand), blob):
                return True
    return False


def selectors_for(cls, entry, method_types):
    keys = [k for k in (method_types.get(cls) or {}) if k and k.strip()]
    if keys:
        return sorted({k.lstrip("+- ").strip() for k in keys})
    out = []
    for m in entry.get("methods") or []:
        sel = m[2:] if m[:2] in ("-", "+") else m
        sel = sel.split(" ")[0].strip()
        if sel:
            out.append(sel)
    return sorted(set(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min", type=float, default=0.0)
    ap.add_argument("--class", dest="only", default=None)
    args = ap.parse_args()

    method_types = json.load(open(TYPES, encoding="utf-8")) if os.path.exists(TYPES) else {}
    api = json.load(open(API, encoding="utf-8"))
    blob = collect_sources()

    per_class, total_sel, total_hit = {}, 0, 0
    for cls, entry in sorted(api.items()):
        if not cls.startswith(("CA", "MT")):
            continue
        sels = selectors_for(cls, entry, method_types)
        if not sels:
            continue
        hits = [s for s in sels if hit(s, blob)]
        per_class[cls] = {"selectors_total": len(sels), "selectors_hit": len(hits),
                          "coverage": round(len(hits) / len(sels), 3),
                          "missing": [s for s in sels if s not in hits and s != ".cxx_destruct"][:400],
                          "compiler_generated_missing": sum(1 for s in sels if s not in hits and s == ".cxx_destruct"),
                          "ivars": entry.get("ivars", []),
                          "implemented_in_sources": bool(re.search(r"\b%s\b" % re.escape(cls), blob))}
        total_sel += len(sels)
        total_hit += len(hits)

    out = {"generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
           "scanned_bytes": len(blob),
           "classes": per_class,
           "aggregate": {"classes": len(per_class), "selectors_total": total_sel, "selectors_hit": total_hit,
                         "coverage": round(total_hit / total_sel, 4) if total_sel else 0}}
    json.dump(out, open(os.path.join(ROOT, "SPEC", "method_coverage.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    print("原包 CA*/MT* 类: %d，选择器总数: %d，命中: %d（整体 %.1f%%）"
          % (len(per_class), total_sel, total_hit, 100.0 * total_hit / total_sel if total_sel else 0))
    rows = sorted(per_class.items(), key=lambda kv: -kv[1]["selectors_total"])
    print("\n%-34s %6s %6s %7s" % ("类", "选择器", "命中", "覆盖"))
    shown = 0
    for cls, info in rows:
        if args.only and cls != args.only:
            continue
        if info["coverage"] < args.min:
            continue
        print("%-34s %6d %6d %6.0f%%" % (cls, info["selectors_total"], info["selectors_hit"], 100 * info["coverage"]))
        shown += 1
        if shown > 40:
            print("... 其余见 SPEC/method_coverage.json")
            break
    print("\n明细: SPEC/method_coverage.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
