# -*- coding: utf-8 -*-
"""CI 修复批次 6：
 1) 全局：`[CARuntimePaths.X]` → `CARuntimePaths.X`（属性访问不需要方括号，单括号形式必错）
 2) GeneratedUI：为未知类型补 `@class` 前向声明
 3) GeneratedUI：结构体返回值用正确的零值（CGRectZero/CGSizeZero/…）替换 `return 0;`
用法：python scripts/fix_ci_errors3.py
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
GEN = os.path.join(ROOT, "MTAgent", "Sources", "GeneratedUI")

BRACKET_ONLY = re.compile(r"\[CARuntimePaths\.([A-Za-z_]\w*)\]")
STRUCT_ZERO = {
    "CGRect": "CGRectZero", "CGSize": "CGSizeZero", "CGPoint": "CGPointZero",
    "UIEdgeInsets": "UIEdgeInsetsZero", "NSRange": "NSMakeRange(0, 0)",
    "CGAffineTransform": "CGAffineTransformIdentity", "NSDirectionalEdgeInsets": "NSDirectionalEdgeInsetsZero",
}
KNOWN = {
    "id", "instancetype", "void", "BOOL", "SEL", "Class", "NSString", "NSArray", "NSDictionary", "NSSet",
    "NSNumber", "NSData", "NSDate", "NSError", "NSURL", "NSObject", "NSMutableArray", "NSMutableDictionary",
    "NSMutableSet", "NSMutableString", "NSIndexPath", "NSIndexSet", "NSNotification", "NSUserDefaults",
    "NSTimer", "NSLock", "NSValue", "NSAttributedString", "NSMutableAttributedString", "NSDateFormatter",
    "NSFileManager", "NSOperationQueue", "NSXPCConnection", "NSProgress", "NSBundle", "NSCharacterSet",
    "UIView", "UIViewController", "UIImage", "UIColor", "UIFont", "UILabel", "UIButton", "UIImageView",
    "UITableView", "UITableViewCell", "UICollectionView", "UICollectionViewCell", "UICollectionViewLayout",
    "UIScrollView", "UITextView", "UITextField", "UIStackView", "UIWindow", "UIScreen", "UIGestureRecognizer",
    "UITableViewDiffableDataSource", "UICollectionViewDiffableDataSource", "UIDocumentInteractionController",
    "UIActivityViewController", "UIMenu", "UIAction", "UIBarButtonItem", "UITraitCollection", "UIBlurEffect",
    "UIVisualEffectView", "UISearchController", "UITabBarController", "UINavigationController", "UIAlertController",
    "UIAlertAction", "WKWebView", "WKWebViewConfiguration", "WKUserContentController", "WKScriptMessage",
    "AVPlayer", "AVAudioPlayer", "AVAudioSession", "QLPreviewController", "PHPickerViewController",
    "UTType", "CAProcess", "NSPipe", "NSOperation", "NSLayoutConstraint", "NSLayoutAnchor", "CADisplayLink",
}


def fix_brackets(text):
    return BRACKET_ONLY.sub(lambda m: "CARuntimePaths.%s" % m.group(1), text)


def gen_forward_decls(text):
    """收集签名里用作指针类型的未知类名，返回 (@class 行列表, 新文本)"""
    used = set()
    for line in text.splitlines():
        stripped = line.strip()
        if not (stripped.startswith("- (") or stripped.startswith("+ (") or stripped.startswith("@property")):
            continue
        for token in re.findall(r"\b([A-Z][A-Za-z0-9_]*)\s*\*", stripped):
            if token not in KNOWN:
                used.add(token)
    if not used:
        return text, []
    lines = [ln for ln in used if not re.search(r"@class\s+%s\b" % re.escape(ln), text)]
    if not lines:
        return text, []
    block = "\n".join("@class %s;" % n for n in sorted(lines))
    m = re.search(r"@interface\s+[A-Za-z_]\w*", text)
    if not m:
        return text, []
    return text[:m.start()] + block + "\n\n" + text[m.start():], sorted(lines)


def fix_struct_returns(text):
    """把结构体返回值处的 `return 0;` 换成对应零值"""
    out = []
    current_ret = None
    changed = 0
    for line in text.splitlines():
        m = re.match(r"\s*-\s*\(([^)]+)\)", line)
        if m:
            current_ret = m.group(1).strip()
        if current_ret in STRUCT_ZERO and re.match(r"\s*return 0;\s*$", line):
            out.append(line.replace("return 0;", "return %s;" % STRUCT_ZERO[current_ret]))
            changed += 1
            continue
        out.append(line)
    return "\n".join(out) + "\n", changed


stats = []
for d in DIRS:
    for rd, _sd, names in os.walk(d):
        for f in sorted(names):
            if not f.endswith((".m", ".h")):
                continue
            path = os.path.join(rd, f)
            text = open(path, encoding="utf-8", errors="replace").read()
            original = text
            text = fix_brackets(text)
            nb = len(BRACKET_ONLY.findall(original))
            added, structs = [], 0
            if os.path.dirname(path) == GEN:
                text, added = gen_forward_decls(text)
                text, structs = fix_struct_returns(text)
            if text != original:
                open(path, "w", encoding="utf-8", newline="\n").write(text)
                stats.append((f, nb, len(added), structs))

print("修补文件 %d 个" % len(stats))
print("  总括号修复 %d，@class 新增 %d，结构体返回 %d"
      % (sum(s[1] for s in stats), sum(s[2] for s in stats), sum(s[3] for s in stats)))
for f, a, b, c in sorted(stats, key=lambda kv: -(kv[2] + kv[3]))[:8]:
    print("   %-42s 括号%d @class%d 结构体%d" % (f, a, b, c))
