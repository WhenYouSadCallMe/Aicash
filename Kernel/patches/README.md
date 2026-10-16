# Kernel/patches — iOS 交叉编译补丁

CI 按**文件名编号顺序** `git apply`（见 `.github/workflows/build-kernel-ios.yml`），失败即中断。

## 补丁规范
- 每个补丁只解决一类问题：`0001-ios-cfg-stubs.patch`、`0002-ios-no-fork.patch` …
- 头部注释写明：影响范围、是否影响其他平台、来源。
- 任何 `git apply` 失败都要让 CI 报错，禁止静默跳过。

## 常见补丁内容
| 问题 | 处理 |
|---|---|
| 缺 `/proc`、`sysctl` 部分字段 | `#[cfg(target_os = "ios")]` 打桩返回默认值 |
| 无 `fork` | 改用 `posix_spawn`，避免 `fork+exec` |
| signal/SIGCHLD 差异 | 降级为轮询 `waitpid` |
| 沙盒路径假设 | 全部改读 `CODEX_HOME` 环境变量 |
| TLS 证书校验失败 | 设置 `SSL_CERT_FILE` 指向内置 cacert.pem |

## 迭代方法
首次运行 CI 必然失败（正常）。把完整错误日志交给编码模型，用分片提示词
（一次只修一批错误，输出 unified diff），存为下一个编号补丁后 push 重跑。
若 2 周内仍编不过，回退方案：直接取 susu123oss/CodexApp-Runtime Release 的
`wiki.qaq.codex_0.162.1-3_iphoneos-arm64.deb` 作内核（需保留来源声明）。
