//
//  MTLocalArtifactPreview.m
//

#import "MTLocalArtifactPreview.h"

// iPhoneOS SDK 无独立 WebKit 头目录时按需动态声明（与 CAArtifactPreviewViewController 同策略）
#import <Foundation/Foundation.h>
@class WKWebView;
@class WKWebViewConfiguration;
@protocol WKNavigationDelegate;
@interface WKWebViewConfiguration : NSObject <NSCopying>
@property (nullable, nonatomic, weak) id scriptMessageHandler;
@property (nonatomic) BOOL allowsInlineMediaPlayback;
@end
@interface WKWebView : UIView
- (nullable instancetype)initWithFrame:(CGRect)frame configuration:(nullable WKWebViewConfiguration *)configuration;
@property (nullable, nonatomic, readonly, strong) WKWebViewConfiguration *configuration;
@property (nonatomic, readonly, strong) UIScrollView *scrollView;
- (void)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;
- (void)loadHTMLString:(nullable NSString *)string baseURL:(nullable NSURL *)baseURL;
@end

@implementation MTLocalArtifactPreview
{
    WKWebView *_webView;
    UILabel *_placeholderLabel;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor systemBackgroundColor];

        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        configuration.allowsInlineMediaPlayback = YES;
        _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
        _webView.translatesAutoresizingMaskIntoConstraints = NO;
        _webView.scrollView.showsVerticalScrollIndicator = YES;
        _webView.hidden = YES;
        [self addSubview:_webView];

        _placeholderLabel = [UILabel new];
        _placeholderLabel.text = @"暂无可预览内容";
        _placeholderLabel.textColor = [UIColor secondaryLabelColor];
        _placeholderLabel.textAlignment = NSTextAlignmentCenter;
        _placeholderLabel.font = [UIFont systemFontOfSize:14.0];
        _placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_placeholderLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_webView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_webView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_webView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_webView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_placeholderLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_placeholderLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

+ (BOOL)canPreviewPath:(NSString *)path
{
    if (!path.length) return NO;
    NSString *extension = path.pathExtension.lowercaseString;
    static NSArray<NSString *> *extensions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        extensions = @[ @"html", @"htm", @"txt", @"md", @"json", @"xml", @"csv", @"log",
                        @"png", @"jpg", @"jpeg", @"gif", @"webp", @"svg", @"pdf" ];
    });
    return [extensions containsObject:extension];
}

- (void)loadFileAtPath:(NSString *)path
{
    if (![MTLocalArtifactPreview canPreviewPath:path]) {
        _placeholderLabel.hidden = NO;
        _webView.hidden = YES;
        _placeholderLabel.text = [NSString stringWithFormat:@"暂不支持预览 .%@ 文件", path.pathExtension ?: @"?"];
        if (self.loadFailure) self.loadFailure(@"unsupported preview type");
        return;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        _placeholderLabel.hidden = NO;
        _webView.hidden = YES;
        _placeholderLabel.text = @"文件不存在";
        if (self.loadFailure) self.loadFailure(@"file missing");
        return;
    }

    _previewPath = [path copy];
    _placeholderLabel.hidden = YES;
    _webView.hidden = NO;

    NSURL *url = [NSURL fileURLWithPath:path];
    NSString *extension = path.pathExtension.lowercaseString;
    static NSArray<NSString *> *imageExtensions;
    static dispatch_once_t imageOnce;
    dispatch_once(&imageOnce, ^{ imageExtensions = @[ @"png", @"jpg", @"jpeg", @"gif", @"webp", @"svg" ]; });

    if ([imageExtensions containsObject:extension]) {
        NSString *html = [NSString stringWithFormat:
            @"<html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
            @"<style>body{margin:0;background:#111;display:flex;justify-content:center;align-items:center;min-height:100vh;}"
            @"img{max-width:100%%;max-height:100%%;object-fit:contain;}</style></head>"
            @"<body><img src='%@'></body></html>",
            [url.lastPathComponent stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
        [_webView loadHTMLString:html baseURL:[url URLByDeletingLastPathComponent]];
    } else if ([extension isEqualToString:@"md"] || [extension isEqualToString:@"log"] || [extension isEqualToString:@"txt"]) {
        // 纯文本类包一层 pre 布局，避免超长行溢出
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"";
        NSString *escaped = [text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
        NSString *html = [NSString stringWithFormat:
            @"<html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
            @"<style>body{font-family:monospace;font-size:13px;padding:12px;white-space:pre-wrap;}</style></head>"
            @"<body>%@</body></html>", escaped];
        [_webView loadHTMLString:html baseURL:nil];
    } else {
        [_webView loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
    }
}

- (void)reset
{
    _previewPath = nil;
    [_webView loadHTMLString:@"" baseURL:nil];
    _webView.hidden = YES;
    _placeholderLabel.hidden = NO;
}

@end
