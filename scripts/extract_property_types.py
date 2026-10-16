# -*- coding: utf-8 -*-
"""从原包字符串表中提取 ObjC 属性类型编码，生成"属性名 → 类型"映射。
用途：为补齐复刻类的属性/访问器提供类型正确的声明依据。

属性属性串格式（原包 __objc_proplist 中实测）：
    T@"NSString",C,N,V_directory        → type=@"NSString"  ivar=_directory
    T@"NSNumber",&,N,V_heartbeatHealthy → type=@"NSNumber"  ivar=_heartbeatHealthy
    Tq,N,V_rootMode                     → type=q（long long）

用法：python scripts/extract_property_types.py
"""
import json, os, re, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRINGS = os.path.join(ROOT, "SPEC", "assets", "strings_full.txt")
API_MAP = os.path.join(ROOT, "SPEC", "assets", "objc_api_map.json")
OUT = os.path.join(ROOT, "SPEC", "property_types.json")

ENC_TO_OBJC = {
    "@": "id", "c": "char", "i": "int", "s": "short", "l": "long", "q": "long long",
    "C": "unsigned char", "I": "unsigned int", "S": "unsigned short", "L": "unsigned long",
    "Q": "unsigned long long", "f": "float", "d": "double", "B": "BOOL", "v": "void",
    "*": "char *", ":": "SEL", "#": "Class", "?": "id /* block */",
}


def decode_type(enc):
    """把类型编码翻译成 ObjC 声明类型。"""
    if not enc:
        return None
    if enc.startswith('@"') and enc.endswith('"'):
        inner = enc[2:-1]
        return inner + " *"
    if enc.startswith("^{") or enc.startswith("^{"):
        return "void *"
    if enc.startswith("{") or enc.startswith("["):
        return "void * /* struct/array */"
    if enc.startswith("r"):
        return decode_type(enc[1:])
    if enc.startswith("^"):
        return decode_type(enc[1:]) + "*" if len(enc) > 1 else "void *"
    return ENC_TO_OBJC.get(enc[0], None)


def main():
    text = open(STRINGS, encoding="utf-8", errors="replace").read()

    by_ivar = collections.defaultdict(set)
    for m in re.finditer(r'T([^,]*),([A-Za-z0-9&,]*?)V_([A-Za-z_][A-Za-z0-9_]*)', text):
        enc, attrs, ivar = m.group(1), m.group(2), m.group(3)
        by_ivar[ivar].add(enc)

    api = json.load(open(API_MAP, encoding="utf-8"))
    per_class = {}
    for cls, entry in api.items():
        ivars = [i for i in (entry.get("ivars") or [])]
        props = {}
        for ivar in ivars:
            encs = by_ivar.get(ivar) or by_ivar.get(ivar.lstrip("_")) or by_ivar.get("_" + ivar)
            if not encs:
                continue
            if len(encs) > 1:
                enc = sorted(encs)[0]
                ambiguous = True
            else:
                enc = next(iter(encs))
                ambiguous = False
            typ = decode_type(enc)
            if not typ:
                continue
            props[ivar.lstrip("_")] = {"encoding": enc, "type": typ, "ambiguous": ambiguous}
        if props:
            per_class[cls] = props

    json.dump({"encoding_map": {k: v for k, v in ENC_TO_OBJC.items()},
               "classes": per_class},
              open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    total_props = sum(len(v) for v in per_class.values())
    ambiguous = sum(1 for v in per_class.values() for p in v.values() if p["ambiguous"])
    print("提取到属性: %d 个（跨 %d 个类），其中跨类同名歧义 %d 个" % (total_props, len(per_class), ambiguous))
    focus = ["CACodexEngine", "CATheosEnvironment", "CAPythonEnvironment", "CAConversationStore",
             "CARemoteOperations", "CALogger", "CAStorageManager", "CAUpdateManager", "CAAppServerSession"]
    for cls in focus:
        props = per_class.get(cls)
        if not props:
            print("  %-28s 无属性（或无线索）" % cls)
            continue
        sample = ", ".join("%s:%s" % (k, v["type"]) for k, v in list(props.items())[:6])
        print("  %-28s %3d 个属性；示例 %s" % (cls, len(props), sample))
    print("\n输出: SPEC/property_types.json")


if __name__ == "__main__":
    main()
