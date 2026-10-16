//
//  MTLocalArtifactPreview — 本地文件预览容器（原包零细节符号）
//  WKWebView 承载文本/HTML/图片，PDF 等走 QuickLook。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTLocalArtifactPreview : UIView

/// 当前预览的本地文件路径
@property (nonatomic, copy, readonly, nullable) NSString *previewPath;

/// 加载失败回调（主线程）
@property (nonatomic, copy, nullable) void (^loadFailure)(NSString *message);

- (instancetype)initWithFrame:(CGRect)frame;

/// 加载本地文件（文件缺失触发 loadFailure）
- (void)loadFileAtPath:(NSString *)path;

/// 释放 WebView 内容（cell 复用时调用）
- (void)reset;

/// 该路径是否可由本视图预览
+ (BOOL)canPreviewPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
