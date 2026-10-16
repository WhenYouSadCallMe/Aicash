//
//  CAChatTextLabel — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAChatTextLabel;

@interface CAChatTextLabel : NSObject
    - (void)handleLinkTap:(id)arg1;
    - (bool)hasMeasuredText;
    - (CAChatTextLabel *)initWithFrame:(id)arg1;
    - (CGSize)intrinsicContentSize;
    - (CGSize)measuredTextSize;
    - (id)onOpenLink;
    - (void)setAttributedText:(id)arg1;
    - (void)setFont:(id)arg1;
    - (void)setHasMeasuredText:(id)arg1;
    - (void)setMeasuredTextSize:(id)arg1;
    - (void)setOnOpenLink:(id)arg1;
    - (void)setPreferredMaxLayoutWidth:(id)arg1;
    - (void)setText:(id)arg1;

@end

NS_ASSUME_NONNULL_END
