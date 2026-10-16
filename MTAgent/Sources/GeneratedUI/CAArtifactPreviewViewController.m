//
//  CAArtifactPreviewViewController — 产物预览面板
//
//  真实数据来源：磁盘上的产物文件本身（-path），信息条里的相对路径基于 CARuntimePaths.documentsDirectory。
//  按扩展名分流：
//    · png/jpg/jpeg/gif/webp/heic → UIScrollView + UIImageView（捏合 / 双击缩放）
//    · txt/md/json/log/py/js/ts/swift/m/h/hpp/c/cpp/sh/yml/yaml/toml/plist/xml/css → 只读 UITextView（等宽字体）
//    · html → WKWebView（只放行 file: / about: 导航，外链交给系统浏览器）
//    · mp3/m4a/wav/mp4/mov/m4v → AVPlayerViewController
//    · 其他 → QLPreviewController
//

#import "CAArtifactPreviewViewController.h"
#import "CARuntimePaths.h"
#import "CACommon.h"
#import "CAGitChipLabel.h"   // 原包的类型标签控件（已实现为 UILabel 子类）；本页 statusChip 用等价的轻量 UILabel 承载
#import <AVFoundation/AVFoundation.h>
#import <QuickLook/QuickLook.h>
#import <dlfcn.h>

#if __has_include(<WebKit/WebKit.h>)
#import <WebKit/WebKit.h>
#define CA_ARTIFACT_HAS_WEBKIT_HEADERS 1
#else
// 本机自检用 SDK 未随附 WebKit.framework/Headers（CI 用完整 Xcode SDK 时会命中上一分支）
#define CA_ARTIFACT_HAS_WEBKIT_HEADERS 0
#endif

/// WKWebView 的最小接口声明：只声明真正用到的选择器，
/// 运行期用 NSClassFromString(@"WKWebView") 取系统实现（两种 SDK 环境都能编译，行为一致）。
@protocol CAArtifactWebViewAPI <NSObject>
- (instancetype)initWithFrame:(CGRect)frame configuration:(id)configuration;
- (id)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;
- (void)setNavigationDelegate:(id)delegate;
@end

/// AVKit 的 AVPlayerViewController 最小接口：main binary 没有链接 AVKit（见 build/Makefile 的 framework 列表），
/// 因此按类名在运行期取，避免产生链接期未定义符号。
@protocol CAArtifactPlayerControllerAPI <NSObject>
- (void)setPlayer:(AVPlayer *)player;
@end

static NSSet<NSString *> *CAArtifactImageExtensions(void)
{
    return [NSSet setWithArray:@[ @"png", @"jpg", @"jpeg", @"gif", @"webp", @"heic" ]];
}

static NSSet<NSString *> *CAArtifactTextExtensions(void)
{
    return [NSSet setWithArray:@[ @"txt", @"md", @"json", @"log", @"py", @"js", @"ts", @"swift", @"m", @"h",
                                  @"hpp", @"c", @"cpp", @"sh", @"yml", @"yaml", @"toml", @"plist", @"xml", @"css" ]];
}

static NSSet<NSString *> *CAArtifactMediaExtensions(void)
{
    return [NSSet setWithArray:@[ @"mp3", @"m4a", @"wav", @"mp4", @"mov", @"m4v" ]];
}

#if CA_ARTIFACT_HAS_WEBKIT_HEADERS
@interface CAArtifactPreviewViewController () <QLPreviewControllerDataSource, WKNavigationDelegate>
#else
@interface CAArtifactPreviewViewController () <QLPreviewControllerDataSource>
#endif
{
    NSString *_path;                          // -path / -setPath: 的真实存储
    AVPlayerViewController *_playerController;
    QLPreviewController *_quickLookController;
    id _shareItem;
    WKWebView *_webView;
    AVPlayer *_player;                        // 播放器本体（AVFoundation 已链接）
    UIView *_infoBar;                         // 顶部信息条
    UIView *_contentView;                     // 内容容器
    UIImageView *_symbolView;                 // 类型图标
    UIImageView *_placeholderIconView;
    UILabel *_nameLabel;
    UILabel *_detailLabel;
    UILabel *_statusChip;                     // 扩展名 / 大小标签
    UILabel *_placeholderLabel;
    UILabel *_noticeLabel;
    UITextView *_textView;
    UIScrollView *_scrollView;
    UIImageView *_imageView;
}

