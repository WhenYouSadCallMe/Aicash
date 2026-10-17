#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""截图字面量门禁。

依据 7 张 tipa 真机截图（参考截图/01..07）逐字提取的 UI 文案，
逐条在 MTAgent/Sources 下做**逐字**匹配；缺任何一条即失败（退出码 1）。

用法：
    python3 scripts/check_screenshot_literals.py            # 检查，缺项打印清单
    python3 scripts/check_screenshot_literals.py --list     # 只打印全部字面量
    python3 scripts/check_screenshot_literals.py --json out.json
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "MTAgent", "Sources")

# ---------------------------------------------------------------------------
# 按屏分组的逐字面量（严格照抄截图；半角/全角、·/—/…/“ ” 一律保持原样）
# ---------------------------------------------------------------------------
SCREENS: dict[str, list[str]] = {
    "01 主会话页·空态": [
        "今天想完成什么？",                     # 全角问号（原包字符串）
        "从理解项目到交付代码",
        "在当前工作区开始一个任务",
        "了解这个项目",
        "检查代码问题",
        "实现一个功能",
        "Agent 协作就绪",
        "上下文 0%",
        "缓存 —",                              # 全角破折号
        "6.1-Sol",
        "High",
    ],
    "02 左侧抽屉": [
        "MT 智能体",
        "新对话",
        "还没有项目工作区",
        "点击左上角选择或新建项目",
        "个人中心",
        "登录账户",
        "套餐余量",
        "暂未获取",
        "主限额",
        "次限额",
    ],
    "03 工作区 sheet": [
        "工作区",
        "打开文件夹",
        "选择已有项目",
        "新建项目",
        "在 Documents 中创建",
        "全部工作区",
        "还没有添加项目。打开已有文件夹或新建项目后，会出现在这里。",
    ],
    "04 设置页·上半": [
        "设置",
        "官方账户",
        "登录方式",
        "选择登录方式",
        "AI 服务",
        "第三方 AI 服务",
        "未配置",
        "模型价格",
        "官方 8 · API 0",
        "地址和 Key 在编辑结束后自动保存。启用第三方服务会保留官方登录，随时可以切回。",
        "应用",
        "主题",
        "系统",
        "浅色",
        "深色",
        "对话显示",
        "详细",
        "简洁",
        "Agent 身份",
        "子代理设置",
        "模型与思考强度",
        "存储管理",
        "安全清理缓存",
        "开发环境与诊断",
        "Codex",
    ],
    "05 设置页·下半": [
        "当前已是最新 · 295.9 MB",
        "Theos",
        "未安装 · 点击安装 · 224.4 MB",
        "Tools",
        "3 个工具包 · 点击展开",
        "Skills 与扩展",
        "指令、Skills、提示词与插件",
        "运行诊断",
        "核心组件与工具链",
        "日志",
        "查看、筛选与复制",
    ],
    "06/07 Git 面板": [
        "Git",
        "Documents",
        "未设置上游 · 尚无提交",
        "添加远程",
        "master",
        "获取",
        "拉取",
        "推送",
        "还没有远程仓库。点击“添加远程”填写 HTTPS 地址后，即可推送提交。",
        "未暂存的更改",
        "全部暂存",
        "24154",
        "未跟踪",
        "项目根目录",
        "AIAnalysisHistory/com.bilibili.nddz",
        ".mt-device-group-id-v1",
        "全部更改",
        "仅已暂存",
        "这次修改了什么？",                      # 全角问号（原包字符串）
        "提交",
        "暂存全部更改",                          # 07 浮层菜单
        "管理分支",
        "还原已跟踪文件…",                       # 单字符省略号
    ],
}


def read_sources() -> str:
    blob = []
    for path in glob.glob(os.path.join(SOURCES, "**", "*.m"), recursive=True):
        try:
            with open(path, encoding="utf-8", errors="ignore") as fh:
                blob.append(fh.read())
        except OSError:
            continue
    for path in glob.glob(os.path.join(SOURCES, "**", "*.h"), recursive=True):
        try:
            with open(path, encoding="utf-8", errors="ignore") as fh:
                blob.append(fh.read())
        except OSError:
            continue
    return "\n".join(blob)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="只打印字面量清单")
    ap.add_argument("--json", metavar="PATH", help="把缺口写进 JSON")
    args = ap.parse_args()

    total = sum(len(v) for v in SCREENS.values())
    if args.list:
        for screen, items in SCREENS.items():
            print(f"[{screen}]")
            for s in items:
                print("   ", s)
        print(f"\n共 {total} 条")
        return 0

    blob = read_sources()
    missing: dict[str, list[str]] = {}
    for screen, items in SCREENS.items():
        lack = [s for s in items if s not in blob]
        if lack:
            missing[screen] = lack

    hit = total - sum(len(v) for v in missing.values())
    for screen, items in SCREENS.items():
        lack = missing.get(screen, [])
        mark = "OK " if not lack else "缺 "
        print(f"{mark}[{screen}] {len(items) - len(lack)}/{len(items)}")
        for s in lack:
            print(f"      - {s}")
    print(f"\n截图字面量命中 {hit}/{total}")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(missing, fh, ensure_ascii=False, indent=1)

    if missing:
        print("\n缺失文案对应的界面区域还没落地 —— 逐字补齐后重跑。")
        return 1
    print("全部逐字命中 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
