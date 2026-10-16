# -*- coding: utf-8 -*-
"""按原包清单装配 CodexApp.app：资源、Helpers 符号链接、权限位。

用法：
  python3 build/assemble_bundle.py --bundle build/out/Payload/CodexApp.app \
      --manifest build/bundle_manifest.json --assets OriginalAssets/Payload/CodexApp.app \
      [--keep-original-binaries]

规则：
  * 目录 / 文件 / 符号链接 的种类、相对目标、权限位一律取自 manifest（= 原包 zip 实测值）
  * 二进制（CodexApp / ca-filetool）默认保留构建产物；--keep-original-binaries 时，
    对 manifest 中标记为 file 的第三方二进制（bash.real / codex-sign）从 assets 复制
  * 已存在文件不覆盖（除非来自 assets 且缺失）
"""
import argparse, json, os, shutil, stat, sys

ORIGINAL_BINARIES = {"Helpers/bash.real", "Helpers/codex-sign"}


def ensure_dir(path, mode):
    os.makedirs(path, exist_ok=True)
    os.chmod(path, mode)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--assets", required=True)
    ap.add_argument("--keep-original-binaries", action="store_true")
    args = ap.parse_args()

    manifest = json.load(open(args.manifest, encoding="utf-8"))
    bundle = os.path.abspath(args.bundle)
    assets = os.path.abspath(args.assets)
    os.makedirs(bundle, exist_ok=True)

    created, skipped, relinked, copied = 0, 0, 0, 0
    symlink_plan = []
    for entry in manifest["entries"]:
        rel, kind, mode = entry["path"], entry["kind"], int(entry["mode"], 8)
        target = os.path.join(bundle, rel)
        if rel.startswith("../"):
            continue  # 交给 package_tipa.py 处理（PlugIns 之外的条目）

        if kind == "dir":
            ensure_dir(target, mode or 0o755)
            continue

        if kind == "symlink":
            link_target = entry["symlink_target"]
            ensure_dir(os.path.dirname(target), 0o755)
            if os.path.islink(target):
                if os.readlink(target) == link_target:
                    continue
                os.unlink(target)
            if os.path.exists(target):
                os.remove(target)
            try:
                os.symlink(link_target, target)
                relinked += 1
            except OSError as exc:
                # Windows 无符号链接权限时，记录计划（package_tipa.py 以 manifest 为准）
                symlink_plan.append({"path": rel, "target": link_target, "error": str(exc)})
            continue

        # file
        keep_original = args.keep_original_binaries and rel in ORIGINAL_BINARIES
        if os.path.exists(target) and not keep_original:
            skipped += 1
            continue
        src = os.path.join(assets, rel)
        if not os.path.exists(src):
            print("  ! 缺少资源: %s（来自 %s）" % (rel, assets))
            continue
        ensure_dir(os.path.dirname(target), 0o755)
        shutil.copy2(src, target)
        os.chmod(target, mode or 0o644)
        copied += 1

    # 可选：接入交叉编译的 codex 内核（Kernel/dist/codex，由 build-kernel-ios 工作流产出）
    kernel_src = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                              "Kernel", "dist", "codex")
    kernel_dst = os.path.join(bundle, "Helpers", "codex")
    if os.path.isfile(kernel_src) and not os.path.exists(kernel_dst):
        ensure_dir(os.path.dirname(kernel_dst), 0o755)
        shutil.copy2(kernel_src, kernel_dst)
        os.chmod(kernel_dst, 0o755)
        print("  + 已接入 codex 内核: Helpers/codex (%d 字节)" % os.path.getsize(kernel_dst))
    elif not os.path.isfile(kernel_src):
        print("  ! Kernel/dist/codex 不存在，产物不含智能内核"
              "（先跑 build-kernel-ios 工作流或 git fetch origin dist-kernel）")

    # 目录权限统一
    for root, dirs, _files in os.walk(bundle):
        for d in dirs:
            p = os.path.join(root, d)
            if not os.path.islink(p):
                os.chmod(p, 0o755)

    print("装配完成: 新建=%(c)d 跳过=%(s)d 符号链接=%(l)d 资源复制=%(p)d" % dict(c=created, s=skipped, l=relinked, p=copied))
    if symlink_plan:
        plan_path = os.path.join(os.path.dirname(os.path.abspath(args.manifest)), "symlink_plan.json")
        json.dump(symlink_plan, open(plan_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("  ! 本机未能创建符号链接 %d 条（已记录 %s；打包时以 manifest 为准）" % (len(symlink_plan), plan_path))
    print("bundle =", bundle)


if __name__ == "__main__":
    main()
