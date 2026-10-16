//
//  MTGeneratedArtifactOpen.m
//

#import "MTGeneratedArtifactOpen.h"

static NSArray<NSString *> *MTArtifactPreviewExtensions(void)
{
    static NSArray<NSString *> *extensions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        extensions = @[ @"txt", @"md", @"log", @"json", @"plist", @"csv", @"c", @"h", @"m", @"swift", @"py", @"sh",
                        @"png", @"jpg", @"jpeg", @"gif", @"webp", @"pdf", @"html", @"xml", @"yaml", @"yml", @"toml" ];
    });
    return extensions;
}

BOOL MTArtifactOpenCanPreviewURL(NSURL *url)
{
    NSString *extension = url.pathExtension.lowercaseString;
    return extension.length > 0 && [MTArtifactPreviewExtensions() containsObject:extension];
}

UIViewController *MTArtifactOpenTopViewController(void)
{
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UIViewController *top = window.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            return top;
        }
    }
    return nil;
}

@implementation MTGeneratedArtifactOpen

+ (void)openFileAtPath:(NSString *)path fromViewController:(UIViewController *)sender
{
    if (!path.length) return;
    NSURL *url = [NSURL fileURLWithPath:path];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return;

    UIViewController *host = sender ?: MTArtifactOpenTopViewController();
    if (host && MTArtifactOpenCanPreviewURL(url)) {
        MTGeneratedArtifactPreviewController *preview = [MTGeneratedArtifactPreviewController new];
        preview.previewPath = path;
        [host presentViewController:preview animated:YES completion:nil];
        return;
    }
    [self shareFileAtPath:path text:nil fromViewController:host];
}

+ (void)shareFileAtPath:(NSString *)path text:(NSString *)text fromViewController:(UIViewController *)sender
{
    NSMutableArray *items = [NSMutableArray array];
    if (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]) [items addObject:[NSURL fileURLWithPath:path]];
    if (text.length) [items addObject:text];
    if (!items.count) return;
    UIViewController *host = sender ?: MTArtifactOpenTopViewController();
    if (!host) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    [host presentViewController:activity animated:YES completion:nil];
}

+ (void)copyPath:(NSString *)path
{
    if (path.length) [UIPasteboard.generalPasteboard setString:path];
}

@end

@implementation MTGeneratedArtifactPreviewController

- (instancetype)init
{
    if ((self = [super init])) {
        self.dataSource = self;
    }
    return self;
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
    return self.previewPath.length ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index
{
    return (id<QLPreviewItem>)[NSURL fileURLWithPath:self.previewPath ?: @""];
}

@end
