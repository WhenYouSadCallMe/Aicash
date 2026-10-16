//
//  MTGeneratedArtifactOpen — 产物打开动作（原包零细节符号）
//  封装"按文件类型选择打开方式"：文本/图片用 QuickLook，其余用 UIDocumentInteractionController / 分享面板。
//

#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>

NS_ASSUME_NONNULL_BEGIN

/// 静态工具：URL 是否可预览（QuickLook 支持的类型）
BOOL MTArtifactOpenCanPreviewURL(NSURL *url);

/// 顶层 VC（keyWindow 场景兜底）
UIViewController *MTArtifactOpenTopViewController(void);

@interface MTGeneratedArtifactOpen : NSObject

/// 展示本地文件（QuickLook 预览，失败回退分享面板）
+ (void)openFileAtPath:(NSString *)path fromViewController:(nullable UIViewController *)sender;

/// 分享面板（文件 + 可选备注文本）
+ (void)shareFileAtPath:(NSString *)path text:(nullable NSString *)text fromViewController:(nullable UIViewController *)sender;

/// 剪贴板复制路径
+ (void)copyPath:(NSString *)path;

@end

/// 轻量 QuickLook 容器
@interface MTGeneratedArtifactPreviewController : QLPreviewController <QLPreviewControllerDataSource>
@property (nonatomic, copy, nullable) NSString *previewPath;
@end

NS_ASSUME_NONNULL_END
