# MT Agent 复刻版（MT-Agent-v1.0.2-Lite.tipa）

对 `MT-Agent-v1.0.2-Lite.tipa`（`wiki.qaq.codexapp`，产品名 **MT 智能体**）的**功能与权限全等价复刻**。
本工程的目标是"行为一致、权限一致、布局一致"，**不做任何安全加固或权限收窄**。

## 目录结构

```
MTAgent-Replica/
├── MTAgent/                      主 app 目标
│   ├── Info.plist                与原包逐键一致（含 CARuntimeManifestURL / URL scheme / 文档类型 / 后台模式）
│   ├── entitlements.plist        与原包 entitlements.plist 完全一致（11 项）
│   ├── ResignEntitlements/       运行时代码重签用的两套 entitlements（取自原二进制内嵌 XML）
│   └── Sources/                  实现（ObjC/ARC）
├── MTShareExtension/             分享扩展（与扩展 Info.plist 一致，PrincipalClass=CAMTShareViewController）
├── OriginalAssets/               原包可直接复用的资产（资源 + 第三方二进制），用于装配 bundle
├── SPEC/
│   ├── assets/                   原包对齐基线：全部字符串、ObjC 类/方法映射、契约分组、原始二进制、zip 布局
│   └── 复刻规格书.md              逐项契约说明（端点/字段/路径/defaults 键/CLI 参数/日志文案）
├── build/
│   ├── Makefile                  macOS 无 Xcode 工程构建（clang + iPhoneOS SDK）
│   ├── assemble_bundle.py        按原包清单装配资源与符号链接
│   ├── package_tipa.py           生成 .tipa（条目顺序/权限位/符号链接与原包一致）
│   └── bundle_manifest.json      装配清单（由原包 zip 实测生成：79 条，含 0o755/0o644 与链接目标）
├── verify/verify_parity.py       与原包的一致性校验（可直接运行）
└── scripts/                      分析/提取脚本（entitlements 模板、清单生成）
```

## 构建（在 macOS 上）

```bash
brew install ldid                      # 或使用 Theos 自带的 ldid
make -C build                          # 编译 CodexApp + ca-filetool + MTShareExtension 并装配 bundle
make -C build package                  # 生成 build/MT-Agent-replica.tipa
```

### 没有 Mac：用 GitHub Actions 构建（推荐）

仓库内置流水线 [`.github/workflows/build-tipa.yml`](.github/workflows/build-tipa.yml)，在 GitHub 的 `macos-14` runner 上完成"编译 → 签名 → 打包 → 校验 → 上传产物"：

1. 把本工程推到 GitHub（私有仓库也可以）；
2. 打开 **Actions → build-tipa → Run workflow**（或向 `main` push 自动触发）；
3. 运行结束后在 **Artifacts** 下载 `MT-Agent-replica-<run号>`，里面含：
   - `build/MT-Agent-replica.tipa`（可直接丢给 TrollStore 安装）
   - `build/out/Payload/CodexApp.app/**`（解包后的 bundle，便于核对布局）
   - `build_*.log`（编译/签名/打包日志）与 `SPEC/*.json`（覆盖度、前向声明、校验汇总）
4. Job 摘要页会显示产物大小、主程序 `file` 信息、装配条目数，以及编译警告/错误前 40 行——**编译报错就把这段贴回来，我据此修到全绿**。

签名说明：CI 里 `ldid -S<entitlements>` 保留原包全部特权；若 runner 上 `ldid` 安装失败会自动回退 `codesign --force --sign - --entitlements`（adhoc）。普通签名会剥离 `platform-application` 等特权，**不要**用 Xcode 的自动签名重签本工程产物。

构建要点：

* **不需要 Xcode 工程**：`build/Makefile` 直接用 `xcrun --sdk iphoneos clang` 编译 arm64 / iOS 15 目标；这与原包自带 Theos makefile 工具链的形态一致。
* **多调用（multi-call）主程序**：`Helpers/bash`、`Helpers/sh`、`Helpers/bash-codex` 是指向 `../CodexApp` 的符号链接；主程序按 `argv[0]` 分派到 bash.real / codex / ca-filetool。
* **`build/bundle_manifest.json`** 是从原包 zip 实测导出的装配清单（顺序、权限位、符号链接目标全部照抄），`assemble_bundle.py` 与 `package_tipa.py` 都按它执行。
* `Helpers/bash.real` 与 `Helpers/codex-sign` 是从原包复用的第三方二进制（bash 为 GPL，随包已含 `ThirdPartyNotices/Bash.txt`；codex-sign 基于 ChOma + FastPathSign + OpenSSL，同目录含相应 notice）。
* 签名：`ldid -S<entitlements>`（TrollStore 生态常用），无 ldid 时回退 `codesign --force --sign - --entitlements`。

