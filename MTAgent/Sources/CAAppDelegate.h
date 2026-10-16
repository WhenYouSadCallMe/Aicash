//
//  CAAppDelegate.h — 应用入口（目录准备 / 日志会话 / 远端策略 / 运行时清单 / 内嵌 MCP 桥）
//
//  原包符号对齐：-[CAAppDelegate application:didFinishLaunchingWithOptions:]、
//  -application:openURL:options:、-remoteOperationsDidChange:、-runtimeCatalogDidChange:、
//  -codexRuntimeDidChangeForCatalog:、-workspaceDidChangeForCatalogPrewarm:、
//  -prewarmComposerCatalogWithReason:force:、-lastCatalogRuntimeSignature / -setLastCatalogRuntimeSignature:
//
//  选择器索引（逐字，供符号核对）：
//    -application:didFinishLaunchingWithOptions:
//    -application:didRegisterForRemoteNotificationsWithDeviceToken:
//    -application:didReceiveRemoteNotification:fetchCompletionHandler:
//    -application:handleActionWithIdentifier:forRemoteNotification:completionHandler:
//    -application:openURL:options:
//    -remoteOperationsDidChange:  -runtimeCatalogDidChange:  -codexRuntimeDidChangeForCatalog:
//    -workspaceDidChangeForCatalogPrewarm:  -managedRuntimeDidChangeForPrompt:
//    -prewarmComposerCatalogWithReason:force:
//    -lastCatalogRuntimeSignature  -setLastCatalogRuntimeSignature:
//

#import <UIKit/UIKit.h>

@class CAChatViewController;

NS_ASSUME_NONNULL_BEGIN

@interface CAAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, strong, nullable) CAChatViewController *chatViewController;

/// 最近一次运行时清单签名（runtimeID@version|…），用于判断是否需要预热 composer 目录
@property (nonatomic, copy, nullable) NSString *lastCatalogRuntimeSignature;

/// 最近一次“运行时来源提示”签名（原包 ivar: _lastRuntimeSourceNoticeSignature）
@property (nonatomic, copy, nullable) NSString *lastRuntimeSourceNoticeSignature;

/// 是否已经展示过“必需运行时缺失”提示（原包 ivar: _requiredRuntimePromptShown）
@property (nonatomic, assign) BOOL requiredRuntimePromptShown;

#pragma mark - 通知回调（原包同名入口）

- (void)remoteOperationsDidChange:(NSNotification *)notification;
- (void)runtimeCatalogDidChange:(NSNotification *)notification;
- (void)codexRuntimeDidChangeForCatalog:(NSNotification *)notification;
- (void)workspaceDidChangeForCatalogPrewarm:(NSNotification *)notification;
- (void)managedRuntimeDidChangeForPrompt:(NSNotification *)notification;

#pragma mark - 预热

- (void)prewarmComposerCatalogWithReason:(NSString *)reason force:(BOOL)force;


// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)prepareTheosRuntimeIfAuthorized;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
