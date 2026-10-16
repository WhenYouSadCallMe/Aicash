# -*- coding: utf-8 -*-
"""机械生成未实现的 UI/模型类骨架（依据 SPEC/assets/objc_api_map.json）。

规则：
  * 目标：原包 CA*/MT* 类中尚未在复刻源码里声明过的类，且至少有一个选择器
  * 父类推断：ViewController→UIViewController，Cell→UITableViewCell，View→UIView，其余→NSObject
  * 方法签名：选择器名逐字照抄，参数类型用 id 占位（T2b 会用真实类型编码替换）
  * 跳过 NSObject/UIKit 既有选择器（init/description/hash/…）与纯属性访问器之外的危险名
  * 输出：MTAgent/Sources/GeneratedUI/<Class>.h/.m，带 "AUTO-GENERATED" 横幅
用法：python scripts/gen_ui_classes.py [--limit N] [--check]
"""
import argparse, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "MTAgent", "Sources")
OUT = os.path.join(SRC, "GeneratedUI")
API = os.path.join(ROOT, "SPEC", "assets", "objc_api_map.json")

SKIP_SELECTORS = {
    "init", "dealloc", "description", "debugDescription", "hash", "isEqual:", "copy", "mutableCopy",
    "class", "self", "retain", "release", "autorelease", "retainCount", "zone", "superclass",
    "respondsToSelector:", "isKindOfClass:", "isMemberOfClass:", "conformsToProtocol:",
    "performSelector:", "performSelector:withObject:", "forwardInvocation:", "methodSignatureForSelector:",
    "valueForKey:", "setValue:forKey:", "setValue:forKeyPath:", "valueForKeyPath:", "load", "initialize",
}
SYSTEM_PREFIXES = ("NS", "UI", "CG", "CF", "AV", "WK", "QL", "UT", "CAAnimation", "CALayer", "CADisplayLink",
                   "CABasicAnimation", "CAKeyframeAnimation", "CAGradientLayer", "CAMediaTimingFunction",
                   "CAGit", "CAMERA", "CAINFO", "CALogger", "CATransaction")
RESERVED = {"id", "self", "super", "class", "instancetype"}


def infer_superclass(name):
    if "ViewController" in name:
        return "UIViewController"
    if name.endswith("Cell"):
        return "UITableViewCell"
    if name.endswith("View") or "View" in name:
        return "UIView"
    return "NSObject"


def selector_signature(sel):
    """由选择器名生成可编译的方法声明。"""
    parts = [p for p in sel.split(":") if p]
    if not sel.endswith(":"):
        return "- (id)%s;" % sel
    segments = sel.split(":")
    pieces = []
    for i, seg in enumerate(segments[:-1]):
        pieces.append("%s:(id)arg%u" % (seg, i + 1))
    return "- (id)%s;" % " ".join(pieces)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    api = json.load(open(API, encoding="utf-8"))
    existing = set()
    for d in (SRC, os.path.join(ROOT, "MTShareExtension", "Sources")):
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if f.endswith((".h", ".m")):
                body = open(os.path.join(d, f), encoding="utf-8", errors="replace").read()
                existing |= set(re.findall(r"@(?:interface|implementation)\s+([A-Za-z_]\w*)", body))

    targets = []
    for cls, entry in api.items():
        if cls in existing or not cls.startswith(("CA", "MT")):
            continue
        if cls.startswith(SYSTEM_PREFIXES):
            continue
        sels = []
        for m in entry.get("methods") or []:
            sel = m[2:] if m[:2] in ("-", "+") else m
            sel = sel.split(" ")[0]
            if sel and sel not in SKIP_SELECTORS and re.fullmatch(r"[A-Za-z_]\w*:?(?:[A-Za-z_]\w*:)*", sel):
                sels.append(sel)
        # 说明：api_map 中相当一部分类只出现在 ObjC 类符号里（选择器未命名），
        # 这类仍然生成空骨架以达成“类级等价”，选择器级由 T2b（方法类型编码抽取）补齐。
        targets.append((cls, sels))
    targets.sort(key=lambda kv: -len(kv[1]))
    if args.limit:
        targets = targets[:args.limit]

    print("待生成类: %d（选择器合计 %d）" % (len(targets), sum(len(s) for _c, s in targets)))
    if args.check:
        for cls, sels in targets[:15]:
            print("   %-38s %3d 个选择器  父类=%s" % (cls, len(sels), infer_superclass(cls)))
        return 0

    os.makedirs(OUT, exist_ok=True)
    written = 0
    for cls, sels in targets:
        superclass = infer_superclass(cls)
        banner = ("//\n//  %s — AUTO-GENERATED（依据原包 ObjC 符号表生成，选择器名逐字照抄）\n"
                  "//  行为待填充：标记 TODO(parity) 处需按原包实现补全（见 SPEC/复刻规格书.md）\n//\n" % cls)
        header = [banner, "#import <Foundation/Foundation.h>", "#import <UIKit/UIKit.h>", "",
                  "NS_ASSUME_NONNULL_BEGIN", "", "@interface %s : %s" % (cls, superclass)]
        for sel in sels:
            header.append(selector_signature(sel))
        header += ["", "@end", "", "NS_ASSUME_NONNULL_END", ""]
        impl = [banner, '#import "%s.h"' % cls, "", "@implementation %s" % cls, ""]
        for sel in sels:
            signature = selector_signature(sel).rstrip(";")
            impl += [signature, "{", "    // TODO(parity)", "    return nil;", "}", ""]
        impl += ["@end", ""]
        if not args.check:
            with open(os.path.join(OUT, cls + ".h"), "w", encoding="utf-8", newline="\n") as fh:
                fh.write("\n".join(header))
            with open(os.path.join(OUT, cls + ".m"), "w", encoding="utf-8", newline="\n") as fh:
                fh.write("\n".join(impl))
            written += 1

    print("已生成 %d 个类（%d 个文件）到 %s" % (written, written * 2, OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
