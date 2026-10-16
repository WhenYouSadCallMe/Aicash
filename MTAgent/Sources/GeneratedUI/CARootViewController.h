//
//  CARootViewController — 应用外壳容器（顶部标题 + 会话 / 设置 / 诊断 三个入口）
//  选择器原型取自 SPEC/method_types.json；本实现补全容器行为：
//    · 顶部标题栏（应用名 + 三个入口按钮）
//    · 内容子控制器（contentViewController）的装载/卸载与状态栏转发
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CARootViewController;

@class UIViewController;

@interface CARootViewController : UIViewController
    - (id)childViewControllerForHomeIndicatorAutoHidden;
    - (id)childViewControllerForStatusBarHidden;
    - (id)childViewControllerForStatusBarStyle;
    - (UIViewController *)contentViewController;
    - (id)initWithContentViewController:(id)arg1;
    - (void)setContentViewController:(id)arg1;
    - (bool)shouldAutorotate;
    - (unsigned long long)supportedInterfaceOrientations;
    - (void)viewDidLoad;

#pragma mark - 外壳补全（使用面）

/// 默认启动外壳：内容区为会话页，顶部提供 会话 / 设置 / 诊断 入口
+ (instancetype)launcherRootViewController;

/// 弹出设置页（与 mtagent://settings 等价）
- (void)presentSettings;

/// 弹出诊断页（与 mtagent://diagnostics 等价）
- (void)presentDiagnostics;

@end

NS_ASSUME_NONNULL_END