#pragma mark - 私有辅助（界面搭建，不属于原包选择器）

- (BOOL)artifactExists;
- (void)buildInfoBar;
- (void)buildContentView;
- (void)pinViewToContent:(UIView *)view;
- (void)showPlaceholderMessage:(NSString *)message;
- (void)showNotice:(NSString *)notice;
- (void)buildImagePreview;
- (void)buildTextPreview;
- (void)buildWebPreview;
- (void)buildMediaPreview;
- (void)buildQuickLookPreview;
- (NSString *)typeSymbolName;
- (NSString *)relativeDocumentsPath;
- (NSString *)fileSizeText;
- (void)handleImagePinch:(UIPinchGestureRecognizer *)sender;
- (void)handleImageDoubleTap:(UITapGestureRecognizer *)sender;

@end

@implementation CAArtifactPreviewViewController

#pragma mark - 关闭 / 分享

- (void)close
{
    UINavigationController *navigation = self.navigationController;
    if (navigation && navigation.viewControllers.firstObject != self) {
        [navigation popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shareFile
{
    id item = _shareItem;
    if (!item) {
        CALog(CALogLevelWarn, @"GENERAL", @"artifact share skipped, no item path=%@", _path ?: @"(none)");
        return;
    }

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ item ]
                                                                          applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.view;
    activity.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:activity animated:YES completion:nil];
    CALog(CALogLevelInfo, @"GENERAL", @"artifact shared path=%@", _path ?: @"(none)");
}

#pragma mark - 构造

- (id)initWithPath:(id)arg1
{
    self = [super init];
    if (self) {
        _path = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : nil;
    }
    return self;
}

#pragma mark - QuickLook

- (signed long long)numberOfPreviewItemsInPreviewController:(id)arg1
{
    return [self artifactExists] ? 1 : 0;
}

- (id)previewController:(id)arg1 previewItemAtIndex:(id)arg2
{
    // NSURL 本身已符合 QLPreviewItem，直接给文件 URL 即可
    if (!_path.length) return nil;
    return [NSURL fileURLWithPath:_path];
}

#pragma mark - getter / setter

- (NSString *)path
{
    return _path;
}

- (void)setPath:(id)arg1
{
    _path = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : nil;
}

- (id)playerController
{
    return _playerController;
}

- (void)setPlayerController:(id)arg1
{
    _playerController = [arg1 isKindOfClass:UIViewController.class] ? (AVPlayerViewController *)arg1 : nil;
}

- (QLPreviewController *)quickLookController
{
    return _quickLookController;
}

- (void)setQuickLookController:(id)arg1
{
    _quickLookController = [arg1 isKindOfClass:QLPreviewController.class] ? (QLPreviewController *)arg1 : nil;
}

- (id)shareItem
{
    return _shareItem;
}

- (void)setShareItem:(id)arg1
{
    _shareItem = [arg1 copy];
}

- (WKWebView *)webView
{
    return _webView;
}

- (void)setWebView:(id)arg1
{
    _webView = [arg1 isKindOfClass:UIView.class] ? (WKWebView *)arg1 : nil;
}

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = _path.lastPathComponent.length ? _path.lastPathComponent : @"产物预览";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(close)];

    [self buildInfoBar];
    [self buildContentView];

    if (![self artifactExists]) {
        [self showPlaceholderMessage:@"文件不存在或已被移动"];
        return;
    }

    self.shareItem = [NSURL fileURLWithPath:_path];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                           target:self
                                                                                           action:@selector(shareFile)];

    NSString *ext = _path.pathExtension.lowercaseString;
    if ([CAArtifactImageExtensions() containsObject:ext]) {
        [self buildImagePreview];
    } else if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) {
        [self buildWebPreview];
    } else if ([CAArtifactTextExtensions() containsObject:ext]) {
        [self buildTextPreview];
    } else if ([CAArtifactMediaExtensions() containsObject:ext]) {
        [self buildMediaPreview];
    } else {
        [self buildQuickLookPreview];
    }

    CALog(CALogLevelInfo, @"GENERAL", @"artifact preview opened ext=%@ path=%@", ext, _path);
}

