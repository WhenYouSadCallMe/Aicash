//
//  CAMermaidDiagramView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAMermaidDiagramView;
@class CAMermaidWeakScriptMessageHandler;

@interface CAMermaidDiagramView : UIView
    - (CGSize)baseContentSize;
    - (void)centerDiagramContent;
    - (bool)configureBundledFallbackWithSource:(id)arg1 firstMeaningful:(id)arg2;
    - (bool)configureWithSource:(id)arg1;
    - (void)copySource;
    - (bool)didApplyInitialFit;
    - (CAMermaidWeakScriptMessageHandler *)fallbackMessageHandler;
    - (NSString *)fallbackResourceDirectory;
    - (id)fallbackTitleForHeader:(id)arg1;
    - (WKWebView *)fallbackWebView;
    - (void)handleDiagramDoubleTap:(id)arg1;
    - (NSLayoutConstraint *)heightConstraint;
    - (CAMermaidDiagramView *)initWithFrame:(id)arg1;
    - (void)layoutSubviews;
    - (NSString *)previewCacheKey;
    - (UIScrollView *)scrollView;
    - (void)scrollViewDidZoom:(id)arg1;
    - (void)setBaseContentSize:(id)arg1;
    - (void)setDiagramZoomContent:(id)arg1 size:(id)arg2;
    - (void)setDidApplyInitialFit:(id)arg1;
    - (void)setFallbackMessageHandler:(id)arg1;
    - (void)setFallbackResourceDirectory:(id)arg1;
    - (void)setFallbackWebView:(id)arg1;
    - (void)setHeightConstraint:(id)arg1;
    - (void)setPreviewCacheKey:(id)arg1;
    - (void)setScrollView:(id)arg1;
    - (void)setSource:(id)arg1;
    - (void)setSourceCopyButton:(id)arg1;
    - (void)setTitleLabel:(id)arg1;
    - (void)setZoomContentView:(id)arg1;
    - (NSString *)source;
    - (UIButton *)sourceCopyButton;
    - (void)tearDownFallbackWebView;
    - (UILabel *)titleLabel;
    - (void)updateDiagramPanAvailability;
    - (void)updateDiagramZoomForCurrentBoundsPreservingUserScale:(id)arg1;
    - (void)userContentController:(id)arg1 didReceiveScriptMessage:(id)arg2;
    - (id)viewForZoomingInScrollView:(id)arg1;
    - (void)webView:(id)arg1 decidePolicyForNavigationAction:(id)arg2 decisionHandler:(id)arg3;
    - (UIView *)zoomContentView;

@end

NS_ASSUME_NONNULL_END