## 一致性校验（三层，均可复跑）

```bash
python verify/verify_parity.py      # ① 工程 vs 原包：plist / entitlements / 重签模板 / 布局 / 资源哈希 / 核心类
python scripts/check_sources.py     # ② 源码自检：头文件引用、括号平衡、@interface 与 @implementation 配对
python build/package_tipa.py ...    # ③ 装配 + 打包（可由 make package 触发）
python verify/verify_package.py     # ④ 产物 vs 原包：条目顺序/种类/权限/符号链接/资源内容哈希
```

已在本机（Windows）跑通的实测结果：

| 校验 | 结果 |
|---|---|
| ① `verify_parity.py` | 10/10 通过：Info.plist（主 app 21 键 / 扩展）语义一致、entitlements 11 项完全一致、两套重签模板命中原包内嵌 XML、Helper+资源布局 77 条零差异、29 个资源 SHA256 一致 |
| ③+④ 打包链路 | 生成 `build/MT-Agent-replica.tipa`：条目 79、顺序与原包一致、布局逐条比对 0 异常、资源内容哈希 31 个文件全一致 |

> 说明：Windows 侧跑通的是"装配 + 打包 + 校验"链路（`CodexApp`/`ca-filetool`/`MTShareExtension` 三个可执行体为占位，实际构建需在 macOS 用 `make -C build` 由 clang 产出）。

## 与原包的已知差异（如实记录）

| 项目 | 状态 |
|---|---|
| Bundle 身份（id / 名称 / 版本 / URL scheme / 文档类型 / 后台模式 / 查询 scheme） | 一致（Info.plist 逐键校验通过） |
| entitlements | 一致（11 项，逐项校验通过） |
| Helper 布局与符号链接目标 | 一致（77 条，逐条校验通过） |
| 资源（cacert.pem、models.json、fallback prompt、Mermaid、ThirdPartyNotices、图标） | 一致（SHA256 逐一校验通过） |
| 远端契约（Supabase 端点/JWT/UA/心跳 8 字段/策略 select 列表） | 一致（见规格书，取自反编译） |
| codex CLI 契约（app-server --stdio、-c 覆盖集、login 四种方式、exec 回退） | 一致（参数与字面量照抄） |
| 密钥存储方式（明文文件 + 旧 Keychain 条目清理） | 一致（按原设计复刻，未改动） |
| UI 交互细节 | **近似**：原包 UI 由数百个未公开的 CA* 视图类组成，本复刻按符号名重建了主要界面（聊天/设置/日志/诊断），像素级排版不保证 |
| 视频/音频/相机等边缘功能 | 近似（保留相同权限声明与入口） |
| `Helpers/codex-sign`、`Helpers/bash.real` | 直接复用原包二进制（重建需上游 ChOma/FastPathSign/OpenSSL 与 bash 源码） |
| 扩展 entitlements | 原包未附该文件，本工程按主 app 特权集 + app-group 对齐；如从设备侧 `codesign -d --entitlements :- Payload/CodexApp.app/PlugIns/MTShareExtension.appex/MTShareExtension` 得到不同集合，请按实测更新 |

## 许可与来源

* `OriginalAssets/` 内的二进制与资源来自原包本身，仅用于复刻装配与一致性校验；第三方组件的许可文本随包保留在 `ThirdPartyNotices/`。
* `SPEC/assets/` 是从原包提取的静态分析产物（字符串、符号、契约），供对齐与审计使用。

## 内核（Helpers/codex）

复刻包当前不含 245MB 的 codex 内核二进制。用 uild-kernel-ios 工作流
（Actions → Run workflow，codex_ref 如 ust-v0.162.1）交叉编译
openai/codex 到 aarch64-apple-ios，产物回传到 dist-kernel 分支 Kernel/dist/codex：

```bash
git fetch origin dist-kernel
git show dist-kernel:Kernel/dist/codex > codex
```

补丁放 Kernel/patches/*.patch，详见该目录 README。