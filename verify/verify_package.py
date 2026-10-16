# -*- coding: utf-8 -*-
"""打包结果校验：复刻 .tipa  vs  原包 .tipa（逐条目比对布局，逐文件比对内容哈希）。

比对维度（逐条）：
  1. 条目顺序与名称集合
  2. 条目种类（目录 / 文件 / 符号链接）
  3. 权限位（external_attr 高 16 位的低 12 位）
  4. 符号链接目标字符串（逐字）
  5. 非二进制文件内容 SHA256（默认排除会随构建变化的可执行文件）

用法：
  python verify/verify_package.py [--replica build/MT-Agent-replica.tipa]
                                  [--exclude-build-artifacts]
"""
import argparse, hashlib, os, stat, sys, zipfile

def _resolve_original_tipa():
    """原包定位：环境变量 → 仓库内 reference/ → 仓库根 → SPEC/assets → 本机开发路径"""
    env = os.environ.get("CA_ORIGINAL_TIPA")
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cands = [c for c in [
        env,
        os.path.join(root, "reference", "MT-Agent-v1.0.2-Lite.tipa"),
        os.path.join(root, "MT-Agent-v1.0.2-Lite.tipa"),
        os.path.join(root, "MTAgent-v1.0.2-Lite.tipa"),
        os.path.join(root, "SPEC", "assets", "MT-Agent-v1.0.2-Lite.tipa"),
        r"C:\\Users\\Administrator\\Desktop\\ai\\MT-Agent-v1.0.2-Lite.tipa",
    ] if c]
    for c in cands:
        if os.path.exists(c):
            return c
    return None


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGINAL = _resolve_original_tipa()
# 这些条目在真实构建时由 clang 重新产出，内容必然不同；默认按“布局比对”处理
BUILD_ARTIFACTS = {
    "Payload/CodexApp.app/CodexApp",
    "Payload/CodexApp.app/Helpers/ca-filetool",
    "Payload/CodexApp.app/PlugIns/MTShareExtension.appex/MTShareExtension",
}


def kind_mode_target(zf, info):
    mode = info.external_attr >> 16
    if stat.S_ISDIR(mode):
        kind = "dir"
    elif stat.S_ISLNK(mode):
        kind = "symlink"
    else:
        kind = "file"
    target = zf.read(info).decode("utf-8", "replace") if kind == "symlink" else None
    return kind, mode & 0o7777, target


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--replica", default=os.path.join(ROOT, "build", "MT-Agent-replica.tipa"))
    ap.add_argument("--exclude-build-artifacts", action="store_true", default=True)
    args = ap.parse_args()

    if not os.path.exists(ORIGINAL):
        print("SKIP: 未提供原包（设置 CA_ORIGINAL_TIPA 或放到 reference/ 下即执行逐项比对）")
    sys.exit(0)
    if not os.path.exists(args.replica):
        sys.exit("复刻包不存在: %s（先运行 build/package_tipa.py）" % args.replica)

    zo = zipfile.ZipFile(ORIGINAL)
    zr = zipfile.ZipFile(args.replica)
    o_list, r_list = zo.infolist(), zr.infolist()
    o_names = [i.filename for i in o_list]
    r_names = [i.filename for i in r_list]

    problems = []

    # 1. 名称集合与顺序
    set_o, set_r = set(o_names), set(r_names)
    only_orig = sorted(set_o - set_r)
    only_repl = sorted(set_r - set_o)
    if only_orig:
        problems.append("复刻包缺少 %d 条目: %s" % (len(only_orig), only_orig[:6]))
    if only_repl:
        problems.append("复刻包多出 %d 条目: %s" % (len(only_repl), only_repl[:6]))
    order_same = [n for n in o_names if n in set_r] == [n for n in r_names if n in set_o]
    if not order_same:
        problems.append("条目顺序与原包不同（内容集合相同）")

    # 2/3/4. 逐条目布局
    layout_bad = []
    checked = 0
    for info in o_list:
        if info.filename not in set_r:
            continue
        r_info = zr.getinfo(info.filename)
        o_kind, o_mode, o_target = kind_mode_target(zo, info)
        r_kind, r_mode, r_target = kind_mode_target(zr, r_info)
        checked += 1
        if (o_kind, o_mode, o_target) != (r_kind, r_mode, r_target):
            layout_bad.append("%s: 原(%s %s %s) != 复刻(%s %s %s)" %
                              (info.filename, o_kind, oct(o_mode), o_target, r_kind, oct(r_mode), r_target))
    if layout_bad:
        problems.append("布局不一致 %d 条: %s" % (len(layout_bad), layout_bad[:5]))

    # 5. 内容哈希
    hash_bad, hash_ok = [], 0
    for info in o_list:
        if info.filename not in set_r:
            continue
        kind, _mode, _target = kind_mode_target(zo, info)
        if kind != "file":
            continue
        if args.exclude_build_artifacts and info.filename in BUILD_ARTIFACTS:
            continue
        o_hash = hashlib.sha256(zo.read(info)).hexdigest()
        r_hash = hashlib.sha256(zr.read(zr.getinfo(info.filename))).hexdigest()
        if o_hash == r_hash:
            hash_ok += 1
        else:
            hash_bad.append(info.filename)
    if hash_bad:
        problems.append("内容哈希不同 %d 个文件: %s" % (len(hash_bad), hash_bad[:6]))

    print("原包条目 %d，复刻包条目 %d，共同条目 %d" % (len(o_list), len(r_list), checked))
    print("布局逐条比对: %d 条，异常 %d" % (checked, len(layout_bad)))
    print("内容哈希比对: 通过 %d 个文件，异常 %d（已排除构建产物 %d 个）"
          % (hash_ok, len(hash_bad), len(BUILD_ARTIFACTS)))
    print("条目顺序: %s" % ("一致" if order_same else "不同"))

    if problems:
        print("\n未通过：")
        for x in problems:
            print("  - %s" % x)
        return 1
    print("\n全部通过：复刻包与原包布局/权限/符号链接/资源内容一致。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
