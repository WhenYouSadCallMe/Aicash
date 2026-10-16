# UI 还原基准（从 7 张真机截图量出来的硬数据）

数据来源：`参考截图/01..07`（1179×2556 px，3x → 逻辑 393×852 pt），
提取脚本：`_cakit/palette.py`（配色）、`_cakit/metrics.py`（版式带），
落盘结果：`SPEC/设计令牌_取自截图.json`。

## 1. 结论先行

原版界面**就是标准 iOS 组件**，不是自绘皮肤：

- 颜色全是系统色（systemBlue / systemOrange / systemGreen / systemGray / 系统分组背景）；
- 分组卡片是 **`UITableView.StyleInsetGrouped`（insetGrouped）** 的默认外观（页底 #F2F2F7、卡片 #FFFFFF、分隔线 systemGray5、圆角 10pt、左右 16pt 内缩）；
- 图标全部是 **SF Symbols**（线型、weight 常规），没有图片资源；
- 字体是系统字体（标题 `.headline/.body`、副标题 `.subheadline`、分组标题 `.footnote` 大写前的小标题样式）；
- 行高是系统默认（两行副标题行 ≈ 60pt，单行 ≈ 44pt）。

因此还原的正确做法是：**用 UIListContentConfiguration / UICollectionLayoutListConfiguration 写 insetGrouped 列表 + SF Symbols + 系统色**，
而不是手绘 Card View。用标准组件，视觉自动对齐（这也是“一摸一样”最省事的路径）。

## 2. 实测配色

| 语义 | 截图实测（JPEG 有压缩偏移） | 应采用 |
|---|---|---|
| 页面背景 | `#F0F0F0` | `UIColor.systemGroupedBackground`（#F2F2F7） |
| 卡片 / 输入框 / 浮层 | `#F8F8F8` | `UIColor.secondarySystemGroupedBackground`（#FFFFFF） |
| 主文字 | `#000000` | `.label` |
| 次要文字 / 副标题 | `#888888` `#909090` | `.secondaryLabel`（#3C3C43 60%） |
| 分隔线 | `#E8E8E8` `#E0E0E0` | `.separator` / `.opaqueSeparator` |
| 强调蓝（图标 / `全部暂存` / `master` 药丸底） | `#0078F8` `#0080F0` | `UIColor.systemBlue`（#007AFF） |
| 橙点（未暂存的更改） | `#F88800` `#F89000` | `UIColor.systemOrange`（#FF9500） |
| 绿标（未跟踪胶囊底） | `#B0F8C8` `#B8F8D0` | `.systemGreen` 的 15~20% 透明度底 + 深绿字 |
| 红角标（分支 99+） | `#F83028` | `UIColor.systemRed`（#FF3B30） |
| 抽屉遮罩 | 叠加后 `#A81818` 系（底色被压暗） | 黑色 35~40% 透明度 scrim |

> 02 抽屉截图里量到的 `#A81818` 是**遮罩叠加**结果，不是界面配色，别当成红色主题。

## 3. 实测版式（逻辑 pt，y 从屏幕顶算）

**01 主会话页·空态**
| 元素 | y 区间 (pt) | 说明 |
|---|---|---|
| 状态栏 | 22–36 | —— |
| 顶部图标行 | 66–85 | 左＝侧栏切换图标；右＝git 分支图标 + 红角标 `99+` |
| 终端图标 `>_` | 238–272 | 空态 hero 图标，约 34pt |
| 标题 `今天想完成什么?` | 295–317 | 字高 ≈22pt → 系统 `.largeTitle`/28pt bold 量级 |
| 建议卡 1/2/3 文案 | 395–414 / 448–469 / 503–522 | 行距 ≈53pt，三张等高白卡，卡片内左图标 + 左对齐文字 |
| 协作药丸 `Agent 协作就绪` | 778–790 | 左电闪图标（蓝）+ 药丸 + 右垃圾桶 |
| 输入卡 | 713–809 | 卡内首行 `上下文 0% · 缓存 —`，其下按钮行 `+` `/` `6.1-Sol ⌄` `High ⌄` + 发送圆钮 |
| Home 指示条 | 839–844 | —— |

**06/07 Git 面板**
| 元素 | y 区间 (pt) | 说明 |
|---|---|---|
| 标题 `Git` | 63.7–86.3 | 居中；左 X 圆钮，右 `⋯` 圆钮 + 刷新图标 |
| `Documents` | 129–141.3 | 摘要卡内，17pt semibold |
| `未设置上游 · 尚无提交` | 189.7–202 | 13pt 次要文字 |
| `未暂存的更改` | 344.7–358.3 | 分组标题 + 计数胶囊 `24154` + 右 `全部暂存 ⌄` |
| 文件行 1..6 | 389.7 / 450.3 / 510.7 / 571 / 631.3 / 691.7 | **行距 60.3pt**（两行行：文件名 17pt + 路径 13pt） |
| 底部固定条 | 715–755 | 分段 `全部更改 24154` \| `仅已暂存 0`；再下一行输入框 `这次修改了什么?` + `提交` |
| Home 指示条 | 839–844 | —— |

## 4. 落地检查单（写代码时逐条对照）

- [ ] 列表用 `UICollectionLayoutListConfiguration(appearance: .insetGrouped)` 或 `UITableView(style: .insetGrouped)`；
- [ ] 分组标题用 `.groupedHeader` 外观（自动小写灰字 `官方账户` / `AI 服务` / `应用` / `开发环境与诊断` / `全部工作区`）；
- [ ] 每个 cell 用 `UIListContentConfiguration.valueCell()` 填 `text` / `secondaryText` / `image`（image 用 SF Symbol）；
- [ ] 数值在右的用 `.valueCell` 自动右对齐 + 系统 chevron（`.cell` accessory = `.disclosureIndicator`）；
- [ ] 开关行用 `accessories = [.disclosureIndicator, .switch]`（或自绘 UISwitch 在 `accessoryView`）；
- [ ] 分段（`系统/浅色/深色`、`详细/简洁`）用 `UISegmentedControl` 放进 `accessoryView`，宽度自适应；
- [ ] 固定底栏（Git 面板提交栏、主会话输入卡）用 `keyboardLayoutGuide`/`safeAreaLayoutGuide` 固定，列表 `contentInset.bottom` 让开；
- [ ] 顶部导航栏固定不透明（截图 05 里 `主题` 行被裁切 = 内容从导航栏下方滚过）；
- [ ] 全部文案逐字：跑 `python3 scripts/check_screenshot_literals.py`，必须 `87/87`。