- (void)viewDidAppear:(id)arg1
{
    BOOL animated = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES;
    [super viewDidAppear:animated];
    [_player play];
}

- (void)viewWillDisappear:(id)arg1
{
    BOOL animated = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES;
    [super viewWillDisappear:animated];
    [_player pause];
}

#pragma mark - WKWebView 导航策略

- (void)webView:(id)arg1 decidePolicyForNavigationAction:(id)arg2 decisionHandler:(id)arg3
{
    void (^handler)(NSInteger) = [arg3 isKindOfClass:NSClassFromString(@"NSBlock")] ? (void (^)(NSInteger))arg3 : nil;
    if (!handler) return;

    NSURL *url = nil;
    Class actionClass = NSClassFromString(@"WKNavigationAction");
    if (!actionClass || [arg2 isKindOfClass:actionClass]) {
        id request = [arg2 respondsToSelector:@selector(request)] ? [arg2 valueForKey:@"request"] : nil;
        if ([request isKindOfClass:NSURLRequest.class]) url = ((NSURLRequest *)request).URL;
    }

    NSString *scheme = url.scheme.lowercaseString ?: @"";
    BOOL allowed = (url == nil) || [scheme isEqualToString:@"file"] || [scheme isEqualToString:@"about"];
    if (allowed) {
        handler(0);   // WKNavigationActionPolicyAllow
        return;
    }

    // 外链（http/https/mailto…）不在预览里打开，交给系统
    handler(1);       // WKNavigationActionPolicyCancel
    CALog(CALogLevelInfo, @"GENERAL", @"artifact html external link scheme=%@ url=%@", scheme, url.absoluteString ?: @"");
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)webView:(id)arg1 didFailNavigation:(id)arg2 withError:(id)arg3
{
    NSError *error = [arg3 isKindOfClass:NSError.class] ? (NSError *)arg3 : nil;
    [self showNotice:[NSString stringWithFormat:@"网页预览失败：%@", error.localizedDescription ?: @"未知错误"]];
}

- (void)webView:(id)arg1 didFailProvisionalNavigation:(id)arg2 withError:(id)arg3
{
    NSError *error = [arg3 isKindOfClass:NSError.class] ? (NSError *)arg3 : nil;
    [self showNotice:[NSString stringWithFormat:@"网页加载失败：%@", error.localizedDescription ?: @"未知错误"]];
}

#pragma mark - 界面搭建

