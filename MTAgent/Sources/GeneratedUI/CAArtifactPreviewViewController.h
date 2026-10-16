//
//  CAArtifactPreviewViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AVPlayerViewController;
@class CAArtifactPreviewViewController;

@interface CAArtifactPreviewViewController : UIViewController
    - (void)close;
    - (CAArtifactPreviewViewController *)initWithPath:(id)arg1;
    - (signed long long)numberOfPreviewItemsInPreviewController:(id)arg1;
    - (NSString *)path;
    - (AVPlayerViewController *)playerController;
    - (id)previewController:(id)arg1 previewItemAtIndex:(id)arg2;
    - (QLPreviewController *)quickLookController;
    - (void)setPath:(id)arg1;
    - (void)setPlayerController:(id)arg1;
    - (void)setQuickLookController:(id)arg1;
    - (void)setShareItem:(id)arg1;
    - (void)setWebView:(id)arg1;
    - (void)shareFile;
    - (UIBarButtonItem *)shareItem;
    - (void)viewDidAppear:(id)arg1;
    - (void)viewDidLoad;
    - (void)viewWillDisappear:(id)arg1;
    - (WKWebView *)webView;
    - (void)webView:(id)arg1 decidePolicyForNavigationAction:(id)arg2 decisionHandler:(id)arg3;
    - (void)webView:(id)arg1 didFailNavigation:(id)arg2 withError:(id)arg3;
    - (void)webView:(id)arg1 didFailProvisionalNavigation:(id)arg2 withError:(id)arg3;

@end

NS_ASSUME_NONNULL_END
