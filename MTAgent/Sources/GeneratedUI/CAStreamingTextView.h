//
//  CAStreamingTextView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAStreamRevealTarget;
@class CAStreamingTextView;
@class NSParagraphStyle;

@interface CAStreamingTextView : UIView
    - (void)advanceReveal:(id)arg1;
    - (double)cachedTextHeight;
    - (double)cachedTextWidth;
    - (void)didMoveToWindow;
    - (void)finishStreamingReveal;
    - (bool)hasCachedTextSize;
    - (CAStreamingTextView *)initWithFrame:(id)arg1;
    - (CGSize)intrinsicContentSize;
    - (bool)intrinsicInvalidationPending;
    - (void)invalidateIntrinsicContentSize;
    - (void)layoutSubviews;
    - (double)measuredWidth;
    - (void)requestIntrinsicSizeInvalidation;
    - (CADisplayLink *)revealDisplayLink;
    - (CAStreamRevealTarget *)revealTarget;
    - (NSMutableArray *)revealUnits;
    - (void)setCachedTextHeight:(id)arg1;
    - (void)setCachedTextWidth:(id)arg1;
    - (void)setFont:(id)arg1;
    - (void)setHasCachedTextSize:(id)arg1;
    - (void)setIntrinsicInvalidationPending:(id)arg1;
    - (void)setMeasuredWidth:(id)arg1;
    - (void)setRevealDisplayLink:(id)arg1;
    - (void)setRevealTarget:(id)arg1;
    - (void)setRevealUnits:(id)arg1;
    - (void)setStreamingParagraph:(id)arg1;
    - (void)setSuppressSizeInvalidation:(id)arg1;
    - (void)setTextColor:(id)arg1;
    - (void)setTextSizeDirty:(id)arg1;
    - (NSParagraphStyle *)streamingParagraph;
    - (bool)suppressSizeInvalidation;
    - (void)textGeometryDidChange;
    - (double)textHeightForWidth:(id)arg1;
    - (bool)textSizeDirty;
    - (void)updateStreamingText:(id)arg1;

@end

NS_ASSUME_NONNULL_END