- (void)buildInfoBar
{
    _infoBar = [[UIView alloc] initWithFrame:CGRectZero];
    _infoBar.translatesAutoresizingMaskIntoConstraints = NO;
    _infoBar.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _infoBar.layer.cornerRadius = 14.0;
    _infoBar.layer.masksToBounds = YES;
    [self.view addSubview:_infoBar];

    _symbolView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolView.image = [UIImage systemImageNamed:[self typeSymbolName]];
    _symbolView.tintColor = UIColor.systemBlueColor;
    _symbolView.contentMode = UIViewContentModeScaleAspectFit;
    [_infoBar addSubview:_symbolView];

    _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _nameLabel.textColor = UIColor.labelColor;
    _nameLabel.text = _path.lastPathComponent.length ? _path.lastPathComponent : @"(未知文件)";
    [_infoBar addSubview:_nameLabel];

    _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _detailLabel.textColor = UIColor.secondaryLabelColor;
    _detailLabel.numberOfLines = 2;
    _detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _detailLabel.text = [self artifactExists]
        ? [NSString stringWithFormat:@"%@ · %@", [self relativeDocumentsPath], [self fileSizeText]]
        : @"文件不存在或已被移动";
    [_infoBar addSubview:_detailLabel];

    _statusChip = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusChip.translatesAutoresizingMaskIntoConstraints = NO;
    _statusChip.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightMedium];
    _statusChip.textColor = UIColor.secondaryLabelColor;
    _statusChip.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _statusChip.textAlignment = NSTextAlignmentCenter;
    _statusChip.layer.cornerRadius = 6.0;
    _statusChip.layer.masksToBounds = YES;
    _statusChip.text = [self artifactExists]
        ? [NSString stringWithFormat:@"%@ · %@",
           _path.pathExtension.length ? _path.pathExtension.uppercaseString : @"FILE",
           [self fileSizeText]]
        : @"丢失";
    [_infoBar addSubview:_statusChip];

    UILayoutGuide *margins = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_infoBar.topAnchor constraintEqualToAnchor:margins.topAnchor constant:8.0],
        [_infoBar.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_infoBar.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

        [_symbolView.leadingAnchor constraintEqualToAnchor:_infoBar.leadingAnchor constant:14.0],
        [_symbolView.centerYAnchor constraintEqualToAnchor:_infoBar.centerYAnchor],
        [_symbolView.widthAnchor constraintEqualToConstant:30.0],
        [_symbolView.heightAnchor constraintEqualToConstant:30.0],

        [_nameLabel.leadingAnchor constraintEqualToAnchor:_symbolView.trailingAnchor constant:10.0],
        [_nameLabel.topAnchor constraintEqualToAnchor:_infoBar.topAnchor constant:12.0],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusChip.leadingAnchor constant:-10.0],

        [_detailLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
        [_detailLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:3.0],
        [_detailLabel.bottomAnchor constraintEqualToAnchor:_infoBar.bottomAnchor constant:-12.0],

        [_statusChip.trailingAnchor constraintEqualToAnchor:_infoBar.trailingAnchor constant:-14.0],
        [_statusChip.centerYAnchor constraintEqualToAnchor:_infoBar.centerYAnchor],
        [_statusChip.heightAnchor constraintEqualToConstant:22.0],
        [_statusChip.widthAnchor constraintGreaterThanOrEqualToConstant:76.0],
    ]];
}

- (void)buildContentView
{
    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_contentView];

    UILayoutGuide *margins = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_contentView.topAnchor constraintEqualToAnchor:_infoBar.bottomAnchor constant:10.0],
        [_contentView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_contentView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_contentView.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-8.0],
    ]];

    // 空态 / 失败态占位（默认隐藏）
    _placeholderIconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _placeholderIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholderIconView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
    _placeholderIconView.tintColor = UIColor.tertiaryLabelColor;
    _placeholderIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_contentView addSubview:_placeholderIconView];

    _placeholderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholderLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _placeholderLabel.textColor = UIColor.secondaryLabelColor;
    _placeholderLabel.textAlignment = NSTextAlignmentCenter;
    _placeholderLabel.numberOfLines = 0;
    [_contentView addSubview:_placeholderLabel];

    // 底部提示条（网页预览失败等）
    _noticeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _noticeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _noticeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _noticeLabel.textColor = UIColor.systemRedColor;
    _noticeLabel.numberOfLines = 2;
    _noticeLabel.textAlignment = NSTextAlignmentCenter;
    _noticeLabel.hidden = YES;
    [_contentView addSubview:_noticeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_placeholderIconView.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor],
        [_placeholderIconView.centerYAnchor constraintEqualToAnchor:_contentView.centerYAnchor constant:-24.0],
        [_placeholderIconView.widthAnchor constraintEqualToConstant:36.0],
        [_placeholderIconView.heightAnchor constraintEqualToConstant:36.0],

        [_placeholderLabel.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:12.0],
        [_placeholderLabel.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-12.0],
        [_placeholderLabel.topAnchor constraintEqualToAnchor:_placeholderIconView.bottomAnchor constant:10.0],

        [_noticeLabel.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:8.0],
        [_noticeLabel.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-8.0],
        [_noticeLabel.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor constant:-6.0],
    ]];

    [self showPlaceholderMessage:nil];
}

