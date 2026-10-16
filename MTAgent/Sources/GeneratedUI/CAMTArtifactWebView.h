//
//  CAMTArtifactWebView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAMTArtifactWebView;

@class NSString;

@interface CAMTArtifactWebView : UIView
    - (NSString *)allowedRoot;
    - (void)applyInitialContentFitIfNeeded;
    - (bool)cacheReusable;
    - (void)centerPreviewContent;
    - (bool)didFitContent;
    - (bool)fitContentOnLoad;
    - (bool)fitWidthOnly;
    - (double)fittedPageScale;
    - (void)handlePreviewPinch:(id)arg1;
    - (id)initWithFrame:(id)arg1 configuration:(id)arg2;
    - (CGSize)lastFitBoundsSize;
    - (void)layoutSubviews;
    - (CGSize)naturalContentSize;
    - (void)setAllowedRoot:(id)arg1;
    - (void)setCacheReusable:(id)arg1;
    - (void)setDidFitContent:(id)arg1;
    - (void)setFitContentOnLoad:(id)arg1;
    - (void)setFitWidthOnly:(id)arg1;
    - (void)setFittedPageScale:(id)arg1;
    - (void)setLastFitBoundsSize:(id)arg1;
    - (void)setNaturalContentSize:(id)arg1;
    - (void)updatePreviewPanAvailability;
    - (void)webView:(id)arg1 decidePolicyForNavigationAction:(id)arg2 decisionHandler:(id)arg3;
    - (void)webView:(id)arg1 didFailNavigation:(id)arg2 withError:(id)arg3;
    - (void)webView:(id)arg1 didFailProvisionalNavigation:(id)arg2 withError:(id)arg3;
    - (void)webView:(id)arg1 didFinishNavigation:(id)arg2;

@end

NS_ASSUME_NONNULL_END
