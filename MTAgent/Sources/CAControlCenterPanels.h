//
//  CAControlCenterPanels.h — 复刻补全面板的统一入口注册
//
//  背景：这一批面板（Git / 模型 / 扩展 / 计划审批 / 存储 / 文本 …）在原包里由会话页、设置页、
//  侧边栏多处入口分别打开。复刻工程在补齐这些面板时，为了不动大文件、也为了让每个面板都能被
//  真实点到，统一在本文件里做「构造函数 + 入口注册」：
//
//    · +panelCenterViewControllerForWorkspace:  一个面板中心列表（按分组列出全部面板）
//    · 各 +xxxViewControllerWith…               构造单个面板（带默认数据源/回调）
//    · +presentPanel:from:                      统一 present（自动包 UINavigationController）
//
//  入口位置：各面板的自然入口（会话页顶栏 Git、输入框模型胶囊、设置页的
//  模型价格 / Agent 身份 / 子代理设置 / 存储管理 / Skills 与扩展）。
//  注：`+panelCenterViewControllerForWorkspace:` 这个聚合列表**不再从设置页暴露**
//  （截图 04/05 里设置页只有官方账户 / AI 服务 / 应用 / 开发环境与诊断四段），
//  工厂方法本身保留，给需要的调用方直接用。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAControlCenterPanels : NSObject

#pragma mark - 面板构造（统一数据源与回调）

/// Git 变更面板（工作区为空时取 defaults CodexActiveWorkspace）
+ (UIViewController *)gitChangesViewControllerForWorkspace:(nullable NSString *)workspacePath;

/// 模型选择（选中后写 defaults，并回调 (slug, thirdParty)）
+ (UIViewController *)modelPickerViewControllerWithSelection:(nullable void (^)(NSString *slug, BOOL thirdParty))selection;

/// 模型价格
+ (UIViewController *)modelPricingViewController;

/// Agent 身份
+ (UIViewController *)agentProfileViewController;

/// Agent 运行状态详情
+ (UIViewController *)agentStatusDetailViewController;

/// 产物预览（path 为空时自动挑一个工作区内真实存在的文件）
+ (UIViewController *)artifactPreviewViewControllerForPath:(nullable NSString *)path;

/// 扩展列表（kind：skill / mcp / prompt / plugin / memory）
+ (UIViewController *)extensionListViewControllerWithKind:(NSString *)kindName;

/// Skills 与扩展入口页
+ (UIViewController *)extensionsViewController;

/// 目录选择器（缺省从 Documents 开始）
+ (UIViewController *)pathPickerViewControllerFrom:(nullable NSString *)path
                                    onSelect:(nullable void (^)(NSString *directory))onSelect;

/// 审批 / 计划确认对话框（带一份可直接操作的演示问题）
+ (UIViewController *)planDecisionDemoViewController;

/// 计划审阅（带一份演示计划）
+ (UIViewController *)planReviewDemoViewController;

/// 项目指令（各工作区的 AGENTS.md）
+ (UIViewController *)projectInstructionsViewController;

/// 存储管理
+ (UIViewController *)storageViewController;

/// 子代理设置
+ (UIViewController *)subagentSettingsViewController;

/// 文本详情（展示一段只读文本）
+ (UIViewController *)textDetailViewControllerWithTitle:(NSString *)title text:(NSString *)text;

/// 文本编辑器（打开/新建一个真实文件）
+ (UIViewController *)textEditorViewControllerForPath:(nullable NSString *)path title:(nullable NSString *)title;

/// 应用外壳容器（会话 / 设置 / 诊断 三入口）
+ (UIViewController *)rootShellViewController;

#pragma mark - 入口注册

/// 面板中心列表：按分组列出全部复刻补全面板，点按即用
+ (UIViewController *)panelCenterViewControllerForWorkspace:(nullable NSString *)workspacePath;

/// 统一 present（自动包一层 UINavigationController；已在 present 中则走 push）
+ (void)presentPanel:(UIViewController *)panel from:(UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