- (void)pinViewToContent:(UIView *)view
{
    if (!view) return;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.layer.cornerRadius = 14.0;
    view.layer.masksToBounds = YES;
    [_contentView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:_contentView.topAnchor],
        [view.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor],
        [view.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor],
    ]];
    // 占位与提示条始终压在内容之上（网页失败提示、解码失败占位都要可见）
    [_contentView bringSubviewToFront:_placeholderIconView];
    [_contentView bringSubviewToFront:_placeholderLabel];
    [_contentView bringSubviewToFront:_noticeLabel];
}

- (void)showPlaceholderMessage:(NSString *)message
{
    BOOL visible = message.length > 0;
    _placeholderLabel.text = message;
    _placeholderLabel.hidden = !visible;
    _placeholderIconView.hidden = !visible;
    if (visible) {
        [_contentView bringSubviewToFront:_placeholderIconView];
        [_contentView bringSubviewToFront:_placeholderLabel];
    }
}

- (void)showNotice:(NSString *)notice
{
    _noticeLabel.text = notice;
    _noticeLabel.hidden = !notice.length;
    if (!_noticeLabel.hidden) [_contentView bringSubviewToFront:_noticeLabel];
    CALog(CALogLevelWarn, @"GENERAL", @"artifact preview notice %@", notice ?: @"");
}

#pragma mark - 各类型预览

- (void)buildImagePreview
{
    UIImage *image = [UIImage imageWithContentsOfFile:_path];
    if (!image) {
        [self showPlaceholderMessage:@"图片解码失败，文件可能已损坏。"];
        return;
    }

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _scrollView.maximumZoomScale = 6.0;
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.showsHorizontalScrollIndicator = NO;
    [self pinViewToContent:_scrollView];

    _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.image = image;
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.userInteractionEnabled = YES;
    [_scrollView addSubview:_imageView];
    [NSLayoutConstraint activateConstraints:@[
        [_imageView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
        [_imageView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
        [_imageView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
        [_imageView.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor],
        [_imageView.heightAnchor constraintEqualToAnchor:_scrollView.heightAnchor],
    ]];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleImagePinch:)];
    [_imageView addGestureRecognizer:pinch];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImageDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [_imageView addGestureRecognizer:doubleTap];
}

- (void)buildTextPreview
{
    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.alwaysBounceVertical = YES;
    _textView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _textView.textColor = UIColor.labelColor;
    _textView.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    _textView.textContainerInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    _textView.text = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:NULL]
        ?: @"(无法以 UTF-8 读取该文件，可能不是纯文本)";
    [self pinViewToContent:_textView];
}

- (void)buildWebPreview
{
    Class webViewClass = NSClassFromString(@"WKWebView");
    Class configurationClass = NSClassFromString(@"WKWebViewConfiguration");
    if (!webViewClass || !configurationClass) {
        // 环境里没有 WebKit → 退化为源码查看，界面依然可用
        [self showNotice:@"当前环境没有 WebKit，已改为显示 HTML 源码。"];
        [self buildTextPreview];
        return;
    }

    id configuration = [[configurationClass alloc] init];
    id<CAArtifactWebViewAPI> web = [(id<CAArtifactWebViewAPI>)[webViewClass alloc] initWithFrame:CGRectZero
                                                                                     configuration:configuration];
    [web setNavigationDelegate:self];

    UIView *webView = (UIView *)web;
    [self pinViewToContent:webView];
    [self setWebView:webView];

    // 只允许访问该文件所在目录，避免越权读取沙盒其他内容
    NSURL *fileURL = [NSURL fileURLWithPath:_path];
    NSURL *directory = [NSURL fileURLWithPath:_path.stringByDeletingLastPathComponent];
    [web loadFileURL:fileURL allowingReadAccessToURL:directory];
}

