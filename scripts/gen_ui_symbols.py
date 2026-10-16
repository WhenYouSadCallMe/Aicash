# -*- coding: utf-8 -*-
"""用 SPEC/method_types.json（IDA 导出的方法原型）重写 GeneratedUI 下的类骨架：
补齐选择器 + 参数个数 + 返回值类型（参数类型统一用 id，T2b 后续可细化）。

用法：python scripts/gen_ui_symbols.py [--limit N] [--dry]
"""
import argparse, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "MTAgent", "Sources", "GeneratedUI")
TYPES = os.path.join(ROOT, "SPEC", "method_types.json")
API = os.path.join(ROOT, "SPEC", "assets", "objc_api_map.json")

SKIP = {"init", "dealloc", "description", "debugDescription", "hash", "isEqual:", "copy", "mutableCopy",
        "class", "self", "retain", "release", "autorelease", "retainCount", "zone", "superclass",
        "respondsToSelector:", "isKindOfClass:", "conformsToProtocol:", "load", "initialize"}


def superclass_of(name):
    if "ViewController" in name:
        return "UIViewController"
    if name.endswith("Cell"):
        return "UITableViewCell"
    if "View" in name:
        return "UIView"
    return "NSObject"


def parse_proto(proto):
    """'void __cdecl(CAFoo *self, SEL, id)' → ('void', 1 个业务参数)"""
    m = re.match(r"^([A-Za-z_][\w \*]*?)\s*(?:__\w+)?\s*\((.*)\)$", proto or "")
    if not m:
        return "id", None  # None 表示参数个数未知
    ret = m.group(1).strip()
    params = [p.strip() for p in m.group(2).split(",") if p.strip()]
    business = [p for p in params if p not in ("SEL",) and "self" not in p]
    if ret in ("", "void"):
        ret = "void"
    return ret, len(business)


def signature(sel, ret, argc):
    if argc is None:
        return "- (id)%s;" % sel
    segments = sel.split(":")
    if not sel.endswith(":"):
        return "- (%s)%s;" % (ret, sel)
    parts = []
    for i, seg in enumerate(segments[:-1]):
        parts.append("%s:(id)arg%u" % (seg, i + 1))
    return "- (%s)%s;" % (ret, " ".join(parts))


def default_return(ret):
    if ret == "void":
        return None
    if ret.endswith("*") or ret in ("id", "instancetype", "Class"):
        return "nil"
    if ret in ("BOOL", "bool"):
        return "NO"
    return "0"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    types = json.load(open(TYPES, encoding="utf-8"))
    api = json.load(open(API, encoding="utf-8"))
    existing = set()
    for d in (os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")):
        for rd, _dd, names in os.walk(d):
            if os.path.basename(rd) == "GeneratedUI":
                continue
            for f in names:
                if f.endswith((".h", ".m")):
                    body = open(os.path.join(rd, f), encoding="utf-8", errors="replace").read()
                    existing |= set(re.findall(r"@(?:interface|implementation)\s+([A-Za-z_]\w*)", body))

    targets = [(c, types[c]) for c in sorted(types) if c not in existing and c in api]
    if args.limit:
        targets = targets[:args.limit]
    print("目标类 %d，选择器合计 %d" % (len(targets), sum(len(s) for _c, s in targets)))

    written = 0
    for cls, sels in targets:
        methods = []
        for sel, proto in sorted(sels.items()):
            if sel in SKIP or not re.fullmatch(r"[A-Za-z_]\w*:?(?:[A-Za-z_]\w*:)*", sel):
                continue
            ret, argc = parse_proto(proto)
            methods.append((sel, ret, argc, signature(sel, ret, argc)))
        banner = ("//\n//  %s — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，"
                  "参数类型统一占位 id）\n//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）\n//\n" % cls)
        hdr = [banner, "#import <Foundation/Foundation.h>", "#import <UIKit/UIKit.h>", "",
               "NS_ASSUME_NONNULL_BEGIN", "", "@interface %s : %s" % (cls, superclass_of(cls))]
        hdr += ["    " + m[3] for m in methods]
        hdr += ["", "@end", "", "NS_ASSUME_NONNULL_END", ""]
        imp = [banner, '#import "%s.h"' % cls, "", "@implementation %s" % cls, ""]
        for _sel, ret, _argc, sig in methods:
            ret_stmt = default_return(ret)
            imp += [sig.rstrip(";"), "{"]
            imp += ["    // TODO(parity)", "    return %s;" % ret_stmt] if ret_stmt else ["    // TODO(parity)"]
            imp += ["}", ""]
        imp += ["@end", ""]
        if not args.dry:
            with open(os.path.join(OUT, cls + ".h"), "w", encoding="utf-8", newline="\n") as fh:
                fh.write("\n".join(hdr))
            with open(os.path.join(OUT, cls + ".m"), "w", encoding="utf-8", newline="\n") as fh:
                fh.write("\n".join(imp))
        written += 1
    print("已写出 %d 个类的方法骨架（含选择器）" % written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
