# -*- coding: utf-8 -*-
"""T1：用原包属性类型编码，为复刻类补齐类型正确的属性/访问器（幂等）。

规则：
  * 属性取自 SPEC/property_types.json（由原包 __objc_proplist 的 T…,V_ 编码还原）
  * 跳过：类型歧义、非对象/标量的聚合类型（struct/array）、与父类冲突的知名属性名、
          头文件里已出现的名字、实现文件里已有同名 `_ivar` 的名字
  * 插入块用标记包裹，重复运行会先移除旧块（幂等）
用法：
  python scripts/apply_property_parity.py [--check] [--only Class1,Class2]
"""
import argparse, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
PROP_JSON = os.path.join(ROOT, "SPEC", "property_types.json")

BEGIN = "// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)"
END = "// ==PARITY-PROPERTIES-END=="

# 与 NSObject / UIKit 基类同名的属性：声明会与父类类型冲突，直接跳过
DENY = {
    "hash", "description", "debugDescription", "superclass", "class", "zone", "isa", "retainCount",
    "self", "window", "view", "nextResponder", "inputAccessoryView", "inputView", "title",
    "tableView", "collectionView", "navigationController", "presentedViewController", "navigationItem",
    "isViewLoaded", "edgesForExtendedLayout", "restorationIdentifier", "accessibilityLabel",
    "accessibilityIdentifier", "accessibilityHint", "userActivity", "undoManager", "traitCollection",
    "preferredContentSize", "modalPresentationStyle", "modalTransitionStyle", "parent",
    "children", "responder", "text", "attributedText", "font", "textColor", "image", "tag",
}
SCALARS = {"char", "int", "short", "long", "long long", "unsigned char", "unsigned int", "unsigned short",
           "unsigned long", "unsigned long long", "float", "double", "BOOL"}


def load_sources():
    out = {}
    for d in SRC_DIRS:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith((".h", ".m")):
                out[f] = open(os.path.join(d, f), encoding="utf-8", errors="replace").read()
    return out


def locate_class(sources, cls):
    """返回 (声明所在头文件名, 实现所在 .m 内容)。支持一个头文件里声明多个类。"""
    header_name, impl_body = None, ""
    for name, body in sources.items():
        if name.endswith(".h") and re.search(r"@interface\s+%s\b" % re.escape(cls), body):
            if header_name is None or not header_name.startswith(cls):
                header_name = name
    for name, body in sources.items():
        if name.endswith(".m") and re.search(r"@implementation\s+%s\b" % re.escape(cls), body):
            impl_body = body
            break
    return header_name, impl_body


def make_property(name, type_str):
    if type_str.endswith("/* block */"):
        type_str = "id"
    if type_str == "id":
        return "@property (nonatomic, copy, nullable) id %s;" % name
    if type_str in SCALARS:
        return "@property (nonatomic, assign) %s %s;" % (type_str, name)
    if type_str.endswith("*"):
        return "@property (nonatomic, strong, nullable) %s %s;" % (type_str, name)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只报告将要插入的内容，不写文件")
    ap.add_argument("--only", default=None, help="逗号分隔的类名白名单")
    args = ap.parse_args()

    props = json.load(open(PROP_JSON, encoding="utf-8"))["classes"]
    sources = load_sources()
    only = set(args.only.split(",")) if args.only else None

    changed, added_total, skipped_total = [], 0, 0
    for cls, plist in sorted(props.items()):
        if only and cls not in only:
            continue
        header_name, impl = locate_class(sources, cls)
        if not header_name:
            continue
        header = sources[header_name]

        # 定位本类的 @interface ... @end
        m = re.search(r"@interface\s+%s\b" % re.escape(cls), header)
        if not m:
            continue
        end_idx = header.find("@end", m.end())
        if end_idx < 0:
            continue

        # 幂等：先移除旧块
        block_re = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", re.S)
        header_clean = block_re.sub("", header)
        end_idx = len(header_clean)
        m2 = re.search(r"@interface\s+%s\b" % re.escape(cls), header_clean)
        end_idx = header_clean.find("@end", m2.end())

        lines, added, skipped = [], 0, 0
        for name, info in sorted(plist.items()):
            if info["ambiguous"] or name in DENY or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
                skipped += 1
                continue
            if re.search(r"\b%s\b" % re.escape(name), header_clean):
                skipped += 1
                continue
            if re.search(r"\b_%s\b" % re.escape(name), impl):
                skipped += 1
                continue
            declaration = make_property(name, info["type"])
            if not declaration:
                skipped += 1
                continue
            lines.append("    " + declaration)
            added += 1

        if not lines:
            skipped_total += skipped
            continue

        block = "\n" + BEGIN + "\n" + "\n".join(lines) + "\n" + END + "\n"
        new_header = header_clean[:end_idx] + block + header_clean[end_idx:]
        added_total += added
        skipped_total += skipped
        changed.append((cls, added, skipped))
        if not args.check:
            path = None
            for d in SRC_DIRS:
                candidate = os.path.join(d, header_name)
                if os.path.exists(candidate):
                    path = candidate
                    break
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(new_header)

    print("%s：%d 个类被补充，共新增 %d 个属性声明（跳过 %d）"
          % ("[check]" if args.check else "[apply]", len(changed), added_total, skipped_total))
    for cls, added, skipped in sorted(changed, key=lambda x: -x[1])[:25]:
        print("   %-34s +%-4d (skip %d)" % (cls, added, skipped))
    if len(changed) > 25:
        print("   ... 其余 %d 个类见 SPEC/property_parity_report.json" % (len(changed) - 25))

    json.dump({"applied": bool(not args.check),
               "classes": [{"class": c, "added": a, "skipped": s} for c, a, s in changed]},
              open(os.path.join(ROOT, "SPEC", "property_parity_report.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