- (void)buildMediaPreview
{
    _player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:_path]];

    Class controllerClass = NSClassFromString(@"AVPlayerViewController");
    if (!controllerClass) {
        // AVKit 未随主二进制链接时按需加载系统框架（真机一定存在）
        void *handle = dlopen("/System/Library/Frameworks/AVKit.framework/AVKit", RTLD_LAZY);
        if (handle) controllerClass = NSClassFromString(@"AVPlayerViewController");
    }
    if (!controllerClass) {
        [self showNotice:@"系统缺少 AVKit，无法内嵌播放，可点右上角分享到其它 App。"];
        return;
    }

    id controller = [[controllerClass alloc] init];
    if ([controller respondsToSelector:@selector(setPlayer:)]) {
        [(id<CAArtifactPlayerControllerAPI>)controller setPlayer:_player];
    }
    [self setPlayerController:controller];

    UIViewController *child = (UIViewController *)controller;
    [self addChildViewController:child];
    [self pinViewToContent:child.view];
    [child didMoveToParentViewController:self];
}

- (void)buildQuickLookPreview
{
    QLPreviewController *controller = [[QLPreviewController alloc] init];
    controller.dataSource = self;
    [self setQuickLookController:controller];

    [self addChildViewController:controller];
    [self pinViewToContent:controller.view];
    [controller didMoveToParentViewController:self];
}

#pragma mark - 缩放手势

- (void)handleImagePinch:(UIPinchGestureRecognizer *)sender
{
    CGAffineTransform transform = CGAffineTransformScale(_imageView.transform, sender.scale, sender.scale);
    _imageView.transform = transform;
    sender.scale = 1.0;
}

- (void)handleImageDoubleTap:(UITapGestureRecognizer *)sender
{
    BOOL zoomed = !CGAffineTransformIsIdentity(_imageView.transform);
    [UIView animateWithDuration:0.25 animations:^{
        _imageView.transform = zoomed ? CGAffineTransformIdentity : CGAffineTransformMakeScale(2.0, 2.0);
    }];
}

#pragma mark - 私有辅助实现

- (BOOL)artifactExists
{
    if (!_path.length) return NO;
    return [NSFileManager.defaultManager fileExistsAtPath:_path];
}

- (NSString *)typeSymbolName
{
    NSString *ext = _path.pathExtension.lowercaseString;
    if ([CAArtifactImageExtensions() containsObject:ext]) return @"photo";
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return @"globe";
    if ([CAArtifactTextExtensions() containsObject:ext]) return @"doc.text";
    if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [ext isEqualToString:@"m4v"]) return @"film";
    if ([ext isEqualToString:@"mp3"] || [ext isEqualToString:@"m4a"] || [ext isEqualToString:@"wav"]) return @"waveform";
    return @"doc";
}

- (NSString *)relativeDocumentsPath
{
    if (!_path.length) return @"";
    NSString *documents = [CARuntimePaths documentsDirectory];
    if (documents.length && [_path hasPrefix:[documents stringByAppendingString:@"/"]]) {
        return [NSString stringWithFormat:@"~/Documents/%@", [_path substringFromIndex:documents.length + 1]];
    }
    return _path;
}

- (NSString *)fileSizeText
{
    NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:_path error:NULL];
    if (!attributes) return @"—";
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    return [NSByteCountFormatter stringFromByteCount:(long long)size countStyle:NSByteCountFormatterCountStyleFile];
}

@end
